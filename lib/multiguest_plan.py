#!/usr/bin/env python3
import argparse, base64, ipaddress, json, re, sys
from collections import defaultdict, deque

SAFE=re.compile(r'^[A-Za-z0-9._-]+$')
STATES={'started','ready','exited'}
ACTION_TYPES={'link-flap','signal','guest-power-cut','kernel-panic'}

EMPTY="__KLAB_EMPTY__"
def b64(s):
    text=str(s)
    return base64.b64encode(text.encode()).decode() if text else EMPTY

def _safe(value, what):
    if not isinstance(value,str) or not SAFE.match(value): raise SystemExit(f'invalid {what}: {value!r}')
    return value

def _network_map(o): return {n['id']:n for n in o['networks']}

def _process_key(gid,pid): return f'{gid}/{pid}'

def _norm_dep(dep, gid, pids_by_guest):
    if isinstance(dep,str):
        dgid, dpid = (dep.split('/',1) if '/' in dep else (gid,dep)); state='exited'
    elif isinstance(dep,dict):
        dgid=dep.get('guest',gid); dpid=dep.get('process',''); state=dep.get('state','exited')
    else: raise SystemExit(f'guest {gid} process dependency must be string or object')
    _safe(dgid,'dependency guest'); _safe(dpid,'dependency process')
    if dgid not in pids_by_guest or dpid not in pids_by_guest[dgid]: raise SystemExit(f'unknown process dependency {dgid}/{dpid}')
    if state not in STATES: raise SystemExit(f'invalid dependency state {state!r} for {dgid}/{dpid}')
    return {'guest':dgid,'process':dpid,'state':state}

def _toposort_processes(o):
    nodes=[]; indeg={}; edges=defaultdict(list)
    for g in o['guests']:
        for p in g['processes']:
            k=_process_key(g['id'],p['id']); nodes.append(k); indeg[k]=0
    for g in o['guests']:
        for p in g['processes']:
            dst=_process_key(g['id'],p['id'])
            for d in p.get('depends_on',[]):
                src=_process_key(d['guest'],d['process'])
                if src==dst: raise SystemExit(f'process {dst} cannot depend on itself')
                edges[src].append(dst); indeg[dst]+=1
    q=deque([n for n in nodes if indeg[n]==0]); out=[]
    while q:
        n=q.popleft(); out.append(n)
        for m in edges[n]:
            indeg[m]-=1
            if indeg[m]==0:q.append(m)
    if len(out)!=len(nodes): raise SystemExit('process dependency graph contains a cycle')
    return out

def norm(path):
    with open(path,encoding='utf-8') as f: o=json.load(f)
    schema=o.get('schema')
    if schema not in (None,'klab-multiguest-scenario-v1','klab-multiguest-scenario-v2'): raise SystemExit('unsupported multiguest scenario schema')
    o['schema']='klab-multiguest-scenario-v2'; o.setdefault('timeout_seconds',60)

    # Backward-compatible v1 single-network form.
    if 'networks' not in o:
        net=o.get('network') or {}; net.setdefault('cidr','10.77.0.0/24')
        o['networks']=[{'id':'lan0','cidr':net['cidr'],'capture':bool(net.get('capture',False)),'delay_us':int(net.get('delay_us',0))}]
    nets=o.get('networks')
    if not isinstance(nets,list) or not nets: raise SystemExit('multiguest scenario requires at least one network')
    netids=set(); subnets=[]
    for n in nets:
        nid=_safe(n.get('id',''),'network id')
        if nid in netids: raise SystemExit(f'duplicate network id: {nid}')
        netids.add(nid)
        nw=ipaddress.ip_network(n.get('cidr',''),strict=False)
        if nw.version!=4: raise SystemExit('multiguest supports IPv4 networks only')
        if nw.prefixlen not in (8,16,24): raise SystemExit('multiguest supports /8, /16, or /24 networks')
        n['cidr']=str(nw); n.setdefault('capture',False); n.setdefault('delay_us',0)
        n['delay_us']=int(n['delay_us'])
        if n['delay_us']<0: raise SystemExit(f'network {nid} delay_us must be >= 0')
        subnets.append((nid,nw))
    for i,(aid,a) in enumerate(subnets):
        for bid,b in subnets[i+1:]:
            if a.overlaps(b): raise SystemExit(f'networks {aid} and {bid} overlap')
    nmap=_network_map(o)

    guests=o.get('guests')
    if not isinstance(guests,list) or len(guests)<2: raise SystemExit('multiguest scenario requires at least two guests')
    gids=set(); used_ips=set(); used_macs=set(); auto_host=defaultdict(lambda:11)
    pids_by_guest={}
    for gi,g in enumerate(guests):
        gid=_safe(g.get('id',''),'guest id')
        if gid in gids: raise SystemExit(f'duplicate guest id: {gid}')
        gids.add(gid)
        for k in ('target','arch'):
            if not isinstance(g.get(k),str) or not g[k]: raise SystemExit(f'guest {gid} missing {k}')
        g.setdefault('profile','normal'); g.setdefault('userspace','buildroot:minimal'); g.setdefault('timeout_seconds',o['timeout_seconds'])
        g['timeout_seconds']=int(g['timeout_seconds'])
        if g['timeout_seconds'] <= 0: raise SystemExit(f'guest {gid} timeout_seconds must be > 0')
        g.setdefault('forward_ipv4',False); g.setdefault('routes',[])
        if not isinstance(g['routes'],list): raise SystemExit(f'guest {gid} routes must be an array')

        # v1 ip/mac become one interface on lan0.
        if 'interfaces' not in g:
            g['interfaces']=[{'id':'net0','network':'lan0'}]
            if g.get('ip'): g['interfaces'][0]['ip']=g['ip']
            if g.get('mac'): g['interfaces'][0]['mac']=g['mac']
        if not isinstance(g['interfaces'],list) or not g['interfaces']: raise SystemExit(f'guest {gid} requires at least one interface')
        ifids=set()
        for ii,iface in enumerate(g['interfaces']):
            ifid=iface.setdefault('id',f'net{ii}'); _safe(ifid,f'guest {gid} interface id')
            if ifid in ifids: raise SystemExit(f'guest {gid} duplicate interface id: {ifid}')
            ifids.add(ifid)
            nid=iface.get('network')
            if nid not in nmap: raise SystemExit(f'guest {gid} interface {ifid} references unknown network {nid!r}')
            nw=ipaddress.ip_network(nmap[nid]['cidr'],strict=False)
            if not iface.get('ip'):
                while True:
                    cand=nw.network_address+auto_host[nid]; auto_host[nid]+=1
                    if cand not in (nw.network_address,nw.broadcast_address): break
                iface['ip']=f'{cand}/{nw.prefixlen}'
            ipif=ipaddress.ip_interface(iface['ip'])
            if ipif.network.network_address!=nw.network_address or ipif.network.prefixlen!=nw.prefixlen: raise SystemExit(f'guest {gid} interface {ifid} ip {iface["ip"]} not in {nw}')
            if str(ipif.ip) in used_ips: raise SystemExit(f'duplicate guest ip: {ipif.ip}')
            used_ips.add(str(ipif.ip))
            iface.setdefault('mac',f'52:54:{gi:02x}:{ii:02x}:{(gi+17)&255:02x}:{(ii+1):02x}')
            if not re.match(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$',iface['mac']): raise SystemExit(f'invalid MAC for guest {gid}/{ifid}')
            ml=iface['mac'].lower()
            if ml in used_macs: raise SystemExit(f'duplicate guest MAC: {iface["mac"]}')
            used_macs.add(ml)
            iface.setdefault('capture',nmap[nid].get('capture',False)); iface.setdefault('delay_us',nmap[nid].get('delay_us',0)); iface['delay_us']=int(iface['delay_us'])
            if iface['delay_us'] < 0: raise SystemExit(f'guest {gid} interface {ifid} delay_us must be >= 0')
            iface['guest_ifname']=f'eth{ii}'
        # legacy convenience fields retain first interface.
        g['ip']=g['interfaces'][0]['ip']; g['mac']=g['interfaces'][0]['mac']
        directly_connected=[ipaddress.ip_interface(i['ip']).network for i in g['interfaces']]
        own_ips={ipaddress.ip_interface(i['ip']).ip for i in g['interfaces']}
        for r in g['routes']:
            if not isinstance(r,dict): raise SystemExit(f'guest {gid} route must be object')
            dst=ipaddress.ip_network(r.get('to',''),strict=False); via=ipaddress.ip_address(r.get('via',''))
            if dst.version!=4 or via.version!=4: raise SystemExit(f'guest {gid} route must be IPv4')
            if via in own_ips: raise SystemExit(f'guest {gid} route gateway {via} is one of the guest own addresses')
            if not any(via in nw for nw in directly_connected): raise SystemExit(f'guest {gid} route gateway {via} is not directly reachable from any interface')
            r['to']=str(dst); r['via']=str(via)

        for key in ('builds','files','modules','processes'): g.setdefault(key,[])
        bids=set()
        for x in g['builds']:
            bid=_safe(x.get('id',''),f'guest {gid} build id')
            if bid in bids: raise SystemExit(f'guest {gid} duplicate build id: {bid}')
            bids.add(bid)
            if not isinstance(x.get('source'),str) or not x['source']: raise SystemExit(f'guest {gid} build {bid} missing source')
            x.setdefault('remote',f'/tmp/{bid}'); x.setdefault('static',True); x.setdefault('flags',[])
        mids=set()
        for m in g['modules']:
            mid=_safe(m.get('id',''),f'guest {gid} module id')
            if mid in mids: raise SystemExit(f'guest {gid} duplicate module id: {mid}')
            mids.add(mid)
            if not isinstance(m.get('source_dir'),str) or not m['source_dir']: raise SystemExit(f'guest {gid} module {mid} missing source_dir')
            m.setdefault('args',''); m.setdefault('unload_after',True); m.setdefault('name',mid)
        pids=set()
        for p in g['processes']:
            pid=_safe(p.get('id',''),f'guest {gid} process id')
            if pid in pids: raise SystemExit(f'guest {gid} duplicate process id: {pid}')
            pids.add(pid)
            if not isinstance(p.get('command'),str) or not p['command']: raise SystemExit(f'guest {gid} process {pid} missing command')
            p.setdefault('timeout_seconds',g['timeout_seconds']); p['timeout_seconds']=int(p['timeout_seconds'])
            if p['timeout_seconds'] <= 0: raise SystemExit(f'guest {gid} process {pid} timeout_seconds must be > 0')
            p.setdefault('expected_exit',0); p.setdefault('expected_signal',0); p.setdefault('depends_on',[])
            p.setdefault('on_dependency_failure','skip')
            if p['on_dependency_failure'] not in ('skip','run','fail'):
                raise SystemExit(f'guest {gid} process {pid} on_dependency_failure must be skip, run, or fail')
            ready=p.get('ready')
            if ready is not None:
                if not isinstance(ready,dict) or not isinstance(ready.get('stdout'),str) or not ready['stdout']: raise SystemExit(f'guest {gid} process {pid} ready requires stdout marker')
                ready.setdefault('timeout_seconds',p['timeout_seconds'])
            gate=p.get('gate')
            if gate is not None:
                if not isinstance(gate,dict) or not SAFE.match(str(gate.get('name',EMPTY))): raise SystemExit(f'guest {gid} process {pid} invalid gate')
                gate.setdefault('timeout_seconds',p['timeout_seconds'])
        pids_by_guest[gid]=pids
        for f in g['files']:
            if not isinstance(f.get('source'),str) or not isinstance(f.get('remote'),str) or not f['remote'].startswith('/'):
                raise SystemExit(f'guest {gid} file entries require source and absolute remote')
            f.setdefault('mode','0644')

    # Normalize process dependencies after all process names are known.
    for g in guests:
        for p in g['processes']:
            p['depends_on']=[_norm_dep(d,g['id'],pids_by_guest) for d in p.get('depends_on',[])]
    proc_lookup={(g['id'],p['id']):p for g in guests for p in g['processes']}
    for g in guests:
        for p in g['processes']:
            for d in p['depends_on']:
                src=proc_lookup[(d['guest'],d['process'])]
                if d['state']=='ready' and not src.get('ready'):
                    raise SystemExit(f'process {g["id"]}/{p["id"]} depends on readiness of {d["guest"]}/{d["process"]}, but that process has no ready marker')
                if d['state'] in ('ready','exited') and src.get('gate'):
                    raise SystemExit(f'process {g["id"]}/{p["id"]} depends on {d["state"]} of gated process {d["guest"]}/{d["process"]}; use started or remove the gate to avoid deadlock')
    order=_toposort_processes(o); o['_process_order']=order

    # Fault/action model. Triggered actions are tied to observed process state
    # transitions; untriggered actions run after process startup.
    o.setdefault('actions',[])
    if not isinstance(o['actions'],list): raise SystemExit('actions must be an array')
    aids=set()
    for a in o['actions']:
        aid=_safe(a.get('id',''),'action id')
        if aid in aids: raise SystemExit(f'duplicate action id: {aid}')
        aids.add(aid)
        typ=a.get('type')
        if typ not in ACTION_TYPES: raise SystemExit(f'action {aid} has unsupported type {typ!r}')
        trig=a.setdefault('after',{})
        if trig:
            if not isinstance(trig,dict): raise SystemExit(f'action {aid} after must be object')
            tg=trig.get('guest'); tp=trig.get('process'); st=trig.get('state','ready')
            if tg not in pids_by_guest or tp not in pids_by_guest[tg]: raise SystemExit(f'action {aid} references unknown process {tg}/{tp}')
            if st not in STATES: raise SystemExit(f'action {aid} invalid trigger state {st}')
            if st=='ready' and not proc_lookup[(tg,tp)].get('ready'): raise SystemExit(f'action {aid} waits for readiness of {tg}/{tp}, but that process has no ready marker')
            trig['state']=st
        a.setdefault('delay_ms',0); a['delay_ms']=int(a['delay_ms'])
        if a['delay_ms']<0: raise SystemExit(f'action {aid} delay_ms must be >=0')
        if typ=='link-flap':
            gid=a.get('guest'); ifid=a.get('interface')
            gg=next((x for x in guests if x['id']==gid),None)
            if gg is None or ifid not in {i['id'] for i in gg['interfaces']}: raise SystemExit(f'action {aid} unknown link {gid}/{ifid}')
            a.setdefault('down_ms',1000); a['down_ms']=int(a['down_ms'])
            if a['down_ms'] < 0: raise SystemExit(f'action {aid} down_ms must be >= 0')
        elif typ=='signal':
            gid=a.get('guest'); pid=a.get('process');
            if gid not in pids_by_guest or pid not in pids_by_guest[gid]: raise SystemExit(f'action {aid} unknown process {gid}/{pid}')
            a.setdefault('signal',15); a['signal']=int(a['signal'])
            if not 1 <= a['signal'] <= 64: raise SystemExit(f'action {aid} signal must be in Linux signal range 1..64')
        elif typ in ('guest-power-cut','kernel-panic'):
            if a.get('guest') not in gids: raise SystemExit(f'action {aid} unknown guest {a.get("guest")!r}')
            a.setdefault('expected',True)
            if not isinstance(a['expected'],bool): raise SystemExit(f'action {aid} expected must be boolean')
    return o

def main():
    cmds=['validate','meta','networks','guests','interfaces','routes','builds','files','modules','processes','process-order','dependencies','gates','actions']
    ap=argparse.ArgumentParser(); ap.add_argument('command',choices=cmds); ap.add_argument('scenario'); a=ap.parse_args(); o=norm(a.scenario)
    if a.command=='validate':
        x=dict(o); x.pop('_process_order',None); json.dump(x,sys.stdout,indent=2,sort_keys=True); print(); return
    if a.command=='meta': print(int(o['timeout_seconds'])); return
    if a.command=='networks':
        for n in o['networks']:
            print('\t'.join([n['id'],n['cidr'],'1' if n.get('capture') else '0',str(int(n.get('delay_us',0)))]))
        return
    if a.command=='guests':
        for g in o['guests']: print('\t'.join([g['id'],g['target'],g['arch'],g['profile'],g['userspace'],g['ip'],g['mac'],str(int(g['timeout_seconds'])),'1' if g.get('forward_ipv4') else '0']))
        return
    if a.command=='interfaces':
        for g in o['guests']:
            for i in g['interfaces']: print('\t'.join([g['id'],i['id'],i['network'],i['ip'],i['mac'],i['guest_ifname'],'1' if i.get('capture') else '0',str(int(i.get('delay_us',0)))]))
        return
    if a.command=='routes':
        for g in o['guests']:
            for r in g['routes']: print('\t'.join([g['id'],r['to'],r['via']]))
        return
    if a.command=='process-order':
        for k in o['_process_order']: print(k)
        return
    for g in o['guests']:
        gid=g['id']
        if a.command=='builds':
            for x in g['builds']: print('\t'.join([gid,x['id'],b64(x['source']),b64(x['remote']),'1' if x['static'] else '0',b64(json.dumps(x['flags']))]))
        elif a.command=='files':
            for x in g['files']: print('\t'.join([gid,b64(x['source']),b64(x['remote']),str(x['mode'])]))
        elif a.command=='modules':
            for m in g['modules']: print('\t'.join([gid,m['id'],b64(m['source_dir']),b64(m['args']),'1' if m['unload_after'] else '0',m['name']]))
        elif a.command=='processes':
            for p in g['processes']:
                gate=p.get('gate') or {}; ready=p.get('ready') or {}
                print('\t'.join([gid,p['id'],b64(p['command']),str(int(p['timeout_seconds'])*1000),str(int(p['expected_exit'])),str(int(p.get('expected_signal',0))),str(gate.get('name',EMPTY)),str(int(gate.get('timeout_seconds',p['timeout_seconds']))*1000),b64(ready.get('stdout','')),str(int(ready.get('timeout_seconds',p['timeout_seconds']))*1000),p.get('on_dependency_failure','skip')]))
        elif a.command=='dependencies':
            for p in g['processes']:
                for d in p.get('depends_on',[]): print('\t'.join([gid,p['id'],d['guest'],d['process'],d['state']]))
        elif a.command=='gates':
            for p in g['processes']:
                gate=p.get('gate') or {}
                if gate: print('\t'.join([str(gate['name']),gid,p['id'],str(int(gate.get('timeout_seconds',p['timeout_seconds']))*1000)]))
    if a.command=='actions':
        for x in o['actions']: print('\t'.join([x['id'],x['type'],b64(json.dumps(x,sort_keys=True))]))
if __name__=='__main__': main()

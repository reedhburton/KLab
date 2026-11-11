#!/usr/bin/env python3
"""One-time conversion of a klab-suite-v1 directory to the unified schema."""
import json,os,sys
if len(sys.argv)!=2: raise SystemExit('usage: suite_migrate.py SUITE_DIR')
root=os.path.realpath(sys.argv[1]); manifest=os.path.join(root,'suite.json')
o=json.load(open(manifest,encoding='utf-8'))
if o.get('schema')=='klab-suite-v2': print('already unified'); raise SystemExit(0)
if o.get('schema')!='klab-suite-v1' or o.get('kind')!='module': raise SystemExit('unsupported legacy suite schema')
def safe(value,label):
    if not isinstance(value,str) or not value or os.path.isabs(value) or '..' in value.split('/'): raise SystemExit(f'invalid {label}')
    path=os.path.realpath(os.path.join(root,value))
    if os.path.commonpath([root,path])!=root or not os.path.exists(path): raise SystemExit(f'missing or escaping {label}')
    return value
module=safe(o.get('module'),'module'); script=safe(o.get('script'),'script')
scenario={'schema':'klab-scenario-v1','target':'upstream:v6.6','arch':'x86_64','profile':'normal','userspace':'buildroot:minimal','timeout_seconds':60,
 'modules':[{'id':'module','source_dir':module,'name':'kernel_lab_hello','auto_load':True,'unload_after':True}],
 'files':[{'source':script,'remote':'/tmp/klab-suite-test.sh','mode':'0755'}],
 'processes':[{'id':'suite_test','command':'/tmp/klab-suite-test.sh','expected_exit':0}],
 'collect':{'dmesg':True,'events':True}}
with open(os.path.join(root,'scenario.json'),'w',encoding='utf-8') as f: json.dump(scenario,f,indent=2,sort_keys=True);f.write('\n')
os.replace(manifest,os.path.join(root,'suite.v1.json'))
new={'schema':'klab-suite-v2','name':o.get('name') or os.path.basename(root),'description':o.get('description','Migrated module suite'),'scenario':'scenario.json','targets':[]}
with open(manifest,'w',encoding='utf-8') as f: json.dump(new,f,indent=2,sort_keys=True);f.write('\n')
print(manifest)

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import importlib.util,pathlib,tempfile,sys,os
root=pathlib.Path(sys.argv[1]); sys.path.insert(0,str(root/'lib')); spec=importlib.util.spec_from_file_location('kb',root/'lib/klab_buildenv.py'); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as td:
 r=pathlib.Path(td)/'root'; (r/'var/lib/klab').mkdir(parents=True); (r/'bin').mkdir(); (r/'usr/bin').mkdir(parents=True,exist_ok=True)
 tools=['/bin/sh','/usr/bin/make','awk','sed','grep','find','xargs','basename','dirname','tr','cut','sort','head','mkdir','rm','cp','mv','ln','cat']
 rows=[]
 for t in tools:
  p=t if t.startswith('/') else '/usr/bin/'+t; hp=r/p.lstrip('/'); hp.parent.mkdir(parents=True,exist_ok=True); hp.write_text('#!/bin/sh\n'); hp.chmod(0o755); rows.append(f'{t}\t{p}\tbasepkg')
 (r/'var/lib/klab/host-tool-owners.tsv').write_text('\n'.join(rows)+'\n'); inv=pathlib.Path(td)/'installed.tsv'; inv.write_text('basepkg\t1\tx86_64\n')
 m.validate_host_tool_owners(r,inv)
 inv.write_text('other\t1\tx86_64\n')
 try: m.validate_host_tool_owners(r,inv)
 except SystemExit as e: assert 'owner absent' in str(e)
 else: raise SystemExit('missing owner was accepted')
 (r/'var/lib/klab/host-tool-owners.tsv').write_text('\n'.join(rows[:-1])+'\n'); inv.write_text('basepkg\t1\tx86_64\n')
 try: m.validate_host_tool_owners(r,inv)
 except SystemExit as e: assert 'missing baseline' in str(e)
 else: raise SystemExit('incomplete baseline was accepted')
print('buildenv host-tool owner semantics: PASS')
PY

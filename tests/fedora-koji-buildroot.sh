#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import importlib.util,sys
root=sys.argv[1]
spec=importlib.util.spec_from_file_location('fk',root+'/lib/fedora_koji.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
class S:
 def getBuild(self,x,strict=False):
  if x=='kernel-6.17.1-300.fc43': return {'id':1,'nvr':x,'task_id':9,'creation_event_id':100}
  return {10:{'nvr':'gcc-15.1.1-1.fc43'},11:{'nvr':'binutils-2.44-1.fc43'},12:{'nvr':'make-4.4.1-2.fc43'},13:{'nvr':'bash-5.2-1.fc43'}}[int(x)]
 def listRPMs(self,buildID=None): return [{'name':'kernel-core','arch':'x86_64','buildroot_id':77}]
 def getBuildroot(self,x,strict=False): return {'id':77,'arch':'x86_64','tag_id':5,'tag_name':'f43-build','repo_id':6,'create_event_id':99,'repo_create_event_id':98,'task_id':8,'host_name':'builder','container_type':'chroot'}
 def getBuildrootListing(self,x): return [
  {'name':'gcc','epoch':0,'version':'15.1.1','release':'1.fc43','arch':'x86_64'},
  {'name':'binutils','epoch':0,'version':'2.44','release':'1.fc43','arch':'x86_64'},
  {'name':'make','epoch':0,'version':'4.4.1','release':'2.fc43','arch':'x86_64'},
  {'name':'bash','epoch':0,'version':'5.2','release':'1.fc43','arch':'x86_64'}]
 def getRPM(self,row,strict=False):
  ids={'gcc':10,'binutils':11,'make':12,'bash':13}; z=dict(row); z.update({'id':ids[row['name']], 'build_id':ids[row['name']]}); return z
 def repoInfo(self,x,strict=False): return {'id':6,'tag_id':5,'tag_name':'f43-build','create_event':98,'state':1}
 def getExternalRepoList(self,*a,**kw): return [{'id':2,'name':'fedora'}]
 def getBuildConfig(self,*a,**kw): return {'name':'f43-build','extra':{'mock.package_manager':'dnf'}}
x=m.capture_manifest(S(),'kernel-6.17.1-300.fc43','x86_64','https://example.invalid/kojihub')
assert x['buildroot']['id']==77
assert x['package_inventory_sha256']
assert x['repo_info']['id']==6 and x['external_repos'][0]['name']=='fedora'
assert [r['build_nvr'] for r in x['toolchain_builds']]==['gcc-15.1.1-1.fc43','binutils-2.44-1.fc43','make-4.4.1-2.fc43']
c=m.compiler_metadata_from_manifest(x)
assert c['cc_version']=='15.1.1' and c['as_version']=='2.44' and c['cc_target']=='x86_64-redhat-linux'
assert m.koji_repo_url(x,'https://kojipkgs.example/')=='https://kojipkgs.example/repos/f43-build/6/x86_64/'
fp=m.resolve_fallback_plan(S(),x)
assert fp['schema']=='klab-fedora-koji-fallback-plan-v1'
assert [r['build_nvr'] for r in fp['builds']]==['bash-5.2-1.fc43','binutils-2.44-1.fc43','gcc-15.1.1-1.fc43','make-4.4.1-2.fc43']
assert 'gcc-15.1.1-1.fc43.x86_64.rpm' in {r['filename'] for r in fp['packages']}
assert fp['package_inventory_sha256']==x['package_inventory_sha256']
PY
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
python3 - "$tmp/plan.json" <<'PYPLAN'
import json,sys
p={'schema':'klab-fedora-koji-fallback-plan-v1','packages':[{'filename':'a-1-1.x86_64.rpm'},{'filename':'b-1-1.noarch.rpm'}],'builds':[{'build_nvr':'a-1-1'},{'build_nvr':'b-1-1'}]}
json.dump(p,open(sys.argv[1],'w'))
PYPLAN
touch "$tmp/a-1-1.x86_64.rpm" "$tmp/b-1-1.noarch.rpm" "$tmp/extra-1-1.x86_64.rpm"
python3 "$ROOT/lib/fedora_koji.py" fallback-verify-dir "$tmp/plan.json" "$tmp" >/dev/null
[[ ! -e "$tmp/extra-1-1.x86_64.rpm" ]] || { echo 'fallback verifier did not prune extra RPM' >&2; exit 1; }
grep -Fq 'koji-buildroot.json' "$ROOT/providers/fedora.sh" || { echo 'Fedora provider is not buildroot-driven' >&2; exit 1; }
grep -Fq 'Koji-pinned GCC/binutils/make' "$ROOT/providers/fedora.sh" || { echo 'Fedora provider description not updated' >&2; exit 1; }
grep -Fq 'KLAB_PROVIDER_TARGET_BUNDLE' "$ROOT/providers/fedora.sh" || { echo 'Fedora toolchain capture is not bound to exact kernel bundle' >&2; exit 1; }
grep -Fq 'compiler-json' "$ROOT/providers/fedora.sh" || { echo 'Fedora compiler metadata is not derived from Koji buildroot' >&2; exit 1; }
grep -Fq 'klab-koji-buildroot' "$ROOT/providers/fedora.sh" || { echo 'Fedora buildenv does not prefer exact Koji buildroot repo' >&2; exit 1; }
grep -Fq 'synchronizing modern execution root to recorded Koji buildroot' "$ROOT/providers/fedora.sh" || { echo 'modern Fedora root is not synchronized to reconstructable Koji packages' >&2; exit 1; }
grep -Fq 'KLAB_FEDORA_STRICT_BUILDROOT_REPO' "$ROOT/providers/fedora.sh" || { echo 'Fedora exact-repo strict mode is missing' >&2; exit 1; }
grep -Fq 'KLAB_FEDORA_KOJI_FALLBACK' "$ROOT/providers/fedora.sh" || { echo 'Fedora Koji package fallback mode is missing' >&2; exit 1; }
grep -Fq 'fallback-plan' "$ROOT/providers/fedora.sh" || { echo 'Fedora Koji package fallback reconstruction is missing' >&2; exit 1; }
grep -Fq 'KLAB_BUILDENV_AUX_REPO_DIR' "$ROOT/providers/fedora.sh" || { echo 'Fedora fallback repo is not mounted into buildenv capture' >&2; exit 1; }
echo 'fedora-koji-buildroot: PASS'

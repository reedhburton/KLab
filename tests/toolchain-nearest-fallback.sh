#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
f="$root/kernel-lab.sh"
grep -q 'selecting closest available GCC' "$f"
! grep -q 'selecting newest available GCC' "$f"
choose(){
  local requested="$1"
  awk -v req="$requested" '
    function vnum(v, a,n,i,x) { n=split(v,a,"."); x=0; for(i=1;i<=3;i++) x=x*10000+(i<=n?a[i]:0); return x }
    BEGIN { r=vnum(req); above=""; below=""; ad=0; bd=0 }
    { x=vnum($0); if (x>=r && (above=="" || x<ad)) { above=$0; ad=x } else if (x<r && (below=="" || x>bd)) { below=$0; bd=x } }
    END { if (above!="") print above; else if (below!="") print below }
  '
}
versions=$'5.5.0\n6.4.0\n6.5.0\n7.3.0'
[[ "$(printf '%s\n' "$versions" | awk '$1 ~ /^6\./' | choose 6.3.0)" == 6.4.0 ]]
[[ "$(printf '%s\n' "$versions" | awk '$1 ~ /^6\./' | choose 6.4.0)" == 6.4.0 ]]
[[ "$(printf '%s\n' "$versions" | awk '$1 ~ /^6\./' | choose 6.6.0)" == 6.5.0 ]]
echo 'PASS: kernel.org fallback selects closest compatible GCC release, not newest major'

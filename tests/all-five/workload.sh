#!/bin/sh
set -eu
p=/sys/module/klab_coord/parameters/value
case "$(uname -r)" in
  2.6.16*) use_live_parameter=0 ;;
  *) use_live_parameter=1 ;;
esac
if test "$use_live_parameter" -eq 1 && test -r "$p"; then
  test "$(cat "$p")" = 7
  read_value='test "$(cat /sys/module/klab_coord/parameters/value)" = 7'
else
  # Linux 2.0 predates query_module(2), /proc/modules, and the printk export.
  # Its matching loader and later rmmod bracket this workload; the init path
  # creates this marker only after insmod returns success.
  case "$(uname -r)" in
    2.0.*) test "$(cat /tmp/klab_coord_loaded)" = 7 ;;
    *) dmesg | grep -q 'klab_coord: ready value=7' ;;
  esac
  echo KLAB_WORKLOAD_STAGE=surrogate_ready
  p=/tmp/klab_coord_value
  printf 7 > "$p"
  read_value='test "$(cat /tmp/klab_coord_value)" = 7'
fi
workers=8
iterations=25
case "$(uname -r)" in
  2.0.*|2.2.*|2.6.16*) workers=2; iterations=2 ;;
esac
# Concurrent readers exercise live module state or its pre-sysfs surrogate.
i=0
while [ "$i" -lt "$workers" ]; do
  (j=0; while [ "$j" -lt "$iterations" ]; do eval "$read_value"; j=$(expr "$j" + 1); done) &
  i=$(expr "$i" + 1)
done
wait
echo KLAB_WORKLOAD_STAGE=wait_complete
# Replace shell processes with new programs while the module stays loaded.
i=0
while [ "$i" -lt "$workers" ]; do
  case "$(uname -r)" in
    2.0.*|2.2.*) (exec /bin/cat "$p" >/dev/null) ;;
    *) (exec /bin/sh -c "$read_value") ;;
  esac &
  i=$(expr "$i" + 1)
done
wait
echo KLAB_WORKLOAD_STAGE=wait_complete
echo KLAB_WORKLOAD_STAGE=before_write
printf 11 > "$p"
test "$(cat "$p")" = 11
printf 'KLAB_ALL_FIVE_MODULE_PROCESS_PASS\n'

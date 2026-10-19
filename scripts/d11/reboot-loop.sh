#!/bin/bash
# D11 reboot loop: reboot the FP4 N times over SSH; when a boot ends in the
# Qualcomm ramdump (05c6:900e), read the ramoops region and the printk ring out
# of RAM over Sahara BEFORE resetting it, print the crashed kernel's console
# tail, then recover it with edl-reset.py. After every boot, pull
# /sys/fs/pstore (the previous kernel's console; unreliable across a clean
# reboot, see docs/fp4-d11-mdss-reset.md).
#
#   PHONE_IP=192.168.3.x scripts/d11/reboot-loop.sh [N] [OUTDIR]
#
# CHECK_CMD, if set, runs on the phone after every boot and its output is
# printed on the boot's line (e.g. grep the journal for a fix's log message).
#
# The dumps contain the kernel command line (device serial, MACs): keep OUTDIR
# out of the repo.
set -u
N=${1:-20}; OUT=${2:-${XDG_RUNTIME_DIR:-/tmp}/d11-loop}; mkdir -p "$OUT"
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/../.." && pwd)
IP=${PHONE_IP:?set PHONE_IP to the phone IP}
LOGBUF_PHYS=${LOGBUF_PHYS:-0xa3d72e80}   # phys of __log_buf; see the doc for how to derive it
SSHO="-i $HOME/.ssh/id_claude -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=5"
s() { timeout 30 ssh $SSHO moarchy@$IP "$@" 2>/dev/null; }
rescan() {  # the DHCP lease can move after a network blip
  local ip; for ip in $(nmap -n -p22 --open -T4 "${IP%.*}.0/24" -oG - 2>/dev/null | awk '/22\/open/{print $2}'); do
    timeout 8 ssh $SSHO moarchy@$ip 'test "$(hostname)" = moarchy' 2>/dev/null && { IP=$ip; echo "   phone found at $ip"; return 0; }
  done; return 1; }
sread() {  # sread ADDR LEN FILE: Sahara MEMORY_READ, retrying once with a USB reset
  timeout 120 python3 "$HERE/sahara-dump.py" read "$1" "$2" "$3" >/dev/null 2>&1 ||
  timeout 120 python3 "$HERE/sahara-dump.py" --usbreset read "$1" "$2" "$3" >/dev/null 2>&1; }
RD=0; CRASHED=0
wait_up() {
  local t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 600 ]; do
    if lsusb | grep -qi '05c6:900e'; then
      RD=$((RD+1)); CRASHED=1; echo "   ramdump #$RD at +$(( $(date +%s)-t0 ))s -> read ramoops, edl-reset"
      f="$OUT/ramdump-$RD-$(date +%H%M%S).bin"
      sread 0xffc00000 0x100000 "$f" && python3 "$HERE/ramoops-console.py" "$f" 20 | sed 's/^/   /' || echo "   (ramoops read failed)"
      sread "$LOGBUF_PHYS" 0x20000 "${f%.bin}-logbuf.bin" || echo "   (logbuf read failed)"
      python3 "$REPO/scripts/edl-reset.py" >/dev/null 2>&1; sleep 15; continue
    fi
    if fastboot devices 2>/dev/null | grep -q fastboot; then echo "   fastboot -> continue"; fastboot continue >/dev/null 2>&1; sleep 15; continue; fi
    s true && return 0
    [ $(( $(date +%s)-t0 )) -gt 120 ] && lsusb | grep -qi 1d6b:0104 && rescan && s true && return 0
    sleep 4
  done; return 1; }
pull() {
  local B; B=$(s 'cut -c1-8 /proc/sys/kernel/random/boot_id') || return
  local d="$OUT/$(date +%H%M%S)-$B-$1"; mkdir -p "$d"
  s 'sudo -n tar -C /sys/fs/pstore -cf - .' | tar -C "$d" -xf - 2>/dev/null; }
wait_up || { echo "phone not reachable"; exit 1; }
for i in $(seq 1 "$N"); do
  s 'sudo -n systemctl reboot'; sleep 10; CRASHED=0
  wait_up || { echo "boot $i: not back after 10 min"; exit 1; }
  chk=""; [ -n "${CHECK_CMD:-}" ] && { sleep 20; chk=" | $(s "$CHECK_CMD" | tr '\n' ' ')"; }
  if [ $CRASHED = 1 ]; then echo "boot $i: CAME BACK VIA RAMDUMP$chk"; pull after-ramdump; else echo "boot $i: clean$chk"; pull clean; fi
done
echo "LOOP DONE: $N boots, $RD ramdump(s); dumps in $OUT"

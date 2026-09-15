#!/bin/bash
# Exercise the boot backends without building an image.
#
# Run: ./image/boot/test-backends.sh
#
# `bash -n` says a backend is fine when it is not. The bug this exists for:
# _set_dtb_name was renamed to _set_device_facts, backend_kernel's call was
# updated and backend_image's -- forty lines away -- was not. The file parsed
# perfectly, build.sh's "does it define all three hooks?" check passed, and the
# failure was `_set_dtb_name: command not found` at the very END of a
# forty-minute image build, after the pacstrap and the 6 GB filesystem.
#
# So this checks two things a parser cannot:
#
#   1. Every backend-private function that is CALLED is also DEFINED. That is
#      the rename bug, statically, in every hook including the ones that cannot
#      be run here.
#   2. The hooks that need no rootfs actually run: device facts resolve, fstab
#      is what the disk layout says, and an unknown DEVICE is refused rather
#      than silently producing an image for nothing.
#
# backend_kernel and backend_image are not run -- they need a populated rootfs
# and a container. Check (1) is what covers their bodies.
set -uo pipefail
cd "$(dirname "$0")/../.."

fail=0
ok()  { printf '  ok   %s\n' "$*"; }
no()  { printf '  FAIL %s\n' "$*"; fail=1; }

for backend in image/boot/sunxi-gpt.sh image/boot/android-bootimg.sh; do
  printf '\n%s\n' "$backend"

  # (1) Calls without definitions. Both are matched at the start of a line,
  # which is how every helper in these files is written and called.
  defs=$(grep -oE '^_[a-z_]+\(\)' "$backend" | tr -d '()' | sort -u)
  calls=$(grep -oE '^_[a-z_]+$' "$backend" | sort -u)
  missing=$(comm -23 <(echo "$calls") <(echo "$defs"))
  if [ -n "$missing" ]; then
    no "calls a function it does not define: $(echo "$missing" | tr '\n' ' ')"
  else
    ok "every helper it calls is defined$([ -n "$defs" ] && echo " ($(echo "$defs" | wc -l | tr -d ' ') of them)")"
  fi

  # (2) Source it and run what can be run. A backend must define three hooks
  # and must do NOTHING at source time (docs/devices.md D8).
  out=$(
    set -uo pipefail
    say() { :; }; info() { :; }; die() { echo "DIED: $*"; exit 3; }
    OUT=/nonexistent NAME=test WORK=/nonexistent ROOTDIR=/nonexistent
    REPO=$PWD ROOT_SLACK_MIB=1
    . "$backend" || exit 4
    for h in backend_kernel backend_fstab backend_image; do
      declare -F "$h" >/dev/null || { echo "NOHOOK: $h"; exit 5; }
    done
    echo "HOOKS-OK"
    backend_fstab
  ) 2>&1
  case "$out" in
    *HOOKS-OK*) ok "sources cleanly and defines all three hooks (D8)" ;;
    *NOHOOK*)   no "missing hook: ${out#*NOHOOK: }" ;;
    *DIED*)     no "died at source time, which a backend must never do: ${out#*DIED: }" ;;
    *)          no "could not source it: $out" ;;
  esac

  # /etc/fstab must name a root filesystem, and must mount it rw -- the kernel
  # mounts root ro so fsck can run, and this line is what makes it writable
  # again. An fstab saying ro is a phone that stays read-only forever.
  fstab=$(echo "$out" | grep -v 'HOOKS-OK')
  case "$fstab" in
    *" / "*) ok "fstab has a root entry" ;;
    *) no "fstab has no root entry: $fstab" ;;
  esac
  root_line=$(echo "$fstab" | awk '$2 == "/"')
  case "$root_line" in
    *rw*) ok "root is mounted rw (systemd-remount-fs reads these options)" ;;
    *) no "root entry is not rw -- the phone would stay read-only: $root_line" ;;
  esac
  [ "$(echo "$root_line" | awk '{print $NF}')" != 0 ] \
    && ok "root has a non-zero passno, so systemd-fsck-root is pulled in" \
    || no "root passno is 0 -- fsck-root never runs: $root_line"
done

# An unknown device must be refused. Only the Android backend resolves per-
# device facts; sunxi-gpt has none to resolve.
printf '\nunknown device\n'
out=$(
  set -uo pipefail
  say() { :; }; info() { :; }; die() { echo "DIED: $*"; exit 3; }
  DEVICE=nosuchphone
  . image/boot/android-bootimg.sh
  _set_device_facts && echo "RESOLVED anyway"
) 2>&1
case "$out" in
  *DIED*) ok "android-bootimg refuses DEVICE=nosuchphone" ;;
  *) no "an unknown DEVICE was not refused: $out" ;;
esac

printf '\n'
[ "$fail" = 0 ] && echo "all checks passed" || echo "FAILED"
exit "$fail"

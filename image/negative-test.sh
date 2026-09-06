#!/bin/bash
# Prove the verifier can fail.
#
# Every check in verify.sh passed on the first image that was built, including
# two that were passing for the wrong reason and two that were FAILING for the
# wrong reason. A suite that has only ever been run against a good image has not
# been shown to measure anything.
#
# So: take a good image, break five specific things, and assert that verify.sh
# reports exactly those and exits non-zero.
set -uo pipefail
IMG_XZ=${1:?usage: negative-test.sh <image.img.xz>}
W=/ntwork; rm -rf $W; mkdir -p $W
FAIL=0
ok() { printf '  \033[32mok\033[0m   %s\n' "$*"; }
no() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=1; }

echo "==> building a deliberately broken copy"
xz -dc "$IMG_XZ" > $W/bad.img

# 1. destroy the SPL magic the BROM looks for
printf 'XXXXXXXX' | dd of=$W/bad.img bs=1 seek=131076 conv=notrunc status=none

mkdir -p $W/r
ROOT_OFF=$((266240*512))
mount -o loop,offset=$ROOT_OFF $W/bad.img $W/r || { echo "mount failed"; exit 1; }
# 2. a credential the image must never carry
mkdir -p $W/r/etc/NetworkManager/system-connections
echo "[connection]" > $W/r/etc/NetworkManager/system-connections/leaked.nmconnection
# 3. mark it a debug image
touch $W/r/etc/moarchy-debug-image
# 4. give the account a real password hash
sed -i 's|^moarchy:!:|moarchy:$6$fakehashfakehashfakehash:|' $W/r/etc/shadow
# 5. remove a shell plugin
rm -rf $W/r/usr/share/moarchy/plugins/moarchy.shade
# 6. un-enable the grow unit
rm -f $W/r/etc/systemd/system/sysinit.target.wants/moarchy-grow-rootfs.service
umount $W/r

echo "==> running verify.sh against it (it MUST fail)"
WORK=/ntverify bash /repo/image/verify.sh $W/bad.img > $W/out.txt 2>&1
rc=$?
sed -e 's/\x1b\[[0-9;]*m//g' $W/out.txt > $W/plain.txt

echo
echo "==> did each break get caught?"
catches() {
  if grep -q "FAIL.*$1" $W/plain.txt; then ok "caught: $2"; else no "MISSED: $2"; fi
}
catches "eGON.BT0"                     "corrupted u-boot SPL"
catches "network profile"              "leaked wifi credential"
catches "DEBUG image"                  "debug-image marker"
catches "real password hash"           "a real password in the image"
# Matched on the shape of the message, not a count: the check used to say
# "expected 9 plugins" and now derives the number from the repo.
catches "plugins, image has"           "a missing shell plugin"
catches "not enabled in either tree"   "a disabled first-boot unit"

echo
if [ $rc -ne 0 ]; then ok "verify.sh exited non-zero ($rc)"; else no "verify.sh exited 0 on a broken image"; fi
echo
if [ $FAIL = 0 ]; then
  printf '  \033[32mthe verifier detects every planted defect\033[0m\n'
else
  printf '  \033[31mthe verifier is blind to something\033[0m\n'
fi
exit $FAIL

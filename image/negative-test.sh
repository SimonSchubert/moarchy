#!/bin/bash
# Prove the verifier can fail.
#
# Every check in verify.sh passed on the first image that was built, including
# two that were passing for the wrong reason and two that were FAILING for the
# wrong reason. A suite that has only ever been run against a good image has not
# been shown to measure anything.
#
# So: take a good artifact, break specific things, and assert that verify.sh
# reports exactly those and exits non-zero.
#
# Ported from the sunxi-gpt artifact on 2026-09-19. That version broke the
# u-boot SPL magic at byte 131076 and loop-mounted the rootfs at LBA 266240 --
# both facts about a whole-disk image on removable media, and neither one
# expressible about a directory of boot.img/vbmeta.img/rootfs.simg. The planted
# defects below are the same six ideas against the shape that is left: one per
# layer verify.sh has (artifact, boot image, verified boot, rootfs contents,
# first-boot units).
#
# Disk: the rootfs is sparse, so breaking anything inside it means expanding it,
# editing it, and re-sparsing it. Peak usage is about twice the rootfs -- the
# raw copy is deleted as soon as img2simg has read it, and verify.sh then
# expands its own. [[docker-vm-disk-kills-image-build]] is what this comment is
# here to prevent a repeat of.
set -uo pipefail
ART=${1:?usage: negative-test.sh <artifact-directory>}
ART=${ART%/}
W=/ntwork; rm -rf $W; mkdir -p $W/bad $W/r
FAIL=0
ok() { printf '  \033[32mok\033[0m   %s\n' "$*"; }
no() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=1; }

[ -d "$ART" ] || { echo "not a directory: $ART -- an Android artifact is a directory (D10)"; exit 1; }

echo "==> building a deliberately broken copy of $(basename "$ART")"
# The small files are copied; the rootfs is rebuilt below.
cp "$ART/boot.img" "$ART/vbmeta.img" "$ART/flash.sh" $W/bad/
chmod +x $W/bad/flash.sh

# 1. destroy the boot image magic the bootloader looks for
printf 'XXXXXXXX' | dd of=$W/bad/boot.img bs=1 seek=0 conv=notrunc status=none

# 2. clear the AVB "verification disabled" flag, so an Android 12 bootloader
#    would refuse this kernel. Flags are a big-endian u32 at byte 120.
printf '\0\0\0\0' | dd of=$W/bad/vbmeta.img bs=1 seek=120 conv=notrunc status=none

# 3. drop the slot retry reset (D26) -- the defect that bricks a boot silently
sed -i 's/--set-active/--no-such-flag/g' $W/bad/flash.sh

echo "==> expanding the rootfs to plant the rest"
simg2img "$ART/rootfs.simg" $W/root.raw || { echo "simg2img failed"; exit 1; }
mount -o loop $W/root.raw $W/r || { echo "mount failed"; exit 1; }
# 4. a credential the image must never carry
mkdir -p $W/r/etc/NetworkManager/system-connections
echo "[connection]" > $W/r/etc/NetworkManager/system-connections/leaked.nmconnection
# 5. mark it a debug image
touch $W/r/etc/moarchy-debug-image
# 6. give the account a real password hash
sed -i 's|^moarchy:!:|moarchy:$6$fakehashfakehashfakehash:|' $W/r/etc/shadow
# 7. remove a shell plugin
rm -rf $W/r/usr/share/moarchy/plugins/moarchy.shade
# 8. un-enable the grow unit
rm -f $W/r/etc/systemd/system/sysinit.target.wants/moarchy-grow-rootfs.service
umount $W/r

echo "==> re-sparsing"
img2simg $W/root.raw $W/bad/rootfs.simg || { echo "img2simg failed"; exit 1; }
# Freed before verify.sh expands its own copy, so the peak is two rootfs and
# not three.
rm -f $W/root.raw

echo "==> running verify.sh against it (it MUST fail)"
# DEVICE is explicit because this directory is called `bad` on purpose --
# verify.sh otherwise infers the device from the artifact's name
# (docs/devices.md D12) and would refuse it before running any of the checks
# below, so this suite would fail without ever testing what it exists to test.
DEVICE=sargo WORK=/ntverify bash /repo/image/verify.sh $W/bad > $W/out.txt 2>&1
rc=$?
sed -e 's/\x1b\[[0-9;]*m//g' $W/out.txt > $W/plain.txt

echo
echo "==> did each break get caught?"
catches() {
  if grep -q "FAIL.*$1" $W/plain.txt; then ok "caught: $2"; else no "MISSED: $2"; fi
}
catches "ANDROID!"                     "corrupted boot image header"
catches "vbmeta flags"                 "AVB verification left enabled"
catches "set-active"                   "flash.sh no longer resets the retry counter"
catches "network profile"              "leaked wifi credential"
catches "DEBUG image"                  "debug-image marker"
catches "real password hash"           "a real password in the image"
# Matched on the shape of the message, not a count: the check used to say
# "expected 9 plugins" and now derives the number from the repo.
catches "plugins, image has"           "a missing shell plugin"
# The full message is "not enabled in either tree: <target>.wants/<name>" and
# <target> is `system/sysinit.target`, not `sysinit.target`. A pattern missing
# that `system/` matches nothing, which reads as "the verifier is blind" about
# a check that is working -- [[empty-grep-is-not-absence]], costing one run.
catches "not enabled in either tree: system/sysinit.target.wants/moarchy-grow-rootfs" \
        "a disabled first-boot unit"

echo
if [ $rc -ne 0 ]; then ok "verify.sh exited non-zero ($rc)"; else no "verify.sh exited 0 on a broken image"; fi
echo
if [ $FAIL = 0 ]; then
  printf '  \033[32mthe verifier detects every planted defect\033[0m\n'
else
  printf '  \033[31mthe verifier is blind to something\033[0m\n'
fi
exit $FAIL

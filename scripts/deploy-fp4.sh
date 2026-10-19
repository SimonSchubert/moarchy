#!/usr/bin/env bash
# Build moarchy for a Fairphone 4 and flash it, in one command.
#
#   ./scripts/deploy-fp4.sh
#
# Plug the phone in, put it in fastboot, run this. It does the whole chain --
# host preflight, packages, image, verification, flash -- and every stage is
# resumable, so re-running it after a failure picks up where it stopped rather
# than starting the kernel build again.
#
# ---------------------------------------------------------------------------
# READ THIS BEFORE THE FIRST RUN
# ---------------------------------------------------------------------------
#
# This is a PORT THAT HAS NEVER BOOTED. docs/fairphone-4.md is the honest
# status; the short version is that every fact in it was verified against
# postmarketOS's own packages and the live services, and none of it was
# verified against a Fairphone, because nobody here had one when it was
# written.
#
# What that means in practice:
#
#   * The phone may not boot. It is recoverable -- the flash stays on the
#     current slot, so the other slot still holds Android and the bootloader
#     can switch back (`fastboot --set-active=<other>`).
#   * Three things do not work UPSTREAM and this port cannot fix them: the
#     built-in microphone, audio on cellular calls, and Wi-Fi that stays up
#     (pmaports#2841 -- it associates, then degrades).
#   * Flashing ERASES ANDROID. userdata is overwritten. Back up first.
#
# ---------------------------------------------------------------------------
# What it does, in order
# ---------------------------------------------------------------------------
#
#   0  preflight   host tools, binfmt, disk, and the phone
#   1  packages    ./scripts/provision.sh build      (the long one: a kernel)
#   2  image       DEVICE=fp4 ./scripts/build-image.sh
#   3  verify      ./scripts/verify-image.sh
#   4  flash       the generated flash.sh, after an explicit confirmation
#
# Stages 1-4 can be run alone:  ./scripts/deploy-fp4.sh image
# Everything up to but not including the flash:  SKIP_FLASH=1 ./scripts/deploy-fp4.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Which container engine, and the flags that differ between docker and podman.
. "$REPO_ROOT/scripts/container.sh"

DEVICE=fp4
export DEVICE

# Build only this phone's device-exclusive packages. The tree carries two
# kernels -- one per supported handset -- and on an emulated host compiling the
# one you are not flashing is hours spent on nothing. Overridable, so
# DEVICES="sargo fp4" still builds both if that is what you want.
DEVICES="${DEVICES:-fp4}"
export DEVICES

# Colours only when someone is watching; this gets piped into a log often
# enough that escape codes in it are a nuisance.
if [ -t 1 ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'
else
  R=; G=; Y=; B=; N=
fi
say()  { printf '\n%s==> %s%s\n' "$B" "$*" "$N"; }
ok()   { printf '  %sok%s   %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!!%s   %s\n' "$Y" "$N" "$*"; }
die()  { printf '\n%s!! %s%s\n' "$R" "$*" "$N" >&2; exit 1; }

STAGE="${1:-all}"
case "$STAGE" in
  all|preflight|packages|image|verify|flash) ;;
  *) die "unknown stage '$STAGE' -- one of: all preflight packages image verify flash" ;;
esac
_want() { [ "$STAGE" = all ] || [ "$STAGE" = "$1" ]; }

# ---------------------------------------------------------------------------
# 0. Preflight
#
# Everything here is checked BEFORE the kernel build, because the kernel build
# is the expensive step and discovering a missing fastboot after it is the
# worst possible ordering. Each check says what to do about it rather than
# just what is wrong.
# ---------------------------------------------------------------------------
preflight() {
say "preflight"

# --- the device package has to exist, or every later stage is confusing ----
[ -d "$REPO_ROOT/pkgbuilds/moarchy-device-$DEVICE" ] ||
  die "no pkgbuilds/moarchy-device-$DEVICE -- this checkout has no Fairphone support"
ok "pkgbuilds/moarchy-device-$DEVICE is present"

# --- the container engine ---------------------------------------------------
#
# podman when it is there, docker otherwise; MOARCHY_CONTAINER forces one.
# Rootless podman is the reason this whole script can run without sudo:
# nothing in the build actually needs root, and the one privileged thing left
# -- arch-chroot's bind mounts -- works inside a user namespace.
ctr_require
ok "container engine: $(ctr_describe)"
if ctr_is_rootless; then
  ok "rootless -- no daemon, no docker group, nothing owned by root"
fi

# --- aarch64 emulation ------------------------------------------------------
#
# The whole build runs in arm64 containers (`--platform linux/arm64`). On an
# aarch64 host that is native. On this x86_64 host it is qemu-user through
# binfmt_misc, which must be REGISTERED WITH THE KERNEL -- --platform does not
# provide the handler, it only asks for it, and without one the first command
# in the container dies with "exec format error" several minutes into a build.
#
# This is the one piece that genuinely needs root ONCE, to install and register
# the handler. It is already registered on this host (flags PF -- the F matters,
# it makes the kernel hold the interpreter open so it works inside a container
# without qemu being copied in).
if [ "$(uname -m)" != aarch64 ]; then
  if [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    ok "qemu-aarch64 binfmt is registered ($(uname -m) host, emulated build)"
    warn "the kernel build is emulated and will take HOURS, not minutes"
  else
    die "no qemu-aarch64 binfmt handler on this $(uname -m) host.
   Install it:  sudo pacman -S qemu-user-static qemu-user-static-binfmt
   then:        sudo systemctl restart systemd-binfmt
   Verify:      ls /proc/sys/fs/binfmt_misc/qemu-aarch64"
  fi
else
  ok "aarch64 host -- the build is native"
fi

# --- fastboot ---------------------------------------------------------------
#
# Only needed at the flash, but checked here: finding out after a six-hour
# kernel build that the one tool which talks to the phone is missing is
# exactly the ordering this function exists to prevent.
if command -v fastboot >/dev/null; then
  ok "fastboot is present ($(fastboot --version 2>&1 | head -1))"
  # Having fastboot is not the same as being allowed to use it. android-tools
  # ships no udev rules, so on a stock Arch install the phone's device node
  # belongs to root and `fastboot devices` prints an empty list -- which reads
  # as "not plugged in" and sends you looking at the cable.
  #
  # Checked here, before the build, because the fix needs a password and the
  # worst time to discover that is with the phone already in fastboot.
  if grep -rqlE "18d1|2ae5" /usr/lib/udev/rules.d/ /etc/udev/rules.d/ 2>/dev/null; then
    ok "android udev rules are installed"
    # Installed is not the same as effective. The rules grant access by
    # TAG+="uaccess" -- an ACL the local seat gets -- and by GROUP="adbusers".
    # Over SSH only the group works, so a setup that is fine at the desk fails
    # from a laptop, and fails as an EMPTY DEVICE LIST rather than as an error.
    # Worth one line now, because the fix needs a password and a re-login.
    if id -nG 2>/dev/null | tr ' ' '\n' | grep -qx adbusers; then
      ok "you are in adbusers -- fastboot works from any session"
    elif [ "$(loginctl show-session "${XDG_SESSION_ID:-}" -p Remote --value 2>/dev/null)" = yes ]; then
      warn "this is an SSH session and you are not in adbusers"
      printf '       uaccess does not apply here, so fastboot will see nothing.\n'
      printf '       sudo usermod -aG adbusers %s   (then re-login)\n' "$(id -un)"
      printf '       ...or run the flash from the machine'"'"'s own desktop.\n'
    else
      ok "local seat session -- uaccess will grant fastboot access"
      printf '       (not in adbusers, so this works at the desk but not over ssh)\n'
    fi
  else
    warn "no android udev rules -- fastboot will not see the phone as this user"
    printf '       sudo pacman -S android-udev     (then replug the phone)\n'
    printf '       Not fatal now; it is fatal at the flash.\n'
  fi
else
  if [ "${SKIP_FLASH:-0}" = 1 ]; then
    warn "no fastboot -- fine, SKIP_FLASH=1 is set"
  else
    die "fastboot is not installed, and the last stage needs it.
   sudo pacman -S android-tools
   (or re-run with SKIP_FLASH=1 to build the image and flash it later)"
  fi
fi

# --- disk -------------------------------------------------------------------
#
# A kernel tree, its object files, a pacstrapped rootfs and the image. Measured
# against the sargo build, which is the same shape, and rounded up rather than
# down -- running out mid-pacstrap produces "No space left on device" about a
# library, thirty minutes in, which reads like a broken package.
_free=$(df -BG --output=avail "$REPO_ROOT" | tail -1 | tr -dc '0-9')
if [ "${_free:-0}" -lt 60 ]; then
  die "only ${_free}G free under $REPO_ROOT; this needs about 60G
   (kernel tree + objects ~25G, pacstrap cache ~5G, rootfs and image ~20G)"
fi
ok "${_free}G free -- enough"

# --- the working tree -------------------------------------------------------
#
# build-image.sh refuses a dirty tree unless ALLOW_DIRTY=1, because a file
# edited while it builds is copied half-written. Said here rather than left to
# fail later, since the fix is a commit and that is easier before a build than
# during one.
if [ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]; then
  if [ "${ALLOW_DIRTY:-0}" = 1 ]; then
    warn "working tree is dirty and ALLOW_DIRTY=1 -- this image matches no commit"
  else
    git -C "$REPO_ROOT" status --porcelain | sed 's/^/       /'
    die "the working tree has uncommitted changes.
   Commit them, or re-run with ALLOW_DIRTY=1 if you mean it."
  fi
else
  ok "working tree is clean ($(git -C "$REPO_ROOT" rev-parse --short HEAD))"
fi
}

# ---------------------------------------------------------------------------
# The phone. Separated from preflight because the flash stage re-checks it --
# the phone can be unplugged, or reboot out of fastboot, during a long build.
# ---------------------------------------------------------------------------
# Why fastboot cannot open a device that is demonstrably on the bus.
#
# There are three causes and they need different fixes, so guessing at one is
# how an evening goes. Asked in the order that distinguishes them.
_diagnose_usb_permissions() {
  # 1. No rules at all. android-tools ships none; android-udev is separate.
  if ! grep -rqlE "18d1|2ae5" /usr/lib/udev/rules.d/ /etc/udev/rules.d/ 2>/dev/null; then
    printf '  There are no android udev rules on this machine -- android-tools\n'
    printf '  does not ship them:\n\n'
    printf '    sudo pacman -S android-udev\n\n'
    printf '  Then unplug the phone and plug it back in: udev applies rules when\n'
    printf '  a device appears, not when the rules are installed.\n\n'
    return
  fi

  # 2. Rules exist. They grant access two ways -- TAG+="uaccess", which gives
  #    an ACL to the LOCAL SEAT session only, and GROUP="adbusers". Over SSH
  #    the first does not apply, so a setup that works at the desk fails from
  #    a laptop, with the same empty list either way.
  local _seat _remote
  _seat=$(loginctl show-session "$(loginctl --no-legend list-sessions 2>/dev/null |
            awk -v u="$(id -un)" '"'"'$3==u {print $1; exit}'"'"')" -p Seat --value 2>/dev/null)
  _remote=$(loginctl show-session "$XDG_SESSION_ID" -p Remote --value 2>/dev/null)

  printf '  The udev rules ARE installed, so this is which session you are in.\n'
  printf '  They grant access by TAG+="uaccess" -- an ACL for the local seat --\n'
  printf '  and by GROUP="adbusers". Neither is helping right now.\n\n'

  if [ "${_remote:-}" = yes ] || [ -z "${_seat:-}" ]; then
    printf '  This looks like an SSH or non-seat session, where uaccess never\n'
    printf '  applies. Either run this from the machine'"'"'s own desktop, or join\n'
    printf '  the group, which works from anywhere:\n\n'
  else
    printf '  Joining the group is the reliable fix:\n\n'
  fi
  printf '    sudo usermod -aG adbusers %s\n' "$(id -un)"
  printf '    newgrp adbusers            # or log out and back in\n\n'
  id -nG 2>/dev/null | tr " " "\n" | grep -qx adbusers &&
    printf '  (You ARE in adbusers already -- so replug the phone; the node was\n  created before the group applied.)\n\n'
}

check_phone() {
command -v fastboot >/dev/null || die "fastboot is not installed"

if ! fastboot devices 2>/dev/null | grep -q .; then
  # An empty `fastboot devices` has TWO causes that look identical, and the
  # unhelpful one is the likelier on a fresh Arch install: the phone is not in
  # fastboot, OR it is and this user cannot open it.
  #
  # android-tools ships NO udev rules -- that is android-udev, a separate
  # package -- so without it the device node belongs to root and fastboot, run
  # as you, simply sees nothing. No error, no "permission denied", just an
  # empty list that reads exactly like an unplugged phone.
  #
  # So ask the USB bus, which needs no permissions to enumerate. If something
  # that looks like a phone in fastboot is sitting there, say which problem
  # this is rather than letting the wrong one be debugged.
  _usb=$(lsusb 2>/dev/null | grep -iE "18d1:|2ae5:|fairphone|google.*fastboot" || true)
  if [ -n "$_usb" ]; then
    printf '\n  %sA device is on the USB bus but fastboot cannot open it:%s\n' "$R" "$N"
    printf '    %s\n\n' "$_usb"
    _diagnose_usb_permissions
    die "fastboot sees no device, but the bus does -- fix the permissions above"
  fi

  printf '\n  %sNo phone in fastboot.%s\n\n' "$Y" "$N"
  printf '  On a Fairphone 4: hold Volume Down, and WHILE HOLDING IT plug the\n'
  printf '  USB cable in. (Not the Pixel gesture -- this one is plug-while-held.)\n\n'
  printf '  Waiting... Ctrl-C to give up.\n'
  local _n=0
  until fastboot devices 2>/dev/null | grep -q .; do
    sleep 2
    _n=$((_n + 1))
    # Re-check the bus while waiting: the phone may be plugged in DURING this
    # loop, and then the permissions problem appears here rather than above.
    if [ $((_n % 15)) = 0 ]; then
      _usb=$(lsusb 2>/dev/null | grep -iE "18d1:|2ae5:|fairphone" || true)
      [ -n "$_usb" ] && { printf '\n  %s!!%s a device appeared on the USB bus but fastboot cannot open it:\n' "$R" "$N"
                          printf '     %s\n     sudo pacman -S android-udev, then replug.\n' "$_usb"
                          die "fastboot cannot open the device on the bus"; }
    fi
    [ "$_n" -gt 150 ] && die "no fastboot device after five minutes"
  done
fi
ok "fastboot device: $(fastboot devices | head -1)"

# --- is it actually a Fairphone 4? -----------------------------------------
#
# Worth one round trip. Flashing a moarchy-fp4 image onto some other handset
# would overwrite its boot and userdata with a kernel for the wrong SoC, and
# `fastboot getvar product` is the cheapest possible way not to.
local _prod
_prod=$(fastboot getvar product 2>&1 | sed -n 's/^product: *//p' | head -1)
case "$_prod" in
  *FP4*|*fp4*|*lagoon*|*[Ll]ito*)
    ok "product reports '$_prod'" ;;
  "")
    warn "the bootloader did not answer getvar product -- cannot confirm this is an FP4" ;;
  *)
    printf '\n  %sThis device reports product = "%s".%s\n' "$R" "$_prod" "$N"
    printf '  A moarchy-fp4 image is for a Fairphone 4 and nothing else.\n'
    read -r -p '  Type the product name again to flash it anyway: ' _c
    [ "$_c" = "$_prod" ] || die "not confirmed -- nothing was flashed" ;;
esac

# --- unlocked? --------------------------------------------------------------
local _unl
_unl=$(fastboot getvar unlocked 2>&1 | sed -n 's/^unlocked: *//p' | head -1)
if [ "$_unl" = yes ]; then
  ok "bootloader is unlocked"
else
  die "the bootloader is locked (unlocked: ${_unl:-unknown}).
   Unlock it first -- Fairphone's own instructions, and note that
   unlocking ERASES THE PHONE by itself:
   https://support.fairphone.com/hc/en-us/articles/10492476238865
   You do NOT need to unlock critical partitions for this."
fi
}

# ---------------------------------------------------------------------------
# 1. Packages
# ---------------------------------------------------------------------------
build_packages() {
say "packages"
# Resumable by construction: docker/build-packages.sh skips anything already
# in packages/ at the pinned version, so a re-run after a failure does not
# rebuild the kernel. That is the whole reason this stage is not guarded by a
# marker file of its own -- the build already knows what it has.
if [ -f "$REPO_ROOT/packages/.build-manifest" ]; then
  ok "packages/ has a build manifest; provision.sh will skip what is current"
fi
printf '  This is the long stage. On an emulated x86_64 host the kernel alone\n'
printf '  is measured in hours. Output follows.\n\n'
./scripts/provision.sh build

# The packages this device needs, by name. provision.sh building "successfully"
# while one of these is missing is possible -- a PKGBUILD that fails is logged
# and the loop continues -- and the failure would otherwise surface as a
# pacstrap error about an unresolvable dependency.
local _missing=0
for _p in linux-moarchy-sm6350 firmware-moarchy-fp4 moarchy-device-fp4 pil-squasher; do
  if compgen -G "$REPO_ROOT/packages/$_p-*.pkg.tar.*" >/dev/null; then
    ok "$_p built"
  else
    warn "$_p is NOT in packages/"
    _missing=1
  fi
done
[ "$_missing" = 0 ] ||
  die "at least one Fairphone package did not build. Scroll up for its error;
   re-running this script retries only what is missing."
}

# ---------------------------------------------------------------------------
# 2. Image
# ---------------------------------------------------------------------------
build_image() {
say "image (DEVICE=$DEVICE)"
DEVICE=$DEVICE ./scripts/build-image.sh
}

# Find the newest image directory for this device. Used by verify and flash so
# neither has to be told where the build put things.
latest_image() {
  local _d
  _d=$(ls -1d "$REPO_ROOT"/images/moarchy-$DEVICE-* 2>/dev/null | sort | tail -1)
  [ -n "$_d" ] || return 1
  printf '%s\n' "$_d"
}

# ---------------------------------------------------------------------------
# 3. Verify
# ---------------------------------------------------------------------------
verify_image() {
say "verify"
local _img
_img=$(latest_image) || die "no images/moarchy-$DEVICE-* to verify -- did the image stage run?"
printf '  %s\n\n' "$_img"
# Not fatal on its own. The suite includes checks for hardware chains that
# have never been exercised on this device, and a FAIL there is information
# rather than a reason to refuse to flash -- the point of flashing is to find
# out. The confirmation below is where a human decides.
if ./scripts/verify-image.sh "$_img"; then
  ok "verification passed"
  VERIFY_OK=1
else
  warn "verification reported failures (see above)"
  VERIFY_OK=0
fi
}

# ---------------------------------------------------------------------------
# 4. Flash
# ---------------------------------------------------------------------------
flash_image() {
say "flash"
local _img
_img=$(latest_image) || die "no images/moarchy-$DEVICE-* to flash"
[ -x "$_img/flash.sh" ] || die "$_img has no flash.sh"

check_phone

printf '\n'
printf '  %sThis will overwrite boot and userdata on the attached phone.%s\n' "$B" "$N"
printf '  Android does not survive it. Anything on the phone is gone.\n\n'
printf '  image:  %s\n' "$_img"
printf '  device: %s\n' "$(fastboot devices | head -1)"
if [ "${VERIFY_OK:-1}" != 1 ]; then
  printf '  %sverification FAILED for this image%s\n' "$R" "$N"
fi
printf '\n  This port has never booted on hardware. It may not boot. The flash\n'
printf '  stays on the current slot, so the other slot still holds Android.\n\n'

if [ "${ASSUME_YES:-0}" = 1 ]; then
  warn "ASSUME_YES=1 -- not asking"
else
  read -r -p "  Type FLASH to continue: " _c
  [ "$_c" = FLASH ] || die "not confirmed -- nothing was flashed"
fi

"$_img/flash.sh"

say "flashed"
printf '  The phone should reboot on its own. First boot grows the rootfs and\n'
printf '  runs the first-boot scripts, so it is slower than later ones -- give\n'
printf '  it a few minutes before concluding it has hung.\n\n'
printf '  If it does NOT come up:\n'
printf '    * the other slot still has Android. Reboot to the bootloader and\n'
printf '      `fastboot --set-active=%s` to go back.\n' 'a'
printf '    * docs/fairphone-4.md has the list of things to suspect, in the\n'
printf '      order worth suspecting them.\n'
}

# ---------------------------------------------------------------------------
_want preflight && preflight
# The phone is checked up front too, when the flash is going to happen anyway,
# so "it was not plugged in" is discovered now rather than after the build.
if [ "$STAGE" = all ] && [ "${SKIP_FLASH:-0}" != 1 ] && command -v fastboot >/dev/null; then
  say "phone"
  if fastboot devices 2>/dev/null | grep -q .; then
    check_phone
  else
    warn "no phone in fastboot yet -- continuing; you will be asked again before the flash"
  fi
fi

_want packages && build_packages
_want image    && build_image
_want verify   && verify_image

if _want flash; then
  if [ "${SKIP_FLASH:-0}" = 1 ]; then
    say "flash"
    warn "SKIP_FLASH=1 -- stopping here"
    _img=$(latest_image) && printf '  flash it later with: %s/flash.sh\n' "$_img"
  else
    flash_image
  fi
fi

say "done"

#!/bin/bash
# Verify a built image without a phone.
#
#   ./scripts/verify-image.sh [path/to/moarchy-pinephone-<date>.img.xz]
#
# Three layers, in order of how much they prove:
#
#   structure   the GPT, the SPL where the BROM reads it, the boot partition
#   contents    what pacman placed, and what the image does NOT carry
#   behaviour   the two first-boot scripts, actually run in a chroot
#
# What it cannot prove: that the A64 BROM accepts the SPL, that megi's kernel
# brings up this panel, or that sway starts on a Mali-400. Those need hardware.
set -uo pipefail

IMG_XZ=${1:?usage: verify.sh <image.img.xz>}
WORK=${WORK:-/vwork}
FAIL=0

ok()   { printf '  \033[32mok\033[0m   %s\n' "$*"; }
no()   { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=1; }
sec()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
chk()  { if [ "$1" = 0 ]; then ok "$2"; else no "$2"; fi; }

rm -rf "$WORK"; mkdir -p "$WORK"
IMG="$WORK/image.img"

sec "decompress"
# A raw .img is accepted too, so the negative control (image/negative-test.sh)
# can tamper with a copy without paying for a compress/decompress round trip.
case "$IMG_XZ" in
  *.xz) xz -dc "$IMG_XZ" > "$IMG"
        printf '  raw %s, compressed %s\n' \
          "$(du -h "$IMG" | cut -f1)" "$(du -h "$IMG_XZ" | cut -f1)" ;;
  *)    cp "$IMG_XZ" "$IMG"
        printf '  raw %s (uncompressed input)\n' "$(du -h "$IMG" | cut -f1)" ;;
esac

# ---------------------------------------------------------------------------
sec "structure"

# The SPL, where the Allwinner BROM looks for it. eGON.BT0 sits at offset 4 of
# the SPL header, so the magic is at 131072 + 4.
magic=$(dd if="$IMG" bs=1 skip=131076 count=8 status=none)
[ "$magic" = "eGON.BT0" ] && ok "eGON.BT0 at byte 131076 (SPL at 128 KiB)" \
                          || no "no eGON.BT0 at byte 131076 -- got '$magic'"

# Partition table. The layout has to match DanctNIX's, because their u-boot is
# what reads it.
sfdisk -d "$IMG" > "$WORK/table.txt" 2>/dev/null
grep -q 'label: gpt' "$WORK/table.txt" && ok "GPT label" || no "not a GPT label"
grep -qE 'start= *16384,.*name="boot"'   "$WORK/table.txt" && ok "boot at LBA 16384"   || no "boot not at LBA 16384"
grep -qE 'start= *266240,.*name="rootfs"' "$WORK/table.txt" && ok "rootfs at LBA 266240" || no "rootfs not at LBA 266240"

BOOT_OFF=$((16384*512)); ROOT_OFF=$((266240*512))
BOOT_SZ=$(( $(grep -oE 'start= *16384, size= *[0-9]+' "$WORK/table.txt" | grep -oE '[0-9]+$') * 512 ))

dd if="$IMG" of="$WORK/boot.img" bs=1M skip=$((BOOT_OFF/1048576)) count=$((BOOT_SZ/1048576)) status=none
dd if="$IMG" of="$WORK/root.img" bs=1M skip=$((ROOT_OFF/1048576)) status=none

# ---------------------------------------------------------------------------
sec "boot partition"
mdir -i "$WORK/boot.img" -b :: > "$WORK/bootls.txt" 2>/dev/null
for f in Image.gz boot.scr initramfs-linux.img dtbs; do
  grep -qi "/$f" "$WORK/bootls.txt" && ok "$f" || no "$f missing from the boot partition"
done
# u-boot loads the DTB by name from boot.txt; the wrong name is a black screen.
mdir -i "$WORK/boot.img" -b ::/dtbs/allwinner 2>/dev/null | grep -q 'sun50i-a64-pinephone-1.2.dtb' \
  && ok "sun50i-a64-pinephone-1.2.dtb present" || no "PinePhone 1.2 DTB missing"
# boot.scr is a u-boot legacy image; the magic is what mkimage stamps.
mcopy -i "$WORK/boot.img" ::/boot.scr "$WORK/boot.scr" 2>/dev/null
if [ -f "$WORK/boot.scr" ]; then
  hdr=$(dd if="$WORK/boot.scr" bs=1 count=4 status=none | od -An -tx1 | tr -d ' \n')
  [ "$hdr" = "27051956" ] && ok "boot.scr carries the u-boot image magic" \
                          || no "boot.scr is not a u-boot image (magic $hdr)"
fi

# ---------------------------------------------------------------------------
sec "rootfs contents"
R="$WORK/root"
mkdir -p "$R"
# Read-write on purpose: root.img is a copy carved out of the image, so the
# behavioural section below can actually run the first-boot scripts in it. The
# published .img.xz is untouched.
mount -o loop "$WORK/root.img" "$R" 2>/dev/null || {
  no "could not mount the rootfs"; exit 1; }

have() { [ -e "$R$1" ] && ok "$1" || no "$1 missing"; }
have /usr/bin/sway
have /usr/bin/quickshell
have /usr/bin/moarchy-keyboard
have /usr/lib/moarchy/bin/moarchy-selftest
have /usr/lib/moarchy/bin/hyprctl
have /etc/profile.d/zz-moarchy.sh
have /etc/profile.d/omarchy.sh
have /etc/fonts/conf.d/50-moarchy-weight.conf
have /etc/systemd/logind.conf.d/10-power-key.conf
have /usr/share/moarchy/config/sway/config
have /usr/share/omarchy/default/themed/sway.conf.tpl
have /usr/share/omarchy/config/omarchy/shell.json
have /usr/share/fonts/omarchy/omarchy.ttf
have /usr/share/applications/moarchy.device.desktop
# A dozen runtime omarchy-* scripts source out of upstream's install/ tree.
have /usr/share/omarchy/install/helpers/browser-policy.sh
have /usr/share/omarchy/shell/shell.qml
# The camera app, and the package it needs that nothing declares -- without
# xdg-user-dirs every photo is captured and silently discarded.
have /usr/bin/megapixels
# Provenance: an image that answers "no commit" cannot be rebuilt or bisected.
if [ -f "$R/usr/share/moarchy/build-info" ]; then
  . "$R/usr/share/moarchy/build-info"
  [ "${dirty:-1}" = 0 ] && ok "built from commit ${commit:0:12}, clean tree" \
                        || no "built from a DIRTY tree (commit ${commit:0:12}) -- corresponds to no commit"
else
  no "no build-info in the image -- it cannot say what commit it is"
fi
have /usr/share/pacman/keyrings/moarchy.gpg
have /usr/share/libalpm/hooks/50-moarchy-shell-reload.hook
# The update path in one check: without the stanza a phone can only be upgraded
# by reflashing, which is the thing the repo exists to stop.
if grep -q '^\[moarchy\]' "$R/etc/pacman.conf" 2>/dev/null; then
  ok "pacman.conf carries the [moarchy] repo ($(grep -A2 '^\[moarchy\]' "$R/etc/pacman.conf" | sed -n 's/^SigLevel = //p'))"
else
  no "no [moarchy] repo in pacman.conf -- the phone could only be updated by reflashing"
fi
have /usr/bin/xdg-user-dirs-update
# Without /var/log/journal, a boot that fails leaves nothing to read next time.
have /var/log/journal
# The image shipped once with a dangling /etc/resolv.conf and resolved disabled:
# raw IPs routed, no name resolved, and pacman could not reach a mirror. Check
# both halves, because either alone looks fine.
if [ -e "$R/etc/systemd/system/dbus-org.freedesktop.resolve1.service" ] ||
   [ -L "$R/etc/systemd/system/multi-user.target.wants/systemd-resolved.service" ] ||
   [ -e "$R/etc/systemd/system/multi-user.target.wants/systemd-resolved.service" ]; then
  ok "systemd-resolved enabled (so /etc/resolv.conf resolves)"
else
  no "systemd-resolved NOT enabled -- /etc/resolv.conf will dangle and no name will resolve"
fi
have /etc/systemd/journald.conf.d/10-moarchy.conf

# Checked here, in the image AS SHIPPED, not only after the behaviour section
# has run moarchy-firstboot. That is exactly how this was missed: the suite ran
# firstboot, then asserted the drop-in existed, and passed -- while the image
# itself had no autologin, so the first boot on hardware stopped at a login
# prompt that a locked password cannot answer.
if grep -q -- '--autologin' "$R/etc/systemd/system/getty@tty1.service.d/autologin.conf" 2>/dev/null; then
  ok "tty1 autologin is in the image itself (not deferred to first boot)"
else
  no "no autologin drop-in in the shipped image -- first boot stops at a login prompt"
fi

# Counted from the repo rather than hardcoded. The literal 9 here failed the
# build that added a tenth plugin, which is a check reporting on itself.
want=$(ls -1d /repo/default/omarchy/plugins/*/ 2>/dev/null | wc -l | tr -d ' ')
n=$(ls -1d "$R"/usr/share/moarchy/plugins/*/ 2>/dev/null | wc -l | tr -d ' ')
[ "$n" = "$want" ] && ok "$n shell plugins (all of the repo's)" \
                   || no "repo has $want plugins, image has $n"

hy=$(grep -rl 'import Quickshell.Hyprland' "$R/usr/share/omarchy/shell" --include=*.qml 2>/dev/null | wc -l)
i3=$(grep -rl 'import Quickshell.I3'       "$R/usr/share/omarchy/shell" --include=*.qml 2>/dev/null | wc -l)
[ "$i3" -gt 0 ] && ok "$i3 QML files on Quickshell.I3" || no "no I3 imports -- the port is not in the image"
[ "$hy" -eq 0 ] && ok "0 QML files left on Quickshell.Hyprland" || no "$hy files still import Quickshell.Hyprland"

grep -q '"id": "moarchy.bar"' "$R/usr/share/omarchy/config/omarchy/shell.json" \
  && ok "packaged shell.json selects moarchy.bar" || no "shell.json does not select moarchy.bar"

# The sway config is passed with -c and includes by absolute path.
# The session lives in zz-moarchy.sh, together with the PATH it needs -- see
# the comment at the top of that file for why it is not two files.
sess_cfg=$(grep -oE '/usr/share/moarchy/config/sway/config' "$R/etc/profile.d/zz-moarchy.sh" | head -1)
[ -n "$sess_cfg" ] && ok "the session names the packaged sway config" || no "zz-moarchy.sh does not exec sway -c"
# And nothing else may exec a session: a second profile.d file that execs would
# reintroduce the ordering bug, sorted earlier or later.
extra=$(grep -l 'exec sway' "$R"/etc/profile.d/*.sh 2>/dev/null | grep -cv 'zz-moarchy.sh')
[ "$extra" = 0 ] && ok "only one profile.d file execs sway" \
                 || no "$extra other profile.d files exec sway -- ordering hazard"
miss=0
while read -r _ f; do [ -e "$R$f" ] || { no "sway include missing: $f"; miss=1; }; done \
  < <(grep '^include /' "$R/usr/share/moarchy/config/sway/config")
[ $miss = 0 ] && ok "every absolute sway include resolves"

sec "units"
# A unit is enabled if the .wants symlink is under EITHER tree: /etc is what
# `systemctl enable` writes, /usr/lib is how a package enables one by default.
# Checking only /etc reported two working units as broken.
# -L as well as -e, and that is the whole point: `systemctl enable` writes an
# ABSOLUTE symlink (/usr/lib/systemd/system/...), which resolves against the
# container's root rather than the mounted image, so -e follows it into nothing
# and reports a correctly enabled unit as missing. The package-shipped links are
# relative and resolve fine, which is what made the false negative look like a
# real difference between the two trees.
unit() {
  local target=$1 name=$2
  if [ -e "$R/etc/systemd/$target.wants/$name" ] || [ -L "$R/etc/systemd/$target.wants/$name" ]; then
    ok "enabled (/etc): $name"
  elif [ -e "$R/usr/lib/systemd/$target.wants/$name" ] || [ -L "$R/usr/lib/systemd/$target.wants/$name" ]; then
    ok "enabled (/usr/lib): $name"
  else
    no "not enabled in either tree: $target.wants/$name"
  fi
}
unit system/multi-user.target moarchy-firstboot.service
unit system/multi-user.target moarchy-led-perms.service
unit system/sysinit.target    moarchy-grow-rootfs.service
unit user/default.target      moarchy-user-setup.service

sec "credentials -- what must NOT be here"
u=$(grep -c '^moarchy:' "$R/etc/passwd" 2>/dev/null)
[ "$u" = 1 ] && ok "user 'moarchy' exists" || no "user 'moarchy' not in /etc/passwd"
# A locked password is ! or * in the hash field; anything else is a real hash.
for acct in moarchy root; do
  h=$(awk -F: -v a="$acct" '$1==a{print $2}' "$R/etc/shadow" 2>/dev/null)
  case "$h" in
    '!'*|'*'*|'!') ok "$acct password is locked ($h)" ;;
    '')            no "$acct has an EMPTY password" ;;
    *)             no "$acct has a real password hash -- the image ships a credential" ;;
  esac
done
[ -e "$R/etc/moarchy-debug-image" ] && no "this is a DEBUG image -- do not publish" \
                                    || ok "not a debug image"
# An authorized_keys in a PUBLISHED image would make every phone that flashes it
# trust one person's key. A public key is not a secret, which is why this is easy
# to wave through and worth checking for anyway.
if [ -s "$R/home/moarchy/.ssh/authorized_keys" ]; then
  no "an ssh key is authorised in this image -- everyone who flashes it would trust it"
else
  ok "no ssh key authorised (nobody but the owner can log in)"
fi
np=$(ls -1 "$R"/etc/NetworkManager/system-connections/ 2>/dev/null | wc -l)
[ "$np" = 0 ] && ok "no preseeded network profiles" || no "$np network profile(s) baked in"
# -L too: an absolute symlink here would read as absent to -e, turning "sshd is
# enabled" into a silent pass -- the direction that matters for a published image.
if [ -e "$R/etc/systemd/system/multi-user.target.wants/sshd.service" ] ||
   [ -L "$R/etc/systemd/system/multi-user.target.wants/sshd.service" ]; then
  no "sshd is enabled"
else
  ok "sshd not enabled"
fi
grep -qi '^PasswordAuthentication no' "$R/etc/ssh/sshd_config.d/10-moarchy.conf" 2>/dev/null \
  && ok "sshd password auth disabled" || no "sshd password auth not disabled"

# ---------------------------------------------------------------------------
# Everything above reads the image. This runs it. These two scripts do the work
# a package cannot, they have no other test, and a phone is the only other
# place they would ever execute for the first time.
sec "behaviour: the first-boot scripts"

mount --bind /proc "$R/proc" 2>/dev/null
mount --bind /sys  "$R/sys"  2>/dev/null
mount --bind /dev  "$R/dev"  2>/dev/null
cleanup() { umount -l "$R/proc" "$R/sys" "$R/dev" 2>/dev/null; umount -l "$R" 2>/dev/null; }
trap cleanup EXIT

# --- moarchy-firstboot -----------------------------------------------------
# SYSTEMD_OFFLINE stops `systemctl enable` reaching for a bus that is not there.
if chroot "$R" env SYSTEMD_OFFLINE=1 /usr/lib/moarchy/bin/moarchy-firstboot \
     > "$WORK/firstboot.log" 2>&1; then
  ok "moarchy-firstboot ran"
else
  no "moarchy-firstboot exited $?"; sed 's/^/       /' "$WORK/firstboot.log"
fi

# firstboot rewrites the same file; this checks it names the right user, not
# that it is present -- the shipped-state check above owns that.
grep -q -- "--autologin moarchy" \
  "$R/etc/systemd/system/getty@tty1.service.d/autologin.conf" 2>/dev/null \
  && ok "firstboot's autologin drop-in names the user" \
  || no "firstboot wrote a wrong or missing autologin drop-in"

for g in input feedbackd; do
  chroot "$R" id -nG moarchy 2>/dev/null | tr ' ' '\n' | grep -qx "$g" \
    && ok "moarchy is in group $g" || no "moarchy is not in group $g"
done
[ -f "$R/var/lib/moarchy/firstboot-done" ] && ok "firstboot stamped itself" \
                                           || no "no firstboot stamp -- it would run again"

# --- moarchy-user-setup ----------------------------------------------------
# Runs as the user, from their own HOME, the way the user unit does.
if chroot "$R" runuser -u moarchy -- env HOME=/home/moarchy \
     PATH=/usr/lib/moarchy/bin:/usr/bin:/bin \
     /usr/lib/moarchy/bin/moarchy-user-setup > "$WORK/usersetup.log" 2>&1; then
  ok "moarchy-user-setup ran"
else
  no "moarchy-user-setup exited $?"; sed 's/^/       /' "$WORK/usersetup.log"
fi

# A theme apply that half-works is the failure mode this project keeps hitting:
# the exit status is 0 and a sub-step printed the reason nobody read.
if grep -qE 'No such file|command not found|does not exist' "$WORK/usersetup.log"; then
  no "moarchy-user-setup logged errors even though it exited 0:"
  grep -E 'No such file|command not found|does not exist' "$WORK/usersetup.log" | sed 's/^/       /'
else
  ok "moarchy-user-setup logged no missing files or commands"
fi

for f in .config/foot/foot.ini .config/btop/btop.conf .config/alacritty; do
  [ -e "$R/home/moarchy/$f" ] && ok "user config $f" || no "user config $f missing"
done
grep -q 'style=Regular' "$R/home/moarchy/.config/foot/foot.ini" 2>/dev/null \
  && ok "foot keeps Regular weight" || no "foot.ini was not adjusted"
grep -q 'shown_boxes = "cpu mem"' "$R/home/moarchy/.config/btop/btop.conf" 2>/dev/null \
  && ok "btop trimmed to cpu+mem" || no "btop.conf was not adjusted"

# ~/.config/omarchy MUST NOT hold a shell.json: a user file overrides the
# packaged defaults, so copying one there would mask the phone UI entirely.
[ -e "$R/home/moarchy/.config/omarchy/shell.json" ] \
  && no "a user shell.json was created -- it masks the packaged defaults" \
  || ok "no user shell.json (packaged defaults stay in force)"

# The theme is what generates the sway colour config /etc/..../sway/config
# includes. Without it sway starts with no theme at all.
THEME="$R/home/moarchy/.local/state/omarchy/current/theme"
[ -e "$THEME/sway.conf" ] && ok "theme generated sway.conf" \
                          || no "no sway.conf generated -- omarchy-theme-set did not run"
[ -e "$THEME/colors.toml" ] && ok "theme colors.toml (the keyboard reads this)" \
                            || no "no colors.toml -- moarchy-keyboard has no palette"
[ -f "$R/home/moarchy/.local/state/moarchy/user-setup-done" ] \
  && ok "user-setup stamped itself" || no "no user-setup stamp -- it would run again"

# ---------------------------------------------------------------------------
# I7 has no other test. It runs exactly once, on a card, on first boot -- so
# without this the first time it executes is on someone's phone.
# The session is started by /etc/profile.d, and what sway inherits from it is
# the whole ballgame: moarchy-restart-shell lives in /usr/lib/moarchy/bin, so if
# that is not on PATH the shell never starts -- no bar, no gesture strip, and no
# log either, because the script that writes the log is the missing one.
#
# Every static check passed while this was broken. It took the phone to find it,
# so it is simulated here: a login shell on tty1, with sway replaced by a stub
# that reports the environment it was handed instead of starting a compositor.
sec "behaviour: what sway inherits from a tty1 login"

install -Dm755 /dev/stdin "$R/usr/local/bin/sway" <<'STUB'
#!/bin/bash
echo "PATH=$PATH"
echo "OMARCHY_PATH=${OMARCHY_PATH:-<unset>}"
echo "MOARCHY_PATH=${MOARCHY_PATH:-<unset>}"
for c in moarchy-restart-shell moarchy-keyboard omarchy-theme-set swaybg; do
  command -v "$c" >/dev/null 2>&1 && echo "resolves $c" || echo "MISSING $c"
done
STUB

login_env=$(chroot "$R" runuser -u moarchy -- \
  env -i HOME=/home/moarchy XDG_VTNR=1 TERM=dumb /bin/bash -l -c true 2>&1)
rm -f "$R/usr/local/bin/sway"

if [ -z "$login_env" ]; then
  no "the tty1 login never reached sway -- profile.d did not exec it"
else
  # The stub only runs if the session block was reached at all.
  echo "$login_env" | grep -q '^PATH=' \
    && ok "the login shell execs sway" || no "sway was not exec'd from profile.d"
  for c in moarchy-restart-shell moarchy-keyboard omarchy-theme-set swaybg; do
    if echo "$login_env" | grep -q "^resolves $c$"; then ok "sway would find $c"
    else no "sway would NOT find $c -- it is not on the session PATH"; fi
  done
  for v in OMARCHY_PATH MOARCHY_PATH; do
    val=$(echo "$login_env" | sed -n "s/^$v=//p")
    [ "$val" != "<unset>" ] && [ -n "$val" ] \
      && ok "$v=$val in the session" || no "$v is unset in the session"
  done
fi

sec "behaviour: the rootfs grows onto a bigger card"

# I7 runs exactly once, on a card, on first boot -- so without a test here the
# first execution is on someone's phone.
#
# It cannot be tested the obvious way. moarchy-grow-rootfs takes a partition
# device, and Docker Desktop's kernel has loop.max_part=0, so `losetup -P`
# attaches the disk but /dev/loopNp2 is never created -- no partition nodes
# exist to hand it, whatever the image contains. Reporting that as a failed
# growth test would blame the image for the harness.
#
# So the two operations the script performs are exercised directly, on the real
# image, with the same commands: sfdisk grows the last partition, resize2fs
# follows it. What is left untested is only the script's device discovery
# (findmnt / lsblk), which needs a booted system.
GROW="$WORK/grow.img"
cp --sparse=always "$IMG" "$GROW"
truncate -s "+2G" "$GROW"          # what a bigger card looks like

before_end=$(sfdisk -d "$GROW" | sed -n 's/.*start= *266240, size= *\([0-9]*\).*/\1/p')

# The backup GPT header is stranded mid-disk after the file grows; sfdisk will
# not extend a partition past it until it is moved to the new end.
sgdisk -e "$GROW" >/dev/null 2>&1 || true
# The same command moarchy-grow-rootfs runs, against partition 2.
echo ", +" | sfdisk --no-reread --force -N 2 "$GROW" >/dev/null 2>&1 || true

after_end=$(sfdisk -d "$GROW" | sed -n 's/.*start= *266240, size= *\([0-9]*\).*/\1/p')
if [ "${after_end:-0}" -gt "${before_end:-0}" ]; then
  ok "sfdisk grew the rootfs partition $(( before_end / 2048 ))M -> $(( after_end / 2048 ))M"
else
  no "sfdisk did not grow the partition (${before_end:-?} -> ${after_end:-?} sectors)"
fi

# And resize2fs follows it -- the half that actually gives you the space. The
# rootfs is attached at its offset, with no sizelimit, so the filesystem sees
# the grown partition.
if LOOP=$(losetup -o $((266240*512)) --show -f "$GROW" 2>/dev/null); then
  fs_before=$(dumpe2fs -h "$LOOP" 2>/dev/null | sed -n 's/^Block count: *//p')
  e2fsck -fp "$LOOP" >/dev/null 2>&1 || true
  resize2fs "$LOOP" >/dev/null 2>&1 || true
  fs_after=$(dumpe2fs -h "$LOOP" 2>/dev/null | sed -n 's/^Block count: *//p')
  losetup -d "$LOOP" 2>/dev/null
  if [ "${fs_after:-0}" -gt "${fs_before:-0}" ]; then
    ok "resize2fs grew the filesystem $(( fs_before * 4096 / 1048576 ))M -> $(( fs_after * 4096 / 1048576 ))M"
  else
    no "resize2fs did not grow the filesystem (${fs_before:-?} -> ${fs_after:-?} blocks)"
  fi
else
  no "could not attach the rootfs to a loop device -- I7 filesystem half NOT tested"
fi

sec "result"
if [ $FAIL = 0 ]; then
  printf '  \033[32mall checks passed\033[0m\n'
else
  printf '  \033[31msome checks failed\033[0m\n'
fi
exit $FAIL

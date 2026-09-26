#!/bin/bash
# Verify a built image without a phone.
#
#   ./scripts/verify-image.sh [path/to/moarchy-sargo-<version>-<date>]
#
# Three layers, in order of how much they prove:
#
#   structure   the boot image header, the DTB, the AVB flags, the cmdline
#   contents    what pacman placed, and what the image does NOT carry
#   behaviour   the two first-boot scripts, actually run in a chroot
#
# What it cannot prove: that the bootloader accepts the boot image, that this
# kernel brings up this panel, or that the session starts on the Adreno. Those
# need hardware.
set -uo pipefail

IMG_XZ=${1:?usage: verify.sh <image.img.xz>}
WORK=${WORK:-/vwork}
FAIL=0

ok()   { printf '  \033[32mok\033[0m   %s\n' "$*"; }
no()   { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=1; }
sec()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
# A line that is neither a pass nor a failure: something true of this image
# that the reader should know and that no image could currently make false.
#
# It exists because the alternative is worse in both directions. Reporting a
# known upstream limitation with no() makes every run of a correct image fail,
# and a suite that always fails is a suite nobody reads. Reporting it with ok()
# -- or not at all -- lets "93 checks passed" be read as "the microphone
# works", which on the Fairphone 4 it does not. So: printed, uncoloured, and
# it does not touch FAIL.
note() { printf '  note %s\n' "$*"; }
chk()  { if [ "$1" = 0 ]; then ok "$2"; else no "$2"; fi; }

# Which artifact is this? Inferred from the name rather than passed in, so
# `verify-image.sh <thing>` keeps working without a flag nobody would
# remember. A backend names its output moarchy-<device>-... (image/build.sh
# NAME), which is the one piece of structure every backend shares.
#
# DEVICE in the environment wins, and that is not a convenience flag.
# image/negative-test.sh deliberately hands this a file called `bad.img` -- it
# takes a good image, breaks five specific things and asserts that each one is
# caught. Inference alone would have refused that file before running a single
# check, and the suite whose entire job is proving the checks can FAIL would
# itself have failed for a reason that has nothing to do with the image.
_base=$(basename "$IMG_XZ")
case "${DEVICE:-$_base}" in
  sargo|moarchy-sargo-*)         DEVICE=sargo;     BACKEND=android-bootimg ;;
  fp4|moarchy-fp4-*)             DEVICE=fp4;       BACKEND=android-bootimg ;;
  *) printf "  \033[31mFAIL\033[0m cannot tell what device %s is for; set DEVICE=\n" "$_base"; exit 1 ;;
esac
_here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_here/verify/$BACKEND.sh"
# The repo list comes from the same manifest image/configure.sh writes from, so
# this file cannot check for a repo the image was never told to carry -- which
# is how [moarchy-apps] went missing from every image while this suite passed.
. "$_here/../scripts/manifest.sh"
_repos=$(manifest_repos) || _repos=""
for _hook in verify_artifact verify_grow; do
  declare -F "$_hook" >/dev/null || { printf "  \033[31mFAIL\033[0m verify/%s.sh defines no %s\n" "$BACKEND" "$_hook"; exit 1; }
done
# verify_rootfs is OPTIONAL, unlike the two above: it is for facts that are
# true of one device's rootfs and meaningless for another's, and a backend with
# none of those should not have to define an empty function to say so.
printf "\n  device %s, backend %s\n" "$DEVICE" "$BACKEND"

rm -rf "$WORK"; mkdir -p "$WORK"

# Unpack the artifact and assert everything only THIS artifact shape can be
# asked about: a GPT and an SPL, or a boot header and a vbmeta. Leaves a
# mountable filesystem at $WORK/root.img for the shared checks below.
verify_artifact

# ---------------------------------------------------------------------------
sec "rootfs contents"
R="$WORK/root"
mkdir -p "$R"
# Read-write on purpose: root.img is a copy carved out of the image, so the
# behavioural section below can actually run the first-boot scripts in it. The
# published .img.xz is untouched.
#
# Two ways to mount it, and which one is available is a property of the
# CONTAINER ENGINE rather than of the image.
#
# A loop mount is the better one and is tried first: it puts a real block
# device under the filesystem, which is what lets verify_grow exercise an
# ONLINE resize2fs -- the thing that actually happens on the phone.
#
# Rootless podman cannot do it. `mount -o loop` returns EPERM and
# /dev/loop-control is owned by nobody inside the user namespace, because
# setting up a loop device needs CAP_SYS_ADMIN in the INITIAL namespace and a
# rootless container has it only in its own. That is a real restriction, not a
# missing flag, and no amount of --privileged changes it.
#
# So fall back to fuse2fs, which implements ext4 in userspace over /dev/fuse
# and needs no block device at all. -o fakeroot makes it report the ownership
# recorded in the filesystem rather than mapping everything to the caller,
# which every `have`/ownership check below depends on.
#
# allow_other is not optional here, and the reason is easy to miss. A FUSE
# mount is PRIVATE to the user that mounted it: every other uid gets EACCES,
# including one this script switches to itself. The behavioural checks below
# run parts of the first-boot path as the phone's own user, and without
# allow_other that fails as
#
#   runuser: failed to execute env: Permission denied
#
# which reads like a broken binary or a noexec mount, and is neither -- root
# can execute the very same file. It needs `user_allow_other` in
# /etc/fuse.conf, which image/Dockerfile sets.
#
# ROOT_MOUNT_KIND is read by verify_grow, which cannot do an online grow
# through FUSE and says so rather than silently testing something weaker.
ROOT_MOUNT_KIND=
if mount -o loop "$WORK/root.img" "$R" 2>/dev/null; then
  ROOT_MOUNT_KIND=loop
elif command -v fuse2fs >/dev/null 2>&1 &&
     fuse2fs -o fakeroot,allow_other,default_permissions "$WORK/root.img" "$R" >/dev/null 2>&1 &&
     [ -d "$R/usr" ]; then
  ROOT_MOUNT_KIND=fuse
  ok "rootfs mounted with fuse2fs (no loop device in a rootless container)"
else
  no "could not mount the rootfs"
  if ! command -v fuse2fs >/dev/null 2>&1; then
    printf "       no loop device and no fuse2fs either -- install fuse2fs in image/Dockerfile\n" >&2
  else
    printf "       loop mount refused and fuse2fs failed; is /dev/fuse passed into the container?\n" >&2
  fi
  exit 1
fi

have() { [ -e "$R$1" ] && ok "$1" || no "$1 missing"; }
have /usr/bin/Hyprland
have /usr/bin/quickshell
have /usr/bin/moarchy-keyboard
have /usr/lib/moarchy/bin/moarchy-selftest
have /etc/profile.d/zz-moarchy.sh
have /etc/profile.d/omarchy.sh
have /etc/fonts/conf.d/50-moarchy-weight.conf
have /etc/systemd/logind.conf.d/10-power-key.conf
have /usr/share/moarchy/config/hypr/hyprland.lua
have /usr/share/moarchy/device/hypr/device.lua
have /usr/share/omarchy/config/omarchy/shell.json
have /usr/share/fonts/omarchy/omarchy.ttf
have /usr/share/applications/org.moarchy.Device.plugin.desktop
# A dozen runtime omarchy-* scripts source out of upstream's install/ tree.
have /usr/share/omarchy/install/helpers/browser-policy.sh
have /usr/share/omarchy/shell/shell.qml
# The camera app, and the package it needs that nothing declares -- without
# xdg-user-dirs every photo is captured and silently discarded.
have /usr/bin/megapixels
# The AUR build path. yay's query side works with none of this present, so the
# failure is not that Settings > Packages > Install from AUR does nothing: it
# lists all 119,015 packages, lets you choose one, and then stops at
# `==> ERROR: Cannot find the fakeroot binary.` -- a missing toolchain wearing
# the costume of a dead package. fakeroot and make are the two names `base`
# does not carry that makepkg cannot start without; moarchy-meta pulls the
# other eight beside them.
have /usr/bin/fakeroot
have /usr/bin/make
# Mobile data (docs/devices.md D33). The mode is the check and the file is the
# easy half: NetworkManager refuses a keyfile that the group or the world can
# read, says so once in a journal nobody is tailing, and then behaves exactly
# like a phone with no profile at all -- a SIM in the tray, full bars, and no
# data. 0644 is what the first install of this file shipped.
_md=/usr/lib/NetworkManager/system-connections/moarchy-mobile-data.nmconnection
if [ ! -e "$R$_md" ]; then
  no "$_md missing -- a SIM in this phone would get no data"
elif [ "$(stat -c %a "$R$_md")" = 600 ]; then
  ok "mobile-data profile ships 0600 (NetworkManager loads it)"
else
  no "mobile-data profile is $(stat -c %a "$R$_md"), not 600 -- NetworkManager refuses it"
fi
# Provenance: an image that answers "no commit" cannot be rebuilt or bisected.
if [ -f "$R/usr/share/moarchy/build-info" ]; then
  . "$R/usr/share/moarchy/build-info"
  [ "${dirty:-1}" = 0 ] && ok "built from commit ${commit:0:12}, clean tree" \
                        || no "built from a DIRTY tree (commit ${commit:0:12}) -- corresponds to no commit"
else
  no "no build-info in the image -- it cannot say what commit it is"
fi
have /usr/share/pacman/keyrings/moarchy.gpg
# The file being there is not the check. pacman validates against its own
# keyring in /etc/pacman.d/gnupg, and nothing imports into that automatically --
# moarchy-keyring's post_install runs `pacman-key --populate`, and it swallows
# its own failure with a warning to stderr that pacstrap's output buries. If
# that ran and did not work, SigLevel = Required refuses every package in the
# repo and the phone's only symptom is that `pacman -Syu` stops, which is
# precisely the thing the repo exists to make possible.
#
# Three outcomes, told apart: trusted, present but not trusted (imported without
# the -trusted file, so gpg has no ownertrust and validates nothing), absent.
kt="$R/usr/share/pacman/keyrings/moarchy-trusted"
kf=$(sed 's/:.*//' "$kt" 2>/dev/null | head -1)
if [ -z "$kf" ]; then
  no "no moarchy-trusted beside the key -- pacman-key had no fingerprint to trust"
elif pacman-key --gpgdir "$R/etc/pacman.d/gnupg" --list-keys "$kf" 2>/dev/null |
     grep -qE '\[ *(full|ultimate) *\]'; then
  ok "the moarchy signing key is trusted in the image's own keyring ($kf)"
elif pacman-key --gpgdir "$R/etc/pacman.d/gnupg" --list-keys "$kf" >/dev/null 2>&1; then
  no "the moarchy key is in the keyring but NOT trusted -- SigLevel = Required will refuse every update"
else
  no "the moarchy key is not in /etc/pacman.d/gnupg -- pacman-key --populate did not run, and pacman -Syu will refuse the repo"
fi
have /usr/share/libalpm/hooks/50-moarchy-shell-reload.hook
# The update path, checked for every repo the manifest names rather than for
# [moarchy] alone. Without a stanza a phone can only be upgraded by reflashing,
# which is what the repo exists to stop -- and for [moarchy-apps] it is worse
# than that: the store lists its packages, so a missing stanza is an Install
# button that fails on a phone whose owner did nothing wrong.
#
# Looped rather than repeated, because a hardcoded name here is exactly the bug
# this section is checking for on the other side.
# An empty list here is a failure, not zero work: a `for` over nothing prints
# nothing and passes, which is the exact shape of the bug this section exists
# to catch. negative-test.sh is the other half of that lesson.
[ -n "$_repos" ] || no "could not read any repo from manifest.toml -- the stanza checks did not run"
for _sec in $_repos; do
  _name=$(manifest_get "$_sec" name) || continue
  if grep -q "^\[$_name\]" "$R/etc/pacman.conf" 2>/dev/null; then
    ok "pacman.conf carries [$_name] ($(grep -A2 "^\[$_name\]" "$R/etc/pacman.conf" | sed -n 's/^SigLevel = //p'))"
  else
    no "no [$_name] repo in pacman.conf -- nothing from it can be installed or updated"
  fi
done
# The cached database, and whether it is signed. This is the check that was
# missing while the bug it catches shipped twice.
#
# The stanza above says SigLevel = Required, which implies DatabaseRequired, and
# pacman refuses a database it cannot verify. The build's own repo is file://
# with SigLevel = Never, so the db pacstrap leaves behind has no .sig beside it
# -- and one unverifiable database fails the whole transaction, including
# `pacman -S vim` out of [extra], which has nothing to do with ours. A phone
# like that installs nothing at all until somebody runs `pacman -Sy` by hand,
# and nothing on screen says why.
#
# configure.sh refreshes against the real server to fix exactly this, and it
# failed silently for two different reasons in one evening (no DNS in the
# chroot, then no Landlock on the build host). Both were invisible here,
# because nothing looked.
[ -n "$_repos" ] || no "could not read any repo from manifest.toml -- the database checks did not run"
for _sec in $_repos; do
  _name=$(manifest_get "$_sec" name) || continue
  _db="$R/var/lib/pacman/sync/$_name.db"
  if [ ! -f "$_db" ]; then
    no "no cached $_name.db -- the first install from it must sync first"
  elif [ -f "$_db.sig" ]; then
    ok "cached $_name.db is signed ($(stat -c %s "$_db.sig" 2>/dev/null) byte .sig) -- installs work on first boot"
  else
    no "cached $_name.db has NO .sig -- SigLevel = Required will refuse it, and every install dies until 'pacman -Sy'"
  fi
done
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
# One tree since docs/structure.md B6: the apps live in the same directory as
# the shell's own plugins and ship in the same package, so one count covers
# both. It used to be two, because a check that only counted
# default/omarchy/plugins would pass an image that had the phone UI and no
# calculator.
want=$(ls -1d /repo/default/omarchy/plugins/*/ 2>/dev/null | wc -l | tr -d ' ')
n=$(ls -1d "$R"/usr/share/moarchy/plugins/*/ 2>/dev/null | wc -l | tr -d ' ')
[ "$n" = "$want" ] && ok "$n shell plugins (all of the repo's)" \
                   || no "repo has $want plugins, image has $n"

# The default apps the plugins replaced must not sneak back in. Checking the
# desktop entry, not the package name: that is what the app drawer lists.
for e in org.gnome.clocks org.kde.kalk org.kde.calindori org.gnome.Contacts \
         dev.tchx84.Portfolio org.kde.kweather org.gnome.TextEditor \
         org.gnome.Calls sm.puri.Chatty org.gnome.Geary; do
  if [ -e "$R/usr/share/applications/${e}.desktop" ]; then
    no "$e.desktop is still in the image -- the plugin replaced it"
  else
    ok "$e is not a default app"
  fi
done
# And the ones that left with no plugin in their place. ChiPass was never in
# the list at all: geary pulled it in as the org.freedesktop.secrets provider
# whenever gnome-keyring came after geary in moarchy-meta's depends, which is
# exactly the kind of reordering nobody would think to check.
for e in org.gnome.Loupe org.gnome.Papers com.github.johnfactotum.Foliate \
         org.gnome.World.Secrets org.chipass.ChiPass; do
  if [ -e "$R/usr/share/applications/${e}.desktop" ]; then
    no "$e.desktop is in the image -- it left the default set"
  else
    ok "$e is not a default app"
  fi
done
# Calls and Chatty were daemons as well as windows, and the daemons are the
# half that does harm beside the plugins: Chatty deletes every text it takes
# off the modem, so Messages would never see one. The units that started them
# under the compositor were ours, so they are checked by name rather than by package.
for u in calls-daemon.service sm.puri.Chatty-daemon.service; do
  if [ -e "$R/etc/systemd/user/$u" ] || [ -L "$R/usr/lib/systemd/user/default.target.wants/$u" ]; then
    no "$u is still installed or enabled -- Phone and Messages replaced it"
  else
    ok "$u is not in the image"
  fi
done
# And the plugins that replaced them must be launchable, not merely present
# as QML the shell never enables.
for e in org.moarchy.Calculator org.moarchy.Calendar org.moarchy.Clock \
         org.moarchy.Contacts org.moarchy.Files org.moarchy.Editor \
         org.moarchy.Phone org.moarchy.Messages org.moarchy.Mail; do
  have /usr/share/applications/${e}.plugin.desktop
done
# Mail is a window over a command. Every word it says to a server is a run of
# /usr/bin/moarchy-mail, a Python script, so a package that shipped the plugin
# without it -- or an image without python -- is a sign-in screen that can
# never sign in, and nothing above would notice. The mailto: entry is what a
# tapped address opens now that Geary is not there to claim it.
have /usr/bin/moarchy-mail
[ -x "$R/usr/bin/moarchy-mail" ] && ok "moarchy-mail is executable" \
                                 || no "moarchy-mail is not executable"
have /usr/bin/python3
have /usr/share/applications/org.moarchy.Mail.compose.desktop
grep -q '^MimeType=x-scheme-handler/mailto;' "$R/usr/share/applications/org.moarchy.Mail.compose.desktop" \
  && ok "Mail handles mailto: links" \
  || no "nothing in the image handles mailto: links"

# The editor is the one plugin that is also a default for something outside
# the app drawer, and both of those halves are files the package has to lay down:
# the hidden entry xdg-open is pointed at, and the command $EDITOR runs. A
# package that shipped the plugin without them would pass every line above
# and leave `git commit` with an editor that is not there.
have /usr/share/applications/org.moarchy.Editor.open.desktop
have /usr/bin/moarchy-editor
[ -x "$R/usr/bin/moarchy-editor" ] && ok "moarchy-editor is executable" \
                                   || no "moarchy-editor is not executable"
grep -q '^FALLBACK="moarchy-editor"' "$R/usr/lib/moarchy/bin/omarchy-launch-editor" \
  && ok "omarchy-launch-editor falls back to moarchy-editor" \
  || no "omarchy-launch-editor falls back to an editor the image does not ship"
have /usr/share/moarchy/plugins/moarchy.calculator/Calculator.qml
have /usr/share/moarchy/plugins/moarchy.calculator/ui/qmldir
grep -q '"id": "moarchy.calculator"' "$R/usr/share/omarchy/config/omarchy/shell.json" \
  && ok "packaged shell.json enables moarchy.calculator" \
  || no "shell.json does not enable the calculator plugin"
# Every plugin must be in that list -- the apps and the phone UI's own
# surfaces alike, in one loop since docs/structure.md N4 put them in one
# namespace. A directory that ships in the package and is not named in
# shell.json is a surface that never loads, and nothing about the image says
# so: the count above passes, the files are all there, and the phone simply
# does without it. Third-party ids are only enabled by being listed
# (PluginRegistry.isEnabled); upstream's first-party ones are enabled by
# default and ours never are.
#
# And a plugin that ships a .desktop must have a tile a person can reach --
# that entry is what makes it an app rather than a surface, so the test keys
# on the entry and not on the id, which no longer says which is which. A tile
# is an entry that toggles the plugin and is not hidden: the editor's and
# Mail's second entries summon, and do not count.
_shelljson="$R/usr/share/omarchy/config/omarchy/shell.json"
for _pdir in /repo/default/omarchy/plugins/*/; do
  _pid=$(basename "$_pdir")
  # moarchy.common has no manifest, so the registry skips it and so does this.
  [ -f "$_pdir/manifest.json" ] || continue
  grep -q "\"id\": \"$_pid\"" "$_shelljson" \
    && ok "shell.json enables $_pid" \
    || no "shell.json does not enable $_pid -- the plugin ships and never loads"
  ls "$_pdir"*.desktop >/dev/null 2>&1 || continue
  _tile=$(grep -lx "Exec=omarchy-shell shell toggle $_pid" "$R"/usr/share/applications/*.desktop 2>/dev/null \
            | xargs -r grep -Lx 'NoDisplay=true' 2>/dev/null | head -1)
  [ -n "$_tile" ] && ok "$_pid has a appDrawer tile ($(basename "$_tile"))" \
                  || no "$_pid has no appDrawer tile -- a default app nobody can open"
done
unset _pdir _pid _shelljson _tile

# Which compositor seam the shell is on.
#
# This asked the OPPOSITE question until now -- that Quickshell.I3 was present
# and Quickshell.Hyprland gone -- because it was written when the port ran on
# Sway (b267021). The tree moved back to Hyprland afterwards, in bbc1fa0 and
# 827f362, and this check was not turned round with it: it then failed every
# image, on every device, by asserting the state the project had deliberately
# left. A check that cannot pass is worse than no check, because it teaches
# people to skim the failures.
hy=$(grep -rl 'import Quickshell.Hyprland' "$R/usr/share/omarchy/shell" --include=*.qml 2>/dev/null | wc -l)
i3=$(grep -rl 'import Quickshell.I3'       "$R/usr/share/omarchy/shell" --include=*.qml 2>/dev/null | wc -l)
[ "$hy" -gt 0 ] && ok "$hy QML files on Quickshell.Hyprland" || no "no Hyprland imports -- the shell has no compositor seam"
[ "$i3" -eq 0 ] && ok "0 QML files left on Quickshell.I3 (the sway port is gone)" || no "$i3 files still import Quickshell.I3"

grep -q '"id": "moarchy.bar"' "$R/usr/share/omarchy/config/omarchy/shell.json" \
  && ok "packaged shell.json selects moarchy.bar" || no "shell.json does not select moarchy.bar"

# The Hyprland config is passed with -c. The session lives in zz-moarchy.sh,
# together with the PATH it needs -- see the comment at the top of that file
# for why it is not two files.
sess_cfg=$(grep -oE '/usr/share/moarchy/config/hypr/hyprland.lua' "$R/etc/profile.d/zz-moarchy.sh" | head -1)
[ -n "$sess_cfg" ] && ok "the session names the packaged Hyprland config" || no "zz-moarchy.sh does not exec Hyprland -c"
# And nothing else may exec a session: a second profile.d file that execs would
# reintroduce the ordering bug, sorted earlier or later.
extra=$(grep -lE 'exec (Hyprland|sway)' "$R"/etc/profile.d/*.sh 2>/dev/null | grep -cv 'zz-moarchy.sh')
[ "$extra" = 0 ] && ok "only one profile.d file execs a session" \
                 || no "$extra other profile.d files exec a session -- ordering hazard"
# hyprland.lua requires its siblings by package.path rather than including them
# by absolute path, so the check is that each required file is there.
miss=0
while read -r f; do
  [ -e "$R/usr/share/moarchy/config/hypr/$f.lua" ] || { no "hypr require missing: $f.lua"; miss=1; }
done < <(sed -n 's/^ *require("hypr\.\([a-z]*\)").*/\1/p' "$R/usr/share/moarchy/config/hypr/hyprland.lua")
[ $miss = 0 ] && ok "every hypr require resolves"

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
# sysinit.target, which is where systemd-timesyncd.service's own [Install]
# section puts it -- not multi-user like the moarchy units above.
unit system/sysinit.target    systemd-timesyncd.service

# The clock (I10). An image with no NTP client enabled has no time source at
# all: Arch enables none by default and this systemd ships no
# /usr/lib/clock-epoch, so the clock is whatever the PMIC RTC says. Far enough
# out and every TLS handshake fails certificate validation, which is how it
# actually presented -- as `yay` reporting an expired certificate for the AUR on
# a phone flashed the same day.
if [ -f "$R/var/lib/systemd/timesync/clock" ]; then
  ok "clock floor seeded (/var/lib/systemd/timesync/clock)"
else
  no "no clock floor -- an offline first boot gets whatever the RTC says"
fi

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
# /etc only. The mobile-data profile checked further up ships in /usr/lib and
# is not a credential -- it names no operator, no APN and no password, and gets
# all three from the SIM at runtime. A profile HERE was put here by somebody's
# build, and the only ones that exist are a debug image's wifi and its psk.
np=$(ls -1 "$R"/etc/NetworkManager/system-connections/ 2>/dev/null | wc -l)
[ "$np" = 0 ] && ok "no preseeded network profiles in /etc" || no "$np network profile(s) baked in"
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
# A FUSE mount is not unmounted by `umount -l` reliably -- the helper owns it,
# and fusermount is what tells it to let go. Tried in that order so the loop
# case is unchanged and the FUSE case does not leave a mount behind that makes
# the next run's `rm -rf "$WORK"` hang on a live filesystem.
cleanup() {
  umount -l "$R/proc" "$R/sys" "$R/dev" 2>/dev/null
  if [ "${ROOT_MOUNT_KIND:-}" = fuse ]; then
    fusermount -u "$R" 2>/dev/null || fusermount3 -u "$R" 2>/dev/null || umount -l "$R" 2>/dev/null
  else
    umount -l "$R" 2>/dev/null
  fi
}
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

for f in .config/foot/foot.ini .config/btop/btop.conf; do
  [ -e "$R/home/moarchy/$f" ] && ok "user config $f" || no "user config $f missing"
done
# .config/alacritty was checked here until 2026-09-08. It is not a missing check
# now, it is the opposite one: alacritty is not installed (docs/apps.md T1), so a
# seeded config for it would be the bug.
[ -e "$R/home/moarchy/.config/alacritty" ] \
  && no "a config was seeded for alacritty, which is not installed" \
  || ok "no config seeded for an uninstalled terminal (T6)"

# T1: one terminal. Read from pacman's local database, which is the only record
# in an offline rootfs of what was INSTALLED as opposed to what happens to have
# left a file behind.
#
# The count is checked before any of the three names is. A `ls | grep` over a
# directory that is not there answers "no match" for every package, which reads
# exactly like "alacritty is not installed" and would turn a broken check into
# three green lines -- the failure this whole file exists to catch.
_pdb="$R/var/lib/pacman/local"
_pn=$(ls -1 "$_pdb" 2>/dev/null | wc -l)
if [ "$_pn" -lt 100 ]; then
  no "pacman's local db has $_pn entries -- unreadable, so the terminal checks below prove nothing"
else
  ok "pacman local db readable ($_pn packages)"
  _inst() { ls -1 "$_pdb" 2>/dev/null | grep -qE "^$1-[^-]+-[^-]+$"; }
  for t in alacritty qmlkonsole; do
    _inst "$t" && no "$t is installed -- the image should carry foot alone (T1)" \
                || ok "$t is not installed (T1)"
  done
  _inst foot && ok "foot is installed (T1)" \
             || no "foot is missing -- it IS the terminal"
fi

# T2: foot is the default terminal, which is also what stops xdg-terminal-exec
# hanging. The file is the whole mechanism, so the file is what is checked.
if grep -qx 'foot.desktop' "$R/home/moarchy/.config/xdg-terminals.list" 2>/dev/null; then
  ok "foot is the default terminal (T2)"
else
  no "xdg-terminals.list does not name foot -- xdg-terminal-exec will hang (T2)"
fi

# T3: one terminal in the APP_DRAWER, which is a different claim from T1 -- foot
# ships three TerminalEmulator entries, none of them NoDisplay. Upstream hides
# the other two by id, and this asserts that upstream file rather than anything
# of ours: nothing here implements T3, so the only way it regresses is that
# list losing the lines, which no other check would notice.
_hides="$R/usr/share/omarchy/default/omarchy/launcher.hides"
if [ ! -s "$_hides" ]; then
  no "launcher.hides is missing -- footclient and foot-server would both show as apps (T3)"
else
  for e in footclient foot-server; do
    grep -qx "$e" "$_hides" \
      && ok "$e is hidden from the appDrawer by launcher.hides (T3)" \
      || no "$e is not in launcher.hides -- it will show as a second terminal (T3)"
  done
fi
grep -q 'style=Regular' "$R/home/moarchy/.config/foot/foot.ini" 2>/dev/null \
  && ok "foot keeps Regular weight" || no "foot.ini was not adjusted"
grep -q 'shown_boxes = "cpu mem"' "$R/home/moarchy/.config/btop/btop.conf" 2>/dev/null \
  && ok "btop trimmed to cpu+mem" || no "btop.conf was not adjusted"

# ~/.config/omarchy MUST NOT hold a shell.json: a user file overrides the
# packaged defaults, so copying one there would mask the phone UI entirely.
[ -e "$R/home/moarchy/.config/omarchy/shell.json" ] \
  && no "a user shell.json was created -- it masks the packaged defaults" \
  || ok "no user shell.json (packaged defaults stay in force)"

# The theme's compositor colours. Upstream generates hyprland.lua itself and
# config/hypr/hyprland.lua requires it -- moarchy no longer ships a template.
THEME="$R/home/moarchy/.local/state/omarchy/current/theme"
# Generated by omarchy-theme-set, which user-setup runs AS THE PHONE'S USER --
# so under fuse2fs it cannot execute anything and produces nothing, for the
# same access(X_OK) reason the PATH checks above explain. user-setup itself
# still reports success, which is why this is scoped rather than deleted:
# on a loop mount an empty theme directory is a real defect.
_theme_blind=0
[ "${ROOT_MOUNT_KIND:-}" = fuse ] && _theme_blind=1
if [ -e "$THEME/hyprland.lua" ]; then ok "theme generated hyprland.lua"
elif [ "$_theme_blind" = 1 ]; then note "no hyprland.lua -- omarchy-theme-set cannot run through a fuse2fs mount"
else no "no hyprland.lua generated -- omarchy-theme-set did not run"; fi
# Same origin as hyprland.lua above, same scoping.
if [ -e "$THEME/colors.toml" ]; then ok "theme colors.toml (the keyboard reads this)"
elif [ "$_theme_blind" = 1 ]; then note "no colors.toml -- omarchy-theme-set cannot run through a fuse2fs mount"
else no "no colors.toml -- moarchy-keyboard has no palette"; fi
[ -f "$R/home/moarchy/.local/state/moarchy/user-setup-done" ] \
  && ok "user-setup stamped itself" || no "no user-setup stamp -- it would run again"

# ---------------------------------------------------------------------------
# I7 has no other test. It runs exactly once, on a card, on first boot -- so
# without this the first time it executes is on someone's phone.
# The session is started by /etc/profile.d, and what Hyprland inherits from it is
# the whole ballgame: moarchy-restart-shell lives in /usr/lib/moarchy/bin, so if
# that is not on PATH the shell never starts -- no bar, no gesture strip, and no
# log either, because the script that writes the log is the missing one.
#
# Every static check passed while this was broken. It took the phone to find it,
# so it is simulated here: a login shell on tty1, with Hyprland replaced by a stub
# that reports the environment it was handed instead of starting a compositor.
sec "behaviour: what Hyprland inherits from a tty1 login"

install -Dm755 /dev/stdin "$R/usr/local/bin/Hyprland" <<'STUB'
#!/bin/bash
echo "PATH=$PATH"
echo "OMARCHY_PATH=${OMARCHY_PATH:-<unset>}"
echo "MOARCHY_PATH=${MOARCHY_PATH:-<unset>}"
for c in moarchy-restart-shell moarchy-keyboard omarchy-theme-set hyprctl; do
  command -v "$c" >/dev/null 2>&1 && echo "resolves $c" || echo "MISSING $c"
done
STUB

login_env=$(chroot "$R" runuser -u moarchy -- \
  env -i HOME=/home/moarchy XDG_VTNR=1 TERM=dumb /bin/bash -l -c true 2>&1)
rm -f "$R/usr/local/bin/Hyprland"

if [ -z "$login_env" ]; then
  no "the tty1 login never reached the compositor -- profile.d did not exec it"
else
  # The stub only runs if the session block was reached at all.
  echo "$login_env" | grep -q '^PATH=' \
    && ok "the login shell execs Hyprland" || no "Hyprland was not exec'd from profile.d"
  _pathline=$(echo "$login_env" | sed -n 's/^PATH=//p' | head -1)
  _anymissing=0
  # Under FUSE this question cannot be answered, and pretending otherwise in
  # either direction is worse than saying so.
  #
  # `command -v` decides with access(X_OK), and fuse2fs refuses that for any
  # uid other than the one that mounted it -- even with allow_other and
  # default_permissions, and even on a root-owned 0755 file the mounting user
  # executes perfectly well. This check runs as the phone's own user by
  # design, so it hits exactly that case.
  #
  # So: if the PATH carries both directories the binaries live in, the thing
  # this check exists to catch -- a directory that never got prepended -- is
  # demonstrably not happening, and the failure is the verifier's. That is
  # reported as a note. If the PATH is missing one of them, it is still a
  # hard failure, because that is the real bug and it is visible either way.
  #
  # Under a loop mount -- docker, or anything running as real root -- none of
  # this applies and every check below stays hard.
  _fuse_blind=0
  if [ "${ROOT_MOUNT_KIND:-}" = fuse ]; then
    case ":$_pathline:" in
      *:/usr/lib/moarchy/bin:*) case ":$_pathline:" in *:/usr/bin:*) _fuse_blind=1 ;; esac ;;
    esac
  fi
  for c in moarchy-restart-shell moarchy-keyboard omarchy-theme-set hyprctl; do
    if echo "$login_env" | grep -q "^resolves $c$"; then ok "Hyprland would find $c"
    elif [ "$_fuse_blind" = 1 ]; then
      note "cannot test whether Hyprland finds $c -- fuse2fs denies access(X_OK) to another uid; both PATH entries are present"
    else no "Hyprland would NOT find $c -- it is not on the session PATH"; _anymissing=1; fi
  done
  # Say what the session PATH actually was. "not on the session PATH" is a
  # conclusion, and without the PATH beside it there is no way to tell a
  # missing package from a directory that never got prepended -- which is two
  # very different bugs in two different files.
  if [ "$_anymissing" = 1 ]; then
    printf '       session PATH: %s\n' "${_pathline:-<none>}"
    printf '       (the binaries are in /usr/lib/moarchy/bin and /usr/bin;\n'
    printf '        if both are on that PATH, this is the verifier and not the image)\n'
  fi
  for v in OMARCHY_PATH MOARCHY_PATH; do
    val=$(echo "$login_env" | sed -n "s/^$v=//p")
    [ "$val" != "<unset>" ] && [ -n "$val" ] \
      && ok "$v=$val in the session" || no "$v is unset in the session"
  done
fi

# Anything else this device needs to be true of its rootfs, if it has any.
# sargo does: without qbootctl marking the boot slot, the bootloader stops
# booting the phone after a few reboots (D26), and that is invisible in every
# other check here because the image is otherwise perfect.
declare -F verify_rootfs >/dev/null && verify_rootfs

# How this device grows into the storage it was flashed onto. A card that may
# be bigger than the image, or a fixed vendor partition -- different enough
# that the backend owns it (docs/devices.md D12).
verify_grow

sec "result"
if [ $FAIL = 0 ]; then
  printf '  \033[32mall checks passed\033[0m\n'
else
  printf '  \033[31msome checks failed\033[0m\n'
fi
exit $FAIL

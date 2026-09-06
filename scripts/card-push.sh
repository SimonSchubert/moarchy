#!/usr/bin/env bash
# Get a phone with no network back online, by editing its SD card on the Mac.
#
#   sudo WIFI_SSID='MyNetwork' WIFI_PSK='secret' ./scripts/card-push.sh
#   sudo ./scripts/card-push.sh --packages packages/*.pkg.tar.*
#
# Why this exists
# ---------------------------------------------------------------------------
# A published image ships sshd disabled and the account's password locked
# (docs/structure.md I6a, I8), which is right: there is no credential to leak.
# The consequence is that a phone which cannot reach wifi cannot be reached
# either -- no SSH, no password to type at a console, and USB networking to a
# Mac does not work (DanctNIX presents RNDIS; the CDC-ECM switch binds but never
# carries). The card is the only route in, and this is that route.
#
# Everything is written with debugfs, so the card is never mounted -- macOS
# cannot mount ext4 anyway -- and nothing here needs a Linux VM.
#
# The PSK arrives in the environment and is written through a 0600 temp file.
# It is never an argument: argv is world-readable in /proc and lands in shell
# history.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E2FS_PREFIX="${E2FS_PREFIX:-/opt/homebrew/opt/e2fsprogs}"
DEBUGFS="$E2FS_PREFIX/sbin/debugfs"
E2FSCK="$E2FS_PREFIX/sbin/e2fsck"
PHONE_USER="${PHONE_USER:-moarchy}"
PHONE_UID="${PHONE_UID:-1000}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519.pub}"

PACKAGES=()
if [[ ${1:-} == "--packages" ]]; then shift; PACKAGES=("$@"); fi

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\033[31m!! %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "needs sudo: reading and writing the raw card requires root"
[[ -x $DEBUGFS ]] || die "missing $DEBUGFS -- run: brew install e2fsprogs"

# The Mac's BUILT-IN reader reports as `internal`, so `diskutil list external`
# finds nothing. Ask the reader itself.
CARD="${CARD:-$(system_profiler SPCardReaderDataType 2>/dev/null |
                sed -n 's/^ *BSD Name: *\(disk[0-9]*\)$/\1/p' | head -1)}"
[[ -n $CARD ]] || die "no SD card found (set CARD=diskN to override)"
PART="/dev/${CARD}s2"
say "card /dev/$CARD, rootfs $PART"

diskutil unmountDisk "/dev/$CARD" >/dev/null 2>&1 || true
"$DEBUGFS" -R "ls /" "$PART" >/dev/null 2>&1 || die "$PART is not a readable ext4 filesystem"

WORK=$(mktemp -d); chmod 700 "$WORK"
CMDS="$WORK/cmds"
trap 'rm -rf "$WORK"' EXIT
: > "$CMDS"

# debugfs `write` refuses an existing target, so every write removes first. The
# rm is allowed to fail: on a first run there is nothing there.
put() {  # put <local> <dest> <mode> <uid> <gid>
  { echo "rm $2"
    echo "write $1 $2"
    echo "sif $2 mode $3"
    echo "sif $2 uid $4"
    echo "sif $2 gid $5"
  } >> "$CMDS"
}
mkdirp() { echo "mkdir $1" >> "$CMDS"; }
chmod_dir() {  # chmod_dir <dir> <mode> <uid> <gid>
  { echo "sif $1 mode $2"; echo "sif $1 uid $3"; echo "sif $1 gid $4"; } >> "$CMDS"
}

# --- wifi ------------------------------------------------------------------
if [[ -n ${WIFI_SSID:-} && -n ${WIFI_PSK:-} ]]; then
  say "preseeding wifi: $WIFI_SSID"
  PROFILE="$WORK/wifi.nmconnection"
  ( umask 077; cat > "$PROFILE" <<EOF
[connection]
id=$WIFI_SSID
type=wifi
autoconnect=true
[wifi]
mode=infrastructure
ssid=$WIFI_SSID
[wifi-security]
key-mgmt=wpa-psk
psk=$WIFI_PSK
[ipv4]
method=auto
[ipv6]
method=auto
EOF
  )
  mkdirp /etc/NetworkManager
  mkdirp /etc/NetworkManager/system-connections
  # 0600 and root-owned, or NetworkManager refuses to load it.
  put "$PROFILE" "/etc/NetworkManager/system-connections/$WIFI_SSID.nmconnection" 0100600 0 0
  info "NetworkManager will autoconnect on boot"
else
  info "WIFI_SSID/WIFI_PSK not set -- skipping the wifi profile"
fi

# --- ssh -------------------------------------------------------------------
# A key, not a password: the account's password is locked and sshd has
# PasswordAuthentication off, so a key is the only thing that can work.
if [[ -f $SSH_KEY ]]; then
  say "authorising $(basename "$SSH_KEY") for $PHONE_USER"
  mkdirp "/home/$PHONE_USER/.ssh"
  put "$SSH_KEY" "/home/$PHONE_USER/.ssh/authorized_keys" 0100600 "$PHONE_UID" "$PHONE_UID"
  chmod_dir "/home/$PHONE_USER/.ssh" 040700 "$PHONE_UID" "$PHONE_UID"
  mkdirp /etc/systemd/system/multi-user.target.wants
  echo "symlink /etc/systemd/system/multi-user.target.wants/sshd.service /usr/lib/systemd/system/sshd.service" >> "$CMDS"
  info "sshd enabled; log in with: ssh $PHONE_USER@<its address>"
else
  info "no key at $SSH_KEY -- skipping SSH (set SSH_KEY=/path/to/key.pub)"
fi

# --- packages --------------------------------------------------------------
if (( ${#PACKAGES[@]} )); then
  say "copying ${#PACKAGES[@]} package(s) to /home/$PHONE_USER/pkgs"
  mkdirp "/home/$PHONE_USER/pkgs"
  chmod_dir "/home/$PHONE_USER/pkgs" 040755 "$PHONE_UID" "$PHONE_UID"
  for p in "${PACKAGES[@]}"; do
    [[ -f $p ]] || die "no such package: $p"
    put "$p" "/home/$PHONE_USER/pkgs/$(basename "$p")" 0100644 "$PHONE_UID" "$PHONE_UID"
    info "$(basename "$p")"
  done
fi

# --- apply -----------------------------------------------------------------
say "writing"
# -w is what makes it read-write; without it every command above is a no-op
# that still prints as though it worked.
"$DEBUGFS" -w -f "$CMDS" "$PART" > "$WORK/log" 2>&1 || true

# Show everything debugfs said except the two expected complaints. An earlier
# version filtered so aggressively that a run which created ~/.ssh and ~/pkgs as
# FILES rather than directories -- so every write beneath them failed -- printed
# nothing at all and reported success. Whatever went wrong must be visible.
grep -vE "File not found while trying to resolve|File exists|^debugfs [0-9]|^debugfs: (rm|write|sif|mkdir|symlink) |^$" \
  "$WORK/log" | sed 's/^/      /' | head -30

# And then prove it, rather than trusting the command file. Each destination is
# stat'd back out of the filesystem and its TYPE checked: the failure that cost
# an afternoon was a directory that turned out to be a regular file, which no
# amount of reading debugfs's output would have shown.
say "verifying what actually landed"
verify_type() {  # verify_type <path> <directory|regular>
  got=$("$DEBUGFS" -R "stat $1" "$PART" 2>/dev/null | sed -n 's/.*Type: *\([a-z]*\).*/\1/p' | head -1)
  if [ "$got" = "$2" ]; then info "ok   $1 ($got)"
  else info "FAIL $1 is '${got:-missing}', expected $2"; VERIFY_FAILED=1; fi
}
VERIFY_FAILED=0
[ -n "${WIFI_SSID:-}" ] && verify_type "/etc/NetworkManager/system-connections/$WIFI_SSID.nmconnection" regular
if [ -f "$SSH_KEY" ]; then
  verify_type "/home/$PHONE_USER/.ssh" directory
  verify_type "/home/$PHONE_USER/.ssh/authorized_keys" regular
fi
if (( ${#PACKAGES[@]} )); then
  verify_type "/home/$PHONE_USER/pkgs" directory
  for p in "${PACKAGES[@]}"; do
    verify_type "/home/$PHONE_USER/pkgs/$(basename "$p")" regular
  done
fi
[ "$VERIFY_FAILED" = 0 ] || die "some writes did not land -- see above; nothing here is safe to rely on"

# --- reconcile and verify --------------------------------------------------
# debugfs updates inodes and directory entries but does NOT reconcile the block
# and inode bitmaps or the superblock's free counts. So a run always leaves the
# filesystem reporting differences like
#
#   Block bitmap differences: -1447432
#   Free blocks count wrong (13840453, counted=13835527)
#
# That is accounting, not damage -- no cross-linked blocks, no unattached
# inodes, no bad directory entries -- and reconciling it is precisely what fsck
# is for. Checking without repairing was worse than useless here: it reported a
# routine consequence of the write as a reason to throw the card away.
#
# -y and not -p: preen mode refuses anything it considers non-trivial and exits
# non-zero, which is the same dead end again.
say "reconciling the filesystem after the write"
"$E2FSCK" -fy "$PART" > "$WORK/fix" 2>&1 || true
grep -E "Free (blocks|inodes) count|bitmap differences" "$WORK/fix" | sed 's/^/    /' | head -6

# The one that decides. A second pass has to come back clean; if it does not,
# the problem was never bookkeeping.
if "$E2FSCK" -fn "$PART" > "$WORK/fsck" 2>&1; then
  info "verified clean on a second pass"
else
  info "still not clean after repair:"; tail -20 "$WORK/fsck" | sed 's/^/      /'
  die "this is not bitmap drift -- do NOT boot it; re-flash instead"
fi

say "done -- eject the card and boot the phone"
[[ -n ${WIFI_SSID:-} ]] && info "it should join '$WIFI_SSID' on its own"
(( ${#PACKAGES[@]} )) && info "then on the phone: sudo pacman -U ~/pkgs/*.pkg.tar.*"
exit 0

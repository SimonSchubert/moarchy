#!/bin/bash
# First-boot configuration baked into the rootfs (docs/structure.md I6-I8).
#
# Nothing here is a credential. A published image carries no password, no
# preseeded network and no key (I6a); the wifi preseed is opt-in through the
# environment and is for debug images only.
set -euo pipefail
ROOTDIR=$1
USER_NAME=${MOARCHY_USER:-moarchy}

say() { printf '    %s\n' "$*"; }

# --- the user (I8) ---------------------------------------------------------
# DanctNIX ships `alarm` with the password 123456 and root with `root`. Neither
# is in this image. The account is created with a LOCKED password instead:
#
#   - tty1 autologin is how the phone is used, and it does not consult a
#     password, so the phone comes up usable with no secret to leak or change.
#   - sshd is not enabled, and password authentication is off if it is enabled,
#     so a locked password cannot be brute-forced remotely.
#   - sudo is passwordless for this account. On a device with no disk
#     encryption that concedes nothing: anyone holding the phone can read the
#     SD card. It is the same deliberate choice the dev provisioning makes.
#
# Setting a real password is `passwd`, and the user can do it from the terminal
# once the session and its on-screen keyboard are up.
arch-chroot "$ROOTDIR" useradd -m -G wheel,video,audio,input,feedbackd -s /bin/bash "$USER_NAME"
arch-chroot "$ROOTDIR" passwd -l "$USER_NAME" >/dev/null
arch-chroot "$ROOTDIR" passwd -l root >/dev/null
# Autologin, written HERE rather than left to moarchy-firstboot.
#
# firstboot writes the same file, but it races getty@tty1: on the very first
# boot getty had already started from the packaged default, so the phone came up
# at a `moarchy login:` prompt -- with a locked password, and therefore no way
# in at all until a reboot. Observed on hardware 2026-09-06.
#
# The image build knows the username, so there is no reason to defer it. What
# firstboot does is now only what genuinely needs a running system.
install -d "$ROOTDIR/etc/systemd/system/getty@tty1.service.d"
cat >"$ROOTDIR/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin $USER_NAME %I \$TERM
EOF

printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$USER_NAME" > "$ROOTDIR/etc/sudoers.d/10-moarchy"
chmod 440 "$ROOTDIR/etc/sudoers.d/10-moarchy"
say "user $USER_NAME (locked password, passwordless sudo, root locked)"

# sshd off by default, and no password logins if someone turns it on.
install -d "$ROOTDIR/etc/ssh/sshd_config.d"
cat >"$ROOTDIR/etc/ssh/sshd_config.d/10-moarchy.conf" <<EOF
# A published image ships no password, so password auth could only ever
# succeed against one the user set themselves. Keys only.
PasswordAuthentication no
PermitRootLogin no
EOF
rm -f "$ROOTDIR/etc/systemd/system/multi-user.target.wants/sshd.service"

echo "$USER_NAME" > "$ROOTDIR/etc/hostname"
ln -sf /usr/share/zoneinfo/UTC "$ROOTDIR/etc/localtime"
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' "$ROOTDIR/etc/locale.gen"
arch-chroot "$ROOTDIR" locale-gen >/dev/null 2>&1 || true
echo 'LANG=en_US.UTF-8' > "$ROOTDIR/etc/locale.conf"

# --- grow the rootfs on first boot (I7) ------------------------------------
# The image is sized to its contents plus slack so the download stays small;
# the card is whatever the user put in. sfdisk grows the last partition and
# resize2fs follows it, both online.
install -Dm755 "$(dirname "$0")/moarchy-grow-rootfs" \
  "$ROOTDIR/usr/lib/moarchy/bin/moarchy-grow-rootfs"

cat >"$ROOTDIR/usr/lib/systemd/system/moarchy-grow-rootfs.service" <<'EOF'
[Unit]
Description=Grow the rootfs to fill the card
DefaultDependencies=no
After=systemd-remount-fs.service
Before=systemd-user-sessions.service
ConditionPathExists=!/var/lib/moarchy/grown

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/lib/moarchy/bin/moarchy-grow-rootfs
ExecStartPost=/usr/bin/install -Dm644 /dev/null /var/lib/moarchy/grown

[Install]
WantedBy=sysinit.target
EOF
arch-chroot "$ROOTDIR" systemctl enable moarchy-grow-rootfs.service >/dev/null 2>&1
say "rootfs grows to fill the card on first boot"

# --- wifi preseed, debug images only (I6/I6a) ------------------------------
if [ -n "${WIFI_SSID:-}" ] && [ -n "${WIFI_PSK:-}" ]; then
  install -d -m 700 "$ROOTDIR/etc/NetworkManager/system-connections"
  cat >"$ROOTDIR/etc/NetworkManager/system-connections/$WIFI_SSID.nmconnection" <<EOF
[connection]
id=$WIFI_SSID
type=wifi
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
  chmod 600 "$ROOTDIR/etc/NetworkManager/system-connections/$WIFI_SSID.nmconnection"
  # Turning sshd back on is the whole point of a debug image: preseeded wifi
  # with no way in is not worth building.
  arch-chroot "$ROOTDIR" systemctl enable sshd.service >/dev/null 2>&1 || true
  touch "$ROOTDIR/etc/moarchy-debug-image"
  say "DEBUG IMAGE: wifi '$WIFI_SSID' preseeded and sshd enabled -- do not publish this"
else
  say "no credentials baked in (publishable)"
fi

# --- fstab -----------------------------------------------------------------
# By label, not UUID: mkfs.ext4 set them, and u-boot's boot.txt passes
# root=/dev/mmcblkXpN itself, so nothing here has to know the device.
cat >"$ROOTDIR/etc/fstab" <<'EOF'
LABEL=rootfs  /       ext4  rw,relatime  0 1
LABEL=BOOT    /boot   vfat  rw,relatime  0 2
EOF

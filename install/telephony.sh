#!/bin/bash
# Calls and SMS on the PinePhone's Quectel EG25-G modem.
#
# ---------------------------------------------------------------------------
# What is already there
# ---------------------------------------------------------------------------
# DanctNIX images ship eg25-manager (enabled) and a patched alsa-ucm-conf that
# carries the Allwinner/A64/PinePhone UCM profile. Between them the modem is
# powered and enumerated (/dev/ttyUSB0-3 + /dev/cdc-wdm0) and the audio routes
# for a call already exist. This script adds the layer above: the daemon that
# drives the modem, the two adaptive GTK apps, and call audio switching.
#
# ---------------------------------------------------------------------------
# Why the units are replaced rather than enabled
# ---------------------------------------------------------------------------
# gnome-calls and chatty ship systemd user units written for GNOME:
#
#   Requisite=gnome-session-initialized.target
#
# Requisite= fails a unit immediately unless that target is ALREADY active, and
# under sway it never exists -- so both daemons would sit "enabled" and fail on
# every single start. A drop-in does not fix it: systemd reads the override but
# an empty `Requisite=` does not clear the inherited list (verified on-device;
# `systemctl show` still reported the GNOME dependency afterwards). A unit of
# the same name in ~/.config/systemd/user takes precedence, so default/systemd/
# carries full replacements hung off sway-session.target instead.
#
# This matters because it is the difference between working and silently not:
# without the daemons running, nothing is listening on D-Bus and incoming calls
# never ring and incoming SMS is never received. Outgoing still works, which is
# exactly the sort of half-broken that goes unnoticed.

echo "==> telephony"

sudo systemctl enable --now ModemManager.service 2>/dev/null || \
  echo "    !! could not enable ModemManager" >&2

# eg25-manager owns modem power and the GPIO dance. DanctNIX enables it already;
# make sure, because nothing else brings the modem up.
sudo systemctl enable --now eg25-manager.service 2>/dev/null || true

mkdir -p ~/.config/systemd/user
for unit in calls-daemon.service sm.puri.Chatty-daemon.service; do
  cp "$MOARCHY_PATH/default/systemd/$unit" ~/.config/systemd/user/
done

systemctl --user daemon-reload 2>/dev/null || true
# mmsd-tng (MMS) enables itself into default.target from its package.
systemctl --user enable calls-daemon.service sm.puri.Chatty-daemon.service 2>/dev/null || \
  echo "    !! could not enable the call/SMS daemons" >&2

# callaudiod needs no unit -- it is D-Bus activated on org.mobian_project.CallAudio
# and starts when gnome-calls first routes a call.

echo "    ModemManager + calls/SMS daemons enabled"
if mmcli -L 2>/dev/null | grep -q Modem; then
  echo "    modem detected: $(mmcli -L 2>/dev/null | sed -n 's/.*\[\(.*\)\].*/\1/p' | head -1)"
else
  echo "    no modem yet -- check 'mmcli -L' once the session is up"
fi

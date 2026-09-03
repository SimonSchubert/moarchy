#!/bin/bash
# Autologin on tty1 and start Sway from the login shell -- the same shape
# DanctNIX's own images use, and far lighter than SDDM on 2-3 GB of RAM.

echo "==> session"

USER_NAME=$(id -un)

sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf >/dev/null <<EOF2
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin $USER_NAME %I \$TERM
EOF2

# Start Sway on tty1 only, so SSH sessions stay plain shells.
if ! grep -q "exec sway" ~/.bash_profile 2>/dev/null; then
  cat >>~/.bash_profile <<'EOF3'

# mobileomarchy: start the session on the phone's own screen only
if [[ -z $WAYLAND_DISPLAY && $XDG_VTNR == 1 ]]; then
  [[ -f ~/.profile ]] && source ~/.profile
  export XDG_CURRENT_DESKTOP=sway
  export XDG_SESSION_TYPE=wayland
  export MOZ_ENABLE_WAYLAND=1
  export QT_QPA_PLATFORM=wayland
  export ELECTRON_OZONE_PLATFORM_HINT=wayland
  exec sway
fi
EOF3
fi

# lisgd synthesises swipe gestures by reading the touchscreen's evdev node
# directly -- Sway's own bindgesture only sees libinput gesture events, which
# come from touchpads and never from a touchscreen. Reading /dev/input/event*
# needs the `input` group, and the group membership only takes effect on the
# next login.
#
# The trade this makes: anything running as this user can then read every input
# device, keyboard included. On a single-user phone that is the accepted cost,
# and it is what sxmo and the other PinePhone environments do.
sudo usermod -aG input "$USER_NAME"

# The power button. The AXP803's PEK emits KEY_POWER on a short press, and
# logind turns that into a shutdown by default -- a reasonable desktop default
# and a bad phone one, because this is the single button on the device and the
# one you lean on by accident. Sway binds the key itself (default/sway/
# pinephone.conf) to blank and unblank the screen, so logind has to let the
# short press through untouched.
#
# The long press is kept as poweroff, which is what you want when you do mean
# it, and it is not logind's default (that is `ignore`). Below both, the PMIC's
# own ~10s hold still cuts power in hardware if everything above is wedged.
sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee /etc/systemd/logind.conf.d/10-power-key.conf >/dev/null <<'EOF4'
[Login]
HandlePowerKey=ignore
HandlePowerKeyLongPress=poweroff
EOF4

sudo systemctl daemon-reload
sudo systemctl enable NetworkManager bluetooth 2>/dev/null || true
systemctl --user enable pipewire pipewire-pulse wireplumber 2>/dev/null || true

echo "    autologin + sway session configured"

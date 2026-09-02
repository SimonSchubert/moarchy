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

sudo systemctl daemon-reload
sudo systemctl enable NetworkManager bluetooth 2>/dev/null || true
systemctl --user enable pipewire pipewire-pulse wireplumber 2>/dev/null || true

echo "    autologin + sway session configured"

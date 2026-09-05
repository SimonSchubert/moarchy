#!/bin/bash
# mobileomarchy installer -- run ON the phone, over SSH.
#
#   ssh alarm@<the phone's wifi address>
#   git clone https://github.com/<you>/mobileomarchy ~/.local/share/mobileomarchy
#   ~/.local/share/mobileomarchy/install.sh
#
# This deliberately does NOT run upstream Omarchy's installer. That installer
# guards on x86_64, limine, btrfs and vanilla-Arch markers, and pulls from an
# x86_64-only package repo. We vendor Omarchy's config/theme layer instead.

set -eEo pipefail

export MOBILEOMARCHY_PATH="${MOBILEOMARCHY_PATH:-$HOME/.local/share/mobileomarchy}"
export MOBILEOMARCHY_INSTALL="$MOBILEOMARCHY_PATH/install"
export OMARCHY_PATH="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"

# Ours first, so our shims shadow the Hyprland-specific upstream scripts.
export PATH="$MOBILEOMARCHY_PATH/bin:$OMARCHY_PATH/bin:$PATH"

echo "==> mobileomarchy install"
source "$MOBILEOMARCHY_INSTALL/preflight.sh"
source "$MOBILEOMARCHY_INSTALL/packages.sh"
source "$MOBILEOMARCHY_INSTALL/build-src.sh"
source "$MOBILEOMARCHY_INSTALL/vendor-omarchy.sh"
source "$MOBILEOMARCHY_INSTALL/port-4x.sh"
source "$MOBILEOMARCHY_INSTALL/config.sh"
source "$MOBILEOMARCHY_INSTALL/session.sh"
source "$MOBILEOMARCHY_INSTALL/telephony.sh"

echo
echo "==> Done. Reboot, or start the session now with:  exec sway"

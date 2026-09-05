#!/bin/bash
# moarchy installer -- run ON the phone, over SSH.
#
#   ssh alarm@<the phone's wifi address>
#   git clone https://github.com/<you>/moarchy ~/.local/share/moarchy
#   ~/.local/share/moarchy/install.sh
#
# This deliberately does NOT run upstream Omarchy's installer. That installer
# guards on x86_64, limine, btrfs and vanilla-Arch markers, and pulls from an
# x86_64-only package repo. We vendor Omarchy's config/theme layer instead.

set -eEo pipefail

export MOARCHY_PATH="${MOARCHY_PATH:-$HOME/.local/share/moarchy}"
export MOARCHY_INSTALL="$MOARCHY_PATH/install"
export OMARCHY_PATH="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"

# Ours first, so our shims shadow the Hyprland-specific upstream scripts.
export PATH="$MOARCHY_PATH/bin:$OMARCHY_PATH/bin:$PATH"

echo "==> moarchy install"
source "$MOARCHY_INSTALL/preflight.sh"
source "$MOARCHY_INSTALL/packages.sh"
source "$MOARCHY_INSTALL/build-src.sh"
source "$MOARCHY_INSTALL/vendor-omarchy.sh"
source "$MOARCHY_INSTALL/port-4x.sh"
source "$MOARCHY_INSTALL/config.sh"
source "$MOARCHY_INSTALL/session.sh"
source "$MOARCHY_INSTALL/telephony.sh"

echo
echo "==> Done. Reboot, or start the session now with:  exec sway"

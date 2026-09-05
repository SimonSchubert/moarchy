#!/usr/bin/env bash
# End-to-end provisioning for moarchy, driven from a macOS host.
#
#   ./scripts/provision.sh all          # everything (pauses at the flash step)
#   ./scripts/provision.sh <step>       # run one step
#   ./scripts/provision.sh steps        # list steps
#
# Steps are independent and idempotent, so you can re-run any of them. The only
# step that cannot be automated is `flash`: it needs `sudo dd`, and sudo on macOS
# requires a real terminal. Everything after `flash` talks to the phone over SSH.
#
# Configuration (environment):
#   PHONE       ssh target                (default alarm@192.168.0.18, over wifi)
#   DISK        SD card device            (e.g. /dev/disk28) -- required for `flash`
#   WIFI_SSID   preseed this wifi network into the image (optional)
#   WIFI_PSK    its password (pass via env, never as an argument)
#
# Wifi is the only way in. USB networking to a Mac does not work: DanctNIX's
# gadget presents RNDIS, which macOS cannot drive, and switching it to CDC-ECM
# gets the interface bound but never carrying. Preseeding saves one round trip
# with a USB keyboard and `nmtui`; it is not otherwise required.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

. "$REPO_ROOT/scripts/manifest.sh"

PHONE="${PHONE:-alarm@192.168.0.18}"
# One pin, read here and in scripts/flash-sd.sh, rather than the same date
# written out in both (docs/structure.md V1).
RELEASE="${RELEASE:-$(manifest_get danctnix release)}"
[[ -n $RELEASE ]] || exit 1
CACHE="${CACHE:-$HOME/Downloads/moarchy}"
IMG="$CACHE/archlinux-pinephone-barebone-${RELEASE}.img"
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10)

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\033[31m!! %s\033[0m\n' "$*" >&2; exit 1; }

phone() { ssh "${SSH_OPTS[@]}" "$PHONE" "$@"; }

# ---------------------------------------------------------------------------
step_prereqs() {
  say "prerequisites"
  command -v xz >/dev/null      || die "xz missing (brew install xz)"
  [[ -x /opt/homebrew/opt/e2fsprogs/sbin/debugfs ]] ||
    die "e2fsprogs missing (brew install e2fsprogs) -- needed to edit the ext4 rootfs"
  info "xz, e2fsprogs present"

  if docker info >/dev/null 2>&1; then
    info "docker running ($(docker info --format '{{.Architecture}}')) -- packages will build natively"
  else
    info "docker NOT running -- start Docker Desktop, or the phone will build"
    info "  moarchy-keyboard itself (slow on a 1.15GHz A53)"
  fi
}

step_image() {
  say "preseed wifi into the image"
  if [[ -z ${WIFI_SSID:-} || -z ${WIFI_PSK:-} ]]; then
    info "WIFI_SSID/WIFI_PSK not set -- skipping."
    info "  The image is flashed as downloaded; join the network with nmtui on"
    info "  the phone, which needs a USB keyboard once."
    return 0
  fi
  info "wifi preseed: $WIFI_SSID"
  ./scripts/patch-image.sh "$CACHE/archlinux-pinephone-barebone-${RELEASE}.img.xz"
}

step_flash() {
  say "flash SD card"
  [[ -n ${DISK:-} ]] || {
    diskutil list external physical 2>/dev/null || diskutil list
    die "set DISK=/dev/diskN (see listing above) and re-run"
  }
  cat <<EOS
    This step needs 'sudo dd', which requires a real terminal.
    Run it yourself in Terminal/iTerm:

      IMAGE_FILE="$IMG" ./scripts/flash-sd.sh $DISK

    Then put the card in the phone, boot it, and continue with:

      ./scripts/provision.sh deploy
EOS
}

step_build() {
  # The names come from the manifest rather than from this string: a hand-kept
  # list in a progress message is still a list, and it is the one nobody
  # updates. cbonsai was missing from it for exactly that reason.
  say "build aarch64 packages (moarchy-keyboard, $(manifest_aur_packages | tr '\n' ' ' | sed 's/ $//'))"
  docker info >/dev/null 2>&1 || die "Docker is not running"
  docker build --platform linux/arm64 -f docker/Dockerfile.builder -t moarchy-builder . >/dev/null
  mkdir -p packages
  docker run --rm --platform linux/arm64 -v "$PWD/packages:/out" moarchy-builder
  info "built: $(ls -1 packages/*.pkg.tar.* 2>/dev/null | wc -l | tr -d ' ') packages"
  info "  (the components, the AUR rebuilds, and pkgbuilds/: moarchy,"
  info "   omarchy-config and moarchy-meta)"
}

step_deploy() {
  say "ship the built packages to $PHONE"
  phone true 2>/dev/null || die "cannot reach $PHONE -- set PHONE=alarm@<ip> (the phone's wifi address; key auth via ssh-copy-id)"

  # Passwordless sudo, so the install does not stall on a prompt.
  if ! phone 'sudo -n true' 2>/dev/null; then
    info "installing sudoers drop-in (remove later with: sudo rm /etc/sudoers.d/10-moarchy)"
    phone 'echo 123456 | sudo -S -k sh -c "echo \"$(id -un) ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/10-moarchy && chmod 440 /etc/sudoers.d/10-moarchy && visudo -c -q"' 2>/dev/null ||
      die "could not enable passwordless sudo (is the password still the default?)"
  fi

  # Rename migration, one release only. A phone
  # provisioned before 2026-09-05 has 10-mobileomarchy, and the guard above
  # skips right past it -- `sudo -n true` succeeds precisely *because* that
  # file is there. Write the new drop-in and prove it parses before removing
  # the old one: passwordless sudo is deliberate here, and the window where
  # neither file grants it is the one thing this must not open.
  if phone 'test -f /etc/sudoers.d/10-mobileomarchy' 2>/dev/null; then
    info "renaming sudoers drop-in 10-mobileomarchy -> 10-moarchy"
    phone 'sudo sh -c "echo \"$(id -un) ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/10-moarchy && chmod 440 /etc/sudoers.d/10-moarchy && visudo -c -q && rm -f /etc/sudoers.d/10-mobileomarchy"' 2>/dev/null ||
      info "!! could not rename the sudoers drop-in; 10-mobileomarchy is still in place and still works"
  fi

  # The working tree used to be tarred up and unpacked into
  # ~/.local/share/moarchy, which put files on the phone that no package owned
  # -- exactly what docs/structure.md D2 rules out. Only built packages cross
  # now, and pacman owns every file they place.
  compgen -G "packages/*.pkg.tar.*" >/dev/null ||
    die "no packages built -- run './scripts/provision.sh build' first"

  phone 'rm -rf ~/pkgs && mkdir -p ~/pkgs'
  scp "${SSH_OPTS[@]}" -q packages/*.pkg.tar.* "$PHONE:pkgs/"
  info "shipped $(ls -1 packages/*.pkg.tar.* | wc -l | tr -d ' ') packages"
  info "deployed"
}

step_install() {
  say "install the packages on the phone"

  # This used to run install.sh on the phone as a detached systemd unit, with
  # three environment details that each cost a full run to find -- HOME, the
  # uid/gid to write user config as, and XDG_RUNTIME_DIR for `systemctl --user`.
  # None of them exist any more. The packages own the files, systemd owns the
  # per-user step, and this is one pacman transaction (docs/structure.md M2).
  #
  # -U rather than -S because there is no published repo yet; M3 is what turns
  # this into `pacman -S moarchy-meta`.
  phone 'sudo pacman -U --needed --noconfirm ~/pkgs/*.pkg.tar.*' ||
    die "pacman failed -- run './scripts/provision.sh watch' or check the output above"

  info "installed. reboot the phone, or start the session with: exec sway"
  info "first boot runs moarchy-firstboot (groups, autologin) and"
  info "moarchy-user-setup (app configs, initial theme) automatically"
}


step_watch() {
  # There is nothing to watch any more. The install was a 21-minute detached
  # unit compiling Go and Qt6 on an A53; it is a pacman transaction now, and
  # `install` reports its own result.
  say "nothing to watch -- 'install' is a single pacman transaction and is synchronous"
  phone 'systemctl --no-pager --failed 2>/dev/null; echo; systemctl --user --no-pager --failed 2>/dev/null' || true
}

step_verify() {
  say "verify"
  phone 'export MOARCHY_PATH=$HOME/.local/share/moarchy OMARCHY_PATH=$HOME/.local/share/omarchy
    export PATH="$MOARCHY_PATH/bin:$OMARCHY_PATH/bin:$PATH"
    export XDG_RUNTIME_DIR=/run/user/$(id -u)
    echo "  GPU:        $(EGL_PLATFORM=surfaceless eglinfo 2>/dev/null | sed -n "s/^OpenGL ES profile version: //p" | head -1)"
    echo "  sway -C:    $(WLR_BACKENDS=headless sway -C -c ~/.config/sway/config >/dev/null 2>&1 && echo PASS || echo FAIL)"
    echo "  themes:     $(ls $OMARCHY_PATH/themes 2>/dev/null | wc -l | tr -d " ") vendored"
    echo "  omarchy at: $(git -C $OMARCHY_PATH describe --tags 2>/dev/null)"
    for p in sway quickshell moarchy-keyboard swaybg swayidle; do
      printf "  %-10s %s\n" "$p" "$(pgrep -x $p >/dev/null && echo running || echo -)"
    done'
}

step_screenshot() {
  say "screenshot"
  phone 'export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1; grim /tmp/moa-shot.png'
  scp "${SSH_OPTS[@]}" -q "$PHONE:/tmp/moa-shot.png" ./moa-shot.png
  info "saved ./moa-shot.png"
}

# ---------------------------------------------------------------------------
STEPS=(prereqs image flash build deploy install watch verify screenshot)

case "${1:-all}" in
  steps) printf '%s\n' "${STEPS[@]}" ;;
  all)
    step_prereqs; step_image; step_build; step_flash
    echo; info "run 'deploy', 'install', 'watch', 'verify' once the phone is booted."
    ;;
  *)
    fn="step_${1}"
    declare -F "$fn" >/dev/null || die "unknown step '$1' (see: $0 steps)"
    "$fn"
    ;;
esac

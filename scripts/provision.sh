#!/usr/bin/env bash
# End-to-end provisioning for mobileomarchy, driven from a macOS host.
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
#   PHONE       ssh target                (default alarm@10.15.19.82, USB/ECM)
#   DISK        SD card device            (e.g. /dev/disk28) -- required for `flash`
#   WIFI_SSID   preseed this wifi network into the image (optional but recommended)
#   WIFI_PSK    its password (pass via env, never as an argument)
#
# Why wifi matters: USB networking to a Mac is unreliable even after the image is
# patched from RNDIS to CDC-ECM -- macOS binds the interface but the gadget side
# never gains carrier. Preseeding wifi gives a second, working way in.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PHONE="${PHONE:-alarm@10.15.19.82}"
RELEASE="${RELEASE:-20251224}"
CACHE="${CACHE:-$HOME/Downloads/mobileomarchy}"
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
    info "  walker/elephant itself (slow on a 1.15GHz A53)"
  fi
}

step_image() {
  say "fetch + patch image"
  local args=()
  [[ -n ${WIFI_SSID:-} ]] && info "wifi preseed: $WIFI_SSID"
  ./scripts/patch-image.sh "$CACHE/archlinux-pinephone-barebone-${RELEASE}.img.xz" "${args[@]}"
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
  say "build aarch64 packages (walker, elephant, yay, xdg-terminal-exec, ttf-ia-writer)"
  docker info >/dev/null 2>&1 || die "Docker is not running"
  docker build --platform linux/arm64 -f docker/Dockerfile.builder -t mobileomarchy-builder . >/dev/null
  mkdir -p packages
  docker run --rm --platform linux/arm64 -v "$PWD/packages:/out" mobileomarchy-builder
  info "built: $(ls -1 packages/*.pkg.tar.* 2>/dev/null | wc -l | tr -d ' ') packages"
}

step_deploy() {
  say "deploy repo + packages to $PHONE"
  phone true 2>/dev/null || die "cannot reach $PHONE (set PHONE=alarm@<ip>; key auth via ssh-copy-id)"

  # Passwordless sudo, so the long install steps do not stall on a prompt.
  if ! phone 'sudo -n true' 2>/dev/null; then
    info "installing sudoers drop-in (remove later with: sudo rm /etc/sudoers.d/10-mobileomarchy)"
    phone 'echo 123456 | sudo -S -k sh -c "echo \"$(id -un) ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/10-mobileomarchy && chmod 440 /etc/sudoers.d/10-mobileomarchy && visudo -c -q"' 2>/dev/null ||
      die "could not enable passwordless sudo (is the password still the default?)"
  fi

  local tarball; tarball=$(mktemp -t moa).tar.gz
  tar --exclude='.git' --exclude='packages' -czf "$tarball" .
  scp "${SSH_OPTS[@]}" -q "$tarball" "$PHONE:/tmp/moa.tar.gz"
  rm -f "$tarball"
  phone 'mkdir -p ~/.local/share/mobileomarchy && tar xzf /tmp/moa.tar.gz -C ~/.local/share/mobileomarchy && rm /tmp/moa.tar.gz'

  if compgen -G "packages/*.pkg.tar.*" >/dev/null; then
    phone 'mkdir -p ~/.local/share/mobileomarchy/packages'
    scp "${SSH_OPTS[@]}" -q packages/*.pkg.tar.* "$PHONE:/home/$(phone 'id -un')/.local/share/mobileomarchy/packages/"
    info "shipped prebuilt packages"
  fi
  info "deployed"
}

step_install() {
  say "run installer on the phone (long -- runs as a detached systemd unit)"

  # Clear the log first, and as root. A previous run -- or an older
  # provision.sh that ran this unit as root -- leaves /tmp/moa-install.log
  # owned by root:root, and the redirect below then fails for the
  # unprivileged user before bash executes a single line. That looks exactly
  # like the installer erroring instantly on its own first source.
  phone 'sudo rm -f /tmp/moa-install.log; sudo systemctl reset-failed moa-install 2>/dev/null; true'

  # Detached, so a `pacman -Syu` that restarts sshd cannot kill the install
  # halfway. Three details, each of which cost a full run to find:
  #
  #   --uid/--gid  install.sh writes user config to ~/.config and ~/.local and
  #                calls sudo itself for the system parts. Run the unit bare as
  #                root and every one of those lands in /root instead.
  #   --setenv     systemd sets no HOME for a system unit, so install.sh's
  #                `${MOBILEOMARCHY_PATH:-$HOME/.local/share/...}` expanded to
  #                `/.local/share/...` and it died on the first source.
  #   XDG_...    `systemctl --user enable` needs XDG_RUNTIME_DIR to find the
  #                user manager. Without it install/telephony.sh silently fails
  #                to enable the call and SMS daemons -- and its own comment
  #                names that failure mode: the phone never rings and incoming
  #                SMS is dropped, while outgoing still works.
  #   no --collect a collected unit is unloaded the moment it finishes, and
  #                `systemctl show` then answers from defaults -- reporting
  #                Result=success for a run that exited 1. Without it the failed
  #                unit stays inspectable; the reset-failed above covers re-runs.
  #
  # $HOME, $(id -u) and $(id -g) expand on the phone, in the login shell, which
  # is the one place they are reliably correct.
  phone 'sudo systemd-run --unit=moa-install --no-block --service-type=oneshot \
           --property=TimeoutStartSec=10800 \
           --uid=$(id -u) --gid=$(id -g) \
           --setenv=HOME=$HOME --setenv=XDG_RUNTIME_DIR=/run/user/$(id -u) \
           bash -c "cd $HOME/.local/share/mobileomarchy && ./install.sh > /tmp/moa-install.log 2>&1"' >/dev/null
  info "started. follow with:  ./scripts/provision.sh watch"
}


step_watch() {
  say "watching installer"
  while true; do
    local state; state=$(phone 'systemctl is-active moa-install 2>/dev/null' || echo unknown)
    printf '\r    state=%-12s %s' "$state" "$(phone 'sudo tail -1 /tmp/moa-install.log 2>/dev/null' | cut -c1-60)"
    [[ $state == activating || $state == active ]] || break
    sleep 15
  done
  echo
  phone 'sudo tail -20 /tmp/moa-install.log 2>/dev/null'
}

step_verify() {
  say "verify"
  phone 'export MOBILEOMARCHY_PATH=$HOME/.local/share/mobileomarchy OMARCHY_PATH=$HOME/.local/share/omarchy
    export PATH="$MOBILEOMARCHY_PATH/bin:$OMARCHY_PATH/bin:$PATH"
    export XDG_RUNTIME_DIR=/run/user/$(id -u)
    echo "  GPU:        $(EGL_PLATFORM=surfaceless eglinfo 2>/dev/null | sed -n "s/^OpenGL ES profile version: //p" | head -1)"
    echo "  sway -C:    $(WLR_BACKENDS=headless sway -C -c ~/.config/sway/config >/dev/null 2>&1 && echo PASS || echo FAIL)"
    echo "  themes:     $(ls $OMARCHY_PATH/themes 2>/dev/null | wc -l | tr -d " ") vendored"
    echo "  omarchy at: $(git -C $OMARCHY_PATH describe --tags 2>/dev/null)"
    for p in sway waybar mako swaybg swayidle; do
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

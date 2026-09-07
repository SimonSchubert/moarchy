#!/bin/sh
# Authorise a GitHub account's public SSH keys on this phone. RUNS ON THE PHONE.
#
#   curl -sL https://raw.githubusercontent.com/SimonSchubert/moarchy/main/scripts/authorize-ssh.sh | sh -s <github-user>
#
# Why this exists: a reflash wipes /home/moarchy/.ssh, and the account has no
# password -- image/configure.sh locks it, sshd runs with PasswordAuthentication
# off, and publickey is the only thing that can work. So the way back in is
# either the SD card (scripts/card-push.sh, which means taking the card out of
# the phone) or one line typed on the phone itself. This is that line.
#
# The username is required and has NO default. This file lives in a public repo:
# a default would mean every person who pastes the line out of the README
# authorises somebody else's key on their own phone. That is the backdoor
# image/configure.sh refuses to bake into a published image, arriving by a
# different road, and it is refused here for the same reason.
#
# Keys come from https://github.com/<user>.keys -- GitHub's own listing of the
# public keys on an account. Nothing secret crosses the wire, and this repo
# carries no key material of its own to go stale.
#
# POSIX sh on purpose: it is fetched and piped, so the shebang above is only
# honoured when the file is run directly, and `| sh` has to be the truth.

set -eu

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\033[31m!! %s\033[0m\n' "$*" >&2; exit 1; }

GH_USER="${1:-}"
if [ -z "$GH_USER" ]; then
  cat >&2 <<'USAGE'
usage: curl -sL <this url> | sh -s <github-username>

Authorises every public SSH key on that GitHub account for the user running
this script. There is deliberately no default account -- name the one whose
keys should be able to log into this phone.
USAGE
  exit 2
fi

KEYS_URL="https://github.com/$GH_USER.keys"

tmp="$(mktemp)"; one="$(mktemp)"
trap 'rm -f "$tmp" "$one"' EXIT INT TERM

# --- fetch ------------------------------------------------------------------
say "fetching $KEYS_URL"
if ! curl -fsSL --max-time 30 "$KEYS_URL" -o "$tmp"; then
  printf '\033[31m!! could not fetch %s\033[0m\n' "$KEYS_URL" >&2
  # A freshly flashed phone that has not reached an NTP server yet has a clock
  # from before every certificate it is shown, and rejects all of them. The
  # error curl prints for that says "certificate is not yet valid", which reads
  # like a server problem and is not one.
  printf '   this phone thinks it is %s -- if the failure mentions a\n' "$(date -u '+%Y-%m-%d %H:%M UTC')" >&2
  printf '   certificate that is not yet valid, that clock is why.\n' >&2
  exit 1
fi
[ -s "$tmp" ] || die "GitHub lists no public keys for '$GH_USER' -- right username?"

# --- validate ---------------------------------------------------------------
# Every line has to parse as a public key before any of them is written. An
# error page saved into authorized_keys locks the account out just as well as
# an empty file does, and does it quietly.
count=0
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  printf '%s\n' "$line" >"$one"
  ssh-keygen -l -f "$one" >/dev/null 2>&1 || die "not a public key: ${line%% *}... -- refusing to write any of them"
  count=$((count + 1))
done <"$tmp"
[ "$count" -gt 0 ] || die "nothing key-shaped came back from $KEYS_URL"
info "$count key(s), all well-formed"

# --- install ----------------------------------------------------------------
AUTH="$HOME/.ssh/authorized_keys"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
[ -f "$AUTH" ] || : >"$AUTH"
chmod 600 "$AUTH"

added=0
already=0
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  # Compare on the base64 blob, not the whole line: the comment field differs
  # between what GitHub serves and what is already on disk, and matching whole
  # lines would append a duplicate of a key that is already trusted every run.
  blob="$(printf '%s\n' "$line" | awk '{print $2}')"
  [ -n "$blob" ] || continue
  if awk -v b="$blob" '$2 == b { found = 1 } END { exit !found }' "$AUTH"; then
    already=$((already + 1))
  else
    printf '%s github:%s\n' "$line" "$GH_USER" >>"$AUTH"
    added=$((added + 1))
  fi
done <"$tmp"
say "authorized_keys: $added added, $already already there ($AUTH)"

# --- sshd -------------------------------------------------------------------
# A published image ships sshd disabled (image/verify.sh checks for exactly
# that), so a key alone is not enough after a reflash.
if systemctl is-enabled --quiet sshd 2>/dev/null && systemctl is-active --quiet sshd 2>/dev/null; then
  info "sshd already enabled and running"
elif sudo -n systemctl enable --now sshd >/dev/null 2>&1; then
  info "sshd enabled and started"
else
  printf '\033[33m   could not start sshd non-interactively; run: sudo systemctl enable --now sshd\033[0m\n'
fi

# --- how to get in ----------------------------------------------------------
say "from the other machine:"
ip -4 -o addr show scope global 2>/dev/null |
  awk -v u="$(id -un)" '{ split($4, a, "/"); printf "    ssh %s@%s        (%s)\n", u, a[1], $2 }'

# A reflash gives the phone a new host key, so the first connection after one
# fails with REMOTE HOST IDENTIFICATION HAS CHANGED. That is this fingerprint
# replacing the old one, not an attack -- compare, then clear the stale entry.
if [ -r /etc/ssh/ssh_host_ed25519_key.pub ]; then
  say "this phone's host key (expect this fingerprint on first connect):"
  info "$(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub)"
  info "if ssh refuses with IDENTIFICATION HAS CHANGED, clear the old one there:"
  info "ssh-keygen -R <this phone's address>"
fi

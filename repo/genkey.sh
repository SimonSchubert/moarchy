#!/usr/bin/env bash
# Create the package signing key. Run once, ever.
#
#   ./repo/genkey.sh
#
# The key signs moarchy.db and every package in it, so that a phone can set
# `SigLevel = Required` and refuse anything that is not ours. Without it the
# only thing standing between a download and root on the phone is HTTPS.
#
# It is generated WITHOUT a passphrase, so `repo-add -s` and the publish script
# can run unattended. That is a deliberate trade and it has a cost: anyone with
# this machine can sign packages as this project. Two things follow from it --
#
#   1. Back the private key up somewhere that is not this laptop. Losing it
#      means every phone in the field rejects updates until it is taught to
#      trust a replacement, which for most people means reflashing.
#   2. Adding a passphrase later costs nothing but a prompt at publish time:
#        gpg --edit-key <fingerprint> passwd
#
# Dedicated to this purpose, not a personal key: package signing and identity
# should not share a key, and this one may one day live on a build machine.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="moarchy package signing"
EMAIL="${MOARCHY_KEY_EMAIL:-moarchy@localhost}"

if gpg --list-secret-keys "$NAME" >/dev/null 2>&1; then
  echo "A signing key already exists:" >&2
  gpg --list-secret-keys --keyid-format=long "$NAME" >&2
  echo >&2
  echo "Refusing to make a second one. Signing with two keys over time means" >&2
  echo "phones trust one and reject packages signed with the other." >&2
  exit 1
fi

echo "==> generating an ed25519 signing key"
# ed25519: small, fast, and what Arch's own packagers use. No expiry, because a
# repo key that silently expires breaks every phone at once with an error that
# reads like corruption.
gpg --batch --quiet --passphrase '' --pinentry-mode loopback \
    --quick-generate-key "$NAME <$EMAIL>" ed25519 sign never

FPR=$(gpg --list-secret-keys --with-colons "$NAME" | awk -F: '/^fpr:/{print $10; exit}')
echo "    fingerprint: $FPR"

# The public half is what ships to phones, so it lives in the repo.
mkdir -p "$REPO_ROOT/repo/keyring"
gpg --export --armor "$FPR" > "$REPO_ROOT/repo/keyring/moarchy.asc"
echo "$FPR" > "$REPO_ROOT/repo/keyring/fingerprint"
echo "    public key -> repo/keyring/moarchy.asc"

cat <<EOF

==> BACK THIS UP NOW

    gpg --export-secret-keys --armor $FPR > ~/moarchy-signing-key.asc

Store that somewhere off this machine. It is the only thing that can sign
updates for phones already in the field.
EOF

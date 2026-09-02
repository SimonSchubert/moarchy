#!/usr/bin/env bash
# Verify that every Omarchy theme renders a valid Sway colour config through
# default/themed/sway.conf.tpl.
#
# Runs anywhere bash and git do -- including macOS, before the card is flashed.
#
#   ./scripts/test-themes.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN="${OMARCHY_PIN:-8fcc9d6048af4cb0e3af8512c78049857a3b53dd}"   # v3.8.4

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "==> fetching Omarchy at ${PIN:0:7}"
git clone --quiet --filter=blob:none --no-checkout \
  https://github.com/basecamp/omarchy "$WORK/omarchy"
git -C "$WORK/omarchy" checkout --quiet --detach "$PIN"

export OMARCHY_PATH="$WORK/omarchy"
FAKE_HOME="$WORK/home"
mkdir -p "$FAKE_HOME/.config/omarchy/themed"
cp "$REPO_ROOT/default/themed/sway.conf.tpl" "$FAKE_HOME/.config/omarchy/themed/"

pass=0 fail=0

for theme in "$OMARCHY_PATH"/themes/*/; do
  name=$(basename "$theme")
  [[ -f $theme/colors.toml ]] || continue

  rm -rf "$FAKE_HOME/.config/omarchy/current/next-theme"
  mkdir -p "$FAKE_HOME/.config/omarchy/current/next-theme"
  cp "$theme/colors.toml" "$FAKE_HOME/.config/omarchy/current/next-theme/"

  HOME="$FAKE_HOME" OMARCHY_PATH="$OMARCHY_PATH" \
    bash "$OMARCHY_PATH/bin/omarchy-theme-set-templates"

  out="$FAKE_HOME/.config/omarchy/current/next-theme/sway.conf"
  lines=$(grep -c '^client\.' "$out" 2>/dev/null || echo 0)
  malformed=$(grep '^client\.' "$out" 2>/dev/null |
    grep -vcE '^client\.[a-z_]+( +#[0-9a-fA-F]{6}){1,5} *$' || true)

  if [[ -f $out && $lines -eq 6 && ${malformed:-0} -eq 0 ]] && ! grep -q '{{' "$out"; then
    printf "  ok   %-18s accent=%s\n" "$name" "$(awk '/^client\.focused /{print $2}' "$out")"
    pass=$((pass + 1))
  else
    printf "  FAIL %-18s (client lines=%s malformed=%s)\n" "$name" "$lines" "${malformed:-0}"
    grep '{{' "$out" 2>/dev/null | head -2
    fail=$((fail + 1))
  fi
done

echo
echo "==> $pass passed, $fail failed"
(( fail == 0 ))

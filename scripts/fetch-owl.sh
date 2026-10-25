#!/usr/bin/env bash
# The OWL runtime at manifest.toml's pin, into default/omarchy/plugins/moarchy.owl/
# where the package puts it (docs/owl.md OW1) -- for linting home's OWL files and
# for deploying to a phone by hand. Gitignored: the package fetches its own copy
# and checks it against pkgbuilds/moarchy/PKGBUILD's sums, as this does.
#
#   ./scripts/fetch-owl.sh

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/scripts/manifest.sh"
MANIFEST_FILE="$ROOT/manifest.toml"
ref=$(manifest_get omarchy-widgets ref)
url=$(manifest_get omarchy-widgets url)
raw="${url/github.com/raw.githubusercontent.com}/$ref"
dest="$ROOT/default/omarchy/plugins/moarchy.owl"
files=(Owl.js OwlLayout.js OwlCanvas.qml OwlHost.qml OwlNode.qml OwlSource.qml OwlTerminal.qml OwlWidget.qml owl-source)
# The PKGBUILD's sums, in its order: the runtime's nine, then the licence.
mapfile -t sums < <(sed -n "/^sha256sums=(/,/)/p" "$ROOT/pkgbuilds/moarchy/PKGBUILD" | grep -oE "[0-9a-f]{64}")
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for i in "${!files[@]}"; do
  f=${files[$i]}
  curl -fsSL "$raw/runtimes/quickshell/$f" -o "$tmp/$f"
  got=$(shasum -a 256 "$tmp/$f" 2>/dev/null | cut -d' ' -f1 || sha256sum "$tmp/$f" | cut -d' ' -f1)
  [[ $got == "${sums[$i]}" ]] || { echo "fetch-owl: $f is not the file the PKGBUILD pins" >&2; exit 1; }
done
rm -rf "$dest"; mkdir -p "$dest"
cp "$tmp"/* "$dest/"
chmod 755 "$dest/owl-source"
echo "moarchy.owl at ${ref:0:7}"

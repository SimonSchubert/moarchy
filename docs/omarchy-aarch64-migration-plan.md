# Plan: move from a vendored Omarchy to upstream's aarch64 packages

**Superseded 2026-10-18** by [`mobile-landscape-2026-10.md`](./mobile-landscape-2026-10.md)
and the successor project omarchy-mobile (local, `~/Personal/omarchy-mobile`).
Correction: the shell lives in the `omarchy` package, not `omarchy-settings`,
so "track omarchy-settings only" below would have kept the vendored shell.

**Status: PLAN ONLY, not started (written 2026-10-16).** Waiting for the trigger
in [Gate 0](#gate-0-wait-for-the-packages-on-stable). Background and numbers:
[`omarchy-arm-scan-2026-10.md`](./omarchy-arm-scan-2026-10.md).

## Where we are

moarchy vendors Omarchy's config and theme layer at a pinned ref
(`manifest.toml` `[omarchy]`) into the `omarchy-config` package, adapted for a
phone by `pkgbuilds/omarchy-config/port-4x.patch` (5 files, ~575 lines), and
builds what has no aarch64 binary (`[aur.*]` in the manifest: `yay`,
`xdg-terminal-exec`, `ttf-ia-writer`, ...). `moarchy-meta`'s `depends=()` is the
runtime package set. Everything is pinned in `manifest.toml` (R8: one version of
everything per release directory) and served from the `moarchy` repo (R1-R7).

## What upstream now ships for aarch64 (edge only, 2026-10-16)

| package | what it is | channel |
| --- | --- | --- |
| `omarchy` 4.0.4-2 | the **desktop metapackage**: depends on `omarchy-keyring`, `omarchy-settings=4.0.4`, `hyprland`, `quickshell`, `uwsm`, **`sddm`**, `xdg-desktop-portal-hyprland`, `pipewire`, `wireplumber`, `gnome-keyring`, `gum`, `jq`, `git`, `perl`, `fakeroot`, `pacman-contrib`, `ttf-jetbrains-mono-nerd-basic`, `networkmanager` (the x86 build adds `limine`, `snapper`) | edge |
| `omarchy-settings` 4.0.4-6 | **the config layer**: "user defaults, /etc/skel content, fonts, plymouth theme, and support helpers"; depends on `plymouth` | edge |
| `omarchy-keyring` | the repo signing key | edge |
| `yay`, `xdg-terminal-exec`, `ttf-ia-writer`, `quickshell` 0.3.2, `hyprland` stack | binaries we build or take from Arch Linux ARM today | edge (ttf-ia-writer also stable) |

## Target

- **Track `omarchy-settings`, not `omarchy`.** The metapackage is a laptop desktop:
  `sddm` would replace the tty1 autologin the phone uses, `uwsm` changes how the
  session starts, and on x86 it pulls a bootloader. `moarchy-meta` stays our
  metapackage and depends on `omarchy-settings` plus the phone pieces.
- **`port-4x.patch` shrinks to a phone overlay** that sits on top of upstream's
  files instead of patching them: config fragments, quickshell plugins under
  `default/omarchy/plugins/`, and drop-ins, shipped by the `moarchy` package. What
  is generic (touch, rotation, on-screen keyboard) goes upstream instead.
- **Take binaries from `pkgs.omarchy.org`** where upstream has them (drop our
  builds of `yay`, `xdg-terminal-exec`, `ttf-ia-writer`; consider its
  `quickshell`), keep building only what nobody ships.
- **`omarchy-update` becomes supported**, on a channel we choose (stable).

## Gate 0: wait for the packages on stable

Do not start until all of these hold on **stable** aarch64:

1. `omarchy-settings` and `omarchy-keyring` are on `stable/aarch64`.
2. The `omarchy` metapackage's version is on `stable/aarch64` too. Not to install
   it, but as the signal upstream considers aarch64 releasable.
3. `omarchy-settings` installs on a stock Arch Linux ARM rootfs without pulling
   in anything x86-only.

Check (read-only, no install; the DB is a tar archive):

```
for ch in stable edge; do
  curl -fsSL https://pkgs.omarchy.org/$ch/aarch64/omarchy.db -o /tmp/omarchy-$ch.db &&
  tar -tf /tmp/omarchy-$ch.db | grep -E '^(omarchy|omarchy-settings|omarchy-keyring)-[0-9]' | sed "s|^|$ch: |"
done
```

## Gate 1: the platform question is settled upstream

`omarchy-hw-platform` classifies any device tree with a `qcom,*` compatible as
`aarch64-qualcomm`, the Snapdragon *laptop* family, whose hardware scripts
(`install/hardware/qualcomm/`: Windows firmware extraction, a UKI with device
trees, laptop kernel params) are wrong for a phone booting through Android's ABL.
Before upstream code runs on the phone (installer, `omarchy-update` migrations,
first-run hardware setup), one of these must exist:

- a phone family upstream (`aarch64-<something>`, e.g. by matching phone
  device-tree vendors, or an explicit opt-out), or
- an override honoured by `omarchy-hw-platform` (upstream already lets an image
  build name the platform in an "image-target manifest"; making that work on a
  booted system would do), or
- a guarantee that `omarchy-settings` alone never runs the hardware scripts.

This is a conversation with upstream, and the first contribution worth offering.

## Phases (after both gates)

1. **Inventory `port-4x.patch`.** Classify every hunk as *upstreamable* (generic
   touch/rotation/OSK behaviour), *overlay* (phone-only, expressible as a drop-in
   or plugin), or *obsolete* (upstream already does it). Output: a table in this
   file. The 5 Hyprland-coupled QML files and the bar/launcher changes are the bulk.
2. **Upstream the generic parts** (separate PRs to `omacom/omarchy`, the
   platform family first). Each one merged is a hunk the overlay does not carry.
3. **Build the overlay.** Move the remaining phone behaviour into the `moarchy`
   package as files that override or extend upstream's (no patching of upstream
   files). Prove it against the current pin first, while still vendoring: the
   image must be byte-for-byte equivalent in behaviour.
4. **Add the repo to the image build.** `pacman.conf` stanza for
   `pkgs.omarchy.org/stable/$arch` plus `omarchy-keyring` in the image's trusted
   keys (R9 has the same requirement for our own key). Pinning (R8): record the
   exact `omarchy-settings` and binary versions in `manifest.toml`, and have
   `image/verify.sh` fail if the built image's versions differ, since upstream's
   repo moves and we cannot pin it by commit.
5. **Swap `omarchy-config` for `omarchy-settings`.** `moarchy-meta` depends on
   `omarchy-settings`; `omarchy-config` gets a final release that is empty and
   `replaces`/`conflicts` cleanly so existing phones migrate on `pacman -Syu`.
   Drop the `[aur.yay|xdg-terminal-exec|ttf-ia-writer]` builds and the vendoring
   step for `[omarchy]`.
6. **Turn on `omarchy-update`**, pinned to the stable channel, and remove the
   "Unsupported" rows for it in `docs/settings.md` and `docs/menu-coverage.md`.

## Verification (per phase, on the FP4)

- Image verify passes, including the D30 default-PIN check and the new
  upstream-version check.
- First boot: tty1 autologin into Hyprland, no `sddm`, no plymouth wait.
- The phone UI as today: bar, launcher, settings, on-screen keyboard, rotation
  (D2), lock screen PIN, idle suspend (D28/D29), calls (D33), audio (D32), NFC.
- `omarchy-update` on a phone in the field upgrades without running any
  `aarch64-qualcomm` laptop step (check its log and the boot partition).
- Full flash and the restore kit both still work.

## Risks

- **Misdetection** (Gate 1). The worst case is a migration that writes a UKI or
  touches the boot path on a phone. Mitigate with the gate, plus a moarchy-side
  guard that refuses `aarch64-qualcomm` steps when the device tree says phone.
- **Version skew between repos.** Mixing `pkgs.omarchy.org` with Arch Linux ARM
  (and our own repo) for the Hyprland/quickshell stack. Decide per package which
  repo wins, and keep that in the manifest.
- **Reproducibility.** A moving upstream repo against R8; mitigated by the
  version check in phase 4, at the cost of rebuilds when upstream moves on.
- **Upstream assumes a laptop** in places that are not hardware scripts (screen
  size, keyboard, sddm/uwsm session). The overlay must cover those, and the list
  is unknown until phase 1.
- **sargo / other devices.** This plan is for the FP4 (Hyprland). Upstream's
  Sway-based targets would need their own look.

## Rollback

Until phase 5 nothing is removed: vendoring keeps working beside the overlay.
After phase 5, the previous image (vendored `omarchy-config`) stays a flashable
release, and `omarchy-config` can be re-released with an epoch bump to win back
over `omarchy-settings` if the migration has to be reverted in the field.

# Omarchy on ARM: state of upstream, 2026-10-16

A scan of what upstream Omarchy (`omacom/omarchy`, default branch `quattro`,
pushed 2026-10-16) and its package repo (`pkgs.omarchy.org`) now offer for
aarch64, and what that means for moarchy. It updates the September picture in
`README.md`, `docs/build-log.md`, `docs/structure.md` and `manifest.toml`
(aarch64 repo = "34 packages, app catalog only, no `omarchy` base package"),
which is no longer true.

## The package repo

`https://pkgs.omarchy.org/<channel>/<arch>/omarchy.db`, counted 2026-10-16:

| channel | aarch64 | x86_64 |
| --- | --- | --- |
| stable | **80** (34 in September) | 237 |
| rc | 82 | 235 |
| edge | **196** | 258 |
| dev | 404 (not a package channel, see below) | 404 |

**The `omarchy` base package now exists for aarch64 on edge** (`4.0.4-2`, the
same as x86_64), with `omarchy-keyring`, `omarchy-nvim`, `omarchy-chromium`,
`walker`, `yay`, `xdg-terminal-exec`, and Omarchy's own `hyprland` stack and
`quickshell` builds. Stable aarch64 still has no base package.

aarch64-only packages show who it is for: Apple Silicon (`omarchy-mac`,
`omarchy-mac-boot`, `m1n1-aurora`, `uboot-asahi`, `linux-aurora`, Neural Engine
and MLX packages, `avd-fw`), NVIDIA N1x laptops (`linux-n1x`, `nvidia-open-dkms`,
`cuda`), one ARM laptop's firmware (`asus-proart-p14-speaker-firmware`), and x86
games on ARM (`box64`, `omarchy-steam-fex`, `qemu-user-static`). The 104
x86_64-only names are almost all Intel/NVIDIA-580xx hardware, x86 kernels,
`-debug` splits and proprietary binaries. No phones.

## Upstream code

- **aarch64 is a supported platform.** Upstream AGENTS.md: "Omarchy runs on x86
  and aarch64 (ARM)". Families: `aarch64` (Raspberry Pis, ARM VMs),
  `aarch64-apple`, `aarch64-qualcomm` (Snapdragon laptops), `aarch64-n1x`,
  `aarch64-gb10` (DGX Spark). Feature code asks `omarchy-hw-*` helpers; packages
  are `omarchy-base` + `omarchy-aarch64` (7 lines: zram-generator, rtkit) +
  `omarchy-aarch64-<family>`. "The experience should be the same on every
  platform" -- gaps are meant to be fixed upstream.
- Recent ARM commits: `246f33a2` N1x laptops (10-15), `492b8837` no reboot prompt
  after every update on ARM (10-13), `9a10b488` Superwhisper on aarch64,
  `e1b0e5e9` omarchy-mac merged upstream (10-10), `057681b3` per-arch Node.
- **"dev mode"** is the `dev` channel of `omarchy-channel-set`: it links Omarchy
  to a git checkout in `~/omarchy` (`omarchy-dev-link`), on top of edge packages.
  That is how people run current Omarchy on ARM today.

## What it means for moarchy

1. **Platform detection would misfile a phone.** `omarchy-hw-platform` reads the
   device-tree root `compatible`; any `qcom,*` token means `aarch64-qualcomm`.
   The FP4 (`fairphone,fp4`, `qcom,sm7225`) would be treated as a Snapdragon
   **laptop**: `install/hardware/qualcomm/` extracts firmware from a Windows
   partition (`qcom-firmware-extract`), builds a UKI with device trees
   (`systemd-ukify`, `dtb-uki.sh`) and sets laptop kernel params. The FP4 boots
   through Android's ABL with a `boot.img`; none of that applies and the UKI path
   would be wrong. Harmless while moarchy vendors the config layer and does not
   run upstream's installer or hardware migrations; a blocker the day we adopt
   them. Upstream's image builds already name the platform in an "image-target
   manifest", which may be the hook for a phone family (`aarch64-<family>`).
2. **Three of our own AUR builds now have aarch64 binaries upstream.** `yay` and
   `xdg-terminal-exec` (edge) and `ttf-ia-writer` (stable, `20261002.r63-3`;
   ours is the `20181225-1` AUR pin). Dropping them means adding
   `pkgs.omarchy.org` + `omarchy-keyring` (edge only today) and giving up the
   per-package pins in `manifest.toml` for those three. Not yet: wait until they
   are on stable aarch64 with the keyring.
3. **quickshell version skew.** Omarchy builds `quickshell 0.3.2-6` for aarch64
   (edge); moarchy uses Arch Linux ARM's `0.3.1-1`. Upstream's 4.x shell is
   developed against its own build, so a future `[omarchy]` ref bump may need
   0.3.2. Check when bumping. (`hyprland` 0.56.2 is the same on both sides.)
4. **`omarchy-update` stays unsupported** (`docs/settings.md`, menu coverage):
   the base package exists on edge aarch64, but installing it would replace our
   patched `omarchy-config` (`port-4x.patch`). Revisit only if moarchy moves from
   vendoring to tracking upstream plus a phone overlay.
5. **Upstreaming becomes realistic.** With ARM in scope and "same experience on
   every platform" as policy, phone-specific fixes (touch, rotation, on-screen
   keyboard) have a home upstream instead of only in `port-4x.patch`, and a
   phone family in `omarchy-hw-platform` is the first thing such work would need.

## Method

Repo DBs fetched with curl and read as tar archives (`%NAME%`/`%VERSION%` from
each `desc`); upstream read from a depth-300 clone of `quattro` at `51bfd1db`.
Nothing was installed or executed. Raw lists were kept in the session scratch
directory only.

The follow-up plan, gated on these packages reaching stable, is
[`omarchy-aarch64-migration-plan.md`](./omarchy-aarch64-migration-plan.md).

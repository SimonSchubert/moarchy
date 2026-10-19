# moarchy

Omarchy's look, keybindings and theming on a phone, on Arch Linux ARM. It is
not a fork of Omarchy's installer: it is a thin overlay that vendors Omarchy's
architecture-neutral *config and theme layer* onto an aarch64 base and replaces
the parts that cannot work on the hardware.

**Upstream (`SimonSchubert/moarchy`) targets the PinePhone and Pixel 3a and runs
Sway** in Hyprland's place, because the PinePhone's Mali GPU is limited to GLES2
and Hyprland's renderer needs a GLES3 context. **This fork's focus is the
Fairphone 4 (fp4) port, which runs Hyprland**: the FP4's Adreno 619 clears
GLES 3.2, so the GLES3 floor is met (the device profile
`pkgbuilds/moarchy-device-fp4/hypr-device.lua` is a Hyprland profile,
`provision.sh` execs Hyprland, and D12 was a Hyprland banner bug on the FP4). The
FP4 boots and works as a phone (display, touch, rotation, camera, sensors, mic,
speakers; NFC and call audio are in flight). Do **not** carry the upstream
README's Sway framing onto the FP4; the README still mixes the two and is being
corrected.

**Start here**: [`README.md`](./README.md) for the overview and install, then
[`docs/structure.md`](./docs/structure.md) (the architecture and its numbered
rules R1..), [`docs/build-log.md`](./docs/build-log.md) (how the image is built
and *why* each decision), [`docs/devices.md`](./docs/devices.md) (per-device
pins and state), and the defect register:
[`docs/fp4-defects.md`](./docs/fp4-defects.md) (open) plus
[`docs/fp4-fixes.md`](./docs/fp4-fixes.md) (fixed). Pins live in
[`manifest.toml`](./manifest.toml).

## Layout

```
pkgbuilds/     one dir per package built for the image. The kernels
               (linux-moarchy-sm6350 = fp4, linux-moarchy-sdm670 = sargo),
               firmware-*, device packages (moarchy-device-fp4/-sargo),
               omarchy-config (the vendored Omarchy layer, patched), and
               moarchy-meta (the depends=() that IS the runtime package set).
image/         the image build: build.sh, the boot backends under boot/
               (android-bootimg.sh assembles boot.img via boot/android-image.py,
               since mkbootimg is not packaged for Arch ARM), verify/ checks.
scripts/       provision.sh (build packages), build-image.sh, verify-image.sh,
               manifest.sh (reads manifest.toml).
default/       the shipped rootfs overlay, incl. quickshell plugins under
               default/omarchy/plugins/ (e.g. moarchy.nfc, moarchy.settings).
bin/           helpers installed to /usr/lib/moarchy/bin (moarchy-nfc, ...).
docker/        build-packages.sh runs the package builds in a container.
docs/          extensive; the register, structure, build-log, per-topic docs.
manifest.toml  every pin: kernel refs/commits, AUR versions, [omarchy] ref,
               [moarchy] version. Bumping a pin is the only supported way to
               change what an image contains.
```

## Branches, remotes, commits

- **Remotes:** `origin` = upstream `SimonSchubert/moarchy`; `fork` =
  `taufderl/moarchy` (where our work is pushed). Same for the kernel checkout at
  `~/Personal/linux-fp4-repro` (`origin` = `sm6350-mainline/linux`,
  `fork-taufderl` = `taufderl/linux`).
- **Cadence:** WIP commits go on **`fp4-claude`**. Promote to **`fp4`** (cherry-pick)
  and push to the fork only at a milestone or end of day, not per change.
  The GitHub build workflow runs from `fp4` (the fork's default branch).
- **Commit messages** on this repo end with
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` (match the existing
  history). **Exception:** contributions to upstream kernel (sm6350-mainline,
  GitHub PRs) and to pmaports (GitLab MRs) carry **no AI attribution**, DCO
  `Signed-off-by:` only.

## Git identity and hosts (this is `~/Personal`)

- Git resolves the identity by path via `includeIf`:
  `~/Personal` -> `Tim auf der Landwehr <tadl-git@taufderl.de>`. **Never** pass
  `-c user.email=` / `-c user.name=` to `git commit`; let git pick it.
- For the GitHub API/CLI use **`gh-taufderl`** (the personal account), never
  plain `gh` (that is the work account). To push a branch, the token works:
  `git push "https://x-access-token:$(gh-taufderl auth token)@github.com/taufderl/<repo>" <branch>`.
- **pmaports** is on GitLab (`git@gitlab.postmarketos.org:tadl/pmaports.git`).
  The key is `~/.ssh/id_claude`, but this environment has no ssh-agent and does
  not offer it by default, so name it:
  `GIT_SSH_COMMAND="ssh -i ~/.ssh/id_claude -o IdentitiesOnly=yes" git push ...`
  (authenticates as `@tadl`). Open MRs: !9640 (fp4 mic UCM, **superseded by Luca
  Weiss's !9653** which moves UCM to the `alsa-ucm-conf-qcom-sm6350` package;
  close or leave), !9641 (WirePlumber). The UCM profile itself now lives upstream
  at [sm6350-mainline/alsa-ucm-conf#2](https://github.com/sm6350-mainline/alsa-ucm-conf/pull/2),
  not in the device package.

## The kernel is patch-free by design

`pkgbuilds/linux-moarchy-sm6350` (and -sdm670) build an upstream **pinned tag**
with the vendored config and **no patches** ("if this file grows a patch, the
scope has been exceeded"; the checksum ties it to pmaports' published sha512).
So a kernel or DTS change is **not** made permanent by patching the package. The
supported path is: land it upstream in `sm6350-mainline/linux` (the tree the pin
tracks), then bump `manifest.toml`'s `kernel-ref`/`kernel-commit`. Open kernel
PRs: #11 (fp4 mic DTS), #12 (aw88264 amp), #14 (fp4 NFC, st-nci raw-NCI + fixes),
#15 (camss CSI PHY supply names), #16 (D11: quiesce the splash before the
MDSS reset; draft; carried as package patch 0008 until it lands). ALSA UCM lives in a separate repo:
sm6350-mainline/alsa-ucm-conf#2 (fp4 mic + earpiece).

## Hardware testing (the FP4)

- **Transient boot, no flash:** `fastboot boot boot.img` (assemble with
  `image/boot/android-image.py bootimg --kernel Image.gz --dtb <dtb>
  --cmdline "root=PARTLABEL=userdata ro rootwait rootfstype=ext4 init=/sbin/init
  deferred_probe_timeout=60" --pagesize 4096 --out boot.img`). Needs
  `newgrp adbusers` for fastboot USB access.
- **Build Image, modules and DTB from ONE tree at a distinct `LOCALVERSION`, and
  ship the matching module tree.** WiFi (ath10k), USB gadget and touch are `=m`;
  a kernel whose `uname -r` has no `/lib/modules/<ver>` loses connectivity and
  the phone is unreachable. Do **not** boot a DTB built from a different tree/base
  than the Image: a mismatched or bad DTB **panics into the `05c6:900e` Qualcomm
  ramdump**. Recover with a physical **Power + Volume Up ~10-15s** force-reboot
  (transient boot flashed nothing, so the shipped system is intact). Build with
  `make ARCH=arm64 LLVM=1 LOCALVERSION= ...`; the LOCALVERSION comes from
  `CONFIG_LOCALVERSION` (LOCALVERSION_AUTO off, and pass `LOCALVERSION=` in the
  env so setlocalversion adds no `+`).
- **Reaching the phone:** it is on WiFi at a DHCP address (scan `192.168.3.0/24`);
  `ssh -i ~/.ssh/id_claude moarchy@<ip>`, passwordless `sudo -n`. `pacman -Sy`
  works on images from `fp4` @ `9e118c6` (2026-10-10) on; on older images the
  stale `moarchy-apps` repo db 404s, so disable that stanza in
  `/etc/pacman.conf` to install packages and restore it after.
- **If audio is missing:** look at `/sys/kernel/debug/devices_deferred` first
  (D10: the LPI pinctrl loses a boot race; the fix is `deferred_probe_timeout=60`
  on the cmdline, already in `android-bootimg.sh`).

## Conventions and hard rules

- **No em-dashes, en-dashes, or arrow glyphs in any output or file.** Plain
  ASCII (`-`, `--`, `->`). The repo is being scrubbed of pre-existing ones.
- **Never commit device secrets.** `/proc/cmdline` and logs carry the phone's
  serialno, vbmeta digest, WifiMac, BSSID/MAC, IMEI, GPS coordinates, the screen
  PIN and the home SSID. Keep them out of commits, docs, PRs and MRs; when a
  command prints the cmdline, extract only the field you need
  (`grep -o 'deferred_probe_timeout=[0-9]*'`), never the whole line.
- **The defect register is the source of truth for state.** Reproduced-not-fixed
  goes in `fp4-defects.md` with a status (`OPEN`, `OPEN - important`,
  `UNSUPPORTED`, `WONTFIX`); when fixed and verified on the handset, move the
  whole section to `fp4-fixes.md`, add its table row there, remove it from the
  open table, and fix any cross-references.
- **Full-corpus / outward actions need explicit go-ahead each time**: cutting a
  release, flashing, opening a PR/MR, posting upstream. Test on a small explicit
  scope first, and confirm before anything public.
- `lore*.tmp` in the repo root are scratch (pasted mailing-list threads); do not
  commit them.

## Sibling checkouts an agent may need

- `~/Personal/linux-fp4-repro` - the kernel source (sm6350-mainline fork) for
  DTS/driver work and transient kernels.
- `~/Personal/pmaports` - the postmarketOS pmaports checkout for the UCM /
  WirePlumber MRs.

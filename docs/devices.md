# Devices — specification

How moarchy stops being a PinePhone project and becomes a project that runs on
phones, of which the PinePhone is one.

Status: **D1–D13 built; sargo hardware proven; no image built for either
device yet (2026-09-13).** The device-package abstraction exists and both
phones are on it. On the Pixel 3a, mainline boots, the panel draws and touch
works — §8.1 records what was measured rather than assumed. The kernel,
firmware and device packages for sargo all build, and both boot backends and
both verify backends exist. What has **not** happened: no image has been
produced by either backend, and D7's PinePhone image has not been rebuilt or
booted since D1–D6 (see the note below).

The acceptance criteria are the contract to argue with; where one is my reading
rather than your decision it is marked **?**.

Companion to [structure.md](structure.md), which decides what a package is and
where packages come from. This file decides what a *device* is. It amends one
of that file's non-goals, and §2 says so out loud rather than in a PKGBUILD.

> ### ⚠ Outstanding: the PinePhone has not been re-verified
>
> **Owed since 2026-09-13.** D1–D6 moved the PinePhone onto the device-package
> abstraction — `default/sway/pinephone.conf` became a package-owned file at a
> new path, `moarchy-meta` gained a dependency, `moarchy-firstboot` stopped
> naming `eg25-manager`, and `image/build.sh` gained a `DEVICE` switch. **None
> of it has been booted.** The packages build and the metadata is right, which
> is not the same thing.
>
> D8 (the backend split) then landed on top of that, deliberately and with the
> risk understood: the decision was to focus on the Pixel 3a first. So a
> PinePhone regression and a backend-split bug are currently
> **indistinguishable** — two unverified changes to one pipeline.
>
> What settles it, and what to do first when a PinePhone is free:
>
> 1. `./scripts/provision.sh build` then build the image — it must produce
>    `moarchy-pinephone-<version>-<date>.img.xz` as before.
> 2. `./scripts/verify-image.sh` — the GPT layout, the `eGON.BT0` assertion at
>    byte 131076, and "every absolute sway include resolves", which is the
>    check that covers D6 without modification.
> 3. Flash it, boot it, run `moarchy-selftest`. W2 in particular: it now reads
>    `/usr/share/moarchy/device/sway.conf` instead of the old path.
> 4. Confirm the modem still comes up — `eg25-manager` now arrives via
>    `DEVICE_SERVICES` in the device package rather than being hardcoded.
>
> Until that is done, §9 AC 1 is open and this file should not claim otherwise.

---

## 1. What this decides

The target list is PinePhone (shipping), Pixel 3a (`sargo`), and Fairphone
later. The question is not "can moarchy run on a Pixel 3a" — §9 says it can —
but **what varies per device, where that variation lives, and who owns it.**

Get that wrong and the third device costs as much as the second. Get it right
and it costs a package and two pins.

### 1.1 The PinePhone is the outlier, not the template

It is tempting to treat the PinePhone as device #1 and generalise outward from
it. That is backwards. Of the three targets it is the only one that:

- boots from **raw sectors** (Allwinner BROM reads u-boot SPL at byte 131072)
  rather than from a bootloader that understands partitions
- ships on **removable media**, so the deliverable can be a whole-disk image
- has a kernel, u-boot and firmware **already packaged for pacman**, by DanctNIX
- has **no A/B slots** and no verified boot to defeat
- has a GPU that **cannot exceed GLES 2.0**

The Pixel 3a and the Fairphone 4/5 are the same shape as each other: Qualcomm,
fastboot, Android `boot.img`, A/B slots, AVB, non-removable storage, Adreno.
So the generic case is the Android-phone case, and the PinePhone is the special
one to carve out. **D0** below is that decision.

---

## 2. The non-goal this amends

`structure.md` §2 says, and meant:

> **A distribution.** We are not forking Arch Linux ARM or DanctNIX. Their
> kernel, u-boot, firmware, modem stack and ALSA UCM profiles are consumed as
> packages from their repos, never rebuilt here.

That holds for the PinePhone and should keep holding. It **cannot** hold for
the Pixel 3a, and pretending otherwise is how this turns into a surprise.

postmarketOS has done the SDM670 bring-up and maintains it well — the kernel
tree at `gitlab.com/sdm670-mainline/linux` was tagged `sdm670-v7.2.3_beta2` on
2026-09-03, and `device-google-sargo` sits in their *community* tier. But all
of it is Alpine `.apk`. There is no pacman repo anywhere that carries an
SDM670 kernel or the sargo firmware.

So for every Android-family device, moarchy builds and publishes:

- a kernel package, from someone else's mainline fork, at a pinned tag
- a firmware package, from publicly-downloadable vendor blobs
- a device package tying them together

That is a distribution-shaped commitment: when the kernel tree moves, we move;
when it stops being maintained, the device is dead and we are the ones who
notice. It is the price of the second device and it does not get cheaper for
the third.

**The amendment is narrow and stays narrow:** we package *what upstream has
already brought up*, at a pin, for devices we ship. We do not do bring-up, we
do not carry patches of our own against a kernel, and we do not package for
devices we do not ship. If a device needs us to write kernel code, it is out of
scope and the answer is no.

### Other non-goals, unchanged

- **Not a device-support matrix.** Three devices, chosen deliberately. A
  half-working fourth helps nobody.
- **Not runtime device detection.** An image is built *for* a device and says
  which. Nothing probes the SoC at boot to decide what it is (D3 is about
  hardware *values*, which is a different thing).
- **Not an Android app compatibility layer.** No Waydroid, no Halium.

---

## 3. The shape

```
                       ┌─────────────────────────────┐
                       │  rootfs (device-independent)│
   moarchy-meta ──────►│  pacstrap + configure.sh    │
   moarchy-device-X ──►│  identical for every device │
                       └──────────────┬──────────────┘
                                      │
                 ┌────────────────────┴────────────────────┐
                 ▼                                         ▼
        boot/sunxi-gpt.sh                       boot/android-bootimg.sh
        GPT + SPL @ 131072                      mkbootimg + AVB
        → moarchy-pinephone-*.img.xz            → boot.img + rootfs.img
                                                  + flash.sh
```

One rootfs builder. Two boot backends. N device packages.

---

## 4. What is actually device-specific

Audited against the tree at `d258680`, not guessed. This is the whole list.

| # | coupling | where it is today | verdict |
|---|---|---|---|
| 1 | kernel, bootloader, firmware | was `image/build.sh:203`, now the device package's `depends` | **device package** `depends` — *done* |
| 2 | output scale, gaps, orientation | was `default/sway/pinephone.conf`, now `pkgbuilds/moarchy-device-pinephone/sway.conf` | **device package** file — *done* |
| 3 | modem daemon | was `bin/moarchy-firstboot:71` — `eg25-manager`, now `DEVICE_SERVICES` in `device.conf` | **device package** — *done* |
| 4 | boot artifact + partitioning | `image/build.sh:287`–end | **boot backend** |
| 5 | battery sysfs path | `moarchy.device/Device.qml:166-167` — `axp20x-battery` | **probe**, no key |
| 6 | output name | `moarchy.shade/Shade.qml:825` — `DSI-1` | **probe**, no key |
| 7 | typeable-keyboard test | `bin/moarchy-has-keyboard` | **already generic** — fix comment only |

Everything else in `default/` and `bin/` is already device-independent: the QML
reads `screen.height` with a 720 fallback rather than assuming, and
`omarchy-brightness-display` already takes the first entry in
`/sys/class/backlight`.

Seven items, of which two are already solved and two more dissolve into probes.
The genuine per-device surface is four things.

### 4.1 Prefer a probe to a key

Rows 5 and 6 could each be a `device.conf` key. They should not be.

A key is a cost paid *per device, forever*: every new device must supply it,
a wrong one fails at runtime on hardware you may not have, and nothing checks
it. A probe is written once and is right on hardware nobody has tested yet.

- **Battery** — scan `/sys/class/power_supply/*/` for `type == "Battery"` and
  take the first. Correct on the PinePhone (`axp20x-battery`), on sargo, and on
  a device with a differently-named PMIC that nobody has plugged in yet.
- **Output** — ask sway. `swaymsg -t get_outputs` names the panel; the shell
  wants "the one output this phone has", not the string `DSI-1`.

**D3** states the rule: a `device.conf` key is justified only when the value
cannot be discovered at runtime. Scale (row 2) qualifies — nothing in sysfs
knows that 440 ppi wants scale 3 and 270 ppi wants scale 2, because that is a
judgement about thumbs. The battery path does not qualify.

---

## 5. The device package

**D1** Each supported device has exactly one package, `moarchy-device-<codename>`,
built from `pkgbuilds/moarchy-device-<codename>/`. Codenames are the upstream
ones: `pinephone`, `sargo`, `FP4`.

**D2** It is the *only* place a device's hardware is named. It carries:

| path | content |
|---|---|
| `depends` | kernel, firmware, bootloader, modem stack for this device |
| `/usr/share/moarchy/device/sway.conf` | the output scale and any hardware sway needs told |
| `/usr/share/moarchy/device/device.conf` | shell-sourceable keys that survive D3 |
| `/usr/share/moarchy/device/build-info` | codename, so a running phone can say what it is |
| udev rules, systemd units | only where the hardware needs them |

**D3** `device.conf` holds only values that **cannot be discovered at runtime**
(§4.1). Every proposed key must come with the sentence explaining why a probe
cannot answer it. Initially this is expected to be *scale* and little else; a
key list that grows past ~5 is a sign the probes are not being written.

**D4** Every device package `provides=('moarchy-device')` and
`conflicts=('moarchy-device')`, so pacman enforces exactly one installed.

**D5** `moarchy-meta` gains `moarchy-device` in `depends`. It stays otherwise
device-independent and names no hardware. A rootfs with no device package is a
pacman error, not a phone that boots wrong.

**D6** `config/sway/config:25` stops including
`/usr/share/moarchy/default/sway/pinephone.conf` and includes
`/usr/share/moarchy/device/sway.conf` instead. `default/sway/pinephone.conf`
moves into `pkgbuilds/moarchy-device-pinephone/` and the `moarchy` package
stops shipping it — two packages cannot own one path, and this is the boundary
that makes that a build error rather than a decision.

**D7** The PinePhone gets a device package in the same change that introduces
the concept, and the shipping image is rebuilt from it before any second device
is started. An abstraction with one implementation is a guess; with the
PinePhone moved onto it first, the second device tests the abstraction rather
than inventing it.

---

## 6. Boot backends

**D8** `image/build.sh` gets a backend, sourced from `image/boot/$BACKEND.sh`.
The split is a move, not a rewrite — if the `sunxi-gpt` backend is not the
existing lines verbatim, something has been changed that D7 cannot then test.

*Amended 2026-09-13.* This AC previously said the file cut cleanly in two at
`say "filesystem images"`, with everything above it device-independent. That
was wrong, and implementing it as written would have shipped a PinePhone image
with no initramfs. The device-specific work **interleaves**:

| | what | where |
|---|---|---|
| 1 | initramfs + `mkscr`/`boot.scr` | `build.sh` 237–272 |
| 2 | `/etc/fstab` — a vfat `/boot` labelled `BOOT` | `configure.sh` ≈296–302 |
| 3 | filesystem images, GPT, SPL, compress | `build.sh` 304–end |

Between (1) and (3) sit provenance, `configure.sh` and the rootfs trim, all
device-independent. So a backend is **three hooks, not one tail**:

- `backend_kernel` — after pacstrap: initramfs, and any boot script
- `backend_fstab`  — what `/etc/fstab` should say; the disk layout is the
  backend's business, and sargo has no separate `/boot` partition to mount
- `backend_image`  — after the trim: assemble and compress the artifact

Three hooks rather than reordering the file into two blocks, because the order
is the one thing D7 is supposed to be able to vouch for. Moving the initramfs
generation to sit after `configure.sh` would be a behaviour change smuggled in
as a refactor, and the PinePhone image has not been re-verified since D1–D6.

**D9** Two backends initially:

- `sunxi-gpt` — today's code verbatim: `mkfs.ext4 -d`, sfdisk GPT, `dd` of
  boot/root/SPL, the `eGON.BT0` assertion, `xz`. Output:
  `moarchy-pinephone-<version>-<date>.img.xz`.
- `android-bootimg` — `mkbootimg` with the DTB appended, a rootfs ext4, an
  AVB-disabling `vbmeta`. Output: a **directory** of `boot.img`, `rootfs.img`,
  `vbmeta.img` and a `flash.sh`, tarred and compressed.

**D10** The two backends produce **different artifact shapes**, and that is not
papered over. A PinePhone image is one file you `dd`; an Android image is three
files and a script you run with the phone in fastboot. Forcing both into
`.img.xz` would mean inventing a container nothing can read.

**D11** The backend is chosen by `DEVICE=<codename>`, defaulting to `pinephone`
until the second device ships. `scripts/build-image.sh` passes it through and
refuses a codename with no `pkgbuilds/moarchy-device-<codename>/`.

**D12** `image/verify.sh` splits the same way. Its partition-table and
`eGON.BT0` assertions are `sunxi-gpt` facts; the Android backend asserts its
own (boot.img magic, the DTB appended, vbmeta flags = 2), and the behavioural
section — the first-boot scripts run in a chroot — stays shared because it is
about the rootfs.

---

## 7. Pins

**D13** `manifest.toml` gains one section per device, and it stays the only
file in the project that says what version of anything is (V1):

```toml
[device.sargo]
kernel-url = "https://gitlab.com/sdm670-mainline/linux"
kernel-ref = "sdm670-v7.1.3"          # a tag; makepkg can verify it
firmware-url = "https://github.com/TheMuppets/proprietary_vendor_google_sargo"
firmware-ref = "c631f0f2aa24ea60cfb505d327cd4ae56ca27f16"
```

**D14** A device pin is a hard error when unread, exactly as every other pin is
— `scripts/manifest.sh` already enforces this and needs no change.

---

## 8. What the Pixel 3a needs specifically

Measured on the device (serial `987AY139XT`), not read off a wiki.

| | |
|---|---|
| codename / SoC | `sargo` / SDM670, 4 GB LPDDR4X, 64 GB eMMC |
| panel | 1080×2220, density 440 → **scale 3** gives 360×740 logical |
| bootloader | `b4s4-0.4-8048689`, `secure-boot: PRODUCTION`, now **unlocked** |
| slots | A/B, `current-slot: a`, both bootable |
| dynamic partitions | **retrofit** — no `super`; `system_a`=p68, `system_b`=p69 |
| `max-download-size` | `0x10000000` (256 MiB) → rootfs must flash sparse |
| flash targets | kernel→`boot`, rootfs→`userdata`, plus `vbmeta` |
| GPU | Adreno 615, freedreno — GLES 3.2 and Vulkan |

The scale number is the whole reason row 2 of §4 is a key and not a probe:
360×740 logical against the PinePhone's 360×720 means **the UI lands almost
exactly where it already is**, and nothing in sysfs could have worked that out.

### 8.1 What was proven on the device, 2026-09-13

A postmarketOS image was booted with `fastboot boot` — RAM only, nothing
written to flash — to settle the hardware questions before any of this was
built around them. All of it held:

| question | result |
|---|---|
| mainline SDM670 kernel boots | **yes** — `7.0.10-sdm670`, `Device: Google Pixel 3a (google-sargo)` |
| boot image format | **yes** — the header reverse-engineered in D15 was accepted and jumped to |
| display / DRM / KMS | **yes** — `msm_dpu ae01000.display-controller` drove the full 1080×2220 panel with a rendered UI |
| touch | **yes** — a tap on the on-screen keyboard registered at the shell |
| iteration loop | **yes** — `fastboot boot` writes nothing, so a bad kernel costs a power cycle |

Three things this changed, each of which was a stated risk:

**The kernel config needs no changes.** pmOS runs OpenRC and elogind, so the
worry was that their config omits what systemd requires. Audited: `DEVTMPFS`,
`DEVTMPFS_MOUNT`, `CGROUPS`, `FHANDLE`, `INOTIFY_USER`, `SIGNALFD`, `TIMERFD`,
`EPOLL`, all four namespaces, `SECCOMP`+`SECCOMP_FILTER`, `TMPFS_POSIX_ACL`,
`TMPFS_XATTR`, `AUTOFS_FS`, `EXT4_FS` — every one set. `FHANDLE` and
`DEVTMPFS_MOUNT` are the two that usually bite. No fragment of ours is needed.

**The GPU firmware is mostly free.** The boot showed
`[drm:adreno_request_fw] *ERROR* failed to load qcom/a630_sqe.fw`, which reads
like the vendor-blob problem and is not: `a630_sqe.fw` and `a630_gmu.bin` are
both in upstream `linux-firmware`, which `image/build.sh` already pacstraps.
They were missing only because a pmOS *initramfs* is minimal. Of the Adreno
firmware only `a615_zap.mbn` needs the proprietary blob and `pil-squasher`.

**"There is no console" was wrong, twice.** This kernel prints to the panel,
and pmOS's initramfs puts a usable debug shell *with an on-screen keyboard* on
it. Our initramfs should do the same. A failed boot here is readable.

**D19** The USB network gadget is **CDC-ECM or NCM, never RNDIS.** pmOS's
initramfs came up as RNDIS (`idProduct 0x4EE3`, `serial "postmarketOS"`), macOS
bound no driver, and a phone offering a debug network that the only machine on
the desk cannot speak to is a debug channel that does not exist. The pinned
config already sets `USB_CONFIGFS_ECM=y` and `USB_CONFIGFS_NCM=y`, so this
costs nothing but choosing correctly — and both are what macOS binds natively.

**D15** AVB must be defeated or the Android 12 bootloader rejects an unsigned
kernel. The backend generates an empty vbmeta with the verification-disabled
flag — `avbtool make_vbmeta_image --flags 2 --padding_size 4096` — and flashes
it to `vbmeta`. Verified: a 4096-byte image, `Algorithm: NONE`, `Flags: 2`.

**D16** The rootfs goes to `userdata` (p72, the bulk of the 64 GB), **not**
into the retrofit dynamic partitions. pmbootstrap's default for a device that
overrides neither `flash_fastboot_partition_rootfs` nor `_system` is
`userdata`, and sargo overrides neither. This avoids `make-dynpart-mappings`
and the logical-partition machinery entirely. **?** — it also gives up the
`system_a`/`system_b` space, which is a real cost if 64 GB ever gets tight.

**D17** A/B slots are not used. We flash the current slot and leave the other
alone, so a bricked flash can be recovered by switching slots in the
bootloader. Seamless updates are explicitly not a goal; `pacman -Syu` is the
update path here as it is on the PinePhone.

**D18** The GLES 2.0 ceiling is a PinePhone fact, not a moarchy fact. The shell
keeps targeting GLES 2.0 so one QML codebase serves every device — but this is
now a *choice* with a reason, and `docs/style.md` should say so rather than
leaving it as an unstated assumption that the next device silently violates.

---

## 9. Acceptance criteria

**D0** The Android-phone case is the general one; `sunxi-gpt` is the carve-out.
A change that makes the PinePhone path the default shape of anything is wrong.

Restated as a checklist, in build order. Each carries its state.

1. **D7 — PARTIAL.** `moarchy-device-pinephone` exists and builds
   (`0.2.2-1`, `arch=any`, three files under `/usr/share/moarchy/device/`).
   **Not yet done:** no image has been rebuilt from it and nothing has booted,
   so "no behaviour change from `d258680`" is still a claim. This is the gate
   on everything below and it needs the PinePhone.
2. **D6 — DONE.** `config/sway/config` includes `/usr/share/moarchy/device/sway.conf`;
   `pacman -Qo` on the installed path names `moarchy-device-pinephone`, and the
   `moarchy` package ships no `pinephone.conf` and owns nothing under `device/`.
   `image/verify.sh`'s existing "every absolute sway include resolves" check
   covers this in the image without modification.
3. **D4/D5 — DONE, demonstrated.** Against a throwaway second device package:
   two at once gives `unresolvable package conflicts detected ... are in
   conflict`; `moarchy-meta` with none gives `unable to satisfy dependency
   'moarchy-device'`. Neither was assumed.
4. **§4 rows 5-7 — NOT STARTED.** Battery and output are probed;
   `axp20x-battery` and `DSI-1` appear nowhere in the tree.
   `moarchy-has-keyboard`'s comment is corrected.
5. **D8-D12 — DONE (code), not run.** `image/build.sh` sources
   `image/boot/$BACKEND.sh` and calls `backend_kernel`, `backend_fstab` and
   `backend_image`; it refuses a `DEVICE` with no device package and a device
   with no backend. Both backends satisfy the hook contract, and the two
   bodies moved into `sunxi-gpt.sh` were checked **byte-identical** (34 and 65
   lines) against `build.sh` before the split — so a PinePhone failure points
   at the structure, not at an edit. `image/verify.sh` splits the same way into
   `image/verify/$BACKEND.sh` (`verify_artifact`, `verify_grow`), inferring the
   device from the artifact name; its two moved bodies were checked verbatim
   too (49 and 65 lines). *No image has been produced by either backend yet, so
   all of this is built and not run.*
6. **D13 — DONE.** `manifest.toml` carries `[device.sargo]` with the kernel
   tag, real SHA256s and the config's provenance; `manifest_get` reads all five
   keys and the existing `manifest_components`/`manifest_aur_packages` scans
   are unaffected. `linux-moarchy-sdm670` and `moarchy-device-sargo` both
   build.
7. **D15-D17 — packages done, image not built.** `linux-moarchy-sdm670`
   (7.1.3, pruned to three SDM670 DTBs), `firmware-moarchy-sargo` (six blobs at
   the paths the device tree names) and `moarchy-device-sargo` (`scale 3`) all
   build. The remaining step is the first `DEVICE=sargo` image, then flashing
   it and booting to the shell with touch working.

   Two tools were written rather than depended on, and both are checked against
   artifacts instead of trusted: `image/boot/android-image.py` reproduces
   postmarketOS's own boot image byte-for-byte, and
   `pkgbuilds/firmware-moarchy-sargo/pil-squash.py` reproduces the vendor's own
   unsplit `a615_zap.elf` byte-for-byte. Neither `mkbootimg`, `avbtool` nor
   `pil-squasher` is packaged for Arch; each replacement is ~40 lines with a
   test that fails when broken.

   **D22** Growth is a per-device policy, not a probe. `DEVICE_GROW=partition`
   on the PinePhone (a card of unknown size, and the GPT being rewritten is the
   one `sunxi-gpt.sh` wrote); `DEVICE_GROW=filesystem` on sargo, where the
   rootfs sits in `userdata` inside a vendor GPT that also holds `xbl`, `abl`,
   `tz` and the A/B slots. Running `sfdisk` there would rewrite a vendor
   partition table on a phone with no removable storage and no recovery image
   — the one irreversible thing this project could do to a device. The key
   meets §4.1's bar because "is it safe to rewrite this table" is a policy
   about the hardware, not a fact readable from it, and
   `moarchy-grow-rootfs` defaults to the **safe** value so a device package
   that forgets the key costs storage rather than a partition table.

   **D21** The kernel is built on a **case-sensitive filesystem**, never in a
   macOS bind mount. `net/netfilter/` holds both `xt_TCPMSS.c` and
   `xt_tcpmss.c`; APFS keeps one. The build then dies twelve minutes in with
   `No rule to make target 'net/netfilter/xt_TCPMSS.o'`, which reads like a
   corrupt tarball and is not — `tar` exited 0 and the sha256 matched, because
   the file was overwritten rather than dropped. `docker/build-packages.sh` is
   already safe (it copies `/repo` into the container first); hand-rolled
   `-v $PWD:/work` iteration is not. `prepare()` now checks for both files and
   fails in one sentence.

   **D20** The builder image carries the kernel's build tools (`bc`, `libelf`),
   not `linux-moarchy-sdm670`'s `makedepends`. `docker/build-packages.sh`
   builds every in-repo package with `--nodeps`, so makedepends are declared
   and never installed. Omitting `bc` cost a build and presented as
   `include/generated/timeconst.h ... Error 127` — make's code for "command not
   found", about a header, four directories from the missing tool.

AC 7 is the one that can fail for reasons none of the others predict, which is
why it is last and why nothing above it depends on owning a Pixel 3a.

AC 1 is the one most likely to be declared done without being done. The
packages building and the metadata being right is not the same as a phone
booting, and this file should not say otherwise until one has.

---

## 10. What is not yet decided

- **Who builds the SDM670 kernel.** Answered in part: it builds in the
  existing `moarchy-builder` on the same cached image as everything else, and
  natively — the build host is aarch64, so there is no emulation penalty. What
  is still open is whether a kernel belongs in the *same* `provision.sh build`
  as a 3 KB meta package, given it dwarfs everything else in the loop.
- **Whether `[moarchy]` publishes kernels at all.** It could; the repo is ours.
  But a kernel in the same repo as the shell means a phone's `pacman -Syu`
  can replace its kernel, which on a device with no recovery is a different
  risk profile than replacing a QML file. **?**
- **Fairphone codename and tier.** FP4 and FP5 are both pmOS community, both
  fastboot; which one, and whether the `android-bootimg` backend covers it
  unchanged, is unverified.
- **Calls.** sargo telephony needs `q6voiced` and `hexagonrpcd`, which have no
  Arch packages. Out of scope for a first boot; not out of scope forever.

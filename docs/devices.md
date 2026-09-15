# Devices — specification

How moarchy stops being a PinePhone project and becomes a project that runs on
phones, of which the PinePhone is one.

Status: **moarchy runs on the Pixel 3a, flashed (2026-09-15).**
`moarchy-sargo-0.2.2-20260915` was built by `image/build.sh`, verified (108
checks), flashed over fastboot, and booted to the shell from a clean rootfs
with nothing of postmarketOS's anywhere in it. Our kernel, our device and
firmware packages, systemd, autologin, sway. There is no initramfs at all
(D24), and the bootloader confirms the slot is marked successful (D26).

**The PinePhone has not been re-verified** since D1–D6 — the ⚠ note below, and
the one thing here still owed.

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

- `backend_kernel` — after pacstrap: whatever this device needs doing to the
  kernel. An initramfs and a boot script on the PinePhone; on sargo, checks
  only, because that backend ships neither (D24)
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

**D24** *Added 2026-09-14.* The `android-bootimg` backend ships **no
initramfs**. The kernel mounts root itself: `root=PARTLABEL=` is resolved out
of the GPT by `early_lookup_bdev()`, and `EXT4_FS`, `MMC_BLOCK`,
`MMC_SDHCI_MSM`, `EFI_PARTITION` and `DEVTMPFS_MOUNT` are all `=y` in the
pinned config, so nothing is left for an early userspace to do.
`backend_kernel` asserts the first three against `modules.builtin` rather than
trusting a config file in another package, because the failure is otherwise a
phone that shows two penguins and stops.

> The initramfs was only ever resolving `root=LABEL=` through udev, and it
> resolved it into a night: eighteen megabytes of pre-userspace code on the one
> device in the project that cannot print (D23), where every failure looks
> exactly like every other failure. `PARTLABEL=` needs no udev, so the
> dependency and the debugging surface go together.
>
> `sunxi-gpt` keeps `mkinitcpio -P`, and the asymmetry is not an inconsistency:
> the PinePhone boots from a card of unknown geometry, which is the case an
> initramfs is actually for.

**D12** `image/verify.sh` splits the same way. Its partition-table and
`eGON.BT0` assertions are `sunxi-gpt` facts; the Android backend asserts its
own (boot.img magic, the DTB appended, vbmeta flags = 2, no ramdisk, and the
cmdline read back out of the header), and the behavioural section — the
first-boot scripts run in a chroot — stays shared because it is about the
rootfs.

*Amended 2026-09-15.* `verify_artifact` and `verify_grow` are required;
`verify_rootfs` is a third and **optional** hook, run against the mounted
rootfs, for facts true of one device's rootfs and meaningless for another's.
sargo uses it for D26, which is invisible in every shared check because an
image missing it is otherwise perfect. Optional rather than required because a
backend with no such facts should not have to define an empty function to say
so.

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
| slots | A/B, `current-slot: a`; bootable is a *countdown*, not a state — D26 |
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
| iteration loop | **yes** — `fastboot boot` writes nothing, so a bad kernel costs a power cycle. It still spends a slot retry (D26) |

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

**D19** Any USB network gadget moarchy raises on this device is **CDC-ECM or
NCM, never RNDIS.** pmOS's initramfs comes up as RNDIS (`idProduct 0x4EE3`,
`serial "postmarketOS"`), macOS binds no driver, and a phone offering a debug
network that the only machine on the desk cannot speak to is a debug channel
that does not exist. The pinned config already sets `USB_CONFIGFS_ECM=y` and
`USB_CONFIGFS_NCM=y`, so this costs nothing but choosing correctly.

Nothing raises one today — the rootfs presents no gadget, so a running phone is
invisible over the cable and the shell in D23 is postmarketOS's rather than
ours. That is the gap worth closing next, and it belongs in the rootfs as a
systemd unit now that there is no initramfs to put it in. **?**

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

**D17** *Amended 2026-09-14.* We flash the current slot and leave the other
alone, so a bad flash is recoverable by switching slots in the bootloader.
Seamless updates are explicitly not a goal; `pacman -Syu` is the update path
here as it is on the PinePhone.

This AC used to open "A/B slots are not used", and that was wrong in a way that
costs a phone. The slots are not optional machinery you can decline to operate
— see D26.

**D25** The boot image's cmdline ends with **`init=/sbin/init`**, and removing
it stops the phone booting. ABL does not pass our cmdline through; it builds
one, putting its own `androidboot.*` parameters first — `init=/init` among them
— then ours, then `console=null`. `init=` is last-wins in the kernel
(`init/main.c`, `init_setup`), so ours must be present to win. An Arch rootfs
has no `/init`, and a failed `init=` is a `panic()` with **no fallback** to
`/sbin/init` (`init/main.c:1633-1637`).

> This is what D23 was hiding. Root mounted correctly and the kernel died one
> `execve` later, on every image tried, looking identical to a kernel that
> never found its disk. The same rule applies to `root=`: ABL passes a
> `root=PARTUUID=` of its own for the Android system partition, and ours wins
> only by coming after it.

**D26** Something must mark the boot successful on **every** boot, or the phone
stops booting. `moarchy-device-sargo` depends on `qbootctl` and ships
`qbootctl-mark-successful.service` **already enabled**, by the symlink rather
than through `DEVICE_SERVICES`, so it is true from the moment the package is
installed rather than from the moment a first-boot script succeeds.

> An A/B bootloader decrements a retry counter every time it hands off to a
> slot and marks the slot **unbootable** when it reaches zero with no callback.
> On 2026-09-14 this handset read `slot-retry-count:a:0`,
> `slot-unbootable:a:yes`, and in that state it booted **nothing** — a
> postmarketOS image that had worked an hour earlier failed exactly as ours
> did, which is how the counter was found rather than the image blamed. About
> three reboots of headroom, then a phone that needs a computer with `fastboot`
> to revive.
>
> `flash.sh` runs `fastboot --set-active` for the same reason: it is the only
> thing that clears the unbootable flag, and without it a freshly flashed
> phone can refuse the image just written to it.
>
> **Observed working 2026-09-15**, which is a different claim from "the package
> is installed": after one boot of an image carrying the unit, the bootloader
> reports `slot-successful:a:yes` and `slot-retry-count:a:3`. It had read
> `no` at every check before that, and had been counting down — 3 to 1 across
> the boots of one afternoon.

**D27** *Added 2026-09-15.* **Wi-Fi on this SoC is a modem feature.** The chain
is `rmtfs -s` → modem DSP → `wlanmdsp.mbn` → QMI → `ath10k_snoc` → `wlan0`, and
every link of it is shipped: `firmware-moarchy-sargo` carries `mba.mbn` and
`modem.mbn`, and `moarchy-device-sargo` depends on `moarchy-qcom-modem` (qrtr,
rmtfs, tqftpserv), whose two units ship **enabled** by their own symlinks.

> The five facts that make this non-obvious, each read out of a source rather
> than a wiki:
>
> 1. **The Wi-Fi firmware does not run on the Wi-Fi chip.** WCN3990's
>    `wlanmdsp.mbn` executes on the modem DSP as a protection domain;
>    `ath10k_snoc` reaches it over QMI. This package already shipped that blob,
>    which is why the situation looked like a driver problem.
> 2. **Nothing in the kernel boots that DSP.** `qcom_q6v5_mss.c` sets
>    `rproc->auto_boot = false`. The remoteproc sits idle until userspace writes
>    `start` to its `state` file.
> 3. **`rmtfs` is what writes it.** Its `-s` flag calls `rproc_init()`, which
>    hunts `/sys/class/remoteproc/*` for the `-mss-pil` modalias. The daemon
>    named for the remote *filesystem* service is also the ignition — the name
>    tells you nothing about the job that matters here.
> 4. **`mba.mbn` and `modem.mbn` are not in TheMuppets tree.** That is a dump of
>    `/vendor/firmware`; the modem images live in sargo's own `modem` partition.
>    They come from a third upstream, the one postmarketOS uses, pinned in
>    `manifest.toml` as `modem-url`/`modem-ref`.
> 5. **The protection-domain mapper is the kernel's, and userspace must not run
>    one.** `CONFIG_QCOM_PD_MAPPER` compiles an `sdm670_domains[]` table into
>    `drivers/soc/qcom/qcom_pd_mapper.c` — including `mpss_wlan_pd`, the exact
>    domain `ath10k` looks up — and binds as an auxiliary driver to a device
>    `pdm_notify_prepare()` creates whenever a DSP starts. Shipping
>    `linux-msm/pd-mapper` beside it would put a second `tms/servreg` server on
>    QRTR. Alpine stopped packaging it; so did we, after packaging it first.
>    The kernel announces the case for the daemon when it applies: *"PDM: no
>    support for the platform, userspace daemon might be required."*
>
> The decision this reverses is `firmware-moarchy-sargo`'s own: "the modem pair
> is NOT shipped … it goes in when the daemons that drive it do." The
> *dependency* was right and the *reason* was wrong — 66 MB of `modem.mbn` was
> written off as telephony that nobody had built, when it is what Wi-Fi runs on.
> Telephony turned out to need `q6voiced` (D32) and nothing else on this SIM;
> `hexagonrpcd` is the sensors daemon and was never part of it.
>
> **Bluetooth is not part of this chain and never was.** WCN3990's BT is a UART
> controller on `&uart6` driven by `hci_qca`, wanting `qca/crbtfw21.tlv` and
> `qca/crnv21.bin` — both already in the image, in `linux-firmware-atheros`,
> which plain `linux-firmware` does pull in (checked with `pacman -Fx`, not read
> off the upstream git tree). `bluez` is installed and `moarchy-firstboot`
> enables `bluetooth`. So nothing identifiable is missing, and the next step is
> a measurement rather than a package.
>
> **The one named suspect, so the measurement knows what it is looking for:**
> `sdm670-google-common.dtsi`'s `bluetooth` node has no `local-bd-address`, and
> the vendor keeps the real BD address outside the filesystem. postmarketOS
> covers this with `bootmac`, which every Qualcomm device gets through
> `soc-qcom`: a shell script on a udev rule that derives a stable
> locally-administered address (prefix `0200`) from `androidboot.serialno` in
> `/proc/cmdline`, then applies it with `btmgmt public-addr` for `hci0` and
> `ip link set address` for `wlan0`. Roughly `qbootctl`-sized to package.
>
> So the measurement is two questions in order: **does `hci0` exist at all**
> (`bluetoothctl list`, `dmesg | grep -i qca`), and if it does, **what address
> does it have** — `00:00:00:00:00:00` or a shared vendor default means bootmac,
> and no `hci0` at all means something earlier and unguessed. Writing bootmac
> before asking would be packaging on a hunch.

**D28** *Added 2026-09-15, measured on the handset.* **Bluetooth needs an
address, and nothing else.** `moarchy-device-sargo` depends on `bootmac`, whose
udev rule sets `hci0`'s public address from the bootloader's
`androidboot.serialno` when the controller appears.

> The failure this closes points nowhere. Every component reported success:
>
> ```
> /sys/class/bluetooth/hci0                    exists
> dmesg: QCA Downloading qca/crbtfw21.tlv      firmware loads
> dmesg: QCA setup on UART is completed        controller is up
> rfkill: hci0 Bluetooth  soft no  hard no     not blocked
> systemctl is-active bluetooth: active        daemon running
> btmgmt info: Index list with 0 items         ...and no adapter
> ```
>
> WCN3990 has no BD address Linux can see and the DT has no `local-bd-address`,
> so bluez classes the adapter **unconfigured** — and an unconfigured adapter is
> not in the index list `bluetoothctl` reads. Nothing in that picture contains
> the word "address".
>
> `btmgmt --index 0 public-addr 02:00:ff:14:0f:1b` turned it into a powered
> Primary controller that discovered ten devices, and after packaging it the
> same address came back **by itself across a reboot**. Verified fix, not a
> plausible one.
>
> **`bootmac`'s Wi-Fi half is deliberately not shipped.** It runs, logs
> `WLAN MAC address configured successfully`, and `ip -br link` then shows a
> different address: NetworkManager applies its own cloned MAC when it activates
> the connection, after udev. So `package()` deletes that udev rule. Making the
> Wi-Fi MAC stable is a NetworkManager setting, not a bootmac one — and it is
> worth doing, because a phone that takes a new address every boot is a phone
> you have to hunt for on the LAN. **?**

**D29** *Added 2026-09-15, corrected the same day.* **Sound needed two files,
not a kernel fix.** `firmware-moarchy-sargo` carries `Global_cal.acdb` and
`alsa-ucm-conf-moarchy-sdm670` carries the use-case profile; with both, the card
registers and PipeWire exposes an earpiece, a speaker and a microphone.

> **This entry first said the opposite,** and the mistake is the useful part.
> The symptom was four errors deep:
>
> ```
> qcom-q6afe aprsvc:service:4:4: AFE set params failed -110
> msm8916-wcd-digital-codec 62ec0000.audio-codec: failed to enable mclk -110
> platform sound: deferred probe pending: snd-sm8250: ... codec dai not found
> /proc/asound/cards -> --- no soundcards ---
> ```
>
> All three of those name a DSP that will not answer, so this file recorded a
> bring-up bug, "above this project's line (§2)", and moved on. A rebind forced
> 14 minutes after boot failed identically, which ruled out a boot race and
> seemed to confirm it.
>
> The actual first line was further up the log and had been filtered out of
> every search, because none of the greps included the word that mattered:
>
> ```
> qcom-q6core aprsvc:service:4:3: Direct firmware load for
>     qcom/sdm670/sargo/Global_cal.acdb failed with error -2
> qcom-q6core ...: probe with driver qcom-q6core failed with error -2
> ```
>
> `q6afe` sits on `q6core`, the codec asks `q6afe` for its MCLK, and the card's
> DAI link waits for the codec. One missing 23 KB file, four errors of distance,
> and not one of the downstream three mentions a filename. **The lesson is to
> read the first error rather than the loudest**, and to be slower to call
> something upstream's problem: "the DSP is not answering" was a true
> description and a false diagnosis.
>
> `Global_cal.acdb` is audio calibration and lives in LineageOS's device config
> rather than TheMuppets' `/vendor/firmware` dump, under a directory named for
> the card this phone has — `sdm670-intcodec-s4-snd-card`. A fourth upstream for
> one file, pinned in `manifest.toml` as `acdb-url`/`acdb-ref`.
>
> The second file is the ALSA use-case profile, and without it the card exists
> and the phone is still silent: `wpctl status` shows no sink and no source,
> because WirePlumber does not expose a card it has no routing for. Arch's
> `alsa-ucm-conf` has `Qualcomm/sdm845` and `sc7180` and no sdm670. Ours
> installs only the three sargo files, where postmarketOS's replaces the whole
> `ucm2` tree — on Arch that would be two packages owning several hundred
> identical paths. ALSA finds it through `conf.d/sdm660/Google Pixel 3a.conf`,
> whose name must be the card's name exactly.
>
> **Measured after both:** `0 [G3a]: sdm660 - Google Pixel 3a`, sink "Built-in
> Audio Earpiece (L) and Speaker (R)", source "Built-in Audio Built-in
> Microphone", a tone played through `pw-play` and a 3 s capture that came back
> 48 kHz stereo at full scale rather than silence.
>
> **Closed by D32:** routing a call through the profile's VoiceCall verb also
> wants `q6voiced`. Calls connect, carry audio, and are what exposed all of
> this.

**D32** *Added 2026-09-15.* **Fixing sound broke calling, and that is the
correct order of events.** `moarchy-device-sargo` depends on `q6voiced` and
ships the PCM numbers it needs.

> Calls connected before D29 and carried no audio. After D29 they went
>
> ```
> [modem0/call0] call state changed: unknown -> terminated (unknown)
> ```
>
> immediately, on a modem that was `registered` on `o2 - de+` at signal 92 with
> `CS: 'attached'`. Nothing about the network had changed.
>
> The reason is that a voice call on this SoC is not carried by the modem
> alone. The ADSP exposes a voice PCM — `VoiceMMode1`, card 0 device 4 here,
> visible in `/proc/asound/pcm` — and something has to hold it open for the
> duration of a call. While `qcom-q6core` was failing to probe, the whole q6
> stack was dead and the modem did the call by itself: it connected, and there
> was nowhere for the audio to go. With q6core probing, `q6voice`, `q6mvm`,
> `q6cvs` and `q6cvp` are live, the voice path expects a driver, and a dial
> with nothing on the PCM is torn down at once.
>
> So the sequence reads as "the audio change broke calls", and the truth is
> that it revealed the missing half. `q6voiced` is postmarketOS's daemon; it
> watches ModemManager over D-Bus and drives the PCM.
>
> The card and device numbers live in the **device** package, not in
> `q6voiced`: they are a hardware value (§4). q6voiced's own unit is written
> for that — it `ConditionPathExists` on the config file, so a device that
> ships none skips the unit rather than failing it.
>
> **Also fixed here:** `docker/Dockerfile.builder` gained `alsa-lib`. D20 says
> the builder carries build *tools* because `--nodeps` never installs
> makedepends; this is the same rule one step further, because `--nodeps` does
> not install `depends` either, so a library a package links against has to be
> in the container too.

**D30** *Added 2026-09-15, fixed the same day.* **The camera's colour needed a
profile and a patched megapixels.** `moarchy-device-sargo` generates
`google,b4s4-sdm670,{Rear,Front}.dcp`; `pkgbuilds/megapixels` carries a
three-line patch without which megapixels cannot load a profile at all.

> **Why green.** `process_pipeline.c` falls back to IDENTITY colour matrices
> when it finds no profile, and a Bayer mosaic has twice as many green
> photosites as red or blue, so an uncorrected debayer is green.
>
> **The profile.** `make-dcp.py` builds both from Google's own `ColorMatrix1/2`,
> read out of a Pixel 3a DNG published on raw.pixls.us under CC0 — every DNG
> the stock camera wrote carries those tags, so this is the vendor's
> measurement rather than ours. That DNG has no `ForwardMatrix` and megapixels
> reads them, so both are derived per DNG 1.4
> (`FM = CA(W→D50) · CM⁻¹ · diag(CM·W)`, Bradford) and the script asserts the
> spec's own property — `FM · [1,1,1]` must be the XYZ of D50 — before writing.
> Generated, not committed: a `.dcp` is a TIFF whose payload is nine numbers
> twice over, and as a binary the only reviewable part would be unreadable.
>
> **Three bugs in one upstream function,** `find_calibration_by_model` in
> `src/dcp.c`, in 2.1.0 and on master:
>
> 1. It looks for `<model>.conf` under `XDG_CONFIG_HOME` while hunting for a
>    profile — wrong extension, and it drops the sensor from the name.
> 2. That name **is libmegapixels' device config**. Putting a profile there,
>    the obvious workaround for (1), shadows the file defining the sensors and
>    the media pipeline, and the camera stops starting. Tried here; it cost the
>    camera until the file was deleted.
> 3. `for (const char *fmt = paths[0]; fmt; fmt++)` walks the *bytes* of the
>    first format string instead of the array, matches `.config` — a directory
>    in `$HOME` — and returns it as a calibration file. The tell is
>    `Found calibration file at .config`.
>
> **The names came from the fixed binary, not from inference.** The PinePhone's
> shipped profiles are lowercase and had suggested the camera name was
> lowercased; a patched megapixels says `No calibration found Front`, naming
> the libmegapixels section verbatim. Upstream's own PinePhone profiles are
> evidently misnamed too. Measuring beat inferring, and inferring cost a round
> trip.
>
> **Measured:** `Found calibration file at
> /usr/share/megapixels/config/google,b4s4-sdm670,Front.dcp`.
>
> **The cost, stated plainly.** `pkgbuilds/megapixels` is a fork of an Arch
> package, which §2's amendment says we do not do. It is meant to be temporary:
> the patch goes upstream, and when it lands this package is deleted. It also
> obliged `docker/Dockerfile.builder` to gain `[danctnix]`, because `libdng` and
> `libmegapixels` live there and Arch Linux ARM has neither — the *builder*
> only; a flashed phone's own `pacman.conf` still carries no such stanza (R8a).
> The image's `[moarchy]` is first in its `pacman.conf`, so our megapixels wins
> over danctnix's deterministically rather than by luck.

**D23** **There is no console on this device, and there cannot be one.** ABL
strips any `console=` from the boot image and appends its own `console=null`.
Verified from a shell on the handset: with `console=tty0` in the boot image,
`grep -o "console=[^ ]*" /proc/cmdline` returns `console=null` alone and
`/proc/consoles` lists only `ttynull0`. There is no pstore either — `/dev/pmsg0`,
`/proc/last_kmsg` and `/sys/fs/pstore/console-ramoops*` are all absent — so a
previous boot's log cannot be recovered after the fact.

Nothing printed before userspace is ever visible, so **a failing image and a
working one look identical**: fbcon's penguins, then silence. Do not debug this
device by changing something and watching the screen. What works instead:

- **USB networking.** postmarketOS's initramfs raises a gadget macOS binds; the
  phone answers on 172.16.42.1 with a telnet shell on port 23, host at
  172.16.42.2. `fastboot boot` their image, mount the rootfs, and read it from
  there. This is how D25 and D26 were both found.
- **A getty on tty1 after boot.** Once the real root is running its getty writes
  to the VT and is visible.
- **The assertions in `image/verify/android-bootimg.sh`**, which read the
  cmdline back out of the artifact. On a device that cannot tell you what went
  wrong, a check before the flash is worth more than any amount of looking.

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
   too (49 and 65 lines). *Run on sargo 2026-09-14; the PinePhone half is still
   only built (AC 1).*
6. **D13 — DONE.** `manifest.toml` carries `[device.sargo]` with the kernel
   tag, real SHA256s and the config's provenance; `manifest_get` reads all five
   keys and the existing `manifest_components`/`manifest_aur_packages` scans
   are unaffected. `linux-moarchy-sdm670` and `moarchy-device-sargo` both
   build.
7. **D15-D17, D23-D26 — DONE, booted.** On 2026-09-14 moarchy came up on the
   handset from a boot image this repo produced: `linux-moarchy-sdm670` 7.1.3,
   no ramdisk, `root=PARTLABEL=userdata ro rootwait rootfstype=ext4
   init=/sbin/init`, through `fastboot boot` so that nothing was written while
   it was still a question. The panel, touch, autologin, sway and the shell all
   ran; the Adreno needs `linux-firmware-qcom`, which is why
   `moarchy-device-sargo` depends on it by name (Arch splits `linux-firmware`
   per vendor and the plain package carries every vendor but Qualcomm).

   Three of those criteria were found by booting and could not have been found
   any other way. **D25** (`init=/sbin/init`) is the one that cost a night:
   root was mounting correctly the whole time and the kernel panicked one
   `execve` later, which on a device with no console (D23) is the same picture.
   **D26** (the A/B retry counter) invalidated part of the measurement that
   preceded it — once `slot-unbootable:a:yes` is set the bootloader boots
   nothing, so a run of images tested after that point were all "failing"
   identically for a reason that had nothing to do with any of them. **D24**
   (no initramfs) removed the component all of it was being blamed on.

   The lesson worth keeping: on this device, a boot that produces no output is
   not evidence about the thing you changed. Check
   `fastboot getvar slot-unbootable:a` first, and get a shell — pmOS's
   initramfs at 172.16.42.1:23 — before forming a theory.

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

8. **D27 — BUILT, NOT MEASURED.** The radios. What is true off the device:
   `moarchy-qcom-modem` builds and installs `qrtr`, `rmtfs` and `tqftpserv`;
   both daemons link `libqrtr.so.1` (`readelf -d`, asserted in `build()` so a
   silent unlinked build fails rather than ships); their units name
   `/usr/bin/…` rather than `/usr/local/bin/…` and land in
   `multi-user.target.wants`; `firmware-moarchy-sargo` 0.2.2-2 carries thirteen
   files including `mba.mbn`, `modem.mbn` and five `.jsn` maps, with the two
   modem blobs checked for `\x7fELF` + `EM_QDSP6` so a truncated download fails
   the build rather than the boot. `image/verify/android-bootimg.sh` asserts
   every link of the chain in the image, and the Bluetooth firmware beside it.

   **Not yet done, and it is the only claim that matters:** no image has been
   built from this and nothing has run on the handset. "wlan0 exists" and "it
   associates" are both still unmeasured, and this file should not say
   otherwise until they are. The thing to read first on the device is
   `systemctl status rmtfs`, then `journalctl -b | grep -iE 'q6v5|mss|ath10k'`
   — a skipped `ConditionPathExists` and a failed firmware load look nothing
   alike and both end as "no Wi-Fi".

9. **D27–D30 — MEASURED ON THE HANDSET 2026-09-15.** The flashed image was
   booted and every claim below was read off the device rather than inferred.

   **Works:** Wi-Fi (associated, −55 dBm, `rmtfs`/`tqftpserv` active, all three
   remoteprocs `running`); Bluetooth (`hci0` a powered Primary controller after
   `bootmac`, ten devices discovered, survives a reboot); camera (live preview,
   both sensors); vibration (`drv2624:haptics`, confirmed by hand); NFC
   (`nfc0`); battery and charger (`qcom-battery`, `pm660-charger`); the Venus
   decoder (visible to PipeWire); touch, display and GPU.

   **Also works, found after the first pass:** the modem registers and
   **calls connect in both directions** (`o2 - de+`, LTE, `CS: 'attached'` as
   well as `PS`, so this network still offers circuit-switched fallback and
   needs no IMS); and audio, once D29's two missing files were added — card,
   earpiece, speaker and microphone all measured.

   **Calls carry audio** (D32), measured on a real call after `q6voiced`
   landed. So on this handset the phone is a phone: Wi-Fi, Bluetooth, camera,
   vibration, sound, and calls in both directions with voice on them.

   **Built and verified as an image, 2026-09-15:**
   `moarchy-sargo-0.2.2-20260915`, 132 checks passing and one failing — the
   dirty-tree provenance flag, from another session's uncommitted docs. The
   verify suite now asserts every link of the Wi-Fi chain, the audio chain,
   bootmac, and both halves of the camera fix.

   **Still open:** the image has **not been flashed**. Every fix from D27
   onward was proved by hand-installing onto a running phone, so this is the
   first artifact that carries the packaged form of all of it, and nothing has
   booted from it. That is the gap most likely to be mistaken for done. SMS is
   also unsent and unreceived, and should work on this SIM (`CS: 'attached'`).

   The Bluetooth AC that the previous revision of this file declined to write
   is now written, because the measurement it was waiting for has been taken.

AC 7 was the one that could fail for reasons none of the others predicted,
which is why it was last and why nothing above it depended on owning a Pixel
3a. It did fail that way, three times over, and D24–D26 are what came back.

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
- **Calls, Wi-Fi and Bluetooth — one decision, not three.** *All three
  answered and measured on the handset 2026-09-15; see D27, D28, D29, D32.*
  The modem stack is built and shipped: `mba.mbn` and
  `modem.mbn` from a third upstream, and `moarchy-qcom-modem` carrying qrtr,
  rmtfs and tqftpserv at three pins. `qbootctl` was the precedent and it held —
  upstream C projects, pinned and packaged, at the price of being the ones who
  notice when they move. It was four until reading the kernel showed the fourth,
  `pd-mapper`, had been replaced by `CONFIG_QCOM_PD_MAPPER` — which is the
  cheapest kind of scope cut and the reason D27 quotes sources rather than
  wikis.

  **It works.** Wi-Fi associates, Bluetooth pairs, and a call connects in both
  directions with voice on it — all read off the device rather than inferred.

  **Telephony was far closer than this file claimed,** and the order it
  actually went in is worth keeping, because almost none of it was the order
  predicted. `hexagonrpcd` was never involved — it is the sensors/FastRPC
  daemon. What it took, in the sequence it took:

  1. **A SIM**, and its PIN — which is why `moarchy.sim` exists (D28).
  2. ~~**`q6voiced`**~~ — done (D32). It is what holds `VoiceMMode1` open for
     the duration of a call; without it a dial is torn down immediately.
  3. **`81voltd`** — **not needed on this SIM, and that was luck rather than
     design.** `qmicli --nas-get-serving-system` reports `CS: 'attached'` as
     well as `PS`, capability `cs-ps`: o2's network still offers
     circuit-switched fallback, so the modem carries voice without IMS at all.
     A VoLTE-only operator would need this and the two below, and the next SIM
     is the thing that decides. (`gitlab.com/flamingradian/81voltd`, GPL-2.0,
     in pmaports as `temp/81voltd`) — a host-side implementation of the QMI IMS
     Data service.
     LTE carries no circuit-switched voice, so on a network with no 2G/3G
     fallback the modem must register with IMS, and it will not until something
     answers its request for an IMS PDN. Its only deps are `mm-glib` and
     `libqrtr` — and `moarchy-qcom-modem` already ships `libqrtr`, so this is a
     small package rather than a new stack. Same upstream author as the sargo
     modem firmware this project pins.
  4. **The IMS bearer's netdev**, which ModemManager creates and does not
     configure. Bringing it up with the bearer's own address is reportedly what
     turns an outbound SMS from a 25 s `WmsMessageDeliveryFailure` into a
     one-second success.

  Points 3 and 4 are read from a sibling project's notes on a OnePlus 6T
  (sdm845), not measured here — recorded as a map, not as fact. Its author
  reports 81voltd working on a Pixel 3a, which is encouraging and still
  second-hand. The userspace above all this is already in the image:
  ModemManager 1.24.2, libqmi 1.38, gnome-calls, chatty, mmsd-tng, callaudiod.

  **Bluetooth was never part of it,** and that is now a finding rather than a
  guess. Nothing identifiable is missing: the kernel has `BT_HCIUART_QCA` and
  `BT_QCA`, the DT enables `&uart6` with a `qcom,wcn3990-bt` child, the firmware
  is in `linux-firmware-atheros` (which `linux-firmware` pulls in), `bluez` is
  in `moarchy-meta` and `moarchy-firstboot` enables it. So the next step is to
  look at the device rather than to write a package — and D27 names the suspect
  (no `local-bd-address` in the DT) and the package that would answer it
  (`bootmac`, which pmOS gives every Qualcomm device) precisely so that the
  measurement has something to confirm or rule out. **?**

  The same `bootmac` question applies to Wi-Fi once it works, and is not a
  blocker either way: a `wlan0` on a firmware-default MAC associates fine and
  only becomes a problem when two of these phones meet one network.


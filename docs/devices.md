# Devices — specification

What a device is, what varies between one and the next, and who owns that
variation.

Status: **the Pixel 3a is the phone (2026-09-15).**
`moarchy-sargo-0.2.2-20260915` was built by `image/build.sh`, verified (132
checks), flashed over fastboot, and booted to the shell from a clean rootfs
with nothing of postmarketOS's anywhere in it. Our kernel, our device and
firmware packages, systemd, autologin, sway. There is no initramfs at all
(D24), and the bootloader confirms the slot is marked successful (D26).

On that image, measured rather than reported: **Wi-Fi, Bluetooth, sound,
camera, vibration, NFC, calls with voice on them, and SMS in both
directions** — D27 through D32. All of it from packages, with nothing
installed by hand. `pacman -S` works too, which it did not before
(`SECURITY_LANDLOCK`).

What is open on this device is quality rather than absence: a matrix-only
camera profile with no HueSatMap or look table, and telephony on an operator
with no circuit-switched fallback, which needs a SIM nobody here has.

**The PinePhone was dropped on 2026-09-19.** It was the only device that could
not clear Hyprland's GLES 3.0 floor, and it had not been booted since D1–D6.
[build-log.md](build-log.md) has the account. Every criterion below that named
it is amended or deleted rather than left standing with its own obituary
attached.

The acceptance criteria are the contract to argue with; where one is my reading
rather than your decision it is marked **?**.

Companion to [structure.md](structure.md), which decides what a package is and
where packages come from. This file decides what a *device* is. It amends one
of that file's non-goals, and §2 says so out loud rather than in a PKGBUILD.

---

## 1. What this decides

The target list is Pixel 3a (`sargo`, shipping) and Fairphone later. The
question is not "can moarchy run on a phone" — §9 says it does — but **what
varies per device, where that variation lives, and who owns it.**

Get that wrong and the next device costs as much as this one. Get it right and
it costs a package and two pins.

### 1.1 The Android phone is the template

Every device this project targets is the same shape: Qualcomm, fastboot, an
Android `boot.img`, A/B slots, AVB to defeat, non-removable storage, Adreno.
The Pixel 3a and the Fairphone 4/5 differ in their pins, not in their pipeline.

That is a decision rather than an observation, because it was once the other
way round. moarchy shipped first on a PinePhone, which booted from **raw
sectors** (the Allwinner BROM reads u-boot SPL at byte 131072), shipped on
**removable media** so the deliverable was a whole-disk image, had its kernel,
u-boot and firmware **already packaged for pacman** by DanctNIX, and had
neither A/B slots nor verified boot. Generalising outward from that device
would have made every one of those the default shape of something. **D0** is
the decision not to, and it outlived the device that prompted it: what is left
is the general case, and the next phone is an Android phone.

---

## 2. The non-goal this amends

`structure.md` §2 says, and meant:

> **A distribution.** We are not forking Arch Linux ARM or DanctNIX. Their
> kernel, u-boot, firmware, modem stack and ALSA UCM profiles are consumed as
> packages from their repos, never rebuilt here.

It held while DanctNIX packaged a whole device stack for us. It **cannot** hold
for an Android phone, and pretending otherwise is how this turns into a
surprise.

postmarketOS has done the SDM670 bring-up and maintains it well — the kernel
tree at `gitlab.com/sdm670-mainline/linux` was tagged `sdm670-v7.2.3_beta2` on
2026-09-03, and `device-google-sargo` sits in their *community* tier. But all
of it is Alpine `.apk`. There is no pacman repo anywhere that carries an
SDM670 kernel or the sargo firmware.

So for every device it ships, moarchy builds and publishes:

- a kernel package, from someone else's mainline fork, at a pinned tag
- a firmware package, from publicly-downloadable vendor blobs
- a device package tying them together

That is a distribution-shaped commitment: when the kernel tree moves, we move;
when it stops being maintained, the device is dead and we are the ones who
notice. It is the price of an Android phone and it does not get cheaper for the
next one.

**The amendment is narrow and stays narrow:** we package *what upstream has
already brought up*, at a pin, for devices we ship. We do not do bring-up, we
do not carry patches of our own against a kernel, and we do not package for
devices we do not ship. If a device needs us to write kernel code, it is out of
scope and the answer is no.

> We still consume from `[danctnix]` — `libdng` and `libmegapixels`, which
> `pkgbuilds/megapixels` links against and Arch Linux ARM does not carry. The
> repo outlived the phone it was added for.

### Other non-goals, unchanged

- **Not a device-support matrix.** One device shipping and a second chosen
  deliberately. A half-working third helps nobody.
- **Not runtime device detection.** An image is built *for* a device and says
  which. Nothing probes the SoC at boot to decide what it is (D3 is about
  hardware *values*, which is a different thing).
- **Not an Android app compatibility layer.** Amended by
  [android.md](android.md) §1: Halium stays out, Waydroid comes in as an
  optional package.

---

## 3. The shape

```
                       ┌─────────────────────────────┐
                       │  rootfs (device-independent)│
   moarchy-meta ──────►│  pacstrap + configure.sh    │
   moarchy-device-X ──►│  identical for every device │
                       └──────────────┬──────────────┘
                                      │
                                      ▼
                            boot/android-bootimg.sh
                            mkbootimg + AVB
                            → boot.img + rootfs.img
                              + flash.sh
```

One rootfs builder. One boot backend today, chosen by name. N device packages.

The indirection stays with a single backend in it. It was introduced with two
and has been exercised by both, which is the only reason it is known to be a
seam and not a guess; collapsing it back into `build.sh` now would throw away
the one part of this pipeline that has been demonstrated rather than assumed.

---

## 4. What is actually device-specific

Audited against the tree at `d258680`, not guessed. This is the whole list.

| # | coupling | where it is today | verdict |
|---|---|---|---|
| 1 | kernel, bootloader, firmware | was `image/build.sh:203`, now the device package's `depends` | **device package** `depends` — *done* |
| 2 | output scale, gaps, orientation | was a file in `default/sway/`, now `pkgbuilds/moarchy-device-sargo/sway.conf` | **device package** file — *done* |
| 3 | modem daemon | was `bin/moarchy-firstboot:71` — `eg25-manager`, now `DEVICE_SERVICES` in `device.conf` | **device package** — *done* |
| 4 | boot artifact + partitioning | `image/build.sh:287`–end | **boot backend** |
| 5 | battery sysfs path | `moarchy.device/Device.qml:166-167` — `axp20x-battery` | **probe**, no key |
| 6 | output name | `moarchy.control-center/ControlCenter.qml:825` — `DSI-1` | **probe**, no key |
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
  take the first. Correct on sargo, and on a device with a differently-named
  PMIC that nobody has plugged in yet.
- **Output** — ask sway. `swaymsg -t get_outputs` names the panel; the shell
  wants "the one output this phone has", not the string `DSI-1`.

**D3** states the rule: a `device.conf` key is justified only when the value
cannot be discovered at runtime. Scale (row 2) qualifies — nothing in sysfs
knows that 440 ppi wants scale 3, because that is a judgement about thumbs and
not a fact about hardware. The battery path does not qualify.

---

## 5. The device package

**D1** Each supported device has exactly one package, `moarchy-device-<codename>`,
built from `pkgbuilds/moarchy-device-<codename>/`. Codenames are the upstream
ones: `sargo`, `FP4`.

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

**D6** `config/sway/config` includes `/usr/share/moarchy/device/sway.conf`, a
fixed path owned by whichever `moarchy-device-*` package is installed. The
`moarchy` package owns nothing under `device/` — two packages cannot own one
path, and that is the boundary which makes a mistake here a build error rather
than a decision.

---

## 6. Boot backends

**D8** `image/build.sh` sources its backend from `image/boot/$BACKEND.sh`. The
device-specific work **interleaves** with the device-independent work rather
than sitting in a tail that could simply be cut off — provenance,
`configure.sh` and the rootfs trim all run between the kernel step and the
image step. So a backend is **three hooks, not one tail**:

- `backend_kernel` — after pacstrap: whatever this device needs doing to the
  kernel. On sargo, checks only, because this backend ships no initramfs (D24)
- `backend_fstab`  — what `/etc/fstab` should say; the disk layout is the
  backend's business, and sargo has no separate `/boot` partition to mount
- `backend_image`  — after the trim: assemble and compress the artifact

The hook order is load-bearing. Moving the kernel step to sit after
`configure.sh` would be a behaviour change smuggled in as a refactor.

**D9** One backend today:

- `android-bootimg` — `mkbootimg` with the DTB appended, a rootfs ext4, an
  AVB-disabling `vbmeta`. Output: a **directory** of `boot.img`, `rootfs.img`,
  `vbmeta.img` and a `flash.sh`, tarred and compressed.

*Amended 2026-09-19.* There were two; `sunxi-gpt` went with the PinePhone.

**D10** The artifact is a **directory, not an image file**, and that is not
papered over. An Android image is three files and a script you run with the
phone in fastboot; there is nothing to `dd`. Every script that consumes an
artifact takes that shape, and none of them infer it from an extension.

**D11** The backend is chosen by `DEVICE=<codename>`, defaulting to `sargo`.
`scripts/build-image.sh` passes it through and refuses a codename with no
`pkgbuilds/moarchy-device-<codename>/`.

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

**D12** `image/verify.sh` splits the same way. The backend asserts its own
artifact facts (boot.img magic, the DTB appended, vbmeta flags = 2, no
ramdisk, and the cmdline read back out of the header), and the behavioural
section — the first-boot scripts run in a chroot — stays shared because it is
about the rootfs.

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
1080×2220 at scale 3 is 360×740 logical, and **360 logical pixels wide is what
every layout constant in the shell was tuned against** — the bar height, the
app drawer grid, the keyboard's exclusive zone, the home strip. Nothing in sysfs
could have worked that out; it is a judgement about thumbs.

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
Seamless updates are explicitly not a goal; `pacman -Syu` is the update path.

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

**D33** *Added 2026-09-17, measured on the handset.* **Mobile data is one
packaged file, and NetworkManager refuses it at 0644.** The `moarchy` package
ships `/usr/lib/NetworkManager/system-connections/moarchy-mobile-data.nmconnection`
at **mode 0600**, carrying `[gsm] auto-config=true` and nothing else.
`docs/control-center.md` S29 is the tile that switches it.

> **Nothing was missing below the profile, which is why this is a file and not
> a stack.** Read off the phone before anything was written: NetworkManager
> 1.58.1 already had the modem as a **gsm device** (`qrtr0`, ports `qrtr0 (qmi)`
> and `rmnet_ipa0 (net)`), `nmcli radio` already reported `WWAN-HW enabled` and
> `WWAN enabled`, and `mobile-broadband-provider-info 20251101` was already in
> the image — ModemManager pulls it in. So the operator's APN, username and
> password are all resolvable from the SIM, and there is nothing per-operator
> to maintain and no APN in the file.
>
> **The mode is the whole difficulty, and it fails silently.** The keyfile
> reader refuses any profile the group or the world can read, *wherever it
> lives* — /usr/lib included, secrets or none:
>
> ```
> keyfile: load: ".../moarchy-mobile-data.nmconnection":
>          failed to load connection: File permissions (100644) are insecure
> ```
>
> That is one `<warn>` in a journal nobody is tailing, and the phone is then
> indistinguishable from one with no profile at all: a SIM in the tray, bars on
> the bar, and no data. The first install of this file shipped 0644 and did
> exactly nothing. `image/verify.sh` asserts the mode for that reason, not the
> file.
>
> **/usr/lib and not /etc**, for three reasons that agree: a package's files
> belong in a system path (`docs/structure.md` P8, which is also why this is
> not a line in `moarchy-firstboot`), `image/verify.sh` counts the profiles in
> `/etc` to catch a baked-in credential, and NetworkManager copy-on-writes a
> read-only profile into `/etc` the moment anything edits it — same uuid, 0600
> root:root — which is what makes the tile's `off` outlive a reboot (S29c).
>
> Device-independent on purpose: every phone moarchy targets has a modem that
> NetworkManager presents as a gsm device, so this sits beside ModemManager's
> own placement in `moarchy-firstboot` rather than in a device package. Only
> sargo has run it.
>
> **What is measured, and what is not.** Loaded at 0600, the profile appears in
> `nmcli c show`, NetworkManager derives a uuid from the filename,
> auto-activates it unprompted, and parks the device at
> `connecting (need authentication)` — which is it waiting for the SIM PIN.
> `bin/moarchy-data` reads and writes all of that correctly against a locked
> SIM, and the tile draws it.
>
> **It carries data, measured end to end 2026-09-17** on a Telefónica Germany
> SIM (MCC-MNC `26203`, `o2 - de+`), minutes after the PIN was entered and with
> nothing else done by hand:
>
> ```
> modem       state connected, reg home, PS attached, LTE, signal 81%
> bearer      connected, multiplexed, apn internet.eplus.de, user eplus
> IPv4        10.132.10.120/28 gw 10.132.10.121 dns 62.109.121.17,.18
> IPv6        2a02:3032:1b:3a68::/64, dns 2a02:3018:0:40ff::aaaa,::bbbb
> route       default via 10.132.10.121 dev qmapmux1.0 metric 700 (see below)
> fetch       http=200 in 0.44s bound to the cellular netdev
> public ip   176.0.20.10 over cellular, against the Wi-Fi v6 address over wlan0
> ```
>
> **The APN was never configured anywhere.** `internet.eplus.de`, `eplus` and
> `gprs` came out of `mobile-broadband-provider-info` via `auto-config`, which
> is the whole case for shipping one profile with no operator in it.
>
> Wi-Fi keeps the default route at metric 600 against cellular's 700, so a
> phone on both prefers Wi-Fi without anything having to say so.
>
> **The netdev is not `rmnet_ipa0`, and it has no fixed name.** The bearer
> comes up *multiplexed*, so the traffic is on a QMAP channel —
> `qmapmuxN.0@rmnet_ipa0` — while `rmnet_ipa0` holds a link-local address and
> nothing else. A `curl --interface rmnet_ipa0` against a working connection
> fails, which is a good hour to lose.
>
> **N changes.** This phone was `qmapmux1.0` on the first connect and
> `qmapmux0.0` after one off/on twenty minutes later, with a new address and
> gateway each time (`10.132.10.120/28`, then `10.132.110.212/29`). Anything
> that needs the interface reads it from the default route or from `mmcli -b
> <bearer>`; a hardcoded `qmapmux1.0` is a check that passes once. Both
> connects answered `http=200` over the channel actually in use.
>
> **The modem re-enumerates on reconnect.** One `moarchy-data off; on` took it
> from `Modem/1` to `Modem/0`, and NetworkManager had no gsm device at all for
> several seconds around it — long enough that the tile, bound to "is there a
> modem now", hid itself immediately after being switched on. `docs/control-center.md`
> S29 latches it; `moarchy-data status` answers `sim=` rather than
> `sim=missing` in that window, because a device NetworkManager has lost says
> nothing about the tray.

**D34** *Added 2026-09-19, measured on the handset.* **The speakers were quiet
in three places at once, and only one of them was a volume control.**
`alsa-ucm-conf-moarchy-sdm670` enables both CS35L36 boost converters,
`moarchy` ships `moarchy-loudness.service`, and `moarchy-device-sargo` depends
on `swh-plugins` and carries the filter graph it runs.

> Reported as "Spotify is very quiet" while playing through Waydroid. Every
> stage that has a number was already at its maximum: the PipeWire sink at
> 100%, the `Waydroid` sink-input at 100% and uncorked, `Top`/`Bottom Analog
> PCM Volume` 19/19, `Digital PCM Volume` 816/816. A phone at full volume,
> quiet.
>
> **1. Android has its own volume, and nothing on this phone can reach it.**
> `STREAM_MUSIC` was at **13 of 15** — about -6.5 dB on Android's curve. The
> volume rocker (`default/sway/bindings.conf`) and the control center's slider both
> drive the PipeWire sink, which had no headroom left, so turning the volume up
> was a no-op that looked like a broken rocker. `cmd media_session volume
> --stream 3 --set 15` sets it; `media volume` is not a command in this image.
> This one is not packaged and cannot be: it is state inside the Android
> container, and it is the first thing to check when Waydroid is quiet
> (`docs/android.md`).
>
> **2. Both speaker amplifiers had their boost converters bypassed.** The amps
> are Cirrus **CS35L36**s (`cs35l36.2-0040` top/earpiece, `2-0041` bottom), and
> the device tree provisions a **10 V rail** for them —
> `cirrus,boost-ctl-millivolt = 10000`, 1 uH, 1800 mA peak. Both
> `BOOST Enable Switch` controls read `off`, so the amps were swinging against
> VBAT. This was the only hardware gain the phone had left, and it is audible.
>
> The cset goes in the Speakers **EnableSequence**, not `BootSequence` where a
> volume default would naturally live, because **this device's boot sequences do
> not take**: `BootSequence` sets `Top Analog PCM Volume` to 17 and it reads 19;
> `FixedBootSequence` sets four ramp and zero-cross switches to 1 and all four
> read `off`. `EnableSequence` does take — `SEC_TDM_RX_0 Voice Mixer
> VoiceMMode1` reads `on` and nothing else sets it — and it re-runs on every
> profile switch.
>
> **WirePlumber parses the UCM once and caches it.** Editing the profile and
> cycling the card profile re-runs the *old* sequence, which is indistinguishable
> from a patch that does not work. Verified the way that could fail instead:
> forced both controls `off`, restarted `wireplumber`, and watched them come
> back `on` by themselves.
>
> **3. The headroom was going unused, which is what "quiet" actually meant.**
> With the first two fixed, music still reached the speaker at **-17.0 dBFS RMS
> with peaks at -3.6**. That gap is the loudness: a small driver only ever sees
> the peaks, and spends the rest of its time far from the excursion the
> amplifier could give it. An SC4 compressor into a fast lookahead limiter
> closes it.
>
> | | RMS | peak |
> |---|---|---|
> | as reported | -23.7 dBFS | -10.0 dBFS |
> | `STREAM_MUSIC` 15/15 | -17.0 dBFS | -3.6 dBFS |
> | + compressor and limiter | **-10.8 dBFS** | -0.5 dBFS, zero clipped |
>
> **Measure the monitor, not the room.** Every layer here reports a healthy
> number while the sound is quiet, so the only honest instrument is
> `parecord` on the sink's `.monitor` and RMS in dBFS. Two approaches were tried
> and abandoned first: recording the built-in microphone clips at
> `ADC1 Capture Volume` 63/63, and A/B-ing against whatever music happens to be
> playing is worthless — the *same* setting drifted **8.7 dB** between two runs,
> which is larger than the effect being chased. (`audioop` is gone in Python
> 3.13; compute RMS from `array` by hand.)
>
> **The filter runs as a client, and that is not a style choice.** A drop-in on
> the daemon's own config would mean restarting PipeWire, and a `pipewire-pulse`
> restart drops Waydroid's audio HAL connection — the HAL does not reconnect,
> so Android goes silent until the container restarts. `pipewire -c
> filter-chain.conf` in its own unit builds the sink against the running daemon.
>
> **`priority.session = 2000` is load-bearing.** The filter sink has to outrank
> the ALSA sink or a freshly flashed phone, with no stored WirePlumber state,
> elects the hardware sink and routes nothing through the graph — a chain that
> is built, correct, and inaudible. Verified by deleting
> `default.configured.audio.sink` from the WirePlumber state and restarting it.
>
> **Not measured:** loudness in SPL, battery cost of the 10 V rail, and whether
> the compressor settings hold up on speech or podcasts — they were tuned by ear
> against music, and they are live-adjustable with `pw-cli s <id> Props` for
> exactly that reason.

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

**D18** *Amended 2026-09-19.* **The GLES 2.0 ceiling left with the device that
imposed it.** It was never a moarchy fact; it was an Allwinner A64 fact. Every
device on the target list has an Adreno and clears GLES 3.2, which is what
makes upstream Omarchy's own compositor reachable again.

What the shell targets is therefore a *choice* from here on, and
`docs/style.md` owns it: it must state the floor out loud rather than leave it
as an assumption inherited from hardware nobody here still has. A motion budget
sized for a Mali-400 is not wrong on an Adreno, but it is no longer forced, and
the difference has to be written down or the next device silently violates it.

---

## 9. Acceptance criteria

**D0** The Android-phone case is the general one. A change that makes
removable media, raw-sector boot, or a whole-disk `.img.xz` the default shape
of anything is wrong: no device on the target list works that way, and the one
that did is gone.

Restated as a checklist, in build order. Each carries its state.

1. **D1/D2/D3 — DONE.** `moarchy-device-sargo` is the only package naming
   hardware, and `device.conf` carries the codename, the modem services and the
   grow policy. Nothing else in the tree names a phone.
2. **D6 — DONE.** `config/sway/config` includes `/usr/share/moarchy/device/sway.conf`;
   `pacman -Qo` on the installed path names `moarchy-device-sargo`, and the
   `moarchy` package owns nothing under `device/`.
   `image/verify.sh`'s existing "every absolute sway include resolves" check
   covers this in the image without modification.
3. **D4/D5 — DONE, demonstrated.** Against a throwaway second device package:
   two at once gives `unresolvable package conflicts detected ... are in
   conflict`; `moarchy-meta` with none gives `unable to satisfy dependency
   'moarchy-device'`. Neither was assumed.
4. **§4 rows 5-7 — NOT STARTED.** Battery and output are probed;
   `axp20x-battery` and `DSI-1` appear nowhere in the tree.
   `moarchy-has-keyboard`'s comment is corrected.
5. **D8-D12 — DONE, run.** `image/build.sh` sources `image/boot/$BACKEND.sh`
   and calls `backend_kernel`, `backend_fstab` and `backend_image`; it refuses
   a `DEVICE` with no device package and a device with no backend.
   `image/verify.sh` splits the same way into `image/verify/$BACKEND.sh`
   (`verify_artifact`, `verify_grow`, and the optional `verify_rootfs`),
   inferring the device from the artifact name. *Run on sargo since
   2026-09-14.* The contract is exercised by `image/boot/test-backends.sh`,
   which is what keeps it a contract now that one backend implements it.
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

   **D22** Growth is a per-device policy, not a probe. `DEVICE_GROW=filesystem`
   on sargo, where the rootfs sits in `userdata` inside a vendor GPT that also
   holds `xbl`, `abl`, `tz` and the A/B slots. Running `sfdisk` there would
   rewrite a vendor partition table on a phone with no removable storage and no
   recovery image — the one irreversible thing this project could do to a
   device. `DEVICE_GROW=partition` existed for a device with removable media
   and went with it; the key stays because the *next* device's answer is not
   knowable from sysfs either. The key
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

   **Flashed and booted 2026-09-15.** `moarchy-sargo-0.2.2-20260915` went onto
   the handset over fastboot (166 s, slot marked active), left the bootloader
   and came up. This is the first artifact carrying the packaged form of
   everything from D27 onward — until now every one of those fixes had only
   ever been hand-installed onto a running phone — and it was reported working
   on the device.

   **Measured on that fresh rootfs**, after re-authorising a key by hand —
   a published image has no sshd and no credentials, so getting back in costs
   a person at the screen:

   ```
   kernel      7.1.3-sdm670, LSMs lockdown,capability,landlock,yama,bpf
   pacman      `pacman -S tree` installs over the network, sandbox on,
               no DisableSandbox in pacman.conf
   Wi-Fi       associated, -48 dBm
   modem       rmtfs / tqftpserv / q6voiced all active; cdsp, adsp and
               4080000.remoteproc all running
   Bluetooth   Controller 02:00:FF:14:0F:1B — the same serial-derived
               address as before, unattended, with nobody running btmgmt
   sound       0 [G3a]: sdm660 — Google Pixel 3a, sink "Earpiece (L) and
               Speaker (R)"
   camera      Found calibration file at
               /usr/share/megapixels/config/google,b4s4-sdm670,Front.dcp
   ```

   Every one of those was a hand-installed file this morning. The Bluetooth
   address and the camera profile are the two worth singling out: both prove
   the *packaging* rather than the fix, because both appear with nothing run by
   hand at all.

   **SMS works, both directions, on the flashed image.** Measured rather than
   assumed: `chatty-history.db` holds three rows within three seconds of each
   other, two `direction -1` and one `direction 1`, and ModemManager's journal
   shows `/SMS/1` consumed and deleted — the app took the message off the modem.
   So the whole receive path ran: modem → ModemManager → chatty → store. No
   `81voltd` and no IMS, because this operator still offers circuit-switched
   fallback (`CS: 'attached'`); a VoLTE-only SIM would need §10's items 3 and 4.
   Message bodies were not read; lengths were enough.

   **Nothing on the sargo feature list is untested any more.** The remaining
   open items are quality rather than absence: camera colour beyond a
   matrix-only profile (no HueSatMap, no look table), and telephony on a
   VoLTE-only operator.

   One expected behaviour worth not mistaking for a fault: the SIM re-locks on
   every boot, so the modem reads `locked` until someone enters the PIN. That
   is what `moarchy.sim` is for (D28).

   The Bluetooth AC that the previous revision of this file declined to write
   is now written, because the measurement it was waiting for has been taken.

10. **D34 — MEASURED ON THE HANDSET 2026-09-19; PACKAGED, NOT YET BUILT OR
    FLASHED.** The speaker loudness work. What was measured on the running
    phone, with the tuned chain live: music reaching the speaker went from
    **-23.7 dBFS RMS / -10.0 peak** as reported, to **-10.8 dBFS RMS / -0.5
    peak with zero clipped samples**, across three independent causes —
    Android's own `STREAM_MUSIC` at 13/15, both CS35L36 boost converters
    bypassed, and the crest factor nothing was reclaiming.

    Each half of the persistence was verified against the case that would fail,
    not the case that would pass: the boost cset by forcing both controls
    `off` and watching a `wireplumber` restart bring them back `on`, and the
    default-sink election by deleting `default.configured.audio.sink` from the
    WirePlumber state and confirming the filter sink still won on
    `priority.session`. The packaged fragment was moved to
    `/usr/share/pipewire/filter-chain.conf.d/` and the hand-placed copy under
    `~/.config` removed before that test, so the path the package ships to is
    the path that was measured.

    **Not done:** no package has been rebuilt from these PKGBUILDs, so the
    `sed` that patches `VoiceCall.conf` has been proved only against the
    pristine upstream file outside makepkg, and nothing has been flashed. Until
    an image carries it, the claim is that the *fix* works and not that the
    *packaging* does — the same distinction AC 9 draws, and the one this
    project keeps having to redraw.

    **The handset carries hand-placed copies that will collide, and they have
    to go before these packages are installed on it.** Whoever installs them
    first should remove all three, because each one *wins* against the package
    rather than losing to it:

    ```
    /usr/share/pipewire/filter-chain.conf.d/99-loudness.conf   # -> two graphs
    ~/.config/systemd/user/moarchy-loudness.service            # -> shadows /usr/lib
    ~/.config/systemd/user/pipewire.service.wants/moarchy-loudness.service
    ```

    The first is the worst of them: PipeWire reads every fragment in that
    directory, so the hand-placed one and the packaged
    `99-moarchy-loudness.conf` build **two** chains, both claiming
    `priority.session = 2000`. A user unit also takes precedence over
    `/usr/lib/systemd/user`, so the old copy would keep running after an
    upgrade changed the packaged one. `pacman` will additionally refuse the
    unowned `/usr/share` path with "exists in filesystem" — compare first, then
    `--overwrite` scoped to it. The device also still carries `alsa-utils`,
    installed by hand for `amixer` and deliberately not packaged.

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


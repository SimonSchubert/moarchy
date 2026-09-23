# Fairphone 4 — port status

**This port runs on a Fairphone 4.** Status: **boots, and is usable as a
phone** (2026-09-23).

What has been exercised on the handset: display, touch and rotation, the USB
debug gadget, camera, sensors, the built-in microphone, both speaker
amplifiers, microphone and speaker together, and cellular calls with audio in
both directions. [`fp4-defects.md`](./fp4-defects.md) is the register of
everything found by running it, defect by defect, with status and evidence —
read that for what is still open, which includes Wi-Fi latency (D5), a boot
race that can take all audio with it (D10), and drops into EDL (D11).

Three of the four gaps §10 predicted turned out to be kernel gaps rather than
port bugs, and were closed with kernel work rather than configuration. That
work is upstream-bound rather than carried here:

| gap | where it went |
| --- | --- |
| microphone | [sm6350-mainline/linux#11](https://github.com/sm6350-mainline/linux/pull/11) — LPASS macros, SoundWire, the codec node, its own capture front end |
| speaker | [sm6350-mainline/linux#12](https://github.com/sm6350-mainline/linux/pull/12) — a mainline `aw88264` driver, and the FP4 switched onto it |
| call audio | a q6voice port; left out of #11 because [sc7280-mainline/linux#35](https://github.com/sc7280-mainline/linux/pull/35) already merged the same stack for the Fairphone 5, and converging on that beats a second port. Findings written up on [sc7280-mainline/alsa-ucm-conf#6](https://github.com/sc7280-mainline/alsa-ucm-conf/pull/6) |

**How to read the rest of this file.** Everything below §1 was written *before*
a handset existed, and its section headings say what each claim was verified
against — postmarketOS's own packages, a real download, a measured size. That
framing is kept rather than rewritten, because it records what was inferred
versus what was checked, and inference is exactly where the port was wrong.
Where hardware has since contradicted or confirmed something, the defect
register says so and is the newer document.

Companion to [devices.md](devices.md), which decides what a device *is*. This
file is about one device and how far it has got. It closes one of that file's
open questions in §10 — "Fairphone codename and tier" — and opens several of
its own.

---

## 1. What this answers

devices.md §10 said:

> **Fairphone codename and tier.** FP4 and FP5 are both pmOS community, both
> fastboot; which one, and whether the `android-bootimg` backend covers it
> unchanged, is unverified.

Answered, in both halves:

- **Which one: the FP4**, codename `fp4` here and `fairphone-fp4` in
  postmarketOS. Community tier, maintained by Luca Weiss, who also maintains
  the kernel fork and the firmware package. Checked against pmaports `main` on
  2026-09-21, not against the wiki.
- **Does `android-bootimg` cover it: almost.** It needed four new per-device
  facts and no new code path. They are listed in §4.

---

## 2. What was verified, and against what

Each of these was read off a live service or computed from a real file. None
of it is recalled or inferred.

| Claim | How it was checked |
| --- | --- |
| FP4 is in pmaports' **community** tier | `device/community/device-fairphone-fp4` exists in the pmaports tree listing |
| Kernel is `linux-postmarketos-qcom-sm6350`, **v7.2.0-sm6350** | read that APKBUILD; `v7.2.0-sm6350` is also the newest tag on `sm6350-mainline/linux` |
| The vendored kernel config is genuinely upstream's | its sha512 matched the one pmaports publishes, **before** the one-symbol edit |
| The kernel needs **clang** | `CC_IS_CLANG=y`, `LTO_CLANG_THIN=y`, `SHADOW_CALL_STACK=y`, `CLANG_VERSION=220108`, `GCC_VERSION=0` in that config |
| A **no-initramfs boot is possible** | `SCSI=y`, `BLK_DEV_SD=y`, `SCSI_UFSHCD=y`, `SCSI_UFSHCD_PLATFORM=y`, `SCSI_UFS_QCOM=y`, `PHY_QCOM_QMP_UFS=y`, `EXT4_FS=y`, `EFI_PARTITION=y` — all built in, none a module |
| `SECURITY_LANDLOCK` is **off** upstream | `# CONFIG_SECURITY_LANDLOCK is not set` in that config, with `SECURITY=y` and `landlock` already first in `CONFIG_LSM` |
| Firmware pin is the bytes pmOS ships | downloaded the FairBlobs tarball at the pinned commit; its sha512 matched pmaports' published one exactly |
| `pil-squasher` is genuinely required | the tarball carries **6** `.mdt` headers with `.bNN` segments beside them |
| …and it works on these blobs | ran it: 6 images merged, each a valid `ELF 32-bit LSB executable, QUALCOMM DSP6` |
| `wlanmdsp.mbn` ships **pre-merged** | there is no `wlanmdsp.mdt`; the `.mbn` is in the tarball whole |
| The four vendored device files are upstream's | sha512 of each matched pmaports' published hashes |
| Flashing shape: `boot` + `userdata`, then `erase dtbo` | pmOS wiki's manual-install section for this device |
| `userdata` is a real, flashable partition | the wiki's `fdisk` dump: `/dev/sda11`, 102.8 GiB, GPT name `userdata` |
| Panel is 1080×2340 | `deviceinfo_screen_width/height` in the device package |
| **No microphone, no call audio** in upstream's own profile | `ucm/HiFi.conf` defines `SectionDevice."Speaker"` and nothing else — no capture device, no `VoiceCall` verb |
| **Our boot image's geometry matches one that boots this phone** | compared against postmarketOS's own published FP4 boot.img (edge, 20260918): `kernel_addr`, `ramdisk_addr`, `second_addr`, `tags_addr`, page size and header version are **identical** |
| **Our device tree IS the one pmOS boots** | the appended DTB is **byte-identical** to the one in that image — sha256 `399eb1f6…`, 88067 bytes, both |
| The flash sequence is correct, including its failure path | driven against a mock `fastboot`: the normal run issues `flash boot` → `flash userdata` → `erase dtbo` → `--set-active` → `reboot` and no vbmeta; with `erase dtbo` failing it still reaches `--set-active`; a locked bootloader or absent device refuses before any write |

The microphone row is not a gap in this port. It is upstream's own audio
configuration saying the same thing the wiki says in prose, and it means a
working build will still have no microphone.

**The two boot-image rows are the strongest evidence in this file**, and they
were not available until postmarketOS's prebuilt FP4 image was fetched and
taken apart. Everything else here says "this follows from what upstream
declares". Those two say "this is the same bytes as something that
demonstrably starts this handset". They do not prove the phone will boot —
our boot image carries no initramfs where pmOS's carries 13.8 MB of one, and
the kernel command lines differ accordingly (§9) — but the geometry and the
device tree, which are the two things that fail silently and identically, are
now matched rather than inferred.

---

## 3. What is NOT verified

Everything below is reasoned from the above and has never been executed.

- **That the image boots.** Nothing has been flashed. The kernel has not even
  been compiled yet on this host — see §6.
- **That the boot image is the right shape for this bootloader.** The header
  offsets in `image/boot/android-image.py` were measured off a *sargo*
  boot.img. The FP4's `deviceinfo` declares the same page size (4096) and the
  same kernel offset (`0x00008000`), which is why the same code is being
  reused — but "the numbers agree" is not "a phone accepted it".
- **That skipping vbmeta is right.** Reasoned from pmOS flashing none and from
  Fairphone saying critical partitions need no unlocking. If the phone rejects
  the kernel, this is the first thing to change (§7).
- **Which path the speaker amplifier firmware is requested from.** The package
  installs it under both `/usr/lib/firmware/` and
  `/usr/lib/firmware/postmarketos/` precisely because this is unresolved.
- **That upstream's Bluetooth firmware suits this board.** The image uses
  `linux-firmware-atheros`'s `qca/apbtfw11.tlv` and `qca/apnv11.bin` rather
  than Fairphone's, because two packages cannot own one path and Arch's is the
  maintained copy. They are different bytes (230260/4875 vendor against
  225236/4878 upstream), and `apnv11.bin` is board-specific NVM calibration.
  The wiki reports Bluetooth working — with the vendor blobs. This is the one
  substitution in the firmware package that has not been checked against the
  original, and `pkgbuilds/firmware-moarchy-fp4` records the one-command test
  if Bluetooth misbehaves.
- **That the kernel package can be rebuilt by the documented pipeline.** The
  one in this image was cross-compiled out of band, in an x86_64 container, to
  avoid ~5-12 hours of emulation (§6). It is a correct aarch64 package —
  verified as such — and `packages/.build-manifest` vouches for its bytes, but
  `provision.sh build` did not produce it. The PKGBUILD's fetch, extract and
  `prepare()` path has been exercised since and works; only the compile itself
  has not been run through the container. Delete the package and rebuild if
  that guarantee matters more than the hours.
- **That `hexagonrpcd` is not needed to boot.** It is needed for sensors, and
  it is not packaged for Arch. Nothing suggests the DSPs need it to *start*,
  but nothing has proven they do not.

---

## 4. What the port actually consists of

Nine files. The shape of the change is the evidence for D0's claim that the
next Android phone would be cheap:

| Added | What |
| --- | --- |
| `manifest.toml` `[device.fp4]`, `[pil-squasher]` | the pins |
| `pkgbuilds/linux-moarchy-sm6350/` | kernel, `v7.2.0-sm6350`, + the vendored config |
| `pkgbuilds/firmware-moarchy-fp4/` | the FairBlobs blobs |
| `pkgbuilds/pil-squasher/` | the tool that merges them |
| `pkgbuilds/moarchy-device-fp4/` | device facts, UCM, udev, WirePlumber |
| `docs/fairphone-4.md` | this file |
| `scripts/deploy-fp4.sh` | build + verify + flash, in one command |

| Changed | How much |
| --- | --- |
| `image/build.sh` | one `case` line |
| `image/boot/android-bootimg.sh` | four new per-device facts; no new code path |
| `image/verify.sh` | one `case` line, and a `note()` helper |
| `image/verify/android-bootimg.sh` | the hardware chains guarded per device, + an fp4 set |

The four new device facts, and why each is a fact rather than a generalisation:

- `KFLAVOR` — two SoCs cannot share `/usr/share/kernel/<flavor>/`.
- `ROOT_BUILTINS` — sargo boots off eMMC, the FP4 off UFS. A shared list would
  be the union, and on a kernel that enables both it would pass on either
  phone while checking the wrong half on one of them.
- `ERASE_DTBO` — the FP4 has a `dtbo` partition whose Android overlays must
  not be applied to a mainline DT. sargo has no such partition.
- `NEEDS_VBMETA` — sargo's bootloader demands one; the FP4's does not take one.

Nothing else in the backend moved. `DTB_NAME` and `ROOT_PARTLABEL` already
existed, and `ROOT_PARTLABEL` is `userdata` on both phones.

---

## 5. What will not work, even when it boots

These are upstream limits today. This repo cannot fix them by packaging, and
should not claim to — but they are not permanent, and §10 is the plan for
closing each one and sending the result upstream rather than patching around
it here.

- ~~**The built-in microphone does not work.**~~ **Fixed 2026-09-23** — it
  records. The pmOS wiki says otherwise and upstream's UCM profile still has
  no capture device, both of which were true when this was written; what was
  missing was the device tree, and after that a UCM capture device and two
  PipeWire corrections. See §10.1 and `docs/fp4-defects.md` D13.
- **Cellular calls connect with no audio.** SIP calls work (GNOME Calls is in
  the image).
- **Wi-Fi is not continually usable.** It associates, then degrades with
  latency spikes and eventually drops. Tracked as
  [pmaports#2841](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/work_items/2841).
  This matters more here than it would elsewhere: moarchy updates over
  `pacman -Syu` from `[moarchy]`, and the store installs over the network.
- **NFC does not work**, and neither does the **fingerprint reader**.
- **The camera is partial** — focus is locked at roughly 20 cm, and there is no
  ToF and no actuator support. This port ships no colour profile for it, unlike
  sargo, because the sensors do not stream.
- **Sensors work as of 2026-09-22.** This entry used to say `hexagonrpcd` was
  not packaged for Arch and the sensors therefore had no source. It is
  packaged now (`pkgbuilds/hexagonrpc`), and with `libssc` and
  `iio-sensor-proxy` beside it the accelerometer, gyroscope, magnetometer,
  compass, light and proximity sensors all return real data on the handset.
  Rotation is still manual, because that is a shell decision rather than a
  missing sensor.

What *is* reported working upstream: display, touch, 3D (Adreno 619 on
freedreno), Bluetooth, GPS, SMS, mobile data, USB networking, the speaker,
haptics, and the SD card.

---

## 6. Before the first flash: unlocking, and why the order matters

The bootloader has to be unlocked, and on this device that **cannot be done
from fastboot alone** — it starts in Android, which means it cannot be left
until the phone is already in your hand and half-flashed.

1. Boot the phone into Android, finish setup, join Wi-Fi. **Do not sign in to
   a Google account and do not restore a backup.** Step 6 wipes every bit of
   it, and nothing in this process touches the Play Store — system updates
   come from Fairphone's own updater, which needs no account. Wi-Fi is the
   only connectivity required, for step 2 and for the toggle in step 4.
2. **Update to the latest Fairphone OS.** Not optional politeness —
   postmarketOS says "development is mostly done on the latest firmware", and
   §4 is the reason it matters here: this image flashes `boot` and `userdata`
   and *nothing else*. `xbl`, `abl`, `tz`, `hyp`, `modem` and `dsp` stay
   exactly as Fairphone shipped them, and the mainline kernel talks to those.
   Updating first removes a variable nobody wants to debug later.

   A phone bought new may be several releases behind and will chain through
   them one at a time, so keep re-checking until it reports itself up to date
   rather than stopping at the first success. A unit shipped on Android 13
   (`FP4.TP31.*`, September 2025) has to climb to Android 15 to get current.
3. Enable Developer Options — tap Build Number seven times in About Phone.
4. Settings → System → Developer options → **OEM unlocking** — newer builds
   label it *Bootloader Unlocking* — and toggle it on. The phone must be
   online.

   On builds from **June 2026** onward that is the whole step: Fairphone
   simplified the process and **no unlock code is needed**. On older firmware
   the toggle opens an *Input verify code* popup instead, and the code comes
   from <https://www.fairphone.com/bootloader-unlocking-code-for-fairphone>,
   which wants **IMEI 1 and the serial number** (`*#06#` shows both). Doing
   step 2 properly is the easier way past this.

   `adb shell getprop sys.oem_unlock_allowed` reads `1` once the toggle has
   taken; while it still reads `0`, step 6 will refuse.
5. `adb reboot bootloader`
6. `fastboot flashing unlock`, then confirm on the phone's own screen with the
   volume and power keys.

**`fastboot flashing unlock_critical` is NOT needed**, and that is the same
fact `NEEDS_VBMETA=no` rests on: vbmeta is a critical partition, this image
does not write one, and pmOS's own install notes say critical partitions stay
locked.

Unlocking **wipes the phone**, so it comes before anything you would mind
losing. Budget an hour for steps 1–2 alone, most of it waiting on the update.

> **Do not re-lock the bootloader afterwards.** With an unsigned OS installed,
> re-locking is the one genuinely unrecoverable mistake available here: the
> bootloader refuses to boot what it finds and refuses to unlock again.
> Nothing in this repo does it; it is listed because it is the thing to avoid
> once the phone is yours again.

## 7. Recoverability — what this can and cannot break

Worth stating plainly, because it is the first question worth asking.

The boot chain is **PBL (ROM) → XBL → ABL → boot.img**, and *fastboot is ABL*.
This pipeline writes three things:

```
fastboot flash boot boot.img          the current slot's boot image
fastboot flash userdata rootfs.simg   data
fastboot erase dtbo                   Android's DT overlays; empty is valid
```

It never writes `xbl`, `xbl_config`, `abl`, `tz`, `hyp`, `aop`, `modem`,
`devcfg`, `keymaster`, or the partition table. Those are the things whose loss
is fatal, and nothing here addresses them. `moarchy-grow-rootfs` on the phone
runs `resize2fs` and nothing else — no `sfdisk`, no `parted` — which is what
`DEVICE_GROW=filesystem` means and what verify-image.sh asserts.

So the worst realistic outcome — bad kernel, corrupt image, power lost
mid-write — is a phone that does not boot while ABL still does: hold Volume
Down, plug in USB, and fastboot is there to reflash from. The other slot's
boot image is untouched as well.

What is genuinely lost either way is `userdata`, which is shared between slots
rather than per-slot. Android's data does not survive this even if you switch
back.

## 8. Building it

```bash
./scripts/deploy-fp4.sh          # preflight, packages, image, verify, flash
./scripts/deploy-fp4.sh image    # or one stage at a time
SKIP_FLASH=1 ./scripts/deploy-fp4.sh
```

**It needs no root.** The build runs under **rootless podman** when podman is
installed, which is the default when both engines are present; set
`MOARCHY_CONTAINER=docker` to force the other. Nothing in the pipeline actually
requires root: `image/build.sh` deliberately avoids loop devices, and the one
privileged thing left — `arch-chroot`'s bind mounts — works inside a user
namespace. Using docker instead costs a root daemon and membership of a group
equivalent to root, for no capability this build uses.

`scripts/container.sh` owns the differences between the two engines and
documents each one. The three that matter:

- Podman does not resolve short image names, so both Dockerfiles now write
  `docker.io/` out. This is engine-neutral — docker accepts it too.
- The package builder runs as `builder` (uid 1000), because makepkg refuses to
  run as root. Under rootless podman that would write `packages/` as a subuid
  the host user cannot delete, so it gets
  `--userns=keep-id:uid=1000,gid=1000`. The image builder runs as root and
  must NOT have it — the default mapping already makes container root the host
  user.
- A rootless container cannot set up a loop device at all (`mount -o loop` is
  EPERM; `/dev/loop-control` belongs to nobody inside the namespace), and
  `--privileged` does not change that. So `image/verify.sh` falls back to
  **fuse2fs**, and the verify container gets `--device=/dev/fuse`.

Two host facts that decide how long this takes:

**The build is aarch64, and emulated on an x86_64 host.** Every container is
`--platform linux/arm64`. On Apple Silicon — which the scripts were written
for — that is native. On an x86_64 Linux host it runs through `qemu-aarch64`
via `binfmt_misc`, which must be registered with the kernel; `--platform` asks
for the handler and does not provide it. This is the one step that needs root
once, to install `qemu-user-static-binfmt`. The deploy script checks for the
handler before anything expensive starts.

**Under emulation the kernel build is hours, not minutes.** This is the single
largest cost in the pipeline and it dwarfs everything else in it.

> **A faster path exists and is not taken here.** This kernel builds with
> `LLVM=1`, and clang is a cross-compiler by construction — `make ARCH=arm64
> LLVM=1` on an x86_64 host would produce the same kernel natively, in a
> fraction of the time, with no emulation at all. Taking it would mean
> building one package outside the aarch64 container that builds every other
> package, which is a real change to the build's shape and not a flag. It is
> the obvious next optimisation and it is deliberately not part of this port:
> a port that has never booted should not also be the commit that restructures
> the build.

---

## 9. If it does not boot

In the order worth suspecting, most likely first.

1. **vbmeta.** The port flashes none, reasoning from pmOS. If the bootloader
   is refusing an unsigned kernel, the symptom is a device that returns to the
   bootloader or hangs before any output. Set `NEEDS_VBMETA=yes` in the `fp4`
   stanza of `image/boot/android-bootimg.sh`, rebuild the image, reflash. One
   word, and the vbmeta path already exists and is exercised on sargo.
2. **dtbo.** Should be erased by `flash.sh` automatically. Confirm it was:
   `fastboot erase dtbo` is idempotent, so just run it again.
3. **The slot.** A/B bootloaders mark a slot unbootable once the retry counter
   runs out, and a phone that has been flashed a few times arrives with it
   spent. `flash.sh` calls `fastboot --set-active` on the current slot for
   exactly this reason (D26). Check `fastboot getvar slot-unbootable:a`.
4. **Root not found.** Would mean a UFS or ext4 symbol is a module rather than
   built in — but `backend_kernel` asserts against `modules.builtin` at image
   build time, so this should be impossible to ship. If it happens, that
   assertion is what to read first.
5. **The cmdline.** `init=/sbin/init` is the one that is not optional; ABL
   appends `init=/init`, which is right for an Android ramdisk and a kernel
   panic here. It is in the shared cmdline and sargo needs it too.

### Reading a phone that will not say why

The image ships a **USB gadget with a serial console on it**, enabled at
package time by `moarchy-device-fp4`. It exists because every other way of
reading this device is unavailable when you need it:

| Channel | Why it is not enough |
| --- | --- |
| Screen + on-screen keyboard | needs the phone to reach a shell, which is the thing in doubt |
| `console=` on the cmdline | ABL strips it and appends `console=null` (D23, D25) |
| UART | TP1102 / TP1104 / TP4810 — inside the case, and 1.8 V |
| Debug image (wifi + ssh key) | needs the network, which is both unproven here and upstream-unstable (pmaports#2841) |

The cable is already attached — it is how the phone was flashed — so that is
what this uses. Plug the phone into the same machine and:

```bash
# a shell, as the phone's own user, with no password and no network
screen /dev/ttyACM0 115200          # or: picocom -b 115200 /dev/ttyACM0

# then, on the phone:
journalctl -b --no-pager | tail -100
systemctl --failed
dmesg | grep -iE 'ufs|ext4|mount|panic'
```

A network interface comes up alongside it, fixed rather than served, on the
address postmarketOS uses for the same purpose:

```
phone  172.16.42.1/24 on usb0      host: ip addr add 172.16.42.2/24 dev <iface>
```

**What it cannot do.** It runs from systemd, so it answers "booted, then went
wrong" and not "never booted at all". If the kernel does not start or cannot
mount root, nothing here runs and §9 above is the procedure — the bootloader
and the other slot are the only instruments left.

**If `/dev/ttyACM0` does not appear**, in order of likelihood: the phone has
not got as far as systemd (see above); `libcomposite` did not load; or the
port is not in peripheral mode. `journalctl -u moarchy-usb-debug` on the
phone's own screen says which, and the service is written to say so rather
than to fail silently.

**Getting back to Android:** the flash stays on the *current* slot, so the
other slot is untouched. `fastboot --set-active=<the other one>` returns you to
it. There is no console on this device — as on sargo, ABL strips `console=` and
appends `console=null` — so nothing printed during boot is visible, and UART
(TP1102 / TP1104 / TP4810, per Fairphone's repair documentation) is the only
way to read a boot that fails silently.

---

## 10. The four gaps, and what closing them would take

These are the things that do not work, written as work rather than as
apologies. None of them is blocked on this project: the drivers are largely
in mainline already, and what is missing is per-device integration that
somebody has to sit down and do. The intent here is to do them one at a time
and send the result upstream, so the next person gets a phone that works
rather than a repo that patches around it.

**Nothing below is actionable until the thing boots.** Every one of these
needs a running phone to test against, and three of the four need a working
microphone first.

### 10.1 The microphone — the capture hardware is not in the device tree

> **Resolved 2026-09-23.** AMIC1 records, on a mainline kernel, with no driver
> changes — the analysis below was right that the device tree was the problem,
> and the device tree is where it was fixed. The series lives in
> `~/Personal/fp4-mic-capture`; the configuration that goes with it is in
> `moarchy-device-fp4` (`ucm-HiFi.conf`, `53-fp4-ucm.conf`,
> `moarchy-fp4-mic-route.service`) and the PipeWire side is written up as
> `docs/fp4-defects.md` D13. Which of the other three analogue microphones
> work is still unmeasured. The rest of this section is kept as the reasoning
> that got there.

Bigger than "add some routing", and the device tree says so plainly. Decompile
the DTB this image ships (`dtc -I dtb`) and the sound card is:

```
sound { compatible = "fairphone,fp4-sndcard";
  mm1-dai-link  { cpu only }                  MultiMedia1
  usb-dai-link  { ... }                       USB Playback
  i2s-dai-link  { codec = <aw882xx@34 aw882xx@35> }   I2S Playback
};
```

Three links, all playback. And the capture hardware is not merely unrouted —
it is **absent**: no `wcd938x` codec node, no SoundWire controller, no LPASS
`va`/`rx`/`tx` macro nodes anywhere in the tree. The drivers for all of those
are compiled (`SND_SOC_WCD938X`, `SOUNDWIRE_QCOM`, the three macros), so the
kernel is ready for hardware the DT never describes.

So the work is DT bring-up, not a routing tweak: instantiate the SoundWire
controllers, add the WCD9380 node with its supplies, add the LPASS macros,
add a capture dai-link, then map the three AMICs the wiki documents (MIC1→
AMIC1, MIC2→AMIC3, MIC4→AMIC5). Upstream is the `linux-arm-msm` list; a
capture device in the UCM profile follows and goes to pmaports.

The test is one command once it boots: `arecord -l` should list a capture
device where today there is none.

### 10.2 The speaker amplifier — a mainline driver that does not exist yet

This entry has been wrong twice. The settled version, with the numbers that
settle it:

**The part is an AW88264 and it reports chip id `0x1852`** (vendor header:
`AW882XX_ID = 0x1852`, read from register `0x00`). Mainline's `aw88xxx`
family covers an entirely later generation:

| driver | chip id |
| --- | --- |
| `aw88395` | `0x2049` |
| `aw88166` | `0x2066` |
| `aw88261` | `0x2113` |
| `aw88081` | `0x2116` |
| `aw88399` | `0x2183` |
| **this phone** | **`0x1852`** |

Nothing in mainline claims `0x1852`, and `aw88261.c` would reject it outright
— it reads the id and bails with "unsupported device id".

**What makes the speaker work today** is an out-of-tree vendor driver the
sm6350-mainline fork carries: `CONFIG_SND_SMARTPA_AW882XX=m`,
`sound/soc/codecs/aw882xx/`, nine files and roughly 250 KB with its own DSP,
calibration and monitor code. It ships in this image as
`snd-soc-aw882xx.ko` and binds the two `awinic,aw882xx_smartpa` nodes the DT
declares — `@34` "left" and `@35` "right", both referenced by the I2S link.

So the job is **writing a mainline driver for the 0x1852 generation**, not
re-pointing a compatible. How tractable that is, measured rather than
guessed, by diffing the vendor register map against `aw88261.h`:

```
registers defined:  vendor 61   aw88261 91   sharing an address: 58
name agreement across those 58:  32%

0x00 ID       = ID          0x06 I2SCTRL  vs I2SCTRL1
0x01 SYSST    = SYSST       0x09 HAGCCFG1 vs DACCFG1
0x02 SYSINT   = SYSINT      0x11 PRODID   vs PWMCTRL1
0x03 SYSINTM  = SYSINTM     0x13 TEMP     vs I2SCFG1
0x04 SYSCTRL  = SYSCTRL
0x05 SYSCTRL2 = SYSCTRL2
```

The core control block `0x00`–`0x05` is identical in address *and* name — the
same lineage — and everything from `0x06` up has been rearranged. That is the
shape of a sibling chip, not a variant: close enough that `aw88261.c` is the
right template for structure, ASoC scaffolding and probe flow, and far enough
that its register definitions cannot be reused.

Realistic scope: a new `aw88264.c` / `aw88264.h` of roughly `aw88261.c`'s size
(35 KB), with the register map derived from the vendor's `aw882xx_reg.h` and
the semantics read out of the vendor driver. A DT binding document and a
compatible change go with it. Upstream is `alsa-devel` / the ASoC tree.

**This is no longer the smallest of the four** — that framing came from
believing a driver already existed. It is still the most self-contained, and
it has the best test: the speaker works now, so the bar is "does it still".

### 10.3 Call audio — after the microphone, and in three parts

On Qualcomm, voice never touches the CPU: the modem DSP owns the path. So this
is not "unmute the call", it is three pieces, in order:

1. **A capture path** — §10.1. Without it there is nothing to send, and the
   DT has no capture link at all.
2. **Something to hold the voice session open.** On the Pixel that is
   `q6voiced`, packaged here already, holding `VoiceMMode1` for the duration
   of a call; without it a dial is torn down immediately (devices.md D32).
   `moarchy-device-fp4/device.conf` says why it is deliberately not enabled
   on this device yet.
3. **IMS, for a VoLTE-only network.** LTE carries no circuit-switched voice,
   so on a network with no 2G/3G fallback the modem must register with IMS and
   will not until something answers its request for an IMS PDN. That is
   `81voltd` (`gitlab.com/flamingradian/81voltd`). Whether it is needed at all
   depends on the SIM: o2 still offers CS fallback, which is why the Pixel
   makes calls without it.

### 10.4 Wi-Fi stability — nobody upstream has diagnosed it

[pmaports#2841](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/work_items/2841)
was opened 2024-05-23 and is still `status::reported` as of 2026-01-27 — not
confirmed, not assigned, not diagnosed. The report itself is anecdotal: a
user noticing drops, linking a Reddit thread. There is no upstream fix in
progress to wait for, and no analysis to build on.

So this one starts at zero, and the chain to instrument is the reason it is
not simply "an ath10k bug": the Wi-Fi firmware executes on the MODEM DSP,
reached over QMI, and the protection-domain lookup that finds it comes from
`qcom_pd_mapper`. A stall can therefore be `ath10k_snoc`, the QMI transport,
the remoteproc holding the DSP, or power management putting something to
sleep that does not wake. devices.md D27 maps the same chain on sargo.

First moves, in order: reproduce with `ath10k` tracing and
`CONFIG_ATH10K_DEBUGFS`, watch whether the remoteproc stays up across a drop
(`/sys/class/remoteproc/*/state`), and check whether it correlates with
suspend. Then take it to the issue with something better than a Reddit link —
which, given the state of it, would be the most useful contribution of the
four.

### 10.5 Order, and why

```
  10.1 microphone ─┬──► 10.3 call audio (needs capture, then q6voiced, then IMS)
                   │
  10.2 amplifier ──┘    (independent: write the mainline driver)

  10.4 wifi             (independent, open-ended, undiagnosed upstream)
```

Start at 10.1: it unblocks the most, it is integration rather than invention,
and it has a one-command test. 10.2 is the most self-contained, though
not the smallest: a new driver with a close sibling to model on. 10.4 last, not because it
matters least (it matters most for a phone that updates over the network) but
because it is the one that could absorb unlimited time without a result.

---

## 11. What would make this "shipping"

The bar devices.md sets for sargo, applied here:

- [x] The packages build. *24 of them, 2026-09-21, including a
      cross-compiled kernel.*
- [x] An image builds and passes `verify-image.sh`. *204 checks, 0 failures,
      2026-09-22.*
- [ ] It flashes and boots to the shell from a clean rootfs.
- [ ] `pacman -S` works on the phone (this is what `SECURITY_LANDLOCK` is for,
      and it is the check that is easy to declare done without doing).
- [ ] The slot is marked successful and survives three reboots (D26).
- [ ] Wi-Fi associates — accepting that it will not stay up.
- [ ] Audio out of the speaker, which settles the `postmarketos/` firmware
      path question in §3.

Two of seven are ticked. Everything still unticked needs the handset, and
the third — booting to a shell — is the one that decides whether the rest are
even reachable.

**What the ten notes in a passing run mean.** Four of them are the verifier
admitting it cannot answer a question through a fuse2fs mount: `command -v`
decides with `access(X_OK)`, which fuse2fs refuses for any uid but the one
that mounted it, and those checks run as the phone's own user. The session
PATH is printed beside them and carries both directories the binaries live
in, so what the checks exist to catch is demonstrably absent — but "not
tested" is what they say, because that is what is true. Two more are the
theme files those same binaries would have generated. The rest are the
offline-instead-of-online grow, and the two hardware facts from §5.

Under a loop mount — Docker, or anything running as real root — none of that
scoping applies and all ten become ordinary checks again.

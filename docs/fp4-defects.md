# Fairphone 4 — open defects

Things reproduced on a real handset and not yet fixed. The closed half moved to
[`fp4-fixes.md`](./fp4-fixes.md) — nine entries, kept because several of them
record why something was wrong for a reason that was not the obvious one.

The camera and the sensors both left this file on 2026-09-24 — see D6, D7 and
D24 in the fixes. Both had been recorded as fixed once already and were not,
which is the reason each entry there keeps the wrong turns as well as the fix.

Sources: what the handset does, the
[postmarketOS wiki](https://wiki.postmarketos.org/wiki/Fairphone_4_(fairphone-fp4))
for what upstream considers working, and the handset owner.

**Status vocabulary.** `OPEN` — reproduced, not fixed. `OPEN — important` —
blocks ordinary use. `UNSUPPORTED` — no driver exists; needs writing, not
configuring. `WONTFIX` — understood and deliberately left.

| id | what | status |
| --- | --- | --- |
| [D5](#d5) | Wi-Fi latency tracks the radio's sleep cadence | **OPEN** |
| [D8](#d8) | GPS runs but never reaches a fix; no A-GPS assistance | **OPEN** |
| [D10](#d10) | The LPI pinctrl loses a boot race and takes all audio with it | **OPEN** |
| [D11](#d11) | The phone drops into EDL after repeated reboots | **OPEN — important** |
| [D12](#d12) | Hyprland draws a "started without start-hyprland" banner | **OPEN** |
| [D19](#d19) | The fingerprint reader is an Egis part with no Linux path | **UNSUPPORTED** |
| [D21](#d21) | Bluetooth carries music but not call audio | **OPEN** |
| [D22](#d22) | The touchscreen controller logs recurring i2c failures | **OPEN** |
| [D23](#d23) | The camera's CSI PHY supplies are undescribed, and a clock sticks on | **OPEN** |
| [D25](#d25) | Docker TUI soft-locks: pkexec in a terminal, no passwordless action | **OPEN** |
| [D27](#d27) | The on-screen keyboard does not work in the app drawer search | **OPEN** |

---

## What upstream reports

From the [postmarketOS wiki](https://wiki.postmarketos.org/wiki/Fairphone_4_(fairphone-fp4)),
kept here so this file can be read without it. `Y` works, `P` partial, `N` no.

| | | | | | |
| --- | --- | --- | --- | --- | --- |
| flashing `Y` | usbnet `Y` | emmc `Y` | sdcard `Y` | screen `Y` | touch `Y` |
| 3d `Y` | cameraflash `Y` | bluetooth `Y` | gps `Y` | sms `Y` | mobiledata `Y` |
| fde `Y` | otg `Y` | accel `Y` | magnet `Y` | light `Y` | proximity `Y` |
| haptics `Y` | battery `P` | audio `P` | camera `P` | wifi `P` | calls `P` |
| nfc `N` | fingerprint `N` | hdmidp `N` | fossbootloader `N` | | |

Three of those are behind this tree rather than ahead of it. Upstream records
audio as partial ("the built-in microphones are not working", "speaker audio on
the earpiece is distorted") and calls as "possible to place and receive... but
there will be no audio" — all three work here, see
[`fp4-fixes.md`](./fp4-fixes.md) D3, D13, D14, D16, D17.

Upstream was ahead of us on the sensors until 2026-09-24; accelerometer,
magnetometer, light and proximity now work here too (D7, in the fixes).

Upstream's Wi-Fi note matches D5 exactly and is tracked as
[pmaports#2841](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/work_items/2841).

**The parts, as upstream identifies them.** Useful when a driver has to be
found for something:

| | | | |
| --- | --- | --- | --- |
| Display / touch | HX83112A | Amplifier | AW88264(A) |
| Audio codec | WCD9380 | Microphones | AWC2718M06CX |
| Vibration | AW8695 | Earpiece | BM24-10DS/2 |
| Sixaxis | LSM6DSOQTR | Light / proximity | TCS37013H |
| Magnetometer | AK09918 | ToF | VL53L4 |
| Wi-Fi / BT | WCN3988/3990 | NFC | ST21NFCD |
| Charger / fuel gauge | PM7250B | Camera flash | PM6150L |
| Fingerprint | *not identified upstream either* | | |

**Two things worth keeping.** GPS is enabled with

```
mmcli -m any --location-enable-gps-nmea
```

and the serial console is on test points given in Fairphone's own repair
blueprint — `RXD = TP1102`, `TXD = TP1104`, `GND = TP4810`.

---

## D5 — Wi-Fi latency tracks the radio's sleep cadence {#d5}

**Status: OPEN, but understood.** Found 2026-09-22 while disproving D4.
Not a fault in the link, and probably not a fault at all — recorded because
it looks alarming and will otherwise be rediscovered and misattributed.

The link is excellent: **-49 dBm**, **433.3 MBit/s** VHT-MCS 9 on 80 MHz,
**0% loss in every run**. The latency does not match it:

| power save | min | avg | max | mdev |
| --- | --- | --- | --- | --- |
| **on** (default) | 22.2 | **122.0** | 217.4 | 57.2 ms |
| **off** | 5.0 | **55.7** | 107.2 | 50.3 ms |

For comparison the USB link to the same handset answers in **3.6 ms**.

### It is sleep, not weakness

The numbers are quantised to the radio's own cadence. `iw dev wlan0 link`
reports `dtim period: 3` and `beacon int: 100`, so:

- power save **on** — the station wakes on the DTIM, every 3 x 100 ms =
  **300 ms**. Observed max 217 ms fits inside that window and the average is
  about half of it, which is what uniformly-arriving packets give.
- power save **off** — max collapses to **107 ms**, i.e. the **100 ms** beacon
  interval, and the average is again about half.

So `power_save off` does take effect, and *stays* off across a run — but it
only demotes the station from DTIM cadence to beacon cadence. It never
reaches continuously-awake, which is what the ~5 ms minimum shows the link is
capable of.

### It is latency only

Bulk throughput is unaffected, because once TCP ramps up the station stops
sleeping:

| | |
| --- | --- |
| scp 8 MB over Wi-Fi | 7.6 MB/s |
| scp 8 MB over USB | 21.4 MB/s |

A latency-only problem and a throughput problem have different causes, and
this is firmly the former. Interactive use over Wi-Fi feels bad; file
transfer does not.

### Not the same thing as §10.4

`fairphone-4.md` §10.4 tracks Wi-Fi *instability* upstream (pmaports#2841) —
the connection dropping. Nothing dropped here, across every run. They may
share a cause; nothing establishes that, and conflating them would make a
solved problem look unsolved.

Power save was left **on**, as found: it is presumably there for battery life,
and turning it off permanently is a trade nobody has made. `sudo iw dev wlan0
set power_save off` is the lever.

**Next, if it ever matters:** the interesting question is why beacon-cadence
wakeups persist with power save off, since that is the driver's or firmware's
own power management rather than the one `iw` controls. Worth comparing
against another AP with a DTIM of 1 before blaming the phone — DTIM period is
the access point's setting, not the station's.

---

## D8 — GPS runs but never reaches a fix; no A-GPS assistance {#d8}

**Status: OPEN.** The receiver runs and streams NMEA; what it does not do is
reach a fix in any reasonable time, because it has no assistance data and must
cold-start from the sky alone.

No kernel GNSS device exists and none is needed: the receiver is the modem's,
reached through ModemManager, which reaches the QMI Location service (id 16,
present on qrtr). `mmcli -m any --location-enable-gps-nmea --location-enable-gps-raw`
turns it on, and NMEA then flows -- confirmed 2026-09-24, polling
`--location-get`:

```
$GPGSA,A,1,,,...        automatic mode, fix type 1 = NO FIX
$PQWM1,2437,384234620,1,7,...   Qualcomm proprietary; the receiver is running
(no $GPGSV)             no satellites tracked -- every test has been indoors
```

So the receiver is alive and emitting. Two things stop a fix:

- **No A-GPS assistance.** ModemManager logs, every session:

  ```
  couldn't load supported assistance data types: Failed to receive
  indication with the predicted orbits data source
  ```

  Without predicted orbits / xtra, there is no ephemeris head start, so a
  first fix is a true cold start: 12-15 minutes of open sky, the phone still,
  before `$GPGGA` carries coordinates. GNOME Maps and browser geolocation
  time out long before that, which is what "could not determine exact
  location" was -- not a failure of the receiver, a receiver that had not
  finished yet.

- **A ModemManager crash on rapid toggling.** Cycling location off/on/off/on
  quickly hit `loc_register_events_ready: assertion failed (!priv->loc_client)`
  and MM restarted. A single on or off is safe (verified); the Location quick
  toggle does single actions, so normal use does not trigger it. It is an
  upstream MM bug in the QMI LOC client, worth reporting.

**A-GPS MSB / SUPL was tried directly, 2026-09-24 — it hits the same wall.**
`mmcli --location-status` shows the modem advertises `agps-msa` and `agps-msb`,
not just raw/nmea, so network-assisted GPS (ephemeris fetched from a SUPL
server, phone computes the fix) looked like a path the earlier note missed.
It is not, on this build:

```
mmcli -m any --location-set-supl-server=supl.google.com:7275
  → Aborted: Failed to receive indication with the server update result
mmcli -m any --location-enable-agps-msb ...
  → Aborted: Couldn't enable 'agps-msb': Failed to receive operation mode indication
```

Both fail with the *same* "indication never arrives" signature as the
predicted-orbits error above — and this was **not** a connectivity problem:
the modem was `connected`, packet service `attached` at the
time, so it had its own cellular data path for assistance. `gps-raw` and
`gps-nmea` do enable; only the assistance modes fail. This confirms the root
cause is the modem's QMI-LOC assistance/indication path (izat/xtra), not a
missing config toggle and not the network — the LOC service answers for the
raw receiver but never completes the assistance handshake.

**What would actually fix it:** get the predicted-orbits / SUPL assistance
indication path working — the missing xtra/izat data path that pmOS edge ships
and this build does not (a modem-firmware/assistance-data investigation, now
confirmed as the blocker by the direct A-GPS test above), or accept cold-start
times and give the receiver a genuine 15-minute clear-sky window. There is no
config-only fix; the capability is advertised but the firmware handshake behind
it is incomplete on this image.

**A caution for testing:** do not probe the engine with `qmicli --loc-*` while
ModemManager owns it. They share one LOC session; a `qmicli --loc-stop` tears
down MM's session too, and following NMEA through qmicli came back silent while
MM saw the same stream fine. Read location through `mmcli --location-get`, not
qmicli, unless MM's location is disabled first.

---

## D10 — the LPI pinctrl loses a boot race and takes all audio with it {#d10}

**Status: OPEN.** Seen once on 2026-09-23, cleared by a reboot.

The phone came up with **no sound card at all** — `/proc/asound/cards` said
`--- no soundcards ---` — although all three DSPs were running and all sixteen
audio modules were loaded. `devices_deferred` explains it:

```
33c0000.pinctrl
3200000.codec      wait for supplier .../rx-swr-active-state
3220000.codec      wait for supplier .../tx-swr-active-state
3370000.codec      va_macro: unable to get macro clock
sound              wait for supplier .../i2s1-sleep-state
3230000.soundwire  supplier 3220000.codec not ready
3210000.soundwire  supplier 3200000.codec not ready
```

One device failed to probe — the LPASS low-power-island pinctrl — and every
consumer of its pin states stalled behind it: both macros, both SoundWire
controllers and the card itself. The LPI pinctrl takes `LPASS_HW_MACRO_VOTE`
and `LPASS_HW_DCODEC_VOTE` from `q6afecc`, which only exists once the ADSP's
APR services have registered, so this looks like an ordering race that most
boots win.

A plain reboot fixed it completely: card present, both slaves `Attached`,
nothing deferred.

Worth knowing because the symptom is total and silent — no error, no failed
unit, just no audio hardware. **If audio is missing, look at
`/sys/kernel/debug/devices_deferred` before anything else.**

Not yet established: how often it loses, and whether it is specific to a
power-cycle from EDL (which is how this boot started) rather than an ordinary
reboot.


### Reproduced 2026-09-23, with numbers

Lost the race on one boot out of roughly eight while testing the microphone.
Every audio node stayed in deferred probe:

```
[ 27.892414] platform 3200000.codec: deferred probe pending: platform: wait for supplier /soc@0/pinctrl@33c0000/rx-swr-active-state
[ 27.904572] platform sound: deferred probe pending: platform: wait for supplier /soc@0/pinctrl@33c0000/i2s1-sleep-state
[ 27.935801] platform 33c0000.pinctrl: deferred probe pending: (reason unknown)
[ 27.943287] platform 3370000.codec: deferred probe pending: va_macro: unable to get macro clock
```

`/proc/asound/cards` reads `--- no soundcards ---`, and `amixer` answers
`Invalid card number '0'`. Two facts worth recording:

- **The timing.** The ADSP starts at `[16.5]` and the deferred-probe timeout
  fires at `[27.9]`, about eleven seconds later. `33c0000.pinctrl` cannot
  probe until the LPASS audio clocks exist, and those come from the ADSP. So
  the window is real but narrow, which fits a race lost occasionally rather
  than reliably.
- **Reloading the driver does not fix it.** `modprobe -r
  pinctrl_sm6350_lpass_lpi` followed by `modprobe` leaves the device unbound
  and the card absent, so this is not simply "the module arrived late" --
  once the deferred-probe timeout has expired the probe is not retried.

That points at `deferred_probe_timeout=` on the kernel command line as the
cheap mitigation, since this image sets no value and the default is what
expires here. **Untested**: it needs a boot.img rebuild and a flash, and it
should be measured rather than assumed, because a longer timeout delays every
*genuine* probe failure by the same amount.

A reboot clears it; the next boot came up normally and stayed that way.

---

## D11 — the phone drops into EDL after repeated reboots {#d11}

**Status: OPEN as a cause, RECOVERABLE as a symptom.** Leading theory (A/B retry exhaustion) ruled out 2026-09-24. Seen three times on
2026-09-23. The first two needed a physical power-button hold. The third did
not, because it no longer has to -- see *Recovering without touching the
phone* below.

The phone stops booting and appears on the host as

```
Bus 003 Device 040: ID 05c6:900e Qualcomm, Inc. QUSB_BULK_SN:<serial>
```

which is the SoC's emergency download mode: powered, enumerating, but running
no OS. No fastboot, no adb, no network.

### It is not the reboot argument

The first occurrence followed `systemctl reboot --reboot-argument=bootloader`,
and this entry originally blamed that. **The second occurrence followed an
ordinary `systemctl reboot`**, so that explanation is wrong and is recorded
here only because the correction matters.

### Ruled out: an exhausted A/B retry counter

This was the leading theory. It is measured, on 2026-09-24, and it does not
hold. `qbootctl-mark-successful.service` is active and runs every boot:

```
qbootctl[556]: SLOT _b: already marked successful
qbootctl[556]: SLOT _b: Marked boot successful
systemd[1]: Finished Tell the bootloader this boot worked.
```

and the slot state is stable across boots:

```
SLOT _b:  Active: 1   Successful: 1   Bootable: 1
SLOT _a:  Active: 0   Successful: 1   Bootable: 0
```

So `qbootctl -m` **does** succeed despite the missing `slot_suffix` -- it takes
the slot from the partition table instead -- and every boot is marked
successful. A retry counter that is reset on every boot cannot exhaust. The
hypothesis is wrong.

There is a real but separate bug here: the boot cmdline carries no
`androidboot.slot_suffix`, so `qbootctl` logs `Couldn't find cmdline arg` and
`Unable to read boot slot property` on every run before falling back. It works,
but blind to what the bootloader actually chose. Worth adding the arg to the
boot image for correctness; it is not the EDL cause.

### Cause: still unidentified

With retry-exhaustion out, there is no confirmed cause. What the occurrences
have in common is a session of many reboots around flashing, not ordinary use;
each was plain EDL (a Sahara `HELLO`), never a ramdump, so the application
processor was not crashing into a debug image. Catching the trigger needs an
EDL event with early-boot instrumentation, which a random fault makes hard.
Left open, and cheap to live with now that recovery needs no physical access.

### Recovering without touching the phone

### Recovering without touching the phone

The documented recovery was a power-button hold, which is no use when the
handset is not in the room -- and this happened at 01:00 with nobody near it.
It is not necessary.

EDL speaks Qualcomm's Sahara protocol, and Sahara has a reset command that the
device honours *before* any authentication, with no signed programmer
uploaded and nothing flashed. Two 32-bit words out, an acknowledgement back,
and the phone reboots normally:

```
$ scripts/edl-reset.py
edl-reset: reset acknowledged, the phone is rebooting
```

The device replies `08000000 08000000` -- `SAHARA_RESET_RESPONSE`, length 8 --
and comes back on the network about two minutes later. Verified on hardware
2026-09-23 on a handset that had dropped into EDL after an ordinary reboot.

Worth being precise about what this does and does not do: it recovers the
*symptom*. Why the phone enters EDL at all is still unknown, and the A/B retry
hypothesis above is still the thing to test. But an EDL episode is no longer a
dead end that needs somebody in the room, which changes how safe it is to
reboot this phone unattended.

### Recovery

1. Hold **Power for ~15-20 seconds** until the phone goes dark.
2. **Unplug the cable**, hold **Volume Down**, and plug it back in — this is
   the order that works; holding Volume Down with the cable already attached
   does not.
3. In fastboot: `fastboot --set-active=b`, then `fastboot reboot`.

Nothing is written in EDL unless something deliberately flashes it, and both
occurrences recovered with the device intact.

### What to do about it

Until this is understood, **minimise reboots**, and check `qbootctl` after
each one. If the mark-successful path is indeed broken, the fix is either to
put `androidboot.slot_suffix` in the cmdline `android-bootimg.sh` builds, or
to make the unit pass the slot explicitly.

---

## D12 — Hyprland draws a "started without start-hyprland" banner {#d12}

**Status: OPEN**, cosmetic, and not device-specific.

A red-underlined banner sits across the top of the screen:

> was started without start-hyprland. This is strongly discouraged unless you
> are in a debugging environment.

It overlaps the clock and the status icons, so it is hard to ignore.

Nothing on this phone caused it. `/etc/profile.d/zz-moarchy.sh` is owned by
`moarchy 0.5.0-6`, is unmodified, and ends with

```sh
exec Hyprland -c /usr/share/moarchy/config/hypr/hyprland.lua
```

which is deliberate — `image/verify.sh` has a check that asserts exactly that
line exists. What changed is Hyprland: 0.56.2 ships `/usr/bin/start-hyprland`
and warns whenever the compositor is launched without it.

The fix is presumably to exec the wrapper instead, but that is a change to how
every moarchy device starts its session, and `start-hyprland` does more than
exec — it manages an instance, reads state and can run things itself. Swapping
it in unexamined risks a phone that boots to no UI, which is a worse defect
than a banner.

**Next:** read what `start-hyprland` actually does, check whether it respects
`-c`, and if so change `zz-moarchy.sh` and the matching assertion in
`image/verify.sh` together. Worth doing on a device that can be recovered
easily rather than on the phone.

---

## D19 — the fingerprint reader is an Egis part with no Linux path {#d19}

**Status: UNSUPPORTED**, and investigated 2026-09-24 far enough to say what it
would take. Short answer: a driver and a matching stack, both written from
scratch. This is not a configuration problem.

**The part is Egis** (Egis Technology / Egistec). The wiki leaves this row
blank, so it was read off the handset: a scan of the `super` partition returns
73 occurrences of `egis` and 30 of `EGIS` in the vendor libraries. The exact
model did not surface within the time budget; Egis' side-mounted capacitive
parts are the ET5xx/ET7xx families.

**What the hardware looks like**, from this handset's own Android device tree
overlay in `dtbo_a`:

```
fingerprint_gpio {
        compatible    = "qcom,fingerprint-gpio";
        interrupt-parent = <&tlmm>;
        interrupts    = <17 0>;
        fp-gpio-int   = <&tlmm>, <17 0>;
        fp-gpio-reset = <&tlmm>, <18 0>;
        fp-gpio-power = <&tlmm>, <84 0>;
};
```

That node does nothing but reserve three pins. There is no SPI controller and
no SPI device anywhere in the overlay, so the bus binding lives in the vendor
kernel module rather than in the device tree — which is why the earlier note
here, that the SPI controller is not enabled, was looking for something that
was never described in the first place.

The handset also carries two partitions for this part alone: `fpconfig`
(128 KiB) and `fpconfig_persist`, the latter containing the string
`fpconfig2620`. Calibration data, of a shape nothing open knows how to read.

**Why this is harder than the other entries.** The kernel has no fingerprint
subsystem at all; everything goes through libfprint in userspace. libfprint
does have Egis drivers, but they are for the USB laptop parts (`1c7a:0570`,
`0575`, `0576`, `057e`), reverse-engineered one at a time. Its handful of SPI
drivers assume ACPI platforms where firmware handles regulators and interrupts,
which a device-tree phone does not. So closing this needs, in order: the model
identified, a kernel-side driver that powers and clocks the part and hands
frames to userspace, and a matching implementation for a sensor whose
enrolment and matching formats are undocumented.

**Confirmed against Fairphone's published kernel source, 2026-09-24.**
`kernel/msm-4.19` at `int/15/fp4` (from `gerrit-public.fairphone.software`)
carries exactly one fingerprint driver:
`drivers/misc/fpr_FingerprintCard/fpc1020_platform_tee.c` — a **Fingerprint
Cards FPC1020** TEE-platform driver. Read in full, the whole driver does only:
`vreg_setup` (power rails), `select_pin_ctl` (pinctrl), `hw_reset` (reset GPIO),
`device_prepare` (power sequence), `fpc1020_irq_handler` (a "finger touched"
interrupt that wakes userspace), and probe/remove plumbing. There is **no SPI
transfer, no image read, no `read()`/`write()` data path, no template storage
and no matching anywhere in the file.** The `_tee` suffix is literal: the
sensor's SPI bus and every byte of biometric data are owned by a QSEE/TrustZone
trustlet in the secure world. The kernel driver is a light switch and a
doorbell.

This settles the mechanism regardless of the FPC-vs-Egis question. The board
device tree (`kernel/msm-extra/devicetree`, `int/15/fp4`,
`lagoon-fp4.dtsi`) wires the same chip-agnostic `qcom,fingerprint-gpio` node
seen in the handset overlay above (int gpio17, reset gpio18, power gpio84) — it
names no vendor, so the kernel module binds by probe. The published kernel
module is FPC; this handset's `super` partition ships Egis userspace and Egis
calibration (`fpconfig2620`). The FP4 is known to have shipped more than one
fingerprint supplier; whichever this unit is, both use the identical Android
model — a dumb capture sensor plus a proprietary matcher in TrustZone — so the
conclusion does not move.

**Why the sensor being "already programmed" does not help us** (the question
that keeps coming up): the FPC1020 is a capacitive *image* sensor, not a
self-contained matcher. It has no onboard "is this the right finger?" logic to
query — it captures an image and streams it out, and the deciding is done by
the trustlet on the application processor's secure world, which is a signed
blob we cannot load or run on mainline. So there is nothing running on the chip
to simply talk to; the part that authenticates isn't on the chip at all. To get
fingerprint on this Linux stack you would have to *replace that brain* — either
run Qualcomm's secure OS + trustlet (not feasible on mainline), or build a
normal-world path: a from-scratch SPI capture driver (the register protocol is
undocumented, held by the closed TEE driver) plus an open matcher for a
proprietary template format. That is a reverse-engineering research project,
not a port, and it would also discard the security model (any root process
could then read the sensor and templates). Physically not impossible; but a
large research effort for a convenience feature, which is why the on-screen PIN
lock is the right answer here, not a stopgap for something readily fixable.

Nothing here blocks anything else, and no Linux phone this generation has a
working fingerprint reader for the same reasons. Recorded because it was asked
about, and because "no driver exists" is a different answer from "misconfigured".

## D21 — Bluetooth carries music but not call audio {#d21}

**Status: OPEN**, and narrowed on 2026-09-24: not a missing package, an
unbridged path. Full confirmation needs a paired headset and a call.

A2DP (music) works. What the wiki records as "HFP/HSP don't work at all" is the
headset carrying a *cellular* call, and the pieces for it are further along than
"not installed":

- every PipeWire bluez codec is present, HFP included -- `libspa-codec-bluez5-hfp-cvsd`,
  `-hfp-msbc`, `-hfp-lc3-swb`;
- the adapter advertises the **Handsfree Audio Gateway** UUID as well as
  Handsfree, so bluez registers the AG profile a phone needs.

The gap is the bridge. For a headset to carry a cellular call the phone is the
HFP Audio Gateway, and the call's audio has to move between the modem's voice
path (the q6voice PCMs from [D17](./fp4-fixes.md#d17)) and the Bluetooth SCO
link. Nothing wires those together: there is no oFono (one classic AG backend),
and WirePlumber is not routing the modem call PCM to a BT SCO node. That
bridging is the work, and it is integration rather than a config toggle.

Not pursued further yet: it cannot be confirmed without a paired headset and a
live call, and the fix is sizeable. Recorded so the starting point -- codecs and
AG profile present, bridge absent -- is not re-discovered from scratch.

## D22 — the touchscreen controller logs recurring i2c failures {#d22}

**Status: OPEN**, and cosmetic so far.

The touchscreen works. The HX83112A controller nevertheless fails i2c
transactions periodically — 19 occurrences in one boot of roughly two and a
half hours, in bursts of three:

```
gpi 900000.dma-controller: Error in Transaction
geni_i2c 988000.i2c: DMA txn failed:3
geni_i2c 988000.i2c: GPI transfer failed: -5
[HXTP][ERROR] himax_bus_write: i2c_write_block retry over 3
[HXTP][ERROR] himax_mcu_read_event_stack: i2c access fail!
[HXTP][ERROR] himax_touch_get: can't read data from chip!
```

The driver retries three times and gives up on that event, so the visible
symptom would be an occasional dropped touch rather than a dead screen, which
matches the handset being usable. The failure is at the GPI DMA layer beneath
i2c rather than in the touch driver, which points at the i2c controller's DMA
path and not at the HX83112A.

Worth watching rather than chasing: it has not yet been tied to anything a user
would notice.

---

## D23 — the camera's CSI PHY supplies are undescribed, and a clock sticks on {#d23}

**Status: the regulator half now has the data — UPDATED 2026-09-24 from
Fairphone's own board device tree.** Two separate items, neither with a
user-visible symptom.

**The CSI PHY supplies.** Every CSI PHY rail falls back to a dummy regulator at
probe:

```
qcom-camss acb3000.isp: supply vdd-csiphy0-0p9 not found, using dummy regulator
   ... csiphy0-1p25, csiphy1-*, csiphy2-*, csiphy3-*
```

The `qcom,sm6350-camss` binding defines `vdd-csiphy{0-3}-{0p9,1p25}-supply` and
the FP4 `&camss` node sets none. The earlier note here said the rail identity
"needs data not on hand" — it did, and now it is on hand. The FP4 board device
tree (`kernel/msm-extra/devicetree`, branch `int/15/fp4`,
`qcom/camera/lagoon-camera.dtsi`, cloned from `gerrit-public.fairphone.software`)
names them on each `qcom,csiphy@N` node, under the vendor's own property names
rather than the mainline ones:

```
regulator-names   = "gdscr", "refgen", "mipi-csi-vdd1", "mipi-csi-vdd2";
mipi-csi-vdd1-supply = <&L18A>;   rgltr-min/max 880000 / 1049000   → the 0.9V rail
mipi-csi-vdd2-supply = <&L22A>;   rgltr-min/max 1200000 / 1305000  → the 1.25V rail
```

So, authoritatively:

- **`vdd-csiphy*-0p9` = PMIC LDO L18A** (0.9 V nominal, 0.88–1.049 V range);
- **`vdd-csiphy*-1p25` = PMIC LDO L22A** (1.25 V, 1.2–1.305 V range);
- all four PHYs share the same two rails (both are on the main PMIC, the "A"
  = pm6350 in mainline terms), plus the `cam_cc_titan_top_gdsc` GDSC and the
  SoC `refgen`, which mainline already handles.

The mainline fix is now a concrete, non-guess DTS patch on `&camss`: point
`vdd-csiphy{0..3}-0p9-supply` at the mainline pm6350 L18 node and
`vdd-csiphy{0..3}-1p25-supply` at L22. This is correctness/power-management
polish — the camera works today on the dummy regulators — but it is no longer
blocked. It needs a kernel rebuild + reflash, so it is teed up, not applied
blind. (What the vendor DTS does **not** give, and what would actually improve
image *quality*, is the Qualcomm ISP tuning — chromatix/CAMX black-level, lens
shading, colour matrices — which lives in the gated `camera-devicetree` +
proprietary blobs, not in this open board tree.)

**The stuck AXI clock.** Tearing a capture stream down warns every time:

```
gcc_camera_axi_clk status stuck at 'on'
  camss_disable_clocks / vfe_put / vfe_set_power / video_unprepare_streaming
```

The AXI clock does not report itself off when camss releases it. A clock left
running costs power and can block suspend later. This is a driver/clock issue,
independent of the supplies, and belongs upstream with the SoC's CAMSS support;
it is not fixed by anything in this tree.

---

## D25 — the Docker TUI soft-locks: raw pkexec in a terminal {#d25}

**Status: OPEN**, lower priority since the app store -- the case that mattered --
is fixed separately ([D26](./fp4-fixes.md#d26)). Reproduced 2026-09-24,
recovered over SSH.

Opening the **Docker** app froze the phone: it stopped on a password screen, the
on-screen keyboard would not come up for it, and the app could not be closed. The
phone was not crashed -- Hyprland stayed responsive -- but from the touchscreen
there was no way forward or out.

Cause: `omarchy-launch-docker-tui` runs `pkexec ... lazydocker` in a foot
terminal. `pkexec` needs root authorisation, and with no graphical polkit agent
handling it, it falls back to reading a password on the terminal's TTY. A TTY
password read is not a text field, so the on-screen keyboard cannot feed it, and
the terminal blocks there. Nothing offered a way to dismiss the window either.

So any pkexec-gated app launched into a terminal is a soft-lock trap on a
touch-only device. Docker is the one found; the pattern is the risk.

Recovery, for the record: over SSH, `hyprctl clients` to find the stuck window
(class `TUI.tile`, running `omarchy-launch-docker-tui`), then kill its process
chain. From the phone alone there was no recovery.

**The fix is a design choice, not a typo**, so it is left for a decision:

- a graphical polkit agent whose dialog the on-screen keyboard *can* fill would
  make pkexec prompts answerable, and fixes this for every such app at once; or
- the Docker launcher should not need root interactively on a phone -- rootless
  docker, or the user in the `docker` group, removes the prompt; or
- at minimum, an app that will pkexec should be reachable-and-cancellable, so a
  failed or unanswerable prompt cannot trap the session.

Until then, avoid the Docker app on the handset.

---

## D27 — the on-screen keyboard does not work in the app drawer search {#d27}

**Status: OPEN**, reported 2026-09-24. Under investigation; the exact symptom
(keyboard does not appear vs. appears but does not type) is still to be pinned.

The app drawer is a search field over an app grid, meant to be filtered by
typing (`moarchy.app-drawer`). The keyboard does not do its job there.

Ruled out so far:

- The OSK process is healthy: `moarchy-keyboard` runs, owns `sm.puri.OSK0`, and
  `busctl ... SetVisible b true` raises it -- the keyboard layer appears. So the
  raise *mechanism* works when driven directly.
- Global touch is fine (the rest of the phone is operable), so this is not a
  disabled touchscreen.
- Not the DPMS/lock work: `moarchy-screen`'s FLAG is clear and touch is on.

Confirmed on a clean boot (2026-09-24), so it is a real defect, not the
session churn that first surfaced it. Symptom: tapping the search box raises the
keyboard, but keys do nothing.

Everything checkable by inspection is ruled out:

- **OSK health**: `moarchy-keyboard` runs, owns `sm.puri.OSK0`, `SetVisible`
  raises the layer.
- **Obstruction**: with the drawer open, the keyboard sits at y580-780 and
  nothing is stacked above that region -- taps reach it.
- **Protocol**: the OSK binds both `zwp_virtual_keyboard_v1` and
  `zwp_input_method_v2`, so it can inject raw keys to the focused surface, which
  a Quickshell shell field can receive.
- **Drawer QML path**: the drawer takes `keyboardFocus: Exclusive` when open,
  and the search field is `Qt.ClickFocus` with a MouseArea that calls
  `osk.show()` and passes the press through (`mouse.accepted = false`) so the
  tap also focuses the field. On paper the tap both raises the keyboard and
  focuses the field.

So the failure is runtime, not visible in the code -- most likely QML active
focus landing on the `focusSink` (`Item { focus: true }`) rather than the
search field, so injected keys are absorbed. Confirming that needs observing a
live keystroke, which cannot be done over SSH.

**The datapoint that splits it:** does the OSK type in another field (a browser
URL bar, the Wi-Fi passphrase)? If yes, it is drawer-specific focus; if no, the
OSK's key delivery to shell surfaces is broken everywhere. Pending that.

# Fairphone 4 — open defects

Things reproduced on a real handset and not yet fixed. The closed half moved to
[`fp4-fixes.md`](./fp4-fixes.md) — nine entries, kept because several of them
record why something was wrong for a reason that was not the obvious one.

The camera and the sensors both left this file on 2026-09-24 — see D6, D7 and
D24 in the fixes. Both had been recorded as fixed once already and were not,
which is the reason each entry there keeps the wrong turns as well as the fix. D5, D12, D25 and D27 left on 2026-09-29; see the fixes.

Sources: what the handset does, the
[postmarketOS wiki](https://wiki.postmarketos.org/wiki/Fairphone_4_(fairphone-fp4))
for what upstream considers working, and the handset owner.

**Status vocabulary.** `OPEN` — reproduced, not fixed. `OPEN — important` —
blocks ordinary use. `UNSUPPORTED` — no driver exists; needs writing, not
configuring. `WONTFIX` — understood and deliberately left.

| id | what | status |
| --- | --- | --- |
| [D8](#d8) | GPS runs but never reaches a fix; no A-GPS assistance | **OPEN** |
| [D19](#d19) | The fingerprint reader is an Egis part with no Linux path | **UNSUPPORTED** |
| [D21](#d21) | Bluetooth carries music but not call audio | **OPEN** |
| [D22](#d22) | The touchscreen controller logs recurring i2c failures | **OPEN** |
| [D23](#d23) | The camera's CSI PHY supplies are undescribed, and a clock sticks on | **OPEN** |
| [D29](#d29) | s2idle aborts in ~2s: serial-console RX wakeup (irq 172). Fixed by mainline `d0cd9c8d0fd5` (qcom-geni force-suspend), VALIDATED on FP4 (holds 21s). udev rule is the stopgap until the kernel carries it. Deep-collapse depth cap is a separate open bug | **abort FIXED (mainline fix validated); depth open** |
| [D33](#d33) | No modem after the first suspend: ModemManager 1.24.2 aborts on every suspend/stop on IPA modems (multiplexed-bearer assertion), so calls broke from the 10-10 image on | **FIX APPLIED -- verify on next image** |
| [D34](#d34) | Calls have no audio again: the packaged kernel never carried D17's q6voice stack. Fixed in kernel pkgrel 13 (patch 0009), awaiting a call on the CI image | **OPEN - important** |

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

## D8 — GPS runs but never reaches a fix; no A-GPS assistance {#d8}

**2026-10-17: the two reasons apps never got a position are fixed (pending the
image).** (1) **No geoclue agent.** geoclue answers only clients whose session
has an agent (GNOME/Phosh ship one; this Hyprland session had none), so every
client - GNOME Maps, the browser, `where-am-i` - timed out with "Failed to
connect to GeoClue2 service", and geoclue never asked MM for GPS. Its bundled
agent was there but exits at once without `libnotify`. With `libnotify` and the
agent running, `where-am-i` gets GeoIP, then WiFi at 33 m, and geoclue enables
MM's `gps-nmea` itself. Shipped: `config/hypr/autostart.lua` execs
`/usr/lib/geoclue-2.0/demos/agent`, `moarchy` depends on `geoclue` and
`libnotify` (pkgrel 17). (2) **The NMEA mask** (below): set by
`moarchy-fp4-gnss-nmea.service` at boot (`moarchy-device-fp4` pkgrel 11); MM's
Get then sees GGA and skips its Set. Verified with the mask set: MM serves
`$GPGGA/$GPRMC/$GPGSA/$GPVTG` and four `$GPGSV`, 13 satellites in view, one
tracked indoors at 27 dB-Hz, no fix indoors (expected). Still open: a first fix
is a cold start without xtra (12-15 min of sky, below).

**2026-10-16, worse than in September: no standard NMEA at all.** On the 10-10
image ModemManager logs `couldn't setup required NMEA traces: Operation timed out`
when location is enabled, and the LOC service's NMEA types stay `none`, so only
Qualcomm's `$PQ...` sentences flow (week 65535: no GPS time); no `$GPGSA`/`$GPGSV`
as on 09-24, and geoclue/Maps never get a sentence they can use. Setting the
types directly works (`qmicli -d qrtr://0 --loc-set-nmea-types="gga|rmc|gsv|gsa|vtg"`
succeeds and reads back), so the LOC service answers requests; it is MM's
indication wait that times out, the same signature as the assistance failure
below. Nothing in the image turns location on either: MM had no source enabled
and geoclue starts on demand and exits after 60 s. GNOME Maps was also
OOM-killed at 19:00 that day (no swap/zram on the image, ~700 MB available with
quickshell at ~750 MB RSS), which is a separate problem.

**Status: OPEN, REFRAMED 2026-09-28.** The receiver runs and streams NMEA but
never reaches a fix indoors because it has no assistance data. The earlier
conclusion below - that the assistance *indication path* is firmware-dead and
there is "no config-only fix" - is now shown to be **only half right**: the
failure is real, but it is **ModemManager-specific, not firmware**. A direct
libqmi/qmicli client drives the same QMI-LOC assistance queries that MM fails.
Predicted-orbits (xtra) can be *transferred* into the modem in full from
userspace; the one remaining wall is the modem rejecting the assembled xtra at
its final validation step. See *Reframed 2026-09-28* below.

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

### Reframed 2026-09-28: the assistance query works; injection reaches finalization

The A-GPS tests above were all run *through ModemManager*. Driving QMI-LOC
directly (qmicli / a small libqmi-GIR client over `qrtr://0`, coexisting with
MM via qmi-proxy) tells a very different story. **Every step MM fails, a direct
client completes** - the modem stayed `connected`/`attached` throughout, and
the worst-case recovery is a `systemctl restart ModemManager`, never a reboot.

- **The predicted-orbits data-source query works.**
  `qmicli -d qrtr://0 --loc-get-predicted-orbits-data-source` returns exit 0
  and the live xtra server list:
  `https://path{1,2,3}.xtracloud.net/xtra3Mgrbej.bin`. So the modem's LOC
  assistance path answers a direct client fine - MM's "couldn't load supported
  assistance data types: Failed to receive indication…" is **not** a dead
  firmware handshake.
- **Likely MM root cause: a missing TLV.** The data-source indication carries
  the server list but **omits `allowed_sizes`** (max file / max part size). MM
  needs those to chunk the download, so when they are absent it gives up and
  sets `SupportedAssistanceData = NONE` - which also disables MM's own
  `InjectAssistanceData` D-Bus method. qmicli, meanwhile, exposes no xtra
  inject at all. That is why *both* stock paths dead-end.
- **The xtra file is reachable and current.** `xtra3Mgrbej.bin` is ~64 KiB,
  `Last-Modified` refreshed roughly hourly (a signed XTRA3 file). The filename
  is stable; only the server order rotates.
- **Predicted orbits can be transferred into the modem from userspace.** A
  ~90-line libqmi-GIR injector (`inject_xtra_data`, chunked, lock-step on the
  per-part indication) pushes the whole file: **every part is acknowledged
  `indication_status = SUCCESS`**. The generic `inject_predicted_orbits_data`
  (with `format_type = XTRA`) is **`NotSupported` (QMI error 94)** on this
  firmware; the XTRA-specific `inject_xtra_data` is the supported message.
- **The wall: finalization is a non-functional stub.** Every part transfers
  (per-part indication `SUCCESS`, verified in a `QMI_DEBUG` trace - the sent
  Part Data bytes match the file exactly, so no transit corruption), but the
  **terminal** indication is always `GENERAL_FAILURE (1)` with a **fixed detail
  code 2** and validity stays `missing`. This was isolated exhaustively and the
  result is invariant across: xtra **v1/v2/v3**; part sizes 1024 (the modem's
  hard max - 1025 gives `ArgumentTooLong`) and even-division 997; UTC time
  injected (clock NTP-synced); GNSS engine stopped and started via MM;
  `register_events` for the inject/engine events beforehand; and 1-based part
  numbers (0-based -> `MalformedMessage`). The `detail=2` is constant regardless
  of `total_parts` (41/60/64/65 all report 2), so it is a reason code, not a
  part number. The generic `inject_predicted_orbits_data` (0x0025) is
  `NotSupported` (QMI 94) - the LOC service simply does not implement it.
  Conclusion: on this MPSS build (`MPSS.HI.2.5.1 BITRA`, Nov 2023) the QMI-LOC
  xtra path answers queries and buffers the transfer but its **finalization is
  not implemented** for a mainline client. Android reaches the same modem
  through the proprietary izat/loc-HAL, not this QMI-LOC message, so "Android
  does it" does not translate to a mainline userspace fix here.

**Where this leaves a fix.** Predicted-orbits (xtra) A-GPS is **not reachable
from mainline userspace on this modem firmware** - not because the assistance
path is dead (it answers queries fine), but because the QMI-LOC xtra
*finalization* is a stub. The remaining paths are all heavy: (1) a modem
firmware that implements QMI-LOC xtra finalization (unknown which, if any);
(2) reverse-engineer the proprietary izat/loc-HAL sequence Android uses and
reimplement it (large, uncertain - this is roughly what the FP6 pmOS GPS
bring-up required); (3) capture the exact `detail=2` meaning from Qualcomm QMI
headers to confirm it is "unsupported/disabled" rather than a missing step.

The **one lever that works** is coarse assistance: `--loc-inject-time` succeeds
and `--loc-inject-position-*` is available. That only turns a cold start into a
warm one (~30 s) *once almanac/ephemeris is cached*, so it cannot produce a
first indoor fix, but a small helper that injects time + a coarse (cell/IP)
position on GPS-enable is a real, shippable mitigation for repeat fixes. Not
built yet - deferred pending a decision on whether GPS is worth it given no
xtra.

The injector and data-source reader are kept at
`scripts/fp4-gps-xtra-inject.py` (diagnostic - reaches the finalization stub;
not a working fix). Operational caution: heavy qmicli LOC activity can make MM
briefly re-enumerate the modem (seen once, index 0 -> gone -> back at 0,
self-recovered, data reattached) - no reboot needed, but expect a short blip.
Modem restored to as-found after testing (assistance data deleted, MM location
back to `3gpp-lac-ci`).

**A caution for testing:** do not probe the engine with `qmicli --loc-*` while
ModemManager owns it. They share one LOC session; a `qmicli --loc-stop` tears
down MM's session too, and following NMEA through qmicli came back silent while
MM saw the same stream fine. Read location through `mmcli --location-get`, not
qmicli, unless MM's location is disabled first.

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

**Status: OPEN, re-tiered to a large (Tier-4-sized) task 2026-09-26.** Deeper
research found the gap is more fundamental than "unbridged in WirePlumber": it is
**missing at the kernel/AFE level**. On this phone call audio is DSP-internal --
`q6voiced` holds `VoiceMMode1` open and the DSP routes the voice session straight
to the same hardware backends as media (`QUIN_MI2S_RX` out, `TX_CODEC_DMA_TX_3`
in); the voice audio **never crosses an AP-accessible PCM**. And there is **no
Bluetooth audio backend at all**: the kernel has `# CONFIG_SND_SOC_BT_SCO is not
set`, no BT/AUX-PCM/SCO DAI in the sound card, and no HFP-AG↔modem bridge. So the
DSP has no BT AFE port to route a call to, and userspace has no PCM to loop back.
Two possible architectures, both sizeable: **(A)** add a BT-SCO/AUX-PCM AFE
backend (kernel config + DT DAI + DSP SCO support) + a UCM "Voice Call BT" verb;
or **(B)** a software loopback -- a q6routing voice↔MultiMedia path exposing the
call on host PCMs, bridged to PipeWire's native HFP-AG SCO nodes -- whose
feasibility hinges on whether those voice↔MultiMedia mixers exist on this card.
Either way it is kernel/integration work plus a live paired-headset call to
develop, which only the owner can drive; no repo change fixes it now. Next
code-free steps when the phone is up + a headset paired:
`amixer -c0 controls | grep -iE 'voice|mmode'` (does path B exist?) and, during a
call with the headset connected, `wpctl status`/`pw-dump` for HFP SCO nodes.

**Status (historical): OPEN**, and narrowed on 2026-09-24: not a missing package, an
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

**Likely fix (kernel-delivery-blocked, low priority), scoped 2026-09-26.** The
failures are at the GPI DMA layer under the `988000.i2c` (GENI) controller, not
in the HX83112A. The standard workaround for flaky GENI/GPI-DMA i2c on Qualcomm
is to take that bus **off DMA into FIFO/PIO mode** -- for a low-bandwidth
touchscreen the CPU cost is negligible and it removes the GPI DMA failure path
entirely. That is a DT change on the `&i2c` node for the touch controller
(drop/adjust its `dmas`, or a `qcom,...` FIFO quirk), so it hits the same
kernel-delivery wall as [D11](./fp4-fixes.md#d11)/D23 (the kernel package is upstream-tag, config-only,
no patch step). Cosmetic and not user-visible beyond a rare dropped touch, so it
stays low priority behind the kernel-delivery decision.

**Tested 2026-09-30: the drop-dmas approach is disproven; not DT-fixable.**
Deleting `dmas`/`dma-names` on `&i2c8` does NOT fall back to FIFO here. The geni
i2c driver uses GPI DMA precisely when the SE has FIFO disabled in firmware
(`fifo_disable`, read from the read-only `GENI_IF_DISABLE_RO` register); for this
SE that bit is set, so `setup_gpi_dma()` is mandatory. With the dmas removed the
bus fails probe (`geni_i2c 988000.i2c: error -ENODEV: Failed to get tx DMA ch`),
which takes the touchscreen with it (`hx83112a_probe` backtrace, no input
device). The FIFO path the driver has is gated on that hardware bit, which no DT
change flips. So the GPI-DMA flakiness needs a lower-level fix (GPI DMA driver or
SE firmware), not a device-tree switch. Leave D22 as-is; the driver's retries
absorb it.

---

## D23 — the camera's CSI PHY supplies are undescribed, and a clock sticks on {#d23}

**Status: CSI PHY supplies FIXED 2026-09-30 (sm6350-mainline/linux PR #15),
verified on hardware; the stuck AXI clock remains (an upstream driver issue,
below). The regulator data was UPDATED 2026-09-24 from Fairphone's own board
device tree.** Two separate items, neither with a user-visible symptom.

**Verified 2026-09-30.** The supply-name fix (below) booted on the handset
(7.2.0-dtstest): camss probes, /dev/video0..12 appear, and dmesg shows **zero**
"using dummy regulator" lines for csiphy (was 8). Sent upstream as PR #15;
permanence follows the same upstream-then-pin path as the NFC/mic work. The
stuck AXI clock is unaffected by this and stays open.

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

**The exact patch, confirmed against the mainline kernel 2026-09-26.** The
mainline tree is `v7.2.0-sm6350` (`sm6350-mainline/linux`). Its camss driver
(`csiphy_res_sm6350[]`) requests eight per-PHY supplies
(`vdd-csiphy{0..3}-{0p9,1p25}`, each `init_load_uA = 80000`), but the FP4
`&camss` override in `arch/arm64/boot/dts/qcom/sm7225-fairphone-fp4.dts` sets
only `vdda-0.9-supply` / `vdda-1.25-supply` -- **names the sm6350 camss code
never reads** (grepped the whole `camss/` dir). So those two lines are dead and
all eight supplies fall to dummy regulators. The mainline regulator labels are
confirmed in the same dts: `vreg_l18a` (0.788-1.049 V, the 0.9 V rail) and
`vreg_l22a` (1.08-1.305 V, the 1.25 V rail), both already powering other
consumers, so enabling them from camss is harmless. The patch:

```diff
 &camss {
-	vdda-0.9-supply = <&vreg_l18a>;
-	vdda-1.25-supply = <&vreg_l22a>;
+	vdd-csiphy0-0p9-supply = <&vreg_l18a>;
+	vdd-csiphy0-1p25-supply = <&vreg_l22a>;
+	vdd-csiphy1-0p9-supply = <&vreg_l18a>;
+	vdd-csiphy1-1p25-supply = <&vreg_l22a>;
+	vdd-csiphy2-0p9-supply = <&vreg_l18a>;
+	vdd-csiphy2-1p25-supply = <&vreg_l22a>;
+	vdd-csiphy3-0p9-supply = <&vreg_l18a>;
+	vdd-csiphy3-1p25-supply = <&vreg_l22a>;
 	status = "okay";
```

**Delivery is the blocker, not the diff** (see the note in [D11](./fp4-fixes.md#d11) and below): this is
a kernel-tree change, and `pkgbuilds/linux-moarchy-sm6350` builds the pinned
upstream tag **config-only, with no patch step** by design. So this patch needs a
decided delivery path -- a patch step in the kernel PKGBUILD, or a moarchy kernel
branch the manifest's `kernel-ref` points at -- the same path the existing
kernel DT work (aw88264/mic/NFC) needs. Correctness/power polish; the camera
works today on the dummies, so it is not urgent. (What the vendor DTS does
**not** give, and what would actually improve image *quality*, is the Qualcomm
ISP tuning -- chromatix/CAMX black-level, lens shading, colour matrices -- which
lives in the gated `camera-devicetree` + proprietary blobs.)

**Autofocus (the main sensor's real limiter), scoped, not attempted:** the main
imx582 has a VCM actuator but no focus control because mainline `qcom-camss`
does not drive actuators and no V4L2 lens subdev binds. Unlocking it needs (a)
identifying the VCM chip (the vendor `qcom,actuator` node names none -- an
I2C/CCI probe or the schematic; likely dw9714/dw9807/ak7375), (b) a mainline
V4L2 VCM driver bound over CCI in the dts, and (c) libcamera `CameraLens` +
megapixels AF support. A multi-component upstream/libcamera effort, not a patch.

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

## D29 -- s2idle enters but does not stay asleep {#d29}

**Where it stands (2026-10-11), for the next session:** the *abort* is fixed and
shipping: kernel package patch `0007-d29-geni-force-suspend.patch` (the mainline
qcom-geni force-suspend fix, `d0cd9c8d0fd5`) plus the udev stopgap
`moarchy-device-fp4/82-fp4-serial-wakeup.rules`, both in the `fp4` @ `1e1944b`
image. Neither is in the pinned `sm6350-mainline/linux` tree yet (task: flag the
mainline fix to Luca so the pin can carry it, then drop both). **Open, and the
reason the phone is not yet useful to carry:** the SoC never reaches deep sleep
(`qcom_stats` `aosd`/`cxsd`/`ddr` counts stay 0, `cx` pinned at perf 256), so
standby drains the battery. That is the next session's focus; the "Holder of
`cx` NOT yet pinned" and "Ruled out" notes below are the starting point.

**Findings 2026-10-11 (timed suspends via RTC alarm + `systemctl suspend`, on
battery unless noted; counters from `/sys/kernel/debug/qcom_stats`).**

- **The night that prompted it** (WoWLAN on, so WiFi stayed associated all night):
  100% -> 27% overnight; one s2idle stretch of
  395 min took 87% -> 34%, i.e. **~8%/h while suspended** (D28 had measured
  ~1%/h in September). s2idle itself holds (the D29 abort fix works); the SoC
  never collapses: `aosd`/`cxsd`/`ddr` 0 after 11 h, `adsp` and `modem` sleep
  Count 0, only `cdsp` counts.
- **WoWLAN's cost is NOT yet measured (correction).** Run B was meant to turn it
  off with `wake-on-wlan none`, but `none` is not a valid nmcli value; the command
  failed and the connection kept `magic,disconnect`, so A (14.7%/h) and B (7.3%/h)
  both ran with WiFi associated through suspend; the gap is gauge noise at low
  charge, not WoWLAN. The value that restores the original behaviour is
  `default`: then mac80211 deauthenticates before `PM: suspend entry` (checked in
  dmesg order) and reassociates ~5 s after resume. On the phone a local policy
  (`/usr/local/sbin/fp4-wowlan-policy`, udev on `pm7250b-charger` change + a boot
  unit) now sets `magic,disconnect` only while the charger is online and
  `default` on battery. Not in the image.
- **Holder of `cx` found: the Bluetooth UART.** `pm_genpd_summary` showed exactly
  one consumer of `cx` at perf 256: `884000.serial` (the `hci_uart` serdev,
  `active`), in suspend too. `rfkill block bluetooth` runtime-suspends it and
  `cx`/`mx` drop to `off-0` even awake. Real fix still to find (the UART should
  release `cx` while BT is idle or across suspend, as 0007 does for the console).
- **A permanent DDR vote: the crypto engine.** `1dfa000.crypto` (`qcrypto`, built
  in, runtime PM `unsupported`) holds 393600 on gemnoc/llcc forever. Unbinding it
  (`echo 1dfa000.crypto > /sys/bus/platform/drivers/qcrypto/unbind`) removes it.
  Kernel crypto has the ARM CE instructions, so QCE is likely dispensable.
- **GCC never reaches `sync_state()`:** `gcc-sm6350 100000.clock-controller:
  sync_state() pending due to 3d6a000.gmu` (the GMU has no driver of its own; the
  "drm/msm: Attach a driver to GMU" series addresses it). Forced at runtime with
  `printf 1 > /sys/bus/platform/devices/100000.clock-controller/state_synced`.
- **CPU side is fine:** `power-domain-cpu-cluster0` state S2 (`cluster_aoss_sleep`)
  has 20 s2idle entries, so the apps RSC does hand over its sleep votes.
- **All three removed (BT blocked, QCE unbound, GCC synced), unplugged:** still
  `aosd`/`cxsd`/`ddr` +0, `adsp`/`modem` +0 over 16 min; battery 39 -> 38%
  (~4%/h, weak at 1% resolution; that run also still had WiFi associated
  through suspend, see the correction above). The same outcome as
  SM8550 (portare-ch/portareos#505: sync_state fixed, counters still 0). What
  still blocks the collapse is on the DSP side (ADSP/modem never record a sleep,
  even with audio, sensors, ModemManager and WiFi off) or a firmware bandwidth
  requirement; or the ADSP/modem firmware does not publish its stats at all.

**Findings 2026-10-15 (battery, timed suspends):**

- **Every measured night had WoWLAN on.** The 10-11 udev/boot policy never ran
  after the first plug-in (no uevent on unplug; at boot WiFi was not up yet), so
  the connection kept `magic,disconnect`. Replaced by a `system-sleep` hook
  (`/usr/lib/systemd/system-sleep/fp4-wowlan`) that decides right before each
  suspend from the charger state. NetworkManager must keep `magic,disconnect`:
  with `ignore`/`default` NM itself takes WiFi down at PrepareForSleep (before
  any hook), which is what the earlier "WiFi drops before suspend entry" was,
  and WoWLAN can then never wake it. On battery the hook disables the triggers
  and disconnects WiFi itself; on the charger it leaves it associated. Verified:
  on the charger a magic packet woke the phone in 10 s.
- **Nights:** 10-11 (BT blocked, QCE unbound, GCC synced, but WoWLAN on) 8.7%/h,
  ran flat at 04:30; 10-14 day 9.1%/h; 10-14/15 night 7.4%/h while continuously
  suspended for 8.5 h. So the drain is in suspend itself, not frequent waking.
- **WoWLAN off, modem connected (M1): 4.7%/h. Plus modem radio in low power
  (M2b, 63 min): 4.7%/h.** The modem radio is not the drain (its sleep counter
  moves once the radio is low, +8, but the battery does not care).
- **In suspend the CPUs are quiet:** a 10-min s2idle added only ~8900 IPIs incl.
  resume and WiFi reconnect. (Awake idle, by contrast, runs ~3400 function-call
  IPIs/s and ~860 apps_rsc interrupts/s -- a separate awake-power problem.)
- So ~4.7%/h (~180 mA) is a quiet SoC that never leaves the nominal corner, which
  points back at the Linux-side holders (BT UART `cx`, QCE DDR vote, GCC
  sync_state) that have only ever been tested together with WoWLAN on.
- **Clean combination, first try (2026-10-15 night, cut short):** WoWLAN off and
  WiFi disconnected by the new hook (verified in its log), Bluetooth blocked, QCE
  unbound, GCC synced, ModemManager on `--test-no-suspend-resume`. Unplugged
  ~22:20 UTC, suspended 22:25-23:43 without a break; gauge 66% -> 52% in 85 min.
  The 66% is charging-inflated (the gauge settles several points lower after
  unplug), so the true rate is roughly 6-10%/h -- not better than 4.7%/h without
  the three. Plugged back in to keep the phone usable, so no long curve. Working
  conclusion: the Linux-side holders are not the drain either; something draws
  ~150-250 mA in s2idle that none of WoWLAN, the modem radio, BT, QCE or GCC
  touch. Next: per-component bisection on the charger (touch controller, panel
  supplies, cameras, sensors, regulators left on by the bootloader), using the
  regulator and genpd summaries rather than the 1%-step gauge.
- **Not a regression (2026-10-16, tested).** The September kernel D28 measured
  on (`v7.2.0-sm6350` @ `16337c9dd348`, its 09-23 config, `LOCALVERSION=-sept`,
  own modules in `/lib/modules/7.2.0-sept`, transient boot) drains the same:
  two suspends on battery, 77% -> 66% in 96 min (~7%/h), `aosd`/`cxsd`/`ddr` 0.
  **The fuel gauge reports a stale value at the moment of resume** and catches up
  over the next minutes awake (76% at wake -> 73% 2.5 min later). D28's ~1%/h
  read 57% at wake and dismissed the drop to 49% within 5 min as "re-settle"; the
  49% was the real value, so D28's figure is very likely this artifact and FP4
  s2idle has probably always drained ~5-7%/h. Measure across-suspend drain only
  with a reading taken >= 10 min after wake, or over a full night. The real
  problem remains the missing deep collapse; stock Android on the FP4 sits well
  under 1%/h in standby.
- **Touch ruled out while awake, and a warning (2026-10-16).** Live
  `current_now` on battery, screen off: 174 mA baseline, 188 mA with the
  `Himax-hx83112b-TS` driver unbound (noise), so the touch controller is not the
  awake drain. **Do not unbind that driver.** The hx83112a is a TDDI chip (one IC
  for panel and touch): rebinding fails with -5 while the panel is off, and the
  unbind took the shared supply/reset down so the panel would not come back
  either (dpms stayed Off, power button did nothing). Only a reboot recovered it.
- **Userspace diff and audio ruled out (2026-10-16).** The 10-06 image (`d7f57bf`,
  old kernel + old userspace) and the 10-10 image differ in only ~15 packages:
  ModemManager 1.24.2 was already in 10-06; the rest are our own packages
  (`moarchy-device-fp4` -6 -> -10: D32 audio routes, D31 softdep, UCM; `moarchy`
  -14 -> -15; new `alsa-utils`) and trivial libs. Prime suspect was the D32
  capture routes keeping LPASS/ADSP up, but with the phone idle both PCMs are
  `closed`, nothing holds `/dev/snd/*`, and every codec/DSP DAPM context reports
  bias level `Off` with no widget powered: audio is fully idle. Still open: flash
  the 10-06 image as a full A/B (artifact available until 2026-10-20) and read
  the drain >= 10 min after wake, to settle whether userspace changed anything.

**Status: OPEN (found 2026-10-01, on the flashed 0.5.0 public build).** The
suspend path works but the SoC never stays in s2idle: it enters and exits in
~0.5-1.5 s every time. This is why battery is `P` and why D28's overnight figures
do not reproduce. It is a local/runtime problem, NOT an upstream gap.

**Measured** (over ssh):

| trigger | conditions | s2idle held |
| --- | --- | --- |
| `echo mem` | on USB | ~2 s |
| `echo mem` | unplugged | <1 s |
| `systemctl suspend` (root) | WiFi off | 0.47 s |
| `echo mem` | screen blanked + WiFi off | 1.45 s |

`suspend_stats/success` increments each time, but `pm_wakeup_irq` is empty and no
registered wakeup source increments -- not a clean wakeup-source wake. During the
frozen window the churn is IPI + `arch_timer` + `apps_rsc` (the RPMh RSC) + geni
`gpi-dma`/UART.

**Ruled out** (with evidence): USB charger/typec, WiFi (D5 power-save-off is a red
herring here), the display, phantom touch input (D22 -- input quiet, touch IRQ
flat), the stay-awake flag, blocking sleep inhibitors, active audio, and broken
idle-notify (a probe swayidle fires at its timeout, so Hyprland delivers idle).

**Upstream supports deep sleep on this SoC.** SM6350/SM7225 (pre-Hamoa Qualcomm)
reaches s2ram-equivalent depth *through* s2idle + RPMh; a Jan-2026 lkml RFC
("soc: qcom: rpmh-rsc: Register s2idle_ops...") assumes these targets hit s2ram
depth in s2idle (it only fixes NVMe context loss; the FP4 has UFS, so it does not
apply). `sm6350.dtsi` is fully wired: `cluster_pd` references `cluster_aoss_sleep`
(`arm,psci-suspend-param = <0x4100b244>`), the deepest AOSS cluster idle state.

**Peripheral-hold hypothesis RULED OUT by elimination (2026-10-01).** `cx`/`mx`
sit "on" at perf 256, but stopping the likely holders one by one and cumulatively
did **not** change the ~1 s exit: USB autosuspend 0.9 s, +BT off 0.9 s, +cdsp+adsp
stopped 0.9 s, +modem stopped 1.0 s (baseline 1.4 s). So no peripheral subsystem
(USB, Bluetooth, the adsp/cdsp/modem remoteprocs) is what pulls it out of s2idle.

**So it is kernel-internal:** the s2idle loop exits in ~1 s with no registered
wakeup source and empty `pm_wakeup_irq`, independent of every peripheral.

**CONFIRMED via `qcom_stats` on the PRODUCTION kernel (2026-10-01) - no debug
kernel needed.** `CONFIG_QCOM_STATS=m` ships in the stock config; `sudo modprobe
qcom_stats` exposes `/sys/kernel/debug/qcom_stats/`. The deep-sleep counters are
all zero since boot (uptime 56 min): `aosd` (AOSS) Count 0, `cxsd` (CX collapse)
Count 0, `ddr` (self-refresh) Count 0. So the SoC has **never once reached
system-wide deep sleep** - that is the whole defect, measured directly.
`power-domain-cpu-cluster0` is "on" (never power-collapses).

**Holder of `cx` NOT yet pinned (two earlier conclusions retracted - see below).**
Verified by controlled tests (2026-10-01, prod kernel): with the phone **unplugged
AND the display genuinely idle** (`dpms` off, `disp_cc_mdss_mdp_clk` enable_count
= 0, zero atomic commits in a 6 s passive ftrace), **`cx`/`mx` are still pinned at
perf 256 and a real `echo mem` still never deep-sleeps** (`aosd`/`cxsd`/`ddr`
stay 0). So the deep-sleep blocker is a continuous `cx` NOMINAL vote from a
subsystem that none of the black-box toggles released.

**Ruled out as the holder (by controlled test):**
- **Display / MDP clock.** ftrace shows the kernel DOES release the mdss clocks
  when the compositor is idle (`clk_bulk_disable` via `mdss_runtime_resume`'s
  counterpart; enable_count 0 at idle). The clock is only on while Hyprland is
  committing frames. `cx` stays 256 even with it fully off. (This retracts the
  earlier "MDP clock leak on dpms-off" conclusion, which was taken while the
  screen had bounced back ON - a `dpms("off")` request itself triggers a commit
  that re-enables the panel, which is a *separate* compositor bug: dpms-off does
  not stick.)
- **USB cable** (unplugged, `cx` still 256) and the **dwc3 controller** (unbound
  `a600000.usb`, USB master clock and `cx` unchanged).
- **modem / adsp / cdsp / Bluetooth** (stopped individually + cumulatively
  earlier; no change - though that run was screen-on-confounded).
- Display-clock-leak upstream fixes do not apply anyway: the 2020 DPU
  system-suspend fix is already in our kernel; the 2026-07 dual-MDSS-PD series is
  SM8750-only; no cont_splash/simplefb here.

**Process note / two retractions.** D29's cause was mis-called twice from
*confounded single readings*: first "`0xb0000000` crashes the SoC" (really flaky
transient boots), then "MDP clock leak holds cx" (readings taken with the screen
bounced back on). Lesson: control BOTH confounds (unplugged + display-idle) and
trace the actual `cx` perf-state vote before concluding.

**cx consumer NAMED (2026-10-01, prod kernel, `pm_genpd_summary`).** Reading
`/sys/kernel/debug/pm_genpd/pm_genpd_summary` with the phone unplugged + idle, the
`cx` domain lists exactly one consumer voting the NOMINAL corner:

```
cx                              on                              256
    884000.serial                   active                      256   SW
    ae01000.display-controller      active                      64    SW
    8804000.mmc                     suspended                   0     SW
    genpd:0:4080000.remoteproc      suspended                   0     SW
```

`884000.serial` is `ttyMSM0` (the geni QUP UART). It is **runtime-active for
essentially all of uptime** (`power/runtime_active_time` 22,563 s vs
`runtime_suspended_time` 15 s over a 6 h boot) and votes `cx` perf 256. The
display-controller only votes 64, so even a fully idle display leaves `cx` pinned
at 256 by the serial port - which is exactly why every display/MDP test above left
`cx` at 256. **The serial port is the dominant `cx` holder.**

Two things keep `ttyMSM0` active: (1) it is a registered kernel console (`EC` in
`/proc/consoles`; no explicit `console=` in `/proc/cmdline`, so it comes from the
DTB `chosen`/default), and (2) moarchy runs `serial-getty@ttyMSM0.service`
(`agetty` on it since boot). **The instrumented test below shows only (1) matters -
the getty is NOT the holder.**

**Driver mechanism (source-confirmed, `qcom_geni_serial.c` @ v7.2.0-sm6350).** The
`cx` vote is an **OPP vote**: `geni_serial_set_rate`/`geni_serial_resources_on`
call `dev_pm_opp_set_rate(uport->dev, clk_rate)` (and `dev_pm_opp_set_level` by
baud), which requests the `cx` corner. It is dropped in exactly one place -
`geni_serial_resources_off()` calls `dev_pm_opp_set_rate(uport->dev, 0)` - and that
runs **only** from `qcom_geni_serial_runtime_suspend` (`SET_RUNTIME_PM_OPS`).
Runtime suspend only fires when the port is idle; the **console role** keeps the
port in use, so `runtime_suspend` never runs and the OPP/`cx` vote never falls
(matches the live `runtime_active_time` ≈ full uptime).

**Instrumented test 2026-10-02 (self-healing probe, `qcom_stats` + ftrace). This
REFUTES the earlier "getty is the holder / dropping
it hangs the box / deep-idle slowdown" write-ups - all three were wrong.** The
probe stopped `serial-getty@ttyMSM0` *and* `pkill`ed `agetty`, waited 14 s, then
ran `echo mem` with a +12 s rtc wakealarm, tracing throughout, then auto-restored.

- **Phase B (getty stopped + agetty killed, +14 s): `cx` still 256,
  `884000.serial` still `active`.** Its `runtime_active_time` rose by the full
  ~14,860 ms while `runtime_suspended_time` did **not** move (stayed 15,470 ms) -
  the port was runtime-active the entire 14 s. **So killing the getty does nothing
  to the pin; the registered-console role holds the port active on its own.**
- **Phase C (`echo mem`, rtc +12 s): returned in ~1.98 s, not 12 s** - the D29
  early-exit - and `aosd`/`cxsd`/`ddr` stayed **0**. s2idle still never reaches
  deep sleep, and it exits in ~2 s *independently of the cx pin*.
- **The earlier "userspace hang / deep-idle slowdown" was a measurement artifact:**
  the `qcom_stats` counters prove the SoC never deep-slept, so the ~90 s sluggishness
  was not deep idle. The likely cause is the **function tracer** on
  `dev_pm_opp_set_rate`/`_genpd_set_performance_state` - those fire on every
  clock/perf change system-wide, so tracing them crawls everything; the system
  recovered exactly when restore set `current_tracer=nop`. The phone was never
  wedged and never needed a reboot (it was not rebooted; it is up 1h56m).

**ROOT CAUSE CONFIRMED (2026-10-02, instrumented, two independent confirmations).**
The ~2 s exit is an **armed wakeup IRQ firing the instant s2idle idles the CPUs**.
Traced via the `suspend_resume` tracepoint: the abort happens between
`dpm_suspend_late` end and the `dpm_suspend_noirq`/resume turnaround (no
`machine_suspend`/idle-loop time at all - s2idle never enters). A `func_stack_trace`
on `pm_system_irq_wakeup` caught the single call, from
`irq_pm_handle_wakeup <- handle_fasteoi_irq <- gic_handle_irq <- cpuidle_enter`,
and a kprobe on its argument named the IRQ:

```
irq=172   ->   172:  msmgpio  64  Edge  884000.serial:wakeup
```

**IRQ 172 is the serial console's RX wakeup GPIO (`884000.serial` = `ttyMSM0`, the
geni debug UART, routed through `msmgpio` GPIO 64).** It is armed as a wakeup during
`suspend_device_irqs` and fires immediately, so `irq_pm_handle_wakeup` sets
`pm_abort_suspend`, `pm_wakeup_pending()` is true at the post-noirq check, and the
suspend bails. The handler never runs (the IRQ is masked by the wakeup path), which
is why `/proc/interrupts` shows count 0 for it and why `pm_wakeup_irq` reads empty
after resume (resume clears it) - those two red herrings sent the earlier passes
looking at wakeup *sources* instead of an armed wakeup *IRQ*.

**Confirmation:** `echo disabled >
/sys/devices/platform/soc@0/8c0000.geniqup/884000.serial/power/wakeup`, then
`echo mem` with a +20 s rtc alarm -> **suspend HELD for 21.08 s** (vs ~1.3 s with
it enabled), and the only wake was `irq=116 pm8xxx_rtc_alarm`, i.e. the intended
alarm. So disabling the serial console's wakeup fixes the abort outright.

**It is two stacked serial-console problems, both now correctly placed:**
1. **(primary, the abort) the RX wakeup IRQ 172** aborts every suspend in ~2 s.
   Fixed by disabling `884000.serial` wakeup.
2. **(secondary, depth) even once s2idle HELD for 21 s, `aosd`/`cxsd`/`ddr` stayed
   0** - the SoC held in s2idle but did not reach the RPMh-tracked deep collapse.
   This is where the earlier `cx`-pinned-at-NOM finding belongs: the console's OPP
   vote caps the depth. It is real but second-order; the abort had to be fixed
   first to even observe it.

Both point at the same thing: the serial console does not quiesce for suspend.
Earlier mis-calls on this defect (MDP clock, "getty is the holder", "USB/VBUS",
"deep-idle hang") are all retracted above - this is the first cause backed by a
suspend that actually held.

**Fix (implemented for the primary abort; secondary depth still open).** A udev rule
disables the console's wakeup at boot:
`moarchy-device-fp4/82-fp4-serial-wakeup.rules` ->
`ACTION=="add|change", SUBSYSTEM=="platform", KERNEL=="884000.serial",
DRIVER=="qcom_geni_serial", ATTR{power/wakeup}="disabled"` (installed to
`/usr/lib/udev/rules.d`, `moarchy-device-fp4` pkgrel 5). **Verified via the real
udev path 2026-10-02** (not just a manual echo): rule installed -> `udevadm
control --reload` + `trigger` flips `884000.serial/power/wakeup` `enabled`->`disabled`
-> `echo mem` **held 21 s** to its rtc alarm (was ~1.3 s). Ships in the next image;
no kernel change needed. This is the local stopgap - see the upstream fix below.

**Both D29 layers are one kernel bug, and the upstream fix is already in flight.**
The spurious wake (irq 172) and the depth cap (`cx`/OPP not dropping) have the same
cause: a geni UART kept runtime-active (a console) never runs its runtime-suspend
callback during *system* suspend, so `geni_se_resources_off()` is never called -
and that one function is what applies the **sleep pinctrl** (RX `bias-pull-up`,
which the FP4 DT `qup_uart1_sleep_rx` ships specifically "to avoid ... spurious
wakeups") **and** drops the **OPP/`cx` vote** (`dev_pm_opp_set_rate(dev, 0)`).
`qcom_geni_serial_suspend()` only re-tags the interconnect; it does not deactivate
resources. **Upstream patch (under review, NOT merged):** "serial: qcom-geni: add
force suspend/resume to system sleep callbacks", Praveen Talari (Qualcomm), 2026-07
- calls `pm_runtime_force_suspend()` in suspend / `pm_runtime_force_resume()` in
resume, which invokes the runtime callback (hence `resources_off`: sleep pinctrl +
OPP drop) during system sleep. It skips only when `no_console_suspend` is set; FP4
does not set that, so it should fix **both** layers for us. Its stated motivation
("resources ... not gated ... prevents the platform from reaching its lowest idle
state") is exactly this defect.

**VALIDATED on FP4 hardware 2026-10-02 (patch fixes the abort; depth is a SEPARATE
bug after all).** Talari's patch was cherry-picked onto the pinned kernel (branch
`d29-patch-test`, kernel `pkgrel 2`), built in CI, and transient-booted
(`fastboot boot`, boot-only, modules unchanged since `uname` is identical) with the
udev workaround removed and **serial wakeup ENABLED** - the clean test. Result:
`echo mem` **held 21.8 s** to its rtc alarm (was ~1.3 s), and a kprobe on
`pm_system_irq_wakeup` showed the only wake was `irq 116 pm8xxx_rtc_alarm` (intended)
- **irq 172 no longer aborts suspend.** So the patch fixes the abort on FP4 exactly
as well as the udev rule. **But `aosd`/`cxsd`/`ddr` stayed 0** even with the patch
dropping the serial's OPP/`cx` vote - so the deep-collapse depth cap is **NOT** the
serial after all (this retracts the "secondary = serial OPP vote" guess above): some
other `cx` consumer, or a separate RPMh/cpuidle condition, keeps the SoC out of the
deepest state. The abort - the actual "s2idle won't hold" defect and the battery win
- is what both fixes address; the depth cap is now a distinct open item.

**The patch is ALREADY MERGED TO MAINLINE (checked 2026-10-02): commit
`d0cd9c8d0fd5` "serial: qcom-geni: add force suspend/resume to system sleep
callbacks" is in torvalds/linux.** (Confirmed via the Aug-2026 follow-up "serial:
qcom-geni: Fix unbalanced pm_runtime_enable" by Abel Vesa, which carries
`Fixes: d0cd9c8d0fd5` and its own `Reviewed-by: Praveen` + `Tested-by: David
Heidelberg` (OnePlus 6T) - that follow-up only matters for `no_console_suspend`,
which FP4 does not set, but carry it too for correctness.) So this is **not** an
upstreaming task - no `Tested-by` to send, no new patch. The under-review v2 we
test-carried on `d29-patch-test` is byte-equivalent to the merged commit; use the
**mainline commit(s)** for the real adoption.

**Next (adopt, don't upstream):** (1) in moarchy, either bump the `sm6350-mainline`
kernel to a base that already contains `d0cd9c8d0fd5` (+ the unbalance fix), or
backport those two mainline commits into `linux-moarchy-sm6350` referencing their
SHAs - then drop the udev stopgap (`82-fp4-serial-wakeup.rules`); (2) flag it to
Luca Weiss (sm6350-mainline + the pmaports `linux-postmarketos-qcom-sm6350` aport)
so the fork/pmaports pull it, with our FP4 validation as the justification - a note/
issue, not an MR of an under-review patch. Separate open item: the deep-collapse
depth cap (what still holds `cx`/blocks `cxsd`), and the compositor not keeping the panel
dpms-off.

## D33 -- no modem after the first suspend: ModemManager aborts on IPA modems {#d33}

**Status: FIX APPLIED 2026-10-15 -- verify on the next image.** Found when calls
stopped working: `mmcli -L` said "No modems were found" while the modem
remoteproc, rmtfs, tqftpserv and q6voiced were all up.

**Cause.** ModemManager 1.24.2 (pulled in by the 10-10 image build; earlier
images had an older one) aborts in its cleanup:

    Bail out! ERROR:../ModemManager/src/mm-iface-modem.c:6779:mm_iface_modem_count_bearers: assertion failed: (max >= ctx.count)

70 times between 10-10 and 10-15 -- at nearly every suspend, and on every
`systemctl stop`. systemd restarts it, but the restarted daemon's modem setup is
cancelled by the suspend in progress ("[device qcom-soc] error initializing:
Operation was cancelled") and never retried, so the modem stays gone until the
daemon is restarted by hand. Read from the 1.24.2 source:
`modem_create_bearer_list()` gives IPA (multiplex-only) modems
`max_active_bearers = 0`, and the bearer count that commit `01208cc6`
("base-manager: increase suspend timeout for each active bearer") added to every
cleanup path counts the connected multiplexed bearer against that 0. Upstream:
issue #1013 ("Assertion failing on resume from suspend on Beryllium", the Poco
F1, also IPA), fixed by MR !1401 / commit `0edcb916` ("base-manager: fix cleanup
of multiplexed bearers"), not in any 1.24.x release.

**Fix.** `--test-no-suspend-resume`, which skips ModemManager's sleep handling (the
modem stays registered through suspend, which a phone wants anyway).
`--test-quick-suspend-resume` (what postmarketOS ships) was tried first and does
NOT avoid it: its terse path runs the same count. Shipped as
`default/systemd/system/ModemManager.service.d/10-moarchy-no-suspend-resume.conf`
in `moarchy` pkgrel 16; on the handset as an /etc drop-in. Verified (17:45):
three suspends, same ModemManager PID, modem `connected` after each. A separate,
milder bug remains: an occasional SIGSEGV right after boot (2026-10-16 10:58,
one minute in; also the restart loops seen 10-14). systemd restarts it within a
second and the modem comes up; not the suspend assertion. (A first
"verification" that morning was invalid: the drop-in write had silently failed
while the phone slept, the quick-mode drop-in stayed, and that one crashed at
four more suspends that day.) The shutdown path still hits the assertion, so a
stop or reboot leaves a core dump; harmless until 0edcb916 lands. Drop it once a
ModemManager containing `0edcb916` is in the repos.

**2026-10-16: the SIGSEGV is not rare.** Four in one boot with
`--test-no-suspend-resume` (12:57 at startup, 15:49, 16:39, 17:13), all
`SEGV_MAPERR`, frame #0 at 0x30 (a NULL member call), #1 `ModemManager+0x19759c`.
The 15:49 one came right after `simple connect` created `qmapmux0.0` (mux id 1),
i.e. while bringing up the multiplexed data bearer again. Each one drops the
modem for a few seconds and loses any location setup. Not yet symbolized
(needs the debug package).

---

## D34 -- calls have no audio again: no voice stack in the packaged kernel {#d34}

**Status: FIX IN THE PACKAGE, awaiting a call on the CI image (2026-10-17).**
`linux-moarchy-sm6350` pkgrel 13 carries the port as
`0009-call-audio-q6voice.patch` (drivers, APR nodes, FP4 links, TX topology
`NONE` as the default instead of the uncalibrated `SM_ECNS`) plus
`SND_SOC_QDSP6_Q6VOICE{,_DAI}=m` in `config`. Transient boot of the same tree
(`7.2.0-voice`, own modules): `00-02 CS-VOICE`, `00-03 VoiceMMode1`, 204 voice
mixer controls, `q6voiced` active, media sink/source unchanged, modem
connected. Move to fixes after a call carries audio both ways. Note WirePlumber
also lists `VoiceMMode1` as a source; the default stays MultiMedia2.

Found 2026-10-16. A regression of
[D17](./fp4-fixes.md#d17), which is recorded as fixed.

D17 was fixed on 2026-09-23 by a **hand-built** kernel: a port of the QDSP6
voice services (`q6voice`, `q6mvm`, `q6cvs`, `q6cvp`, `q6voice-dai`) plus a DT
change adding the voice DAI links, which gave `00-02 CS-VOICE` and
`00-03 VoiceMMode1` and let `q6voiced` (configured for `hw:0,3`) hold the voice
session. That work lives only in `~/Personal/fp4-mic-capture` (commits
`c8aa42c` "Port the QDSP6 voice services", `b867d72` "Wire the CODEC_DMA ports
into the voice mixers"; `wip/0005-second-front-end.patch`,
`wip/0006-call-audio-voice-services.patch`). It was deliberately left out of
the mic PR #11 to converge on sc7280-mainline's port instead
([`fairphone-4.md`](./fairphone-4.md) section 1).

The packaged kernel (`linux-moarchy-sm6350`, pin `sm6350-7.2.y` @ `5ba18a1`,
patches 0000-0008) has none of it: no q6voice sources in the tree, no
`CONFIG_SND_SOC_QDSP6_Q6VOICE` in `config`, no voice link in the FP4 DTS. Every
image built from the package, which is what the phone runs since the move to CI
images, therefore has no call audio. On the handset:

```
/proc/asound/pcm:  00-00 MultiMedia1, 00-01 MultiMedia2   (no 00-02 / 00-03)
q6voice modules:   0
q6voiced:          Failed to open tx: No such file or directory
```

**Fix path.** Either carry the port as package patches (against the
patch-free intent of the package, like 0007/0008) until it is upstream, or port
it onto sm6350-mainline following sc7280-mainline/linux#35 and land it there,
then bump the pin. The second is the stated plan; the first gets calls back
now. Either way: rebase `c8aa42c` + `b867d72` and the DT links onto `5ba18a1`,
add the Q6VOICE config symbols, transient-boot it (matching modules, see
AGENTS.md), check `/proc/asound/pcm` for VoiceMMode1, then place a call.
Check `q6voiced.conf`'s device number against the new PCM list.

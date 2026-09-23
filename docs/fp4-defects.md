# Fairphone 4 — defects found on hardware

A register of things observed on a real handset, kept separately from
[`fairphone-4.md`](./fairphone-4.md) because that document describes the
*port* and this one describes what is *wrong with it*. §10 there lists the
four gaps that were known from upstream before the phone existed; everything
here was found by running the thing.

Started 2026-09-22, the day the handset arrived and was first flashed.

**Status vocabulary.** `OPEN` — reproduced, not fixed. `FIXED` — fixed and
verified on hardware. `FIXED (unverified)` — fixed, but the verification
needs something not available yet. `WONTFIX` — understood and deliberately
left.

| id | what | status |
| --- | --- | --- |
| [D1](#d1) | USB debug gadget never bound | **FIXED** |
| [D2](#d2) | Rotation turns the screen but not touch input | **FIXED** |
| [D3](#d3) | Speaker is silent although playback succeeds | **FIXED** |
| [D4](#d4) | ~~Wi-Fi does not come back after a reboot~~ — not a defect | **WITHDRAWN** |
| [D5](#d5) | Wi-Fi latency is ~20x what the link quality implies | **OPEN** |
| [D6](#d6) | Camera: no profile, and a stride bug behind it | **FIXED** |
| [D7](#d7) | Sensors had no daemon | **FIXED** |
| [D8](#d8) | GPS: receiver runs, fix needs sky view | **OPEN** |
| [D9](#d9) | Keyboard tile calls a command that does not exist | **OPEN** |
| [D10](#d10) | LPI pinctrl loses a boot race; all audio disappears | **OPEN** |
| [D11](#d11) | The phone drops into EDL after repeated reboots | **OPEN — important** |
| [D12](#d12) | Hyprland draws a "started without start-hyprland" banner | **OPEN** |
| [D13](#d13) | PipeWire exposed no capture source, then stalled on one | **FIXED** |
| [D14](#d14) | Microphone and speaker could not be used at the same time | **FIXED** |
| [D15](#d15) | Notifications return after every reboot | **OPEN** |
| [D16](#d16) | Recordings were made of crackle: the PCM's S24_LE lies | **FIXED** |
| [D17](#d17) | Calls had no audio path at all: no voice DSP in this kernel | **FIXED** |
| [D18](#d18) | Speakers silent across reboots: UCM used volume as a switch | **FIXED** |

---

## D1 — the USB debug gadget never bound {#d1}

**Status: FIXED** — `c0bf6e2`, verified on the handset.

On the first boot after flashing, `moarchy-usb-debug` reported success and
left nothing behind: no `/dev/ttyACM0` on the host, no gadget. The unit shows
`active (exited)` either way, because it is a `oneshot` with
`RemainAfterExit=yes` whose script deliberately exits 0 on every failure path
— so "active" never meant "worked".

Two independent bugs, both only observable on hardware.

**The symlink target has to be absolute.** configfs resolves it with
`kern_path()`, against *the calling process's CWD* rather than — as every
other symlink in Unix — the directory the link is created in. The script does
`cd "$G"` first, so `../../functions/acm.usb0` resolved to
`/sys/kernel/functions/acm.usb0`, which does not exist. The link failed
silently, the config ended up with no functions in it, and binding a config
with no functions fails as:

```
udc a600000.usb: failed to start moarchy: -22
UDC core: moarchy: couldn't find an available UDC or it's busy
```

which names neither the config nor the missing function. The `ln` failure was
also swallowed by `2>/dev/null`, so the journal said only `could not bind`.

**The re-run guard tested the wrong thing.** `[ -s "$G/UDC" ]` asks whether
the file has a size; configfs's `UDC` is a newline when unbound, so it is true
either way. A second run printed `gadget already bound to ` — to nothing —
and exited, refusing to repair exactly the half-built gadget it exists to
repair.

Both links are absolute now, failures say what went wrong and what the config
actually contains, and the guard tests the content with whitespace stripped.
Verified: the script reports `acm.usb0 -> /dev/ttyGS0`, `ncm.usb0 -> usb0`,
`bound to a600000.usb`, `usb0 is 172.16.42.1/24`, and a shell on
`/dev/ttyGS0`.

**Verified end to end 2026-09-22.** After a reboot with the fixed script
installed, the host sees

```
Bus 003 Device 024: ID 1d6b:0104 Linux Foundation Multifunction Composite Gadget
crw-rw---- 1 root uucp 166, 0 /dev/ttyACM0
enp0s20f0u1i2    UP
```

so the gadget enumerates, the serial console appears and the NCM interface
comes up. It earned its keep immediately: that same reboot lost Wi-Fi (D4),
and the cable was the only way back in.

One host-side note, not a defect in this: `/dev/ttyACM0` is `root:uucp`, and
reaching it needs membership of `uucp` (or the NCM link addressed, which needs
root once). Worth doing before it is needed rather than during.

## D2 — rotation turns the screen but not touch input {#d2}

**Status: FIXED** — `ec5faa3`, confirmed on the handset 2026-09-22: the
rotate tile turns the screen and touch follows it.

Reported from the handset: the rotate tile turns the display to landscape,
but touches still land where they would have in portrait.

`rotate()` in `moarchy.common/widgets/Toggles.qml` sets the *output*
transform via `hl.monitor({ ..., transform = n })` and nothing else. Hyprland
does not carry an output's transform across to the touch devices pointed at
it; a touchscreen has its own `transform`, and until it is set the touch
coordinate space stays in the panel's native orientation. So the two disagree
by exactly 90°, which is what was reported.

The fix applies the same transform to every touch device the compositor
knows about. Two things it must not do:

- **Not `hyprctl keyword`.** Under a Lua config that is refused outright:
  `keyword can't work with non-legacy parsers. Use eval.` The working form is
  `hyprctl eval "hl.device({ name = ..., transform = n })"`, which returns
  `ok`.
- **Not a hardcoded device name.** The touchscreen here is
  `himax-touchscreen-1`, which is an fp4 fact and does not belong in a file
  shared by every device — the same reason `rotate()` already reads the output
  name from the compositor rather than naming `DSI-1` (devices.md D3,
  refactor.md N2). The device list is enumerated instead.

Note the panel also registers a *keyboard* called `himax-touchscreen`,
distinct from the touch device `himax-touchscreen-1`. Only the latter is in
`devices.touch`, which is what the fix iterates.

## D3 — the speaker is silent although playback succeeds {#d3}

**Status: FIXED 2026-09-23, confirmed by ear.** The mainline `aw88264` driver
drives both amplifiers and the speaker makes sound; see *The fix, on hardware*
at the end of this entry. The handset's owner identified the test clip
unprompted ("was this bubbles?" — it is `complete.oga`, which bubbles), which
is a better confirmation than "I heard something".

It was confirmed starting at -75.5 dB and climbing, using
`scripts/fp4-speaker-test`, which is how anyone should approach this speaker —
the warning immediately below is why.

The driver went upstream as
[sm6350-mainline/linux#12](https://github.com/sm6350-mainline/linux/pull/12),
together with the device-tree change that switches this handset onto it.

It went silent again on 2026-09-23 after that switch, which turned out not to
be the driver at all -- see [D18](#d18).

The diagnosis that follows was written 2026-09-22 and still stands.

> ### ⚠ Test this carefully, and mind the waveform
>
> The first attempt here powered the amplifier up and played a tone, and the
> result was loud enough to be mistaken for a fire alarm — **the fire brigade
> was called.**
>
> That was originally written up as "-18 dB is close to full output". Having
> since calibrated the whole scale by ear, that reading was wrong, and the
> correction matters:
>
> | level | dB | how it sounds (1.1s chime) |
> | --- | --- | --- |
> | 100 | -45.5 | inaudible |
> | 120 | -35.5 | "veeeery faint" |
> | 151 | -20.0 | quiet |
> | **157** | **-17.0** | **normal listening volume — what the phone now keeps** |
> | 191 | 0.0 | full output |
>
> -18 dB is an *ordinary* volume for a short sound. What made the original
> incident an alarm was that it was a **sustained sine** at that level. A
> continuous tone reads as a warning signal; a chime at the same level reads
> as a notification. The hazard was the waveform at least as much as the
> level.
>
> So: test with short sounds, never a sustained tone, and start at -75.5 dB
> and climb — `scripts/fp4-speaker-test` does both, and refuses above -13 dB
> without an explicit override.

### What is actually wrong

The amplifiers are left in a silent state and nothing ever takes them out of
it. Read directly over I2C (bus 3, both parts):

| reg | value | meaning |
| --- | --- | --- |
| `0x04` SYSCTRL | `0x4441` | bit 0 **PWDN = 1** — powered down |
| `0x05` SYSCTRL2 | `0x003a` | bit 4 **HMUTE = 1** — muted |
| `0x0c` HAGCCFG4 | `0xf064` | volume bits 15:8 = `0xf0` — 15 x -6 dB = **-90 dB** |

Three independent reasons for silence, all at once.

They stay that way because the vendor driver cannot clear them. Every
DSP-mediated control it owns fails:

```
aw882xx_rx_enable_get: dsp_msg error, ret=-22
aw_qcom_get_module_enable: read afe rx failed
```

`aw882xx_rx_switch_l`/`_r` therefore refuse to leave `0`. The driver expects
the Qualcomm ADSP to carry its control messages and mainline provides no such
path, so the amplifier is reachable over I2C but never *enabled for playback*.

### What is proved to work

- **The part is what the driver assumed.** Register `0x00` reads `0x1852` on
  both amps — the chip id `aw88264-port` checks for, now confirmed on silicon
  rather than inferred from a vendor header.
- **I2C writes reach the part.** Setting PWDN=0, HMUTE=0 and attenuation
  `0x30` read back exactly.
- **The I2S link carries audio.** With the amplifier powered up and unmuted,
  sound came out — loudly. Whatever else is unresolved, the digital path from
  the SoC to the speaker is not in question.
- **The vendor driver reasserts its state.** After the stream stopped, both
  registers were back to `PWDN=1`/`HMUTE=1`; its shutdown path powers the
  part down.

### Why this is the case for the mainline driver

`aw88264-port` drives the part over I2C and uses no DSP channel at all:
`aw88264_power()` writes PWDN/AMPPD in SYSCTRL and `aw88264_hw_mute()` writes
HMUTE in SYSCTRL2, both directly. Everything the vendor driver fails to do
here is a plain register write there.

One calibration datum for it, learned the hard way: **its TLV scale is
correct but its practical range is not what one would guess.** `0x30` is
already near full output. The control should default low.

### The fix, on hardware — 2026-09-23

Done, and **without the reflash**. The plan above assumed the DT change had to
ship first, because the mainline driver matches `awinic,aw88264` and the phone
declares `awinic,aw882xx_smartpa`. Matching the downstream name as well turns
the whole thing into a module swap: `wip/bringup-fp4-no-reflash.patch` in
`aw88264-port`. The DT also already carries `#sound-dai-cells = <0>`, which is
what lets the sound card's `i2s-dai-link` resolve to the new driver's DAI
without caring what it is called.

What ships here: `/etc/modprobe.d/aw88264-blacklist.conf`, which blacklists
`snd_soc_aw882xx` and maps it to `/bin/true`. Both drivers match the same
compatible now, so whichever loads first wins, and it must not be the vendor
one.

Result:

```
3-0034 -> aw88264      Speaker Left Volume    (0..191)
3-0035 -> aw88264      Speaker Right Volume   (0..191)
0 [F4  ]: sm7225 - Fairphone 4
```

Three things turned up that only hardware could tell us, all written up in
`aw88264-port`'s README:

1. **The reset polarity is inverted** relative to the DT's `GPIO_ACTIVE_HIGH`
   flag, measured on both parts. The vendor driver never reads that flag, so
   nothing has ever had to make it true.
2. **The driver's minimum-volume setting wrote near-maximum output.**
   `AW88264_VOL_MAX_STEPS` was 195; the field's real maximum is 191, and 195
   made the coarse nibble overflow and truncate. Asking for the quietest
   setting produced -1.5 dB, and the probe default *was* that setting — so the
   driver came up at -1.5 dB. Given this entry's warning, that is the worst
   possible bug to have had, and it is fixed and round-trip verified over the
   whole range.
3. **Two amplifiers in one card collide on the control name**, and one
   duplicate control is enough to take the entire card down, microphone
   included (`failed to instantiate card -16`). Upstream that is
   `sound-name-prefix` per codec node; for bring-up each instance names its
   control from the `sound-channel` property instead.

### There was a fourth reason for silence

This entry's central claim was "three independent reasons for silence, all at
once" — `PWDN`, `HMUTE`, and -90 dB. That was one short. With the mainline
driver clearing all three, the amplifiers read, mid-playback:

```
SYSCTRL=0x4000  PWDN=0  AMPPD=0     SYSCTRL2 HMUTE=0
```

Powered, un-muted, sensible volume, and still nothing — because **`I2SEN`,
bit 6 of `SYSCTRL`, is the I2S receiver's own enable**, and `0x4000` has bit 6
clear. The part was deaf rather than mute. `aw88264_power()` now sets it, and
`SYSCTRL` reads `0x4040` during playback.

So the register table at the top of this entry should be read as four rows,
not three. The fourth was invisible in the original dump because the original
dump was of a part that was also powered down and muted — with those cleared,
there was nothing left to blame and the missing bit had to be found by going
back to the vendor's register header.

**Every volume measured before that point was measured on a deaf amplifier**,
and none of it says how loud any setting is. The ladder starts from the
bottom again.

**Still to do:** the proper DT change (rename the compatible, add
`sound-name-prefix`, correct the reset flag to `GPIO_ACTIVE_LOW`) and a
boot reflash, after which the bring-up shim comes out. And somebody has to
listen, starting low.

**Next:** build a kernel with `aw88264` plus its DT change, blacklist
`aw882xx_smartpa`, and reflash `boot` only. Verification should be done by
reading registers back, not by listening.

## D4 — Wi-Fi does not come back after a reboot {#d4}

**Status: WITHDRAWN — this was not a defect.** Filed 2026-09-22 and
disproved the same day. Left in place rather than deleted, because the
mistake is instructive and someone will otherwise make it again.

The claim was that the phone never returned after `systemctl reboot`: no
ping, and the host's neighbour table showing the address `FAILED`. All of
that was true. The conclusion drawn from it was wrong.

The journal settles it:

```
16:27:48  boot
16:27:50  policy: auto-activating connection '<wifi>'
16:27:53  dhcp4 (wlan0): new lease, address=192.0.2.29
```

Wi-Fi was back **thirteen seconds after boot**, from a saved profile with
`autoconnect yes`. What actually happened is that the DHCP lease moved from
`192.0.2.26` to `192.0.2.29`, and the pings were going to an address the
phone no longer held.

The real lesson is small and worth keeping: **do not hardcode this phone's
Wi-Fi address**. The lease is not stable across reboots, and an unreachable
IP means "look for it again", not "the network is broken". The USB link
(D1) has a fixed address precisely because it does not depend on any of this,
which is why it is the right thing to reach for first.

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

## D6 — the camera had no profile, and a stride bug behind it {#d6}

**Status: FIXED** — verified on the handset 2026-09-22: megapixels runs, meters
live frames and draws its full UI.

Two problems, the second only visible once the first was solved.

### The profile

`moarchy-device-fp4/PKGBUILD` said the cameras needed "a media graph
libmegapixels does not configure yet and a sensor driver (imx576) that was
still on the mailing list in May 2026". Neither is true on `v7.2.0-sm6350`:
all three sensors bind, `/dev/media0` carries 84 links with every sensor link
`ENABLED,IMMUTABLE`, and `/dev/video0` advertises five formats.

What was missing was one file. megapixels matches a profile against
`/proc/device-tree/compatible` — `fairphone,fp4` — finds none among its
fourteen, and prints `No suitable config, defaulting to uvc`.

Measured, so the next person need not re-derive it:

| sensor | CSI PHY | subdev | mode |
| --- | --- | --- | --- |
| `imx582 1-001a` | `msm_csiphy0` | `/dev/v4l-subdev21` | 4000x2256 |
| `imx582 0-001a` | `msm_csiphy2` | `/dev/v4l-subdev23` | 4000x2256 |
| `imx576 2-0010` | `msm_csiphy3` | `/dev/v4l-subdev22` | 2880x2156 |

all `SRGGB10_1X10`, through `csid0` and `vfe0_rdi0` to `/dev/video0` — the
same shape as the Pixel 3a's profile. The imx576 is the front camera: it is
the 25 MP part in the specification and the only one of the three that is not
an imx582.

Still not established: which of the two imx582s is main and which is
ultra-wide. The profile uses the `csiphy0` one; if the framing is wrong, swap
to `imx582 0-001a` on `msm_csiphy2`. megapixels' v1 format has room for one
rear camera, so the other is unreachable regardless.

### The stride bug

With a profile in place megapixels found the camera, opened it — and died on
its own assertion:

```
mp_camera_capture_buffer: Assertion `bytesused ==
    (width_to_bytes(format, width) + width_to_padding(format, width)) * height' failed
```

libmegapixels pads a raw row to the next multiple of **8** bytes; qcom-camss
pads to **16**. The rear sensor's only mode is 4000 px, and 4000 px of packed
10-bit is 5000 bytes:

```
5000 % 8  == 0    libmegapixels pads 0, expects 5000/row
5000 % 16 == 8    the driver pads 8, produces 5008/row
```

`VIDIOC_G_FMT` confirms `Bytes per Line : 5008`, and three captured frames come
to 33894144 bytes — exactly `5008 * 2256 * 3`.

This is invisible on every device megapixels ships for, because their widths
are 16-byte clean: the Pixel 3a's 4032 px is 5040 bytes, the PinePhone's
3264 px is 4080. It cannot be dodged in the profile either — the sensor offers
one mode, and `media-ctl` accepts 3968 or 4032 while the pipeline stays at
4000.

`pkgbuilds/libmegapixels-moarchy` carries the one-line fix. Aligning to 16 is a
superset, so no working device moves. The tidier fix is for megapixels to take
the stride from the `bytesperline` V4L2 already reports rather than recompute
it; that is a larger change and belongs upstream.

After both: `megapixels-getframe` reports
`Selected mode: 4000x2256 [pRAA] stride 5008` and receives frames,
`megapixels-configlint` passes the profile clean, and megapixels itself runs
with live auto-exposure.

## D7 — the sensors had no daemon {#d7}

**Status: FIXED** — `0cb9dcb`, verified on the handset 2026-09-22.

Every motion and environment sensor on this phone lives on the ADSP's
Snapdragon Sensor Core rather than on a bus Linux can see, so
`/sys/bus/iio/devices` held three PMIC ADCs, three thermal zones, and nothing
else. No accelerometer, gyroscope, magnetometer, light or proximity.

Three pieces were needed and only one had to be written:

| | |
| --- | --- |
| `hexagonrpc` | the FastRPC bridge to the ADSP — **newly packaged** here |
| `libssc` | speaks the sensor core's protocol over it — already in Arch `extra` |
| `iio-sensor-proxy` | publishes on D-Bus — already in `extra`, and already linked against `libssc.so.2` |

After it:

```
accelerometer   X=0.74 Y=0.41 Z=9.83 m/s²   (gravity, lying flat)
light           23 Lux
proximity       FAR
gyroscope       X=-0.06 Y=-0.06 Z=0.15
magnetometer    X=103.2 Y=-9.2 Z=-4.1 µT
compass         3.58°
```

Two traps, both now carried as comments in the packaging:

- **Upstream ships no sysusers or udev rules.** Its units say `User=fastrpc`,
  and `/dev/fastrpc-*` is `root:root 0600` from the kernel, so the daemon
  cannot open the node it exists to talk to. Both are in the PKGBUILD.
- **`-R` defaults to a vendor prefix, not a device one.** Upstream serves
  `/usr/share/qcom/`; this phone's configuration is under
  `/usr/share/qcom/sm7225/Fairphone/fp4`, where `firmware-moarchy-fp4` puts
  it. With the default the daemon attaches to the ADSP quite happily and then
  answers nothing the sensor core asks — an `active` service and no sensors.

Note `ssccli` warns "Mount matrix provided by firmware is all 0". That is
expected and harmless: it reads the firmware directly and ignores udev, while
`iio-sensor-proxy` reads `ACCEL_MOUNT_MATRIX` from
`81-libssc-fairphone-fp4.rules`, which is confirmed set on the fastrpc node.

## D8 — GPS runs but has not been given a fix {#d8}

**Status: OPEN**, and probably only pending a walk outside.

No kernel GNSS device exists (`/dev/gnss*` absent, no gnss modules) and none
is needed: on this SoC the receiver is the modem's, reached through
ModemManager. It advertises the capability and simply was not switched on:

```
Location | capabilities: 3gpp-lac-ci, gps-raw, gps-nmea, agps-msa, agps-msb
         |      enabled: 3gpp-lac-ci          <- cell-tower location only
```

`mmcli -m 0 --location-enable-gps-nmea --location-enable-gps-raw` turns it on,
after which NMEA flows:

```
$PQWM1,65535,31529,0,255,99999999,0,272,11,4,184,...
$PQMECLK,65535,31529,3153599922176.0000,...
```

Those are Qualcomm proprietary sentences, so the receiver is running. What has
**not** been seen is a standard `$GPGGA`/`$GPGSV` sentence or a position,
because every test so far has been indoors. That is the one thing here that
cannot be settled over SSH.

`geoclue` 2.8.2 is installed and its `[modem-gps]` source is enabled, so a
client asking for a position should cause it to turn GPS on by itself — which
is why nothing here makes the `mmcli` setting persistent. Leaving the receiver
running permanently costs battery for a capability nothing is currently asking
for.

**Next:** take the phone outside, run `mmcli -m 0 --location-get`, and look for
`$GPGGA` with a non-empty fix.

## D9 — the Keyboard tile calls a command that does not exist {#d9}

**Status: OPEN**, and deliberately not fixed here because the right fix is a
product decision rather than a typo.

Reported as "the keyboard is broken". **The keyboard is not broken.** The
on-screen keyboard runs from boot as PID 801 and holds the input method —
`hyprctl devices` shows `hl-virtual-keyboard-moarchy-keyboard main=True`, and
a second instance launched by hand loads all three layouts and then exits
with

```
another input method already holds this seat; exiting so two keyboards do not fight over it
```

which is the binary behaving exactly as designed.

What *is* broken is the **Keyboard tile** in the quick toggles:

```js
{ id: "keyboard", name: "Keyboard", glyph: "󰌌", on: false,
  cmdOn: "moarchy-toggle-keyboard" },
```

`moarchy-toggle-keyboard` is not a binary on this image. The package is
`moarchy-keyboard`, and it ships exactly two things — the executable and
`/usr/share/moarchy-keyboard/layouts/` — with no toggle verb, no IPC strings
and no subcommands. So the tile has never done anything, and like the
screenshot tile before it (D-list above), it fails **silently**, because
`Quickshell.execDetached` reports nothing when a command is missing.

This is the second tile found calling a command that does not exist. The
pattern is worth a check of its own: every `cmdOn`/`cmdOff`/`read` in
`Widgets.js` should be verified against an actual binary, because nothing in
the shell will ever tell you.

The fix is not obvious and is not mine to pick. The keyboard is
input-method driven — it appears when a text field asks for input — so there
may be nothing for a tile to toggle, in which case the entry should be
deleted rather than repaired. If a manual show/hide is wanted, it needs a
verb in `moarchy-keyboard` first.

**Note for whoever reads the crash logs:** two `moarchy-keyboard` SIGABRTs
sit in `coredumpctl` from 2026-09-22 21:28. Those are mine, from launching it
over SSH without `WAYLAND_DISPLAY`, so Qt fell back to the `xcb` platform
plugin and aborted. They are not evidence of a fault on the device.

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

## D11 — the phone drops into EDL after repeated reboots {#d11}

**Status: OPEN as a cause, RECOVERABLE as a symptom.** Seen three times on
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

### The likely cause: an exhausted A/B retry counter

This is A/B hardware. The bootloader decrements the active slot's retry
counter on every handoff and marks the slot unbootable at zero unless the OS
calls back to say the boot succeeded — the mechanism `flash.sh` already
documents at length, and the reason it runs `--set-active` at all.

`moarchy-device-fp4` ships `qbootctl-mark-successful.service` for exactly this.
But `qbootctl` on this device says:

```
Couldn't find cmdline arg: 'slot_suffix'
get_current_or_active_slot: Unable to read boot slot property
Current slot: _b
```

It recovers the slot from the partition table, but the cmdline this image
builds carries no `androidboot.slot_suffix`, and whether `qbootctl -m`
succeeds under that condition has **not** been verified. If it does not, every
boot spends a retry and none are given back, which ends exactly here — and
tonight involved an unusual number of reboots.

That fits the evidence better than anything else, but it is a hypothesis, not
a measurement. The way to settle it is one command on a booted phone:

```
qbootctl                 # shows retry counts per slot
systemctl status qbootctl-mark-successful
```

If the retry count for `_b` is low or the unit failed, this is it.

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

## D13 — PipeWire exposed no capture source, then stalled on one {#d13}

**Status: FIXED** — `53-fp4-ucm.conf` in `moarchy-device-fp4`, verified on the
handset 2026-09-23 by recording through `parecord` from a cold boot.

With the microphone working at the ALSA level -- `arecord` on `hw:0,0`
capturing real audio -- nothing could record through PipeWire. Two separate
faults, found one behind the other.

### The card produced no nodes at all

`wpctl status` listed the device but neither a sink nor a source, and the only
sink in the graph was `Dummy Output`:

```
Audio
 ├─ Devices:
 │      45. Built-in Audio                      [alsa]
 ├─ Sinks:
 │  *   64. Dummy Output
 ├─ Sources:
```

`pactl list cards` explains it -- ACP offers exactly one profile:

```
Profiles:
        off: Off (sinks: 0, sources: 0, priority: 0, available: yes)
```

So ACP had rejected the card's UCM. **Why is not understood.** The things that
would explain it were checked and are all fine: the UCM is found
(`conf.d/sm7225/Fairphone 4.conf` resolves, and the driver name really is
`sm7225`), the file parses, the HiFi verb's only control
(`QUIN_MI2S_RX Audio Mixer MultiMedia1`) exists, and `alsaucm -c "Fairphone 4"
set _verb HiFi set _enadev Mic` applies the whole profile by hand without
error. That is left open here rather than guessed at.

Setting `api.alsa.use-acp = false` drops WirePlumber to the raw-PCM node
factory, which produces both a sink and a source. It is a workaround, not a
fix: it also means UCM no longer drives routing, which is what D13's second
half and `moarchy-fp4-mic-route.service` are about.

### Then the stream stalled 96 ms in

With a source finally present, `parecord` connected, ran for exactly 0.096 s,
and then froze -- latency climbing, frame count never moving, no error to the
client. The log said what the client was not told:

```
spa.alsa: hw:0,0c: Channels doesn't match (requested 64, got 4)
spa.alsa: given audio.channels 64 out of range:4-4
```

The capture PCM is narrow, and `--dump-hw-params` says exactly how narrow:

```
FORMAT:      S16_LE S24_LE
CHANNELS:    [1 4]
RATE:        [8000 48000]
PERIOD_SIZE: [480 1920]
```

PipeWire probes 64 channels, does not get them, creates the node as
`s16le 4ch` anyway, and then cannot run it. Pinning the node to what the
hardware actually does -- `S24_32LE`, 2 channels, 48 kHz, period 960 -- makes
it record.

One detail that cost a round trip and is worth writing down: the format is
**`S24_32LE`, not `S24LE`**. ALSA's `S24_LE` is 24 bits in a 32-bit container,
which PipeWire spells `S24_32LE`; `S24LE` is the packed 3-byte format, which
this PCM does not offer. Getting it wrong does not produce a warning -- the
node simply stops appearing, which looks exactly like the first fault again.

### What it looks like fixed

From a cold boot, no manual step, recording through the PipeWire source while
the haptic motor runs for 700 ms at t=1.3 s:

```
channels=2 rate=48000 width=4 frames=98304 (2.05s)
ch0: quiet=9.276e+05  peak-window=5.094e+06 at t=1.45s  ratio=5.49x
ch1: quiet=9.441e+05  peak-window=5.093e+06 at t=1.45s  ratio=5.39x
```

Both channels, the right moment, a clear response.

---

## D14 — the microphone and the speaker could not be used at once {#d14}

**Status: FIXED 2026-09-23**, device-tree change, `boot` reflashed. The patch
is `wip/0005-second-front-end.patch` in `fp4-mic-capture`.

A phone needs three things from its audio: music on the speaker, calls on the
earpiece, and the microphone working *while* one of those plays. The third was
impossible, and not for want of configuration.

The card declared one front end. `aplay -l` and `arecord -l` both named it:

```
playback: card 0: F4, device 0: MultiMedia1
capture:  card 0: F4, device 0: MultiMedia1     <- the same PCM
```

So playback and capture contended for a single q6asm session, and whichever
opened second was refused:

```
q6asm-dai: Audio Client already active
q6asm-dai: cmd = 0x10db3 returned error = 0x9
q6asm-dai: q6asm_dai_prepare: q6asm_open_write failed
ASoC error (-22): at snd_soc_pcm_component_prepare()
```

The visible symptoms were a recorder that failed whenever anything had played
recently, and captures that came back truncated — 0.7s instead of 2s.

### Two halves, and the first alone breaks the card

Adding `mm2-dai-link` is the obvious half. It is not sufficient, and on its
own it is worse than nothing:

```
snd-sm8250 sound: error -EINVAL: MultiMedia2: error getting cpu dai name
snd-sm8250 sound: probe with driver snd-sm8250 failed with error -22
```

`q6asm-dais` builds its DAI list from child nodes of `q6asmdai` and has no
default set — `of_get_child_count()`, and `-EINVAL` if it is zero. The board
declared `dai@0` for MultiMedia1 and nothing else, so a link naming
MULTIMEDIA2 pointed at a DAI that was never registered, and the entire card
failed to probe. No sound card at all, microphone included.

The directions are split deliberately rather than left full-duplex:

```
dai@0  MULTIMEDIA1  direction = Q6ASM_DAI_RX   playback only
dai@1  MULTIMEDIA2  direction = Q6ASM_DAI_TX   capture only
```

which makes the device list unambiguous — `aplay -l` shows only MultiMedia1,
`arecord -l` only MultiMedia2 — so nothing has to be configured to pick the
right one.

### After

```
playback: card 0: F4, device 0: MultiMedia1   (pcm0p)
capture:  card 0: F4, device 1: MultiMedia2   (pcm1c)
```

A 5s capture runs to completion with two clips played during it, and the DSP
error count is zero. Capture routing moves to
`MultiMedia2 Mixer TX_CODEC_DMA_TX_3` accordingly.

### How it was flashed, which is the reusable part

Only `boot` was written. `xbl` and `abl` were never touched, and fastboot
lives in `abl`, so the phone stayed flashable throughout — that, not the A/B
slots, is what made this safe. (Slot `_a` reads `Bootable: 0`, so there was no
slot fallback.)

The procedure, worth repeating for any DT-only change:

1. `dd` the running `boot` partition off the phone. It is the rollback, and on
   this handset it did **not** match the shipped 0.5.0 image.
2. Split the payload: `image/boot/android-image.py` writes `kernel + dtb`
   concatenated, so the appended DTB is found by scanning for FDT magic whose
   own `totalsize` reaches exactly the end of the payload.
3. Rebuild the image from the extracted kernel and the *old* DTB first, and
   check it is byte-identical to what came off the phone. That proves the
   split and the writer before anything is flashed.
4. `dtc -I dtb -O dts` both DTBs and diff them. The change here was 14 lines;
   anything else in that diff is a bug.
5. `fastboot flash boot`, nothing else.

---

## D15 — notifications return after every reboot {#d15}

**Status: OPEN**, reported 2026-09-23.

Notifications that have been dismissed — the update notice, the keybindings
hint and others — come back on the next boot. Dismissing one should be
remembered across reboots, and is not.

Not yet investigated. The thing to establish first is whether these are
genuinely persisted notifications being re-delivered, or whether something in
the session re-creates them at every start, because those have different
fixes: the first is notification-daemon state, the second is whatever emits
them.

---

## D16 — recordings were made of crackle {#d16}

**Status: FIXED 2026-09-23** — `audio.format = "S16LE"` on the capture node in
`53-fp4-ucm.conf`.

Sound Recorder produced files that played back as crackle. The corruption was
in the capture, not the playback: "Recording 6" had **16,657 sample-to-sample
jumps larger than 25% of full scale** in 2.5 s — about one sample in seven —
with 1.55% of samples pinned at full scale.

### The PCM's S24_LE does not contain 24-bit data

The capture PCM advertises `FORMAT: S16_LE S24_LE`. Captured raw with
`arecord`, in the same room, seconds apart:

| format | rms | peak | clipped |
| --- | --- | --- | --- |
| `S24_LE` | 89.6% FS | **484% FS** | 13607 |
| `S16_LE` | 0.4% FS | 2.2% FS | 0 |

A peak of 484% of 2²³ is not possible for genuine 24-bit data. Whatever the
DSP puts in that buffer, it is not a 24-bit sample right-justified in 32 bits,
so anything that believes the framing saturates. The node had been pinned to
`S24_32LE` — by me, while fixing D13 — and that is what made every recording
crackle.

Pinning `S16LE` instead:

| | before | after |
| --- | --- | --- |
| rms | 8–36% FS | **0.46%** |
| peak | 100% FS | **1.9%** |
| clipped samples | 99–217 | **0** |
| discontinuities | 3359 | **0** |

### Two measurement traps, recorded because both cost time

**A full-scale reference that does not match the container.** `arecord -f
S24_LE` writes four-byte samples whose real full scale is 2²³, not 2³¹. Scored
against 2³¹ the raw capture looked quiet and clean at 0.3%, which is how the
hardware got cleared of suspicion for an hour. The 484% above is the same data
scored correctly.

**Counting large sample-to-sample jumps as a crackle detector.** It is not
one: a genuinely loud signal produces them legitimately, so the metric cannot
tell distortion from volume. Clipped-sample count and crest factor do
distinguish them, and should have been the first thing looked at.

### What this cleared

The analogue gain looked broken beforehand — sweeping `ADC1 Volume` from 0 to
20 changed the recorded level not at all, which pointed at the microphone.
It was not: the format bug saturated every setting equally. With `S16LE` the
control behaves, 0.54% to 2.41% rms across its range with no clipping at any
point, and the default is now 15.

---

## D17 — calls had no audio path, because the kernel had no voice DSP {#d17}

**Status: FIXED 2026-09-23, proven by a call.** The handset's owner placed a
call and confirmed audio in both directions. Kernel driver port plus
a device-tree change, `boot` reflashed. Patch:
`wip/0006-call-audio-voice-services.patch` in `fp4-mic-capture`.

`fairphone-4.md` §10.3 said call audio needed three things: a capture path,
something to hold the voice session open, and IMS on a VoLTE-only network.
With the microphone working, the obvious next step was to enable `q6voiced`.

That would not have worked, and the reason is worth writing down: **there was
nothing for it to open.**

```
q6voiced:                      not installed
voice-related mixer controls:  0
device tree:                   mm1-dai-link, mm2-dai-link, and no voice link
sound/soc/qcom/qdsp6/:         no q6voice, q6cvs, q6mvm or q6cvp
```

The Pixel makes calls because `sdm670-mainline` carries an out-of-tree voice
stack — `CONFIG_SND_SOC_QDSP6_Q6VOICE=m` in its config. `sm6350-mainline` has
neither the symbol nor the source. `device.conf`'s note that "there is no call
audio path to hold open" was right, and righter than it knew: the absence went
all the way down to the kernel.

### The port

Eleven files from `sdm670-mainline`'s `on-stable` branch, plus a DT binding
header and Kconfig/Makefile entries. They build against this tree essentially
unchanged — the one incompatibility is AFE ports.

The driver wires up an **LPI_MI2S** family that SDM670 has and SM7225's
`q6afe` never instantiates. `LPI_MI2S_{RX,TX}_5/6` do not compile here at all.
Ports 0–4 *do* compile, which is the trap: they produce a driver that loads,
binds, and then does this —

```
q6voice-dai ...: ASoC: Failed to add route LPI_MI2S_RX_0 Voice Mixer -> LPI_MI2S_RX_0(*)
snd-sm8250 sound: ASoC: failed to instantiate card -19
```

**ASoC fails the entire card on a route to a widget that does not exist.** Not
the route, not the component — the card. So adding voice support with one
stale port reference costs the microphone, the speaker and everything else,
and the phone boots with `--- no soundcards ---`. That happened here for one
boot. Stripping the family fixes it, and the fix is driver-side, so it costs a
module reinstall rather than a reflash.

### After

```
00-00: MultiMedia1 (*) : playback 1
00-01: MultiMedia2 (*) : capture 1
00-02: CS-VOICE    (*) : playback 1 : capture 1
00-03: VoiceMMode1 (*) : playback 1 : capture 1
```

182 voice mixer controls where there were none. Both front ends are declared,
not just VoiceMMode1: CS-VOICE is the path a network with 2G/3G fallback uses,
and which one a SIM gets is the operator's business rather than the handset's.

### Userspace

- **`q6voiced`** is enabled on this device now, and `moarchy-device-fp4` ships
  `q6voiced.conf` naming `hw:0,3`. The daemon runs, watches ModemManager over
  D-Bus, and leaves the PCM `closed` until a call exists — which is correct.
- **`81voltd`** is packaged (`pkgbuilds/81voltd`, v1.2.0) and enabled. It
  answers the modem's request for an IMS PDN, without which a VoLTE-only
  network cannot carry a call at all. Packaged unconditionally rather than
  based on the SIM in the device: whether IMS is needed is a property of the
  operator, and shipping only what one SIM needs makes the phone work for its
  owner and fail for everyone else.

Modem state, for the record: registered on an LTE/5G network, `gsm-umts` still
listed as supported so CS fallback may be available, ModemManager's `Voice`
interface exported with `emergency only: no`.

### Calls work, both directions, 2026-09-23

Confirmed on a real call. Getting there took three more findings, and only the
last one mattered:

**Uplink was silent because of the vocproc topology.** The driver defaults TX
to `VSS_IVOCPROC_TOPOLOGY_ID_TX_SM_ECNS` (`0x10F71`) -- single-microphone echo
cancellation and noise suppression. That is a DSP processing chain driven by
ACDB calibration data, and this device has none: `find /usr/lib/firmware
-iname '*acdb*'` returns nothing, and `firmware-moarchy-fp4` drops `acdb/` on
purpose. Downlink runs `RX_DEFAULT`, which tolerates the absence. So the DSP
was being asked to run an uncalibrated processing chain on the uplink and
returned silence. `TOPOLOGY_ID_NONE` (`0x10F70`) is pass-through and works.

**This is not a local workaround.** `sc7280-mainline/linux` commit
`8bdb8de44a` makes exactly this the driver default for the Fairphone 5 --
*"only this topology seems to work so far for the mic"* -- as part of PR #35,
merged 2026-09-18, which ports the same q6voice stack, the same APR nodes and
the same CODEC_DMA voice-mixer entries this device needed. The whole approach
here was independently reinvented; converging on that tree is the way forward
rather than submitting separately.

**Two of my own detours, recorded because both looked right:**

- A `snd_pcm_start()` patch to `q6voiced`, on the theory that a merely
  *prepared* capture PCM would not power the converter. It moved the PCM from
  PREPARED to RUNNING and changed nothing audible, and it duplicated q6voiced
  MR !3, which upstream **closed**. `prepare` is what drives the DPCM backend.
  Reverted. The working call runs with both PCMs at PREPARED.
- A diagnosis that the ADC was unpowered during a call, from `ANA_CLK_CTL`
  reading `0x34`. Wrong, and wrong for a avoidable reason: I never measured
  the baseline. A *known-working* media capture reads `0x34` too. The codec
  was fine throughout.

**Known divergence from the vendor, for later.** FP4's own
`mixer_paths_lagoon_fp4.xml` routes handset and speaker downlink out
`QUIN_MI2S_RX` to the amplifiers; `RX_CODEC_DMA_RX_0`, which this build uses,
is the vendor's headphone and hearing-aid path. It works audibly, but
converging matters before any upstream submission. The vendor also sets
`VOC_EXT_EC MUX = QUIN_MI2S_TX` for speakerphone echo reference, which
`q6cvp.c` does not do -- expect echo on speakerphone.

---

## D18 — the speakers went silent across reboots, and the amplifiers were fine {#d18}

**Status: FIXED 2026-09-23** — `a31af3d`, verified on the handset.

After the switch to the upstream `aw88264` driver ([D3](#d3)) the speakers
produced nothing, on every boot, through six separate listening tests. The
driver and the device tree were the obvious suspects and both were innocent.

Measured at the amplifiers over I2C during playback, both parts were in exactly
the state they should be in:

```
SYSST=0x0311   PLLS=1  SWS=1  BSTS=1      PLL locked, switching, boost finished
SYSCTRL=0x4040 PWDN=0  AMPPD=0 I2SEN=1    powered, I2S enabled
SYSCTRL2       HMUTE=0                    not muted
HAGCCFG4=0x4364                           -25.5 dB, an ordinary listening level
```

Rather than ask for a seventh listening test, the speaker was measured with the
phone's own microphone: play a 440 Hz tone, record it, Goertzel the result.

| | 440 Hz vs noise floor |
| --- | --- |
| playing | **82x** |
| silence baseline | 1.6x |

Sound was coming out the whole time. What was silent was the PipeWire sink,
sitting at 0% / -inf dB.

**Cause.** These volume controls carry a dB scale, so WirePlumber treats them as
the route's hardware volume: it reads back whatever was last written and
persists it. `HiFi.conf` wound them to 0 in its `DisableSequence` — using the
volume control as an on/off switch — so WirePlumber recorded
`channelVolumes [0.0, 0.0]` in `~/.local/state/wireplumber/default-routes` and
restored silence on every boot afterwards. A diagnostic script ended the same
way, which is how the 0 first got stored.

**Fix.** Route with the routing mixer, the way `SectionVerb` in the same file
already did, and leave the volume controls to the session manager. The Earpiece
device still silences the right amplifier — with no mute kcontrol on this part
(mainline's `aw88261` does not expose one either) the volume control is the only
lever — but it now restores it on the way out. `scripts/fp4-speaker-test` had
the same footgun in its exit trap and now samples and restores instead of
zeroing.

**The lesson, which is not about audio.** Two decode errors of mine pointed at
the wrong layer and cost most of the time: `BSTS`/`SWS` were read at bits 3 and
2 when mainline puts them at 9 and 8, which briefly made a healthy boost
converter look dead. An instrument you have not checked against a known-good
baseline is not evidence. The loopback measurement settled in one pass what six
listening tests had not.

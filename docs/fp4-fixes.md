# Fairphone 4 — defects that are fixed

The closed half of the register. Every entry here was reproduced on a real
handset and then fixed, with the fix verified on the handset. They are kept
rather than deleted because most of them record *why* something was wrong,
and several were wrong for a reason that was not the obvious one.

[`fp4-defects.md`](./fp4-defects.md) holds what is still open.

| id | what | status |
| --- | --- | --- |
| [D1](#d1) | The USB debug gadget never bound | **FIXED** |
| [D2](#d2) | Rotation turns the screen but not touch input | **FIXED** |
| [D3](#d3) | The speaker is silent although playback succeeds | **FIXED** |
| [D4](#d4) | Wi-Fi does not come back after a reboot | **WITHDRAWN** |
| [D13](#d13) | PipeWire exposed no capture source, then stalled on one | **FIXED** |
| [D14](#d14) | The microphone and the speaker could not be used at once | **FIXED** |
| [D16](#d16) | Recordings were made of crackle | **FIXED** |
| [D17](#d17) | Calls had no audio path, because the kernel had no voice DSP | **FIXED** |
| [D18](#d18) | The speakers went silent across reboots, and the amplifiers were fine | **FIXED** |
| [D6](#d6) | The camera had no profile, and a stride bug behind it | **FIXED** |
| [D7](#d7) | The sensors had no daemon | **FIXED** |
| [D24](#d24) | Preview upside down, and the flash was the screen | **FIXED** |
| [D15](#d15) | Notifications came back every boot: first-run never completed | **FIXED** |
| [D9](#d9) | The Keyboard tile called a command that did not exist | **FIXED** |
| [D26](#d26) | The app store could install nothing: a polkit rule prefix typo | **FIXED** |
| [D20](#d20) | NFC: no mainline driver spoke this controller's protocol | **FIXED** |
| [D5](#d5) | Wi-Fi latency tracked the radio's sleep cadence | **RESOLVED** |
| [D12](#d12) | Hyprland drew a "started without start-hyprland" banner | **FIXED** |
| [D25](#d25) | The Docker TUI soft-locked on raw pkexec in a terminal | **FIXED** |
| [D27](#d27) | The on-screen keyboard did not work in the app drawer search | **FIXED** |
| [D10](#d10) | The LPI pinctrl lost a boot race and took all audio with it | **FIXED** |
| [mic-cfg](#mic-port-config) | Capture regressed to silence on a wrong SoundWire port config | **FIXED** |
| [D32](#d32) | A fresh flash had no audio at all: the route helper needed amixer, and nothing set the capture routes | **FIXED** |
| [D11](#d11) | The phone dropped into EDL after reboots: the MDSS core reset hung the SoC on the bootloader's running splash | **FIXED** |
| [D31](#d31) | Some boots had no sound card: the ADSP booted before the PD locator it queries was loaded | **FIXED** |
| [D28](#d28) | The phone never suspended on idle; idle-suspend now works, the depth problem continues as D29 | **CLOSED, see D29** |
| [D30](#d30) | The PIN lock screen trapped a locked-password account after a fresh flash; the image now ships the default PIN `1337` | **FIXED** |

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

---

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

---

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

---

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

---

## D6 — the camera had no profile, and a stride bug behind it {#d6}

**Status: FIXED 2026-09-24, confirmed on the handset.** megapixels no
longer dumps core: it initialises OpenGL ES 3.2, loads the packed-Bayer debayer
shader and runs its exposure loop. The handset's owner confirms the camera works.

The cause was packaging, not code. The stride fix has been in this tree all
along, but `moarchy-device-fp4 0.5.0-1` was built *before* `megapixels` and
`libmegapixels-moarchy` were added to its `depends`, so the handset carried
stock `libmegapixels 0.2.3-1` and asserted on every frame. `libmegapixels-moarchy`
is now built and installed, and the device package's `pkgrel` is bumped to 2 so
that `already_built()` cannot skip it and the dependency actually ships.

`moarchy-device-fp4 0.5.0-1` as installed depends on neither `megapixels` nor
`libmegapixels-moarchy` — those dependencies were added to the PKGBUILD after
that package was built. The handset therefore carries stock `libmegapixels
0.2.3-1`, without the stride patch, and megapixels dies exactly as this entry
describes:

```
No calibration for Rear
mp_camera_capture_buffer: Assertion `bytesused == (width_to_bytes(format, width)
    + width_to_padding(format, width)) * height' failed.
```

The kernel half is not implicated and was re-confirmed: `/dev/video0` reports
`Bytes per Line 5008`, `Size Image 11298048`, and three captured frames each
report `bytesused: 11298048` at ~20 ms intervals. The sensor, the CSI receiver
and the VFE all work. This is a packaging gap, not a driver one.

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

**Resolved 2026-09-24 against Fairphone's own board device tree**
(`kernel/msm-extra/devicetree`, branch `int/15/fp4`,
`qcom/camera/lagoon-camera-sensor-fp4.dtsi`, cloned from
`gerrit-public.fairphone.software`). The vendor DTS labels each sensor in a
comment and pins it to a CSI PHY, which maps straight onto the mainline names:

| vendor node | comment | `csiphy-sd-index` | mainline subdev | role |
| --- | --- | --- | --- | --- |
| `cam-sensor@0` | `48M imx582 ois` | 2 | `imx582 0-001a` / `msm_csiphy2` | **rear MAIN** (OIS + AF actuator) |
| `cam-sensor@1` | `48M imx582 uw` | 0 | `imx582 1-001a` / `msm_csiphy0` | rear ultra-wide |
| `cam-sensor@2` | `imx 576` | 3 | `imx576 2-0010` / `msm_csiphy3` | front |

So the profile above targets **`csiphy0`, which is the ultra-wide** — the
fixed-focus, no-OIS lens. The *main* sensor is `imx582 0-001a` on
`msm_csiphy2`, the one node that carries both an OIS (`qcom,ois@0`) and an
autofocus actuator (`actuator_triple_rear`, `cam_vaf` = L7P @ 3.14 V).
megapixels' v1 format has room for one rear camera, so only one is reachable.

**Tested on the handset 2026-09-24, and reverted — the ultra-wide stays.** The
profile was switched to the main (`msm_csiphy2` / `imx582 0-001a`), pushed, and
confirmed capturing (`megapixels-getframe`: `4000x2256 [pRAA] stride 5008`,
frames received). But the handset's owner reports the result was **visibly worse**,
which has a concrete cause: mainline qcom-camss exposes no actuator/lens subdev
and no V4L2 focus control (verified: media0 lists only the three sensor subdevs,
no focus control anywhere), so the main's VCM lens sits at its *unpowered rest
position* and megapixels cannot step it. The main has a longer focal length and
shallower depth of field, so at rest focus it is soft; the fixed-focus ultra-wide
has a deep depth of field and is sharp with no driving. So the ultra-wide is the
better rear camera **until an autofocus actuator driver exists** — identity was
never the problem, focus is. The profile and the device package (`pkgrel 3`)
now stay on the ultra-wide, and both the config comment and the PKGBUILD record
the finding so it is not re-tried blind. What would actually unlock the main is
an actuator driver (the `actuator_triple_rear` / `qcom,actuator` node in the
vendor DTS) exposed as a V4L2 lens subdev that megapixels can step — a kernel
CAMSS feature, upstream work, not a profile change. See D23 for the rest of what
the vendor DTS gives us and what it does not.

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

---

## D7 — the sensors had no daemon {#d7}

**Status: FIXED 2026-09-24** — two lines of udev rule. All four sensors work.

Both of my earlier diagnoses were wrong and are left below because the wrong
turns are the useful part. libssc was never missing: `libssc 0.4.4-1` is in
Arch's repos, `iio-sensor-proxy 3.9-1` already depends on it, and the daemon is
linked against `libssc.so.2`, `libqmi-glib` and `libprotobuf-c`. I had run
`ldd` against `/usr/libexec/iio-sensor-proxy`, which does not exist — the
binary is `/usr/lib/iio-sensor-proxy` — and read the empty output as proof.

`ssccli`, which libssc ships, reads every sensor on this handset:

```
Accelerometer: X=1.36 Y=0.50 Z=9.82 m/s²    (Z is gravity, phone lying flat)
Light:         5.0 Lux
Proximity:     FAR
Magnetometer:  X=78.2 Y=-37.2 Z=60.3 μT
```

The real cause is upstream's own udev rule. `80-iio-sensor-proxy.rules` says

```
SUBSYSTEM=="misc", KERNEL=="fastrpc-adsp*", ENV{IIO_SENSOR_PROXY_TYPE}+="ssc-light ssc-compass"
```

and every SSC driver gates discovery on finding its own type in that property.
`drv-ssc-accel.c` and `drv-ssc-proximity.c` are compiled in and registered, but
`ssc-accel` and `ssc-proximity` are never advertised, so they return false at
the gate and the daemon asks the sensor core for exactly two data types.

Naming the other two in `81-libssc-fairphone-fp4.rules` — which sorts later,
against a property built with `+=` — is the whole fix:

```
proximity     stk_stk3a5x        accel    lsm6dso
ambient_light tcs3701            compass  Rotation Vector
```

`HasAccelerometer`, `HasAmbientLight` and `HasProximity` all read true. Nothing
about this is specific to the Fairphone 4 and it belongs in upstream's rule.

One more thing that looks like a fault and is not: claiming a sensor needs an
active seat session, so `monitor-sensor` over SSH is correctly refused with
`Not Authorized: Sensor claim not allowed`. Test from the handset's own
session, or the denial is your own.

The first assumption to discard is that these sensors ever appear as kernel IIO
devices. They do not, and cannot: the Fairphone 4's accelerometer, magnetometer,
light and proximity sensors hang off the SSC (Snapdragon Sensor Core, the SLPI),
not off any bus the application processor can see. Checked, and all four agree:

- the mainline device tree for this handset describes no sensor node at all, and
  `sm6350.dtsi` has no SLPI node either — only thermal sensors
- `st_lsm6dsx`, `ak09911`, `tcs3472` and `vl53l0x` are not built in this kernel,
  and would have nothing to bind to if they were
- the i2c buses that exist carry cameras, the two amplifiers, the touch
  controller, the PMIC and the haptics driver — no sensors
- `/sys/bus/iio/devices` holds three PMIC ADCs and three thermal zones

The path that does work runs the other way round. `hexagonrpcd` serves the
sensor firmware tree to the DSP, the sensor core runs the drivers on the SLPI,
and [`libssc`](https://codeberg.org/DylanVanAssche/libssc) talks to that core
over fastrpc and hands the readings to `iio-sensor-proxy`. postmarketOS wires
exactly this up in
[pmaports!5290](https://gitlab.com/postmarketOS/pmaports/-/merge_requests/5290),
whose own comment calls it "iio-sensor-proxy with libssc".

Three of the four pieces are already here and healthy:

```
hexagonrpcd-adsp-sensorspd        active, enabled, serving the device tree root
/usr/share/qcom/.../fp4/sensors   204 files: config/ and a 159-entry registry/
                                  (ak0991x_0.mag* -- the magnetometer is there)
81-libssc-fairphone-fp4.rules     installed, carries the accel mount matrix
/dev/fastrpc-adsp                 present
```

The fourth is missing:

```
ldd /usr/libexec/iio-sensor-proxy | grep -c ssc   ->  0
```

Arch's `iio-sensor-proxy 3.9-1` is built without the SSC backend, so it looks
only for kernel IIO devices, finds none, and every claim fails with
`Not Authorized: Sensor claim not allowed` — which is what megapixels and
`monitor-sensor` both report, and which reads like a permissions problem and is
not one.

Two earlier readings of this entry were wrong and are recorded so they are not
repeated. The daemon's `Tried to open .../temp.json for writing` is
informational, not a failure: the registry directory is `fastrpc:fastrpc` mode
775 and *is* writable by the daemon. And `Could not open sns_bring_to_ear.so`
concerns one optional gesture sensor, not the sensor core.

**What closing this needs:** package `libssc`, and build `iio-sensor-proxy`
against it the way `libmegapixels-moarchy` already forks a package for one
patch. No kernel or device-tree change is implicated.

--- | --- |
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

---

## D24 — the preview was upside down and the flash was the screen {#d24}

**Status: FIXED 2026-09-24** — `b41f964`, reported by the handset's owner once
[D6](./fp4-fixes.md#d6) made the camera usable at all.

Both cameras previewed 180 degrees out. The rotations in the megapixels profile
were inferred from sargo's — 90 rear, 270 front — and that comment said as much.
They are 270 and 90 here, measured by looking at the preview. Mirror on the
front is unchanged.

The flash lit the whole screen white on both cameras, for two separate reasons.

The rear profile declared no `FlashPath`, so libmegapixels had no LED to reach
for. It now names `/sys/class/leds/white:flash`. The front keeps
`FlashDisplay`, because there is no LED on that side of the phone and the
screen is the only flash it can have — `pine64,pinephone.conf` does the same
for its front camera, so a white screen there is correct rather than a bug.

With the path set it still could not fire:

```
Could not open /sys/class/leds/white:flash/flash_strobe: Permission denied
```

`73-moarchy-torch.rules` made only `brightness` group-writable, which is all
the Torch tile needs. A camera strobes the LED for the length of an exposure
through the V4L2 flash attributes and stops at the first one it cannot open.
The rule now covers `flash_brightness`, `flash_strobe` and `flash_timeout` too,
each guarded because those attributes exist only on LEDs the kernel registers
as V4L2 flash devices, and written one per attribute because udev reads `$` as
the start of its own substitution.

---

## D20 — NFC: no mainline driver spoke this controller's protocol {#d20}

**Status: FIXED 2026-09-24** — new kernel driver, prepared as an upstream RFC
(`upstream/nfc-st21nfcd/`). NFC reads work; the moarchy.nfc app shows the tag.

**Superseded upstream 2026-09-29.** The standalone `st21nfcd` driver was a means,
not the goal: mainline already had `st-nci`, and Kristian Brox posted a v4 series
adding a raw-NCI (`st,st21nfcd`) path to it. Bringing that v4 up on the FP4
surfaced three bugs: the `0x90`->MIFARE mapping, a reference-clock restart on
power-up (the controller wedges after a few poll on/off cycles otherwise, the
same wedge Luca Weiss reported on FP5), and treating the idle `0x7e` read as
no-data. Those three fixes were sent to Kristian's v4 thread on LKML
([`20260902-fp5-st21nfcd-v4`](https://lore.kernel.org/all/20260902-fp5-st21nfcd-v4-v4-0-ded2f1c501be@proton.me/))
and mirrored, with the FP4 `nfc@8` node, as
[sm6350-mainline/linux#14](https://github.com/sm6350-mainline/linux/pull/14).
Landing st-nci upstream retires our standalone driver entirely, so the permanent
path is that PR, not carrying `upstream/nfc-st21nfcd/` forward.

The wiki lists NFC as `N` and names an ST21NFCD. The starting assumption here
was that mainline already had the driver and only a device-tree node was
missing. That was wrong in an instructive way: mainline's ST NFC drivers are
`st21nfca` (HCI) and `st-nci` (NDLC-framed NCI), and the ST21NFCD speaks
**plain NCI over I2C** with no link layer. Given NDLC frames it answers its
reset notification and then waits for a command that never parses — so the
existing drivers bind and the controller stays mute.

The controller itself was never the problem. Pointed at the generic nxp-nci
transport as a diagnostic, it completed NCI 2.0 init and ran RF discovery, which
proved the fault was only the framing layer. The fix is a small dedicated
driver, `st21nfcd`, that does plain NCI over I2C — send a frame as an I2C
write, read header-then-payload on the interrupt.

Two values were reverse-engineered from this handset because ST publishes no
datasheet: `0x7e`, returned on an idle read, and `0x90`, the proprietary RF
protocol number the controller reports for MIFARE Classic (the NCI core drops
it as unmappable without a `get_rfprotocol` hook, which is why a card was
activated and then discarded). Both are commented as observed, not documented.

On the FP4 the node lives on i2c0 at 0x08 (the same controller as the two
speaker amplifiers), IRQ on GPIO 9, reset on GPIO 6, reference clock from RPMh
LN_BB_CLK3. Tested: a MIFARE Classic 4K card reads with its SENS_RES/SEL_RES
and UID.

The whole userland side — `bin/moarchy-nfc`, the `moarchy.nfc` app, and a
data-table card database (NXP AN10833 + ISO 7816-6) — is separate from the
kernel work and shipped in this repo. Still open above the driver: active
probing (GET_VERSION/ATS/NDEF) for exact tag models, which a lookup table
cannot give.

---

## D15 — notifications came back every boot; first-run never completed {#d15}

**Status: FIXED 2026-09-24** — via omarchy-config `port-4x.patch`, verified on
the handset.

Dismissed notifications -- the welcome toast, the Wi-Fi and update hints -- came
back on every boot. They were not persisted notifications being re-delivered;
they were re-emitted, because omarchy's first-run provisioning ran again every
login instead of once.

`omarchy-provision-first-run` guards on a done-marker
(`~/.local/state/omarchy/done/first-run-user`) and only writes it if every step
succeeds. One step failed every time:

```
Failed: enable user systemd units (exit code: 1)
One or more first-run steps failed; first-run will retry next login
```

`install/user/first-run/enable-user-units.sh` enables six user units in a
single `systemctl --user enable --now` under `set -euo pipefail`. The phone
ships **none** of them -- `bt-agent`, `omarchy-recover-internal-monitor`,
`omarchy-sleep-lock`, `omarchy-migrate-notify`, `omarchy-fcitx5`,
`omarchy-crash-watch` are all desktop units -- so the command aborts on the
first, the step exits 1, first-run never marks done, and the notification steps
that run just before it fire again on the next login.

**Fix.** Enable each unit only if it is installed, in a loop, so a build that
ships a subset (here, none) completes cleanly. After it, first-run runs once,
marks done, and every later boot short-circuits at the marker check -- verified:
a second run prints "First-run already complete", the marker sits on persistent
storage, and nothing clears it at boot. The notifications show once on the next
fresh first-run, then stop.

This is really an upstream omarchy robustness bug -- the combined enable aborts
on any partial install -- and the same fix is worth offering there.

---

## D9 — the Keyboard tile called a command that did not exist {#d9}

**Status: FIXED** — the binary now ships; verified on the handset 2026-09-24,
not authored here.

Reported 2026-09-23: the Keyboard quick tile ran `moarchy-toggle-keyboard`,
which was not on the image, so the tile failed silently
(`Quickshell.execDetached` reports nothing when a command is missing). The
report suggested either deleting the tile or adding a verb to the keyboard.

The second happened, in the `moarchy` package itself: `moarchy 0.5.0-6` ships
`bin/moarchy-toggle-keyboard`, which drives the on-screen keyboard over DBus on
`sm.puri.OSK0` -- the same interface Phosh uses -- reading the `Visible`
property and flipping it. Verified: `Visible` goes false to true to false as the
command runs, and `/etc/profile.d/zz-moarchy.sh` puts `/usr/lib/moarchy/bin` on
the session PATH so the shell finds the bare name the tile calls.

So the tile works now. Kept here rather than dropped because the diagnosis --
and the wider point, that every `cmdOn`/`cmdOff`/`read` in `Widgets.js` should
be checked against a real binary because the shell never reports a missing one
-- is worth keeping. That audit was run on 2026-09-24: all five commands
(`moarchy-toggle-keyboard`, `-location`, `-nightlight`, `omarchy-shell`,
`omarchy-toggle-idle`) resolve.

---

## D26 — the app store could install nothing: a polkit rule prefix typo {#d26}

**Status: FIXED 2026-09-24** — one word in `default/polkit/49-moarchy-store.rules`,
verified on the handset.

Installing any app from the store froze the phone on a password screen the
on-screen keyboard could not fill (the second report of the pkexec soft-lock,
after [D25](#d25)). Unlike Docker, the store is built to avoid
that: it ships an `org.moarchy.Store.policy` action pointing pkexec at its
curated helper, and a rule that grants that action to the `wheel` group with no
password. The rule was correct in every respect but one:

```
action.id === "moarchy.store.manage"        // the rule (before)
<action id="org.moarchy.store.manage">      // the .policy (actual id)
```

The rule matched the action id without its `org.` vendor prefix, so it never
fired, and every install fell through to the action's `auth_self_keep` default
-- a password dialog. On a phone whose account has no usable password to type,
that is an unrecoverable stick.

**Fix:** match `org.moarchy.store.manage`, the id the `.policy` actually
declares. Verified: `pkcheck --action-id org.moarchy.store.manage` now returns
`polkit.result=yes`, and `pkexec` of the store helper runs as root with no
dialog. App installation works without a prompt.

The Docker TUI ([D25](#d25)) is a different case -- it calls
`pkexec` on a program with no custom action, so it always uses the generic
`org.freedesktop.policykit.exec` and still prompts. That one needs a different
fix and is left open.

## D5 — Wi-Fi latency tracked the radio's sleep cadence {#d5}

**Status: RESOLVED 2026-09-28** - power-save disabled globally (see
*Resolution* below). Found 2026-09-22 while disproving D4.
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

### Resolution

Power-save is now disabled globally, because on this handset the awake-but-idle
window it optimises is short - the system idle path is s2idle (D28), which
suspends the radio outright - so the DTIM-cadence latency it buys costs
interactive feel for almost no real battery return. `moarchy-device-fp4` ships
`/usr/lib/NetworkManager/conf.d/90-moarchy-fp4-wifi-powersave.conf` with
`[connection] wifi.powersave=2`, a conf.d default rather than a per-connection
key so it holds for every network the user ever joins. `/etc` is left free for
an operator override.

Verified 2026-09-28: with the drop-in in place, power-save set back **on** and
the connection fully re-activated (`nmcli con down/up`) comes up **off** driven
by the default alone - i.e. it persists across a reconnect, not just a manual
`iw` for one session. Re-measured host->phone with it off: min **3.6** / avg
**45.6** / max **108.6** ms, 0% loss - the beacon-cadence row above, versus the
DTIM-cadence avg 122 ms it replaces.

This only demotes the station from DTIM to beacon cadence; it does not reach
the ~5 ms the link is capable of continuously awake. **Why beacon-cadence
wakeups persist even with power-save off** is driver/firmware power management
below what `iw` controls, and is the remaining lever if this ever needs to go
further - worth comparing against an AP with a DTIM of 1 first, since DTIM
period is the access point's setting, not the station's.

---

## D12 — Hyprland drew a "started without start-hyprland" banner {#d12}

**Status: FIXED 2026-09-26 (config option), confirmed 2026-09-28.** Confirmed on
the handset (moarchy 0.5.0-13): `hyprctl getoption misc:disable_watchdog_warning`
returns `set: true` at runtime, which is the option that suppresses the banner.
(A `grim` screenshot was attempted as a visual double-check but blocked, most
likely on a locked/blanked screen; the runtime option value is the authoritative
confirmation.) Hyprland
0.56 exposes `misc:disable_watchdog_warning` -- named for the watchdog fd
start-hyprland passes, but its own description is literally "whether to disable
the warning about not using start-hyprland" (confirmed via `hyprctl
descriptions`). Set it in `config/hypr/input.lua` (moarchy pkgrel 12). This turns
the banner off **without** adopting start-hyprland, which the note below rightly
flags as risky: it is a 264 KB binary that manages an instance and does more than
exec, so swapping it into `zz-moarchy.sh` unexamined could boot the phone to no
UI. The session still execs `Hyprland -c ...` as before; only the nag is
silenced. **Confirm:** the red banner across the top is gone once the updated
`input.lua` is deployed and Hyprland reloads (a `hyprctl reload`, or the package
deploy). `hyprctl keyword` cannot set it live here -- under the `.lua` config the
legacy keyword parser is refused (same reason moarchy-screen uses `hl.*` eval),
and there is no `hl.keyword` in this API, so it lands via the config, not a
runtime poke.

**Status (historical): OPEN**, cosmetic, and not device-specific.

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

## D25 — the Docker TUI soft-locked: raw pkexec in a terminal {#d25}

**Status: FIX VERIFIED 2026-09-28 (polkit rule).** A scoped polkit
rule (`default/polkit/50-moarchy-docker.rules`, moarchy pkgrel 11) auto-authorizes
the Docker app's `pkexec` for `wheel`, so no unanswerable password screen appears
-- the same locked-password cause and the same fix shape as the app store
([D26](./fp4-fixes.md#d26)); it is no wider than the `NOPASSWD` sudo the user
already holds. **Verified on the handset 2026-09-28 without installing docker**,
via `pkcheck` as root against the exact command the launcher runs: the deployed
launcher does `pkexec /usr/bin/env TERM=... lazydocker`, so the `command_line`
polkit sees contains the `lazydocker` token the rule matches. `pkcheck
--action-id org.freedesktop.policykit.exec --detail command_line "/usr/bin/env
TERM=xterm-256color lazydocker"` for a `wheel` process returns
`polkit.result=yes` (rc=0, no prompt); a non-lazydocker command returns
`auth_admin` (rc=2), so the rule is correctly scoped and does not blanket-grant
pkexec. The earlier concern (that the wrapper's command might lack the
`lazydocker` token, the D26 failure mode) is thus ruled out. The broader alternative -- grant
`org.freedesktop.policykit.exec` for `wheel` unconditionally -- fixes the whole
class of terminal-pkexec soft-lock on this un-answerable device and is still
bounded by that sudo; it's a security-posture call left to the owner.

**Correction to the note below:** a graphical polkit agent IS present
(`config/hypr/autostart.lua` starts `polkit-gnome-authentication-agent-1`); the
real trap is not a missing agent but that the dialog it raises cannot be answered
(locked password, no OSK for it) and the Docker terminal blocks there.

**Status (historical): OPEN**, lower priority since the app store -- the case that mattered --
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

## D27 — the on-screen keyboard did not work in the app drawer search {#d27}

**Status: FIXED 2026-09-27, confirmed on the handset.** Real root cause: the app
drawer is the shell's ONLY text field on a **layer surface** (a `PanelWindow`);
every field that works -- Wi-Fi passphrase, Mail, Files, Contacts -- is a regular
`AppWindow`. When open, the drawer holds `WlrKeyboardFocus.Exclusive` AND its
input region is the whole screen (`mask` is null), and an Exclusive-keyboard-focus
layer surface makes Hyprland route **all touch** to it. So the on-screen keyboard,
though it sits on a higher layer, received **no `wl_touch` at all** while the
drawer was open -- no key even highlighted, and the omarchy/symbol keys were dead
too. Keys went nowhere because the OSK never saw the taps, not because of any
text-input focus problem.

The earlier 2026-09-26 diagnosis (kept below) was **wrong**: it blamed the field
being a Controls widget and swapped it for a plain `TextInput`. But
`qs.Ui.TextField` was already a plain `TextInput`, so that changed nothing --
proven by a `WAYLAND_DEBUG` trace of `moarchy-keyboard` (the OSK got zero
`wl_touch` while the drawer was open) and by the user's observation that keys
highlight in apps but are completely dead in the drawer. That reframed it from
"focus routing" to "touch never arrives."

**Fix:** the drawer's `keyboardFocus` (AppDrawer.qml) is now `OnDemand` instead of
`Exclusive`. OnDemand takes keyboard focus on tap -- enough to focus the search
field -- without grabbing pointer/touch away from the OSK. Verified on the FP4
2026-09-27: the OSK types into the search and the grid filters. The
close-drag-to-dismiss (the reason `Exclusive` was originally chosen) **still works
under OnDemand** -- verified open -> drag-down -> closed. moarchy pkgrel bumped.

Minor remaining nit (by design): raising the OSK via the bottom keyboard *icon*
does not focus the search field (that icon is a generic OSK-raise); tapping the
search field directly both focuses it and raises the OSK, which is the intended
gesture.

The original open-investigation notes are kept below for the record.

**Status (historical): OPEN**, reported 2026-09-24. Under investigation; the exact symptom
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

## D10 — the LPI pinctrl loses a boot race and takes all audio with it {#d10}

**Status: FIXED 2026-09-26 (`deferred_probe_timeout=60`), verified on hardware 2026-09-29.** Root cause pinned:
the LPASS pinctrl (`33c0000.pinctrl`) can only probe once the ADSP has
registered its clock services (~16.5 s+), and on a slow boot that slips past the
kernel's deferred-probe window -- `CONFIG_DRIVER_DEFERRED_PROBE_TIMEOUT=10`
(config:1662), 10 s. When it does, deferred probe gives up, the pinctrl and every
consumer (both macros, both SoundWire controllers, the sound card) never probe,
and audio is silently gone for the boot, not retried. Raising the window is the
correct lever -- deferred probe already waits for the ADSP; it is just cut off
early, and a longer window costs nothing on a normal boot (it only delays a
genuinely unprobeable device).

**Fix:** `deferred_probe_timeout=60` added to the kernel cmdline in
`image/boot/android-bootimg.sh` (boot.img only, no kernel recompile; shared with
sargo, harmless there). If ABL turns out to strip the param (only `console=` is
known-stripped), the fallback is bumping `CONFIG_DRIVER_DEFERRED_PROBE_TIMEOUT`
and rebuilding the kernel. **Reboot test** (~10-15 cold boots, the race is
~1-in-8): confirm `/proc/cmdline` carries the param, `/proc/asound/cards` is
non-empty every boot, and `33c0000.pinctrl`/`sound` never appear in
`/sys/kernel/debug/devices_deferred`.

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



### Verified 2026-09-29

Across every boot that completed in a reboot loop on the handset, the card came
up: `/proc/asound/cards` non-empty, nothing audio-related in
`/sys/kernel/debug/devices_deferred`, and `/proc/cmdline` still carrying
`deferred_probe_timeout=60` (ABL does not strip it). Four consecutive reboots,
4/4 clean. The 60 s window clears the ~27 s worst-case ADSP timing by a wide
margin, so the race cannot expire the way it did at the 10 s default. (A longer
stress loop hit the phone changing DHCP address and a scan-range bug in the test
harness, not any audio regression.)

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

## Capture regressed on the SoundWire port config, and was re-fixed {#mic-port-config}

**Status: FIXED 2026-10-06, verified on hardware (acoustic loopback + voice +
soundrecorder).** During the fp4-dev-all integration the built-in mic silently
regressed to digital silence. The cause was the SoundWire TX port config in the
DT, not the UCM: the per-direction port counts had been raised to the
controllers' totals (`qcom,din-ports`/`qcom,dout-ports` RX `0/5` -> `1/6`, TX
`5/0` -> `6/1`), the per-port arrays widened to match, and `tx-port-mapping`
set to `<1 2 3 4>`. That was done to silence a qcom-soundwire warning:

```
qcom-soundwire 3210000.soundwire: din-ports (0) mismatch with controller (1)
```

**The warning is cosmetic and expected here.** The smaller per-direction counts
describe this board's real capture routing; raising them to the controller
totals stops capture entirely. It is a nasty failure to spot because the card
still registers and wcd938x still binds over SoundWire, so the probe log looks
clean -- but the ADC's data then lands on ports the TX macro decimators never
read. The analogue front end powers up correctly (codec regmap during capture:
`ANA_MICB1` 0x22->0x62, `ANA_CLK_CTL` 0x00->0x18) and `arecord` runs to
completion, yet every route delivers a short DC transient and then exact zeros.
Only a capture against a stimulus reveals it.

**Fix:** restore the per-direction counts/arrays that capture on hardware and set
`tx-port-mapping = <2 3 4 5>`. Verified: handset AMIC1 reaches userspace via
`TX_CODEC_DMA_TX_3`, a speaker-tone acoustic loopback drives a per-channel RMS
envelope from a ~85 quiet floor to ~8000-30000 under the tone and back. The
capture route is both decimators from ADC0 (`ucm-HiFi.conf`), so the mono mic
lands on both channels. (Correction 2026-10-08: that route also needs
`ADC1_MIXER Switch`, and on this card it is applied by `fp4-audio-route`, not by
the UCM file -- see D32.) The same mistake had reached upstream PR #11 and is
corrected there too (follow-up commit, the controller-count warning documented
as expected). Lesson: do not "fix" the SoundWire port-count warning by matching
the controller totals; the DT counts are load-bearing.

---

## D32 -- a fresh flash had no audio at all {#d32}

**Status: FIXED 2026-10-08, verified on hardware from a clean flash and a clean
mixer state (PipeWire record + playback, and direct ALSA).** Found by the first
full flash of the sm6350-7.2.y image: the card registered, but PipeWire exposed
no sink and no source --

```
wireplumber: s-monitors: Failed to create ALSA node alsa_input.platform-sound.capture.1.0:
             Object activation aborted: PipeWire proxy destroyed
fp4-audio-route: sound card did not appear
```

Three faults, stacked, every one of them hidden on the development phones:

1. **`moarchy-device-fp4` did not depend on `alsa-utils`.** `fp4-audio-route`
   reads and sets every route with `amixer`; without it `get()` returns nothing,
   the helper decides the card is not up and gives up after 30 s, no route is
   ever armed, the PCMs cannot be opened and WirePlumber's node activation
   aborts. Fix: `depends+=(alsa-utils)`.
2. **Nothing set the codec-side capture routing.** `TX DEC0/1 MUX`,
   `TX SMIC MUX0/1` and `TX_AIF1_CAP Mixer DEC0/1` were only in the UCM
   `EnableSequence`, and UCM never runs on this card (ACP offers it no profile,
   D13). `fp4-audio-route` armed only the DSP-side routes. With the codec routes
   off, a stream opens, reports RUNNING and delivers about 7000 frames, then
   nothing. Fix: the helper now arms the codec routes and the calibrated gains.
3. **The capture route itself was incomplete.** Both decimators on ADC0 (the
   route the README and `ucm-HiFi.conf` describe) is not enough on a clean mixer
   state: `ADC1_MIXER Switch` is what puts the ADC on the SoundWire TX port,
   and without it every capture fails with `read error: Input/output error`.
   Fix: added to the helper and to the UCM `Mic` sequence (verified via
   `alsaucm` from a clean state).

Two boot-ordering faults surfaced in the reboot loop that verified the above:

4. **WirePlumber never retries a node it failed to create.** If it reaches
   the card before the routes are armed (one boot in four in the loop), the
   card has no sink and no source for the whole session. Fix: once the routes
   are armed, the helper checks for the card's PipeWire source and, if it is
   missing, restarts WirePlumber -- once per session, guarded by a marker in
   the runtime dir, since the helper is PartOf wireplumber and is restarted
   with it. Verified by forcing the race (routes cleared, WirePlumber
   restarted): nodes failed, the helper restarted WirePlumber once, 1 sink and
   1 source came up, capture followed a stimulus.
5. **Missing call-audio controls blocked the media routes.** The five voice
   controls (`VoiceMMode1 ...`, `CS-Voice ...`, `VoiceMMode1 TX Topology`)
   belong to the DSP's voice services, which can register later than the media
   ones or not at all (absent after a D31 ADSP restart). They sat in the same
   list as the mic and speaker routes, so one absent voice control made the
   helper report "sound card did not appear" for its full 30 s and arm nothing.
   Fix: the voice routes are a separate, best-effort list -- skipped when
   absent, retried on every later event -- and only the media routes gate.

**Why it hid:** development phones had `alsa-utils` installed by hand, and with
it `alsa-restore.service`, which at every boot replayed mixer state saved from
manual test sessions -- state that happened to contain all of the above,
including `ADC1_MIXER Switch` left on by earlier route experiments. So the
mic "worked from a cold boot with no manual step" on exactly the phones it was
tested on, and could not have worked on any fresh install. The lesson: verify
audio on a **fresh flash with a clean mixer state**, not on a phone that has
been hand-tested.

## D11 — the phone drops into EDL after repeated reboots {#d11}

**Long form:** [`fp4-d11-mdss-reset.md`](./fp4-d11-mdss-reset.md) -- root cause
(MDSS core reset on the live splash), the capture method and the tools in
`scripts/d11/`.

**Status: FIXED 2026-10-10.** Root cause: the MDSS core reset in
`msm_mdss_init()` hangs the SoC when it meets the bootloader's running splash.
Fixed by kernel package patch `0008` (stop the CTL-active INTF, gate the MDP/AXI
clocks, then reset; pkgrel 12, `fp4` @ `9e118c6`), verified 20/20 + 10/10 boots on
the CI-built image (50 clean boots across the fix's test kernels before that).
Upstream as draft [sm6350-mainline/linux#16](https://github.com/sm6350-mainline/linux/pull/16);
drop `0008` when the pin includes it. The history below is kept as it was.

**Earlier status (superseded): OPEN as a cause, RECOVERABLE as a symptom.** Leading theory (A/B retry exhaustion) ruled out 2026-09-24. Seen three times on
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

### Findings 2026-10-09 (sm6350-7.2.y kernel)

Three ramdumps in about 13 reboots in one session, all from a plain
`systemctl reboot`. What is now measured rather than assumed:

- **It IS a ramdump, not plain EDL.** Read on hardware: the device's Sahara
  `HELLO` reports `mode=2 (MEMORY_DEBUG)` and it serves a memory table (OCIMEM,
  AOP RAM, PMIC PON history, reset status, and all 6 GiB of DDR in three 2 GiB
  regions). So the earlier "plain EDL, never a ramdump" above is wrong for these
  episodes: something crashed, and RAM is preserved.
- **A watchdog bite produces exactly this.** Opening `/dev/watchdog0` and not
  feeding it gave `05c6:900e` at 30 s. The FP4's `qcom,kpss-wdt` maxes out at
  ~31 s (20-bit counter, 32 kHz clock), so systemd-shutdown's 10 min reboot
  watchdog request fails (`Invalid argument`) and runs at the 30 s default.
- **Linux cannot turn the ramdump mode off.** `qcom_scm.download_mode` reads
  `off`, writing `off` succeeds silently, and a bite still gives `900e`: the DT
  has no `qcom,dload-mode` register and the SCM call has no effect.
- **The reboot watchdog is not the (only) trigger.** With
  `RebootWatchdogSec=off` (verified: the previous shutdown never armed it) the
  second reboot still ended in `900e`. The change was reverted: with remote
  recovery available (below), a bitten hang is recoverable and an unbitten one
  is not.
- **Timing from the host's USB log:** a normal reboot reaches the next boot's
  USB gadget 31.6 s after the old one disappears; the bad one showed `900e`
  24.2 s after (a crash surfaces as `900e` within ~3 s), i.e. ~21 s after the
  gadget dropped -- late in shutdown or early in the next boot, where the
  journal cannot see.
- **The crashing boot's state cannot be read from the journal** (journald dies
  at "Sending SIGTERM to remaining processes"; good and bad shutdown logs end
  identically). Hence ramoops, now applied: kernel package pkgrel 11 enables
  `PSTORE_RAM/_CONSOLE/_PMSG`; after the next episode the crashed kernel's
  console tail is in `/sys/fs/pstore/`.
- **The region is upstream's, not ours.** The 7.2.y `sm6350.dtsi` already
  reserves `ramoops@ffc00000` (1 MiB, `no-map`, console 256 KiB, pmsg 128 KiB,
  ecc 16); only the config was missing. Pkgrel 11 as first built also carried a
  `ramoops@b0000000` node: on the handset the `ffc00000` instance registered as
  the pstore backend and ours failed probe with `-22` ("already initialized").
  The patch is dropped; the config switches alone are the fix.
- **First captured crash (2026-10-09, 20-boot loop):** 3 ramdumps in a row
  during boot 3, each ~24 s after reset with no USB gadget in between (an
  early-boot crash loop; `edl-reset` recovered it on the 5th try). RAM survives
  the bite, so the ramoops region was read straight out of the ramdump over
  Sahara (`MEMORY_READ_64` of `0xffc00000`, 1 MiB). The crashed kernel's console
  ends at **0.71 s**, after `arm-smmu 3d40000.iommu` (the Adreno SMMU) probes
  and `3d00000.gpu`/`3d6a000.gmu` join iommu groups: no panic, no oops, then
  silence until the watchdog bites, i.e. a hard bus hang. On a good boot the
  next lines (0.725 s) are the display takeover from the bootloader's
  framebuffer: MDSS/DSI/panel probe, and **every** boot in the journal (25 of
  25) logs `dsi_pll_10nm_vco_prepare: DSI PLL(0) lock failed` plus a
  `dsi0_phy_pll_out_dsiclk already disabled` clk warning there. Lead: the
  crash is the bad side of that DSI PLL / display-handover path.
- **Second capture, same point (2026-10-09, 20-boot loop, 1 ramdump at boot
  18):** the console again ends on exactly `3d6a000.gmu: Adding to iommu group
  12` (0.766 s). Two of two. On a good boot the next lines are MDSS populating
  its children (the `Fixed dependency cycle(s)` lines for the DPU, DSI and
  panel), then `dsi_phy_driver_probe` registers its clock provider, the
  orphaned `disp_cc` byte/pixel clocks (left running by the bootloader's
  splash) get reparented onto the DSI PLL, the PLL fails to lock and
  `clk_core_disable` WARNs `dsi0_phy_pll_out_dsiclk already disabled`. The
  crashed kernels never printed the populate lines, so the hang is in the
  MDSS probe before `of_platform_populate` (clock/GDSC/interconnect bring-up
  and the first MDSS register reads) or on another CPU in the same window.
- **Third capture (run 4, boot 2): same last line again; run 4 ended at 6 ramdumps in 24 boots, so 8 of 8 captures total end on the `gmu` line.** The printk
  ring (`__log_buf`, phys `0xa3d72e80`, 128 KiB on 7.2.0-11) was also read
  from the ramdump: it holds *less* than the ramoops console (it ends at the
  `gpu` line), because it is cached memory and a watchdog bite does not write
  the caches back, while ramoops maps its region uncached. So ramoops is the
  faithful record and nothing was logged after the `gmu` line: the whole SoC
  froze there (consistent with a wedged interconnect stalling every CPU).
  Prime suspect: `mdss_probe` -> `msm_mdss_init` -> `msm_mdss_reset()` asserts
  `DISP_CC_MDSS_CORE_BCR` as its very first action, while the bootloader's
  splash is still scanning out (simpledrm still owns the framebuffer); a bus
  master reset mid-transfer can hang the NoC. Unproven: next step is a boot
  with `dyndbg` on `drivers/base/dd.c` (per-device probe start) and
  `msm_mdss.c`, plus `ignore_loglevel`, to see which probe is in flight.
- **Pinned to the MDSS probe (2026-10-09, dyndbg boot).** Same kernel, cmdline
  plus `ignore_loglevel dyndbg="file drivers/base/dd.c +p; file
  drivers/gpu/drm/msm/msm_mdss.c +p; file drivers/iommu/arm/arm-smmu/arm-smmu.c
  +p"` (only the boot.img cmdline field patched). 3 ramdumps in the first few
  boots, all three ending on exactly
  `ae00000.display-subsystem: really_probe: probing driver msm-mdss with device`
  -- after the GPU SMMU and `adreno` have both bound -- and none printing
  `msm_mdss_init`'s `mapped mdss address space`, which a good boot prints next.
  Between those two points `msm_mdss_init` does only `msm_mdss_reset()`
  (assert `DISP_CC_MDSS_CORE_BCR`, `msleep(20)`, deassert), a table lookup and
  an ioremap, so the freeze is in the MDSS core reset, taken while the
  bootloader's splash is still scanning out. (Journal timestamps cannot resolve
  the 20 ms hold here: journald reads kmsg late, in batches.)
- **Deciding test, prepared:** the same boot.img with `resets` deleted from
  `/soc@0/display-subsystem@ae00000` in the appended DTB (one property; the
  repack of the unmodified DTB is byte-identical to the flashed image), which
  makes `msm_mdss_reset()` a no-op. Prediction: zero ramdumps over a loop that
  hit ~1 in 2-4 boots on the dyndbg kernel.
- **RESULT: 20 of 20 boots clean, 0 ramdumps (2026-10-09).** With the reset
  present the same kernel+cmdline crashed 3 times in its first ~5 boots (and the
  plain cmdline 6 in 24, ~1 in 4); 20 clean in a row is ~0.3% likely at 1 in 4.
  **D11 root cause: the MDSS core reset in `msm_mdss_init()` freezes the SoC
  when it lands on the bootloader's live splash scanout.** But the reset is
  load-bearing: without it the panel never comes up (backlight on, nothing
  drawn; `dsi_cmds2buf_tx: cmd dma tx failed ... ret=-110`, `panel-himax-hx83112a
  ... sending dcs data b9 83 11 2a failed: -110`). Side effect worth noting: the
  `DSI PLL(0) lock failed` + `already disabled` WARN seen on every normal boot
  is absent without the reset. So the fix is not "drop the reset" but "make the
  reset safe": quiesce the scanout (stop the INTF timing engine / CTL so no
  fetch is in flight) before asserting `DISP_CC_MDSS_CORE_BCR`, or otherwise get
  the splash out of the way first. Context: the reset came from Bjorn Andersson's
  2022 "drm/msm/dpu: Issue MDSS reset during initialization"; a 2025 MSM8939
  thread notes a live splash used to be masked by `DRM_MSM=m` because pre-6.17
  the MDSS power domain dropped before the module loaded. This kernel has
  `DRM_MSM=y` on 7.2. The phone is back on the stable boot.img (reset in place),
  so D11 still occurs on it at the old rate.

**(Superseded, see the status at the top.)** The fix (stop the CTL-active INTF, gate
the MDP/AXI clocks, then reset) ran 20 of 20 boots clean, and a variant that
also disabled the DSI host 30 of 30; see [`fp4-d11-mdss-reset.md`](./fp4-d11-mdss-reset.md#fix).
- **Warm-reboot pstore is unreliable here:** after a *clean* reboot,
  `console-ramoops-0` came back with `ECC: 873 unrecoverable blocks`, so
  something between kernels (bootloader) scribbles on `0xffc00000`. Reading
  the region from the ramdump *before* `edl-reset` is the reliable capture.

### Instrumentation to diagnose it (prepared 2026-09-26, applied 2026-10-09 as kernel pkgrel 11)

The reason the cause stays unidentified is that **nothing captures the moment**:
`/sys/fs/pstore/` is empty because the RAM backend is off. In the vendored kernel
config (`pkgbuilds/linux-moarchy-sm6350/config`) `CONFIG_PSTORE=y` but
`CONFIG_PSTORE_RAM`, `_CONSOLE` and `_PMSG` are all **not set**, and neither the
mainline `sm7225-fairphone-fp4.dts` nor `sm6350.dtsi` reserves a ramoops region.
Enabling ramoops would let the *next* EDL episode leave the previous boot's
console/panic tail in `/sys/fs/pstore/`.

Two ready ways to enable it (both need a kernel rebuild):

1. **Config + DT node (cleaner):** set `CONFIG_PSTORE_RAM=y`, `_CONSOLE=y`,
   `_PMSG=y` (this `select`s `REED_SOLOMON*` via olddefconfig -- re-vendor the
   resolved config to keep `prepare()`'s diff clean), and add a ramoops
   reserved-memory node to the fp4 dts. **The address matters: `0xb0000000` is
   NOT usable (see the hardware test below), despite showing as System RAM in
   `/proc/iomem`.**
2. **Config + cmdline (no DT, fits the no-kernel-patch stance):** the same config
   change, plus `memmap=0x100000$<addr> ramoops.mem_address=<addr>
   ramoops.mem_size=0x100000 ramoops.console_size=0x40000 ramoops.pmsg_size=0x40000
   ramoops.record_size=0x20000` on the cmdline (image/boot/android-bootimg.sh).

**Tested on hardware 2026-09-30 (INCONCLUSIVE -- boot did not come up, cause not
yet isolated).** Built the shipped commit `16337c9dd` with
`PSTORE_RAM/_CONSOLE/_PMSG=y` (`kernelrelease` matches shipped, so on-disk modules
load) plus a `ramoops@b0000000` DT node (1 MiB, no `no-map`), assembled a
transient `boot.img` (`~/Personal/linux-ramoops-d11/`), and `fastboot boot`ed it
twice. Neither came up: the first boot hung, the retry dropped into EDL ramdump
(`05c6:900e`, recovered with `scripts/edl-reset.py`).

**Do not over-read this.** Two *different* failure modes from one image (hang,
then ramdump) is the signature of the known flaky transient boot (D26 spends a
slot retry), not of a deterministic memory fault. And the address is almost
certainly fine: the FP4 **downstream** DT (`lagoon.dtsi` `reserved_memory`) marks
every protected carveout as an explicit `no-map removed-dma-pool` (hyp, xbl,
smem, all the pil_* firmware regions, `removed_region@c0000000`, the display
regions up to `dfps_data@a2300000+0x100000`), and **nothing reserves
`0xb0000000`** -- it is plain HLOS System RAM in both the downstream map and
mainline `/proc/iomem`. So the 2026-09-26 "verified free" note still looks right;
the ramoops node did not obviously crash anything.

**Next (isolation, not a new address):** re-boot the SAME kernel with the ramoops
node REMOVED. If it comes up cleanly, the two failures were flaky transient boots
and `0xb0000000` is usable (just retry the ramoops boot until it takes). If it
also fails, the fault is the `PSTORE_RAM` build or the transient method, not the
address. The build and the transient-boot workflow are otherwise proven.

**Why it is documented and not applied:** the config change requires a kernel
rebuild this environment can't verify (a bad config fails the build), the DT node
hits the same kernel-delivery wall as D23 (the kernel package is upstream-tag +
config-only, no patch step), and the cmdline variant shares D10's unverified
ABL-passthrough risk. So this is teed up for a build + verify, gated on the
kernel-delivery decision below.

**Honest limit of ramoops here:** it captures the *kernel* side -- a panic/oops
or the previous boot's console tail. It will catch an EDL that follows a kernel
crash or dirty shutdown. But "plain EDL, never a ramdump" points at the
bootloader (XBL/ABL) choosing EDL *before* the kernel, which ramoops cannot see;
a full diagnosis may also need the **PMIC PON/POFF warm-boot-reason register**
surfaced (a separate, complementary lead). Ship ramoops as the cheap first
instrument and read `/sys/fs/pstore/` after the next episode.

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

## D28 — the phone never suspends on idle; it only blanks the screen {#d28}

**Status: CLOSED -- continued as [D29](./fp4-defects.md#d29) (2026-10-11).** The
idle-suspend wiring described here is correct and in place: the phone does
suspend on idle. What is left, s2idle not staying asleep and the SoC never
reaching deep sleep, is tracked in D29. Moved here from the open register so it
no longer reads as a second open bug.

**Correction (2026-10-16):** the ~1 %/h below is very likely a fuel-gauge
artifact (the gauge is stale at the moment of resume; see D29 "Not a
regression"). Idle-suspend itself works; s2idle drains ~5-7 %/h on this phone.

**Status (2026-09-27): FIXED, s2idle drain measured (~1 %/h, ~7x better than
screen-blank); pending only the pkgrel-13 reflash to put the same config on the
phone.** The idle->suspend wiring
(steps 1-2) was done 2026-09-26. Two follow-up overnight watches saw zero
suspends, but the cause was NOT the idle logic -- it was that the swayidle under
test had been relaunched over ssh and so had no logind seat, and polkit denies
suspend to a seatless session (see "Root cause" below). The in-session swayidle
is authorized and suspends. The idle action has also been consolidated into one
step (moarchy-idle-action). This is Track A1 in
[`fp4-roadmap.md`](./fp4-roadmap.md) and the reason battery is rated `P`: "screen
off" is not "asleep", so the phone drains while it looks off.

**What is already there** (checked on the handset, read-only):

- s2idle is the supported mode: `/sys/power/state` = `freeze mem`,
  `/sys/power/mem_sleep` = `[s2idle]` (there is no deep/S3 on this SoC in
  mainline, which is normal).
- Wake sources are enabled where it matters: the power-button PMIC pwrkey
  (`pon@800:pwrkey`), all three remoteprocs including `remoteproc1: modem`
  (so an incoming call/SMS can wake the AP), and the RTC alarm (`rtc@6100`).
- The fuel gauge works: `qcom_qg` reports capacity and voltage
  (99 %, 4.39 V). `current_now` reads 0 while on USB, so idle drain cannot be
  measured until the phone is unplugged.
- Nothing is holding a wakelock: no `/sys/kernel/debug/wakeup_sources` entry has
  `prevent_suspend_time > 0`, so s2idle should be enterable.
- `rtcwake` is installed (util-linux 2.42.3) with a working
  `/sys/class/rtc/rtc0/wakealarm`.

**The actual defect.** Nothing triggers a system suspend:

- `logind` has `IdleAction=ignore` (the default), so it never suspends.
- swayidle runs a single rule, `timeout 600 moarchy-idle-blank`, which blanks
  the panel and stops there. The CPU, modem and buses stay fully powered with
  the screen dark.

So after ten minutes the display goes off and the phone keeps running at full
idle power. That is the battery finding.

**What remains, in order:**

1. **Prove s2idle resumes cleanly. DONE 2026-09-26 — it works.** `rtcwake -m mem
   -s 25` (armed detached via `systemd-run` so it did not depend on the ssh
   session), with the owner watching. The phone suspended, woke on the RTC
   alarm, and reconnected on its own; `/sys/power/suspend_stats/success` went
   0 -> 1, fail 0, and dmesg shows a clean cycle:

   ```
   PM: suspend entry (s2idle)
   Filesystems sync: 0.027 seconds
   Restarting tasks: Starting / Done
   PM: suspend exit
   ```

   No failed devices, entry->resume in ~2 s. So s2idle is safe to enable.
2. **Wire idle -> suspend. DONE 2026-09-26, tested live on the FP4.** A second
   swayidle timeout (config/hypr/autostart.lua) runs `bin/moarchy-idle-suspend`
   60 s after the blank, with `before-sleep 'moarchy-lock'` so every suspend path
   wakes to the PIN pad. moarchy-idle-suspend skips Stay Awake and an active
   call/audio (sink/source streams, sleep inhibitors). Shipped by moarchy pkgrel 9.
   Verified on hardware: `moarchy-idle-suspend` suspended to s2idle
   (`suspend_success` incremented, clean resume), and a **single** power-button
   press woke it to the PIN pad, which the PIN unlocked.

   **Also fixed a double-press bug found during this test.** Idle-off used to run
   `moarchy-screen blank`, which blanks WITHOUT setting the lock flag (so touch
   could wake it). But the power button decides lock-vs-wake off that flag, so the
   first press after idle read no flag and re-locked (a no-op blank) instead of
   waking -- you needed two presses, unlike a power-button-off (one). Fix:
   `moarchy-idle-blank` now runs `moarchy-screen lock`, so idle-off leaves the
   same state as power-off and a single press wakes. Trade-off: touch no longer
   wakes from idle (the power button does), which is standard phone behaviour and
   is what removes the two-handler race. Verified: single press now wakes from
   idle.
3. **Measure idle drain** in s2idle vs screen-blank-only, which needs the phone
   unplugged (USB masks `current_now`), same constraint as GPS testing.

**Screen-blank-only drain measured 2026-09-26, unplugged overnight.** With the
system never suspending (confirmed: `/sys/power/suspend_stats/success` = 0, no
suspend lines in dmesg over ~46 h uptime), the battery went **99% -> 34%
overnight** (4.39 V -> 3.72 V). Instantaneous draw ~**0.73 W** (upower), ~8 h to
empty at 34% -- i.e. roughly **~1 day of standby from full**, screen off, doing
nothing. That is the cost of D28: a phone that should get days of s2idle standby
gets about one. The s2idle comparison number still needs step 1 (a proven
resume) before it can be taken. (Aside: the fuel-gauge/charger status
misreports here -- `qcom_qg` status reads Unknown and pm7250b-charger reads
"Charging" while clearly discharging; cosmetic, but it breaks any status-based
UI.)


**Root cause of "zero overnight suspends" (corrected 2026-09-27): a polkit/seat
problem in the test setup, not the idle logic.** Two overnight watches showed
`/sys/power/suspend_stats/success` stuck at its starting value across the whole
night. But the swayidle being watched had, in both cases, been relaunched over
ssh during earlier live debugging -- and an ssh-launched process has no logind
seat. logind/polkit grants `org.freedesktop.login1.suspend` to an **active,
seated** session with no prompt, but requires admin authentication (`auth_admin`)
for a seatless one, which on this locked-password phone can never be satisfied.
So swayidle fired its timeout, ran the action, called `systemctl suspend`, and
was silently denied. The swayidle stderr confirms it:

```
Call to Suspend failed: Access denied as the requested operation requires
interactive authentication. However, interactive authentication has not been
enabled by the calling program.
```

Proof it is the seat, not the code (checked 2026-09-27 with `pkcheck`):

| caller | logind session | `pkcheck ... login1.suspend` |
|---|---|---|
| Hyprland (graphical) | c1, seat0, active | **rc=0 (authorized)** |
| ssh shell | c197/c208, no seat | rc=2, `auth_admin_keep` (denied) |

So the earlier "timer reset" hypothesis (that a 600 s blank reset swayidle's
clock so a 660 s suspend timeout never fired) was wrong: swayidle does fire, and
the graphical session is authorized. **The lesson: idle-suspend cannot be tested
by relaunching swayidle over ssh.** A hand test must put swayidle in the
graphical session -- e.g. `hyprctl dispatch 'hl.exec_cmd("swayidle ...")'`, which
Hyprland runs as its own child on seat0 (`cgroup: session-c1`, `pkcheck rc=0`).

**Code change kept regardless:** the idle action is consolidated into one
`bin/moarchy-idle-action` (lock, then `moarchy-idle-suspend`) driven by a single
swayidle timeout, replacing the two-timeout design -- one atomic action, no
dependence on a second timeout. `config/hypr/autostart.lua`, moarchy pkgrel 13.
This is a simplification, not a fix for a proven bug in note 9.

**Valid test DONE, s2idle drain measured (2026-09-27, on battery, unplugged).**
swayidle launched in-session via `hl.exec_cmd` (`cgroup: session-c1`,
`pkcheck rc=0`), running `timeout 600 moarchy-idle-action ...`; guards all clear.
It suspended once at ~04:16 (last awake 04:13 @ 62%) and held s2idle until the
power-button wake at ~09:22 @ 57% -- `suspend_stats/success` 3 -> 4, fail 0.

**Result: 62% -> 57% = 5% over ~5.1 h = ~1 %/h in s2idle**, vs the
screen-blank-only ~7 %/h (~0.73 W) measured earlier -- about **7x** slower, i.e.
roughly **4 days** of standby from full instead of ~1. It also re-suspended on
its own after the morning wake (idle-suspend fires repeatedly, not just once).
(Caveat: the fuel gauge misreads for a few minutes after resume -- a 57%->49%
jump in 5 min awake is the qcom_qg `status=Unknown` re-settle, not real drain; the
across-suspend delta is the reliable figure.) Step 3 is complete; D28 is fixed,
pending only the same config reaching the phone via the pkgrel-13 reflash.

**Note for the reflash:** the image built overnight (2026-09-27) carries the old
two-stage config -- the change landed after that build started. Rebuild the image
(moarchy is now pkgrel 13) before/with tomorrow's reflash. After reflash, the
valid confirmation is simply: boot, leave the phone idle and unplugged, and watch
`suspend_success` climb -- do NOT relaunch swayidle over ssh (it would be denied).

## D31 -- some boots have no sound card: the ADSP's APR audio services never register {#d31}

**Status: FIXED 2026-10-10.** Root cause: a module-load race; `qcom_pd_mapper`
and `qrtr_smd` loaded after the ADSP was already up, so its PD locator query was
lost. Fixed by the modprobe softdep `qcom_q6v5_pas pre: qrtr qrtr_smd
qcom_pd_mapper` (`moarchy-device-fp4` pkgrel 10). Verified: 10/10 boots with the
card on the test rootfs, then 10/10 on the full CI image (`fp4` @ `9e118c6`) with
the softdep coming from the package. The investigation below is kept as it was.

**Originally: OPEN -- important (found 2026-10-08, on the mic-fix kernel `d7f57bf`
flashed over the fp4-dev-all rootfs).** Intermittent: the boot straight after the
flash had a working card and captured audio; a later cold boot came up with
`/proc/asound/cards` = `--- no soundcards ---` and stayed that way.

It looks like D10 but is not D10. `deferred_probe_timeout=60` is on the cmdline
and the ADSP was **early**, not late:

```
[   16.569564] remoteproc remoteproc0: remote processor adsp is now up
[   78.910054] platform 33c0000.pinctrl: deferred probe pending: (reason unknown)
[   78.853687] platform 3370000.codec: deferred probe pending: va_macro: unable to get macro clock
```

The difference is one layer down. `apr`, `qrtr` and `qcom_pd_mapper` are loaded,
but **no APR service device ever appears**, so `q6afe`, `q6afe_clocks`,
`q6afe_dai` and `snd_q6dsp_common` are never autoloaded. Without q6afe-clocks the
LPASS clocks do not exist, the LPI pinctrl (`33c0000.pinctrl`) cannot probe, and
everything behind it (both macros, both SoundWire controllers, the sound card)
stays deferred until the timeout gives up. Writing `33c0000.pinctrl` to
`/sys/bus/platform/drivers_probe` afterwards does not bring it back, because the
missing supplier is the q6 clock service, not the pinctrl itself.

So on these boots the audio protection domain on the ADSP never announces its
services, although the ADSP remoteproc reports `running`.

**Candidate fix, untested:** upstream `b8e6fa9877f6` ("arm64: dts: qcom: sm6350:
Add memory-region for audio PD", Luca Weiss, on `sm6350-7.2.y` after the
`v7.2.0-sm6350` tag) reserves a remote heap for the ADSP's audio PD dynamic
loading and adds the LPASS/ADSP-heap VMIDs for ownership transfer. The pinned tag
lacks it. Bumping the kernel pin to the branch head picks it up; whether it cures
this needs a multi-boot count, since the failure is intermittent.

**2026-10-08, on the bumped kernel (sm6350-7.2.y @ 5ba18a1da713):**

- **`b8e6fa9877f6` does not prevent it.** In a 5-boot loop on the kernel that
  carries it, boots 1-3 had the card and all three q6 modules; boot 4 came up
  with no card and the identical signature. (The loop stopped there because
  that boot also never got an IPv4 lease; WiFi associated, only IPv6 came up.
  Whether that is related is open -- WiFi's QMI services go over the same QRTR
  bus as the audio PD's service registry.)
- **The APR bus is empty on a bad boot:** `/sys/bus/apr/devices` lists
  nothing, with `apr`, `qrtr` and `qcom_pd_mapper` loaded and the ADSP up at
  ~15 s. So the audio PD's services are never announced, rather than announced
  late.
- **Restarting the ADSP recovers it without a reboot:**

  ```
  echo stop  | sudo tee /sys/class/remoteproc/remoteproc0/state
  echo start | sudo tee /sys/class/remoteproc/remoteproc0/state
  ```

  Within 15 s `q6afe`, `q6afe_clocks`, `q6asm` and `q6adm` autoload, the
  card registers and `devices_deferred` empties -- the stuck devices probe
  even though the 60 s deferred-probe window has long expired. So this is a
  boot-time race in the audio PD's first start, not a lasting fault, and it
  points at a cheap mitigation (if no card ~90 s after boot, restart the ADSP
  once; the sensor core shares the ADSP, so iio-sensor-proxy blips).

**Root cause (2026-10-09): a module-load race, not the DSP.** On a DSP's
start, remoteproc adds a "pd-mapper" auxiliary device, and the separately
loaded `qcom_pd_mapper` module binds to it and starts the service-locator
(servloc) QMI server that the ADSP firmware queries for its audio PD. The ADSP
reaches that QMI service over the QRTR link that `qrtr_smd` provides. Nothing
orders those modules against `qcom_q6v5_pas` (no softdep anywhere upstream);
udev loads them on demand. Measured with the `module_load` tracepoint, armed
before udev coldplug, on 6 boots: `qcom_pd_mapper` loaded **40-235 ms after**
"adsp is now up" every time, and `qrtr_smd` after it too. The ADSP usually
waits long enough; when it does not, its audio services never register (no
APR devices, no `ssctl`) and there is no card.

**Fix:** `softdep qcom_q6v5_pas pre: qrtr qrtr_smd qcom_pd_mapper`
(moarchy-device-fp4, `/usr/lib/modprobe.d/moarchy-fp4-pd-mapper.conf`), so
modprobe/udev load them before the remoteproc driver. Verified on hardware:
across 10 reboots the order flipped to `qrtr_smd` and `qcom_pd_mapper` loading
~150-250 ms **before** "powering up adsp", and all 10 boots had the sound card.
No ADSP restart, so call audio is untouched. Before the fix D31 hit roughly
one boot in 10-15, so 10 clean boots supports the fix but does not yet prove it;
it moves to fp4-fixes.md after more boots in normal use.

**Workaround:** reboot, or restart the ADSP as above. **Diagnose a bad boot:** `lsmod | grep -E 'q6afe|apr'`
(apr present, q6afe absent = this defect) and
`sudo cat /sys/kernel/debug/devices_deferred` (the 33c0000.pinctrl chain).

## D30 -- the quickshell before-sleep lock traps a locked-password account {#d30}

**Status: FIXED 2026-10-11 (verified on hardware).** A fresh full flash of the
`fp4` @ `1e1944b` CI image came up with the account usable (`passwd -S` = `P`) and
its hash equal to the default PIN `1337`, checked over serial before anything was
restored. The quick-fix notes follow.

**Was: QUICK FIX APPLIED 2026-10-10 -- verify on the next image.** The image
now ships the account with the documented default PIN `1337` instead of a locked
password (`image/configure.sh` DEFAULT_PIN; `image/verify.sh` accepts exactly
that hash and still fails on any other real password; ssh password auth stays
off, so the public default only unlocks a phone in hand). Hit again on
2026-10-10 after a full flash of the `9e118c6` CI image: stuck on the lock
screen, recovered by setting the PIN over SSH (`chpasswd`). For our own full
flashes the backup kit also restores the shadow hash. Move to fixes once a
fresh flash of an image with this change unlocks with `1337`.

**Originally: OPEN -- important (found 2026-10-05, on a full flash of the
`fp4-dev-all` dev image).** After a full flash the account ships with a *locked*
password (`passwd -S` reports `L`; tty1 autologin does not consult one, by
design -- see `docs/structure.md` I8 and D-note in `bin/moarchy-system-lock`).
The quickshell shell's own lockscreen ("omarchy lock", PAM config
`omarchy-lock-password`) is triggered on `before-sleep` by
`swayidle -w ... before-sleep moarchy-lock`. It authenticates through PAM, and a
locked password can never satisfy PAM, so the first time the phone sleeps it puts
up a PIN/password prompt that **nothing the user types can clear** -- a full
lockout. `loginctl unlock-sessions` does not dismiss it (the lock is a secure
ext-session-lock client that only releases on a successful PAM auth), so recovery
needs the serial console.

This is the *same* trap `bin/moarchy-system-lock` already guards against for the
swaylock path: it checks `passwd -S` and, when the state is not `P`, blanks the
panel (`moarchy-screen lock`) instead of taking a real ext-session-lock, exactly
because "a locked password authenticates nothing". The quickshell before-sleep
lock path has **no equivalent guard**, so it reintroduces the lockout the shell
script was written to avoid.

**Recovery (serial):** `printf 'moarchy:<pin>\n' | sudo -n chpasswd` over
`/dev/ttyACM0`, then type `<pin>` on the lockscreen. (One gotcha while doing
this: do not leave two `cat /dev/ttyACM0` readers running -- they split the
byte stream and both the command echo and its output come back garbled.)

**Proper fix, one or both:**
1. Guard the quickshell / `moarchy-lock` before-sleep path to skip a real lock
   when `passwd -S "$(id -un)"` is not `P` (blank instead), mirroring
   `bin/moarchy-system-lock`. This is the robust fix: it makes a locked-password
   device un-lock-out-able regardless of how the lock is triggered.
2. Have first-boot setup actually establish a PIN so the password is `P` from the
   start -- the "setup wizard" that is currently missing. `moarchy-firstboot`
   (groups/autologin) and `moarchy-user-setup` (app configs/theme) both run and
   stamp `firstboot-done` / `user-setup-done`, but **neither sets a PIN**, so
   there is no first-run step that moves the password off `L`. A device left on
   the shipped locked password is the exact condition that (1) must handle.

Until fixed, any full flash leaves the phone one sleep away from a serial-only
lockout.

---

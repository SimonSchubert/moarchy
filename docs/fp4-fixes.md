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
after [D25](../fp4-defects.md#d25)). Unlike Docker, the store is built to avoid
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

The Docker TUI ([D25](../fp4-defects.md#d25)) is a different case -- it calls
`pkexec` on a program with no custom action, so it always uses the generic
`org.freedesktop.policykit.exec` and still prompts. That one needs a different
fix and is left open.

# Apps that work on the PinePhone

Every app below was installed and launched on a **Pine64 PinePhone Braveheart
(1.1)** — Allwinner A64, 2 GB RAM, 720×1440 at `scale 2` (360×720 logical) —
running this Sway session. Screenshots are straight off the device via `grim`,
uncropped, so the bar is visible in each one.

## What actually limits app choice

Availability is *not* the constraint. Essentially the whole desktop catalogue is
built for aarch64 in Arch Linux ARM — Firefox, Chromium, GIMP, Inkscape,
LibreOffice, Signal, Telegram all install fine. Three other things decide whether
an app is usable:

1. **A 360×720 logical screen.** Desktop layouts do not reflow. The apps that
   work are the ones designed to adapt — GNOME's libadwaita apps and KDE's
   Kirigami/Plasma Mobile apps. Both families were built for phones.
2. **2 GB of RAM.** Electron and Chromium will run and will hurt.
3. **`*-bin` AUR packages are usually dead.** They ship prebuilt x86_64 binaries
   by definition. `braincup-bin`, for example, ships
   `Braincup-3.5.0-linux-x86_64.tar.gz` and has no source PKGBUILD — there is
   nothing to rebuild for ARM, and `dotnet-runtime` is not in the aarch64 repos
   either. Check for a non-`-bin` package before assuming an app is available.

## GNOME (libadwaita)

These reflow to a phone width natively and are the most comfortable fit.

| App | Package | Notes |
| --- | --- | --- |
| Clocks | `gnome-clocks 50.0-2` | Bottom tab bar, fully adaptive |
| Text Editor | `gnome-text-editor 50.1-1` | Works well with the on-screen keyboard |
| Loupe | `loupe 50.0-1` | Image viewer, gesture zoom |
| Papers | `papers 50.2-1` | PDF viewer (Evince's successor) |
| Foliate | `foliate 3.3.0-3` | E-book reader; genuinely good on this screen |
| Portfolio | `portfolio-file-manager 1.0.2-1` | File manager built for touch |
| Maps | `gnome-maps` | Adaptive; reflows to 360px like the rest of the set |

<p align="center">
  <img src="screenshots/apps/01-gnome-clocks.png" width="30%" alt="GNOME Clocks">
  <img src="screenshots/apps/02-gnome-text-editor.png" width="30%" alt="GNOME Text Editor">
  <img src="screenshots/apps/05-foliate.png" width="30%" alt="Foliate">
</p>
<p align="center">
  <img src="screenshots/apps/03-loupe.png" width="30%" alt="Loupe">
  <img src="screenshots/apps/04-papers.png" width="30%" alt="Papers">
  <img src="screenshots/apps/06-portfolio.png" width="30%" alt="Portfolio">
</p>

```bash
sudo pacman -S gnome-clocks gnome-text-editor loupe papers foliate portfolio-file-manager gnome-maps
```

## Plasma Mobile (Kirigami)

KDE's mobile apps are the other family designed for this form factor, and they
run without a KDE session — they are ordinary Wayland clients under Sway.

| App | Package | Notes |
| --- | --- | --- |
| Kalk | `kalk 26.08.0-1` | Calculator with unit conversion |
| KWeather | `kweather 26.08.0-1` | Weather |
| Keysmith | `keysmith 26.08.0-1` | TOTP / 2FA codes |
| Calindori | `calindori 26.08.0-1` | Calendar |
| QMLKonsole | `qmlkonsole 26.08.0-1` | Touch-friendly terminal |

<p align="center">
  <img src="screenshots/apps/07-kalk.png" width="30%" alt="Kalk">
  <img src="screenshots/apps/09-kweather.png" width="30%" alt="KWeather">
  <img src="screenshots/apps/10-keysmith.png" width="30%" alt="Keysmith">
</p>
<p align="center">
  <img src="screenshots/apps/11-calindori.png" width="30%" alt="Calindori">
  <img src="screenshots/apps/12-qmlkonsole.png" width="30%" alt="QMLKonsole">
</p>

```bash
sudo pacman -S kalk kweather keysmith calindori qmlkonsole
```

**KClock and Index are no longer installed by default** (2026-09-06). Both were
second copies of something already here: GNOME Clocks is the more adaptive of
the two clocks, and Portfolio is the file manager — Index additionally drags the
whole MauiKit stack in behind it. Both still install cleanly:

<p align="center">
  <img src="screenshots/apps/08-kclock.png" width="30%" alt="KClock">
  <img src="screenshots/apps/13-index-fm.png" width="30%" alt="Index">
</p>

```bash
sudo pacman -S kclock index-fm
```

## Reference

| App | Package | Notes |
| --- | --- | --- |
| Linux Command Library | `lcl-gui-bin 4.7.1-2` | Qt6 command reference and cheat sheets |

Useful on a device whose fullscreen terminal is 47 columns: looking a flag up in
a GUI beats scrolling a man page at that width. Not in Arch Linux ARM — built
from the pin in `manifest.toml`, from an AUR PKGBUILD that declares `aarch64`
and ships a matching prebuilt tarball.

```bash
sudo pacman -S lcl-gui-bin
```

## Terminal apps

This is where the hardware is genuinely comfortable, and it is the Omarchy idiom
anyway. Two measured constraints shape it:

- A **fullscreen terminal is 47×41 characters** at font size 9.
- **btop refuses to draw below 60 columns**, whatever `shown_boxes` says.

So `moarchy-launch-tui` opens TUIs fullscreen at font size 7. For something
that fits a *tiled* terminal with the bar still visible, use **`btm`** (bottom) —
it adapts, and shows CPU, memory, all three thermal zones, disks and network.

Also installed and worth knowing: `htop`, `lazygit`, `bluetui`, `wiremix`
(audio), `s-tui` (CPU frequency/temperature graphs).

**Wi-Fi is not a TUI.** The shade's tile and Settings both open `moarchy.wifi`,
a touch screen with a passphrase field — see `docs/shade.md` S6b. `nmtui-connect`
still works from a terminal, but its buttons cannot be pressed with a finger.
`impala` looks like the wifi TUI to reach for and is wrong twice over: its
buttons have the same problem, and it is an **iwd** client on a phone running
NetworkManager with `iwd.service` disabled — iwd is D-Bus activatable, so impala
starts it to fight NetworkManager for `wlan0` rather than failing cleanly.

## Browsers

**Epiphany** (`epiphany`) is the one to reach for — WebKit, ~260 MB, and it has a
genuinely adaptive mobile layout with the URL bar at the bottom. Firefox and
Chromium both install and run, but cost far more memory for no layout benefit.

Heavy SPAs are the real problem, not the browser. x.com loads but paints poorly
and leaves large black regions — that is the workload against a 1.15 GHz A53 and
a GLES 2.0 GPU, not something configuration fixes.

## Camera

**Megapixels 2.1.0** is the camera app. Verified on the device on 2026-09-06:
both sensors stream, the camera switch works, the flash toggles, and a shutter
press captures a three-frame burst at the rear sensor's full 2592×1944.

The reason it works where nothing else does is `libmegapixels`, which ships a
`pine64,pinephone.conf` describing this device's media graph and **configures the
links itself** before streaming:

```
Pipeline: ({Type: "Link", From: "ov5640", FromPad: 0, To: "sun6i-csi-bridge", ToPad: 0},
           {Type: "Mode", Entity: "ov5640"}, {Type: "Mode", Entity: "sun6i-csi-bridge"});
```

That is the whole of the old "`VIDIOC_STREAMON` fails — pipeline links
unconfigured" entry. The links were unconfigured because no one was configuring
them; `sun6i-csi` on 6.18 requires it and a generic app never does. This is also
why **`snapshot` and `plasma-camera` cannot work here** — both assume a camera
that just streams, and neither knows about the `sgm3140` flash.

`megapixels-findconfig` auto-detects from the devicetree (`pine64,pinephone-1.1`):

| | Sensor | Flash | Modes |
| --- | --- | --- | --- |
| Rear | `ov5640` | LED, `/sys/class/leds/white:flash/flash_strobe` | 2592×1944@15, 1280×720@30 (BGGR8 / YUYV) |
| Front | `gc2145` | screen | 1280×720@60 BGGR8 |

The camera switch was confirmed against the media graph rather than by eye —
tapping it flips which sensor link to `sun6i-csi-bridge` is `[ENABLED]`, cycling
`gc2145 → ov5640 → gc2145`.

### Three things that bite

1. **`xdg-user-dirs` is required, and nothing pulled it in.** Without it
   `~/Pictures` never exists, and every photo is captured and then **silently
   thrown away** at the last step:
   `cp: cannot create regular file '/home/…/Pictures/IMG….dng': No such file or
   directory`. The burst is written to `/tmp` first, so the failure appears only
   after the shutter animation, and the app reports nothing.
2. **The flash permission does not survive a reboot.** The shipped
   `90-megapixels.rules` chmods `flash_strobe` to 666 on `ACTION=="add"` only,
   and the LED is added at boot before the rule exists, so it stays root-owned.
   `udevadm trigger --subsystem-match=leds` fixes it until the next boot.
3. **The preview is software-rendered, by Megapixels' own choice.** It matches
   the devicetree and forces `LIBGL_ALWAYS_SOFTWARE=1`, so the GLES preview runs
   on the A53s, not the Mali — GTK4 then reports "OpenGL ES 3.2" because that is
   llvmpipe. It is usable, but the log fills with `Dropping frame`.

### Not yet verified

Whether the flash physically fires, and video recording. Megapixels ships
`movie.sh` → `mpegize.py`, which is GStreamer `x264enc speed-preset=ultrafast`
into `~/Videos/VID*.mkv` — software H.264, since the A64's `cedrus` is
decode-only. Audio would be silent regardless while the microphone records
RMS 0. Video also needs `python-gobject`, `gst-plugins-good` and
`gst-plugins-ugly`, none of which `megapixels` declares.

## Not working

| | |
| --- | --- |
| **Microphone** | Records digital silence (RMS 0) at PipeWire *and* raw ALSA, despite `Mic1` on, boost 7, `ADC` 144/192 and `AIF1 Slot 0 Digital ADC` enabled |
| ~~Camera~~ | **Works as of 2026-09-06** — see [Camera](#camera) below. The old entry here blamed `VIDIOC_STREAMON`; the links were never configured because nothing was configuring them |
| Audio **output** | Works |
| Hardware video decode | `cedrus` present at `/dev/video1`, unexplored |

See [`build-log.md`](build-log.md) for how the device was set up and what else is
known-broken.

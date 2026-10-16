# moarchy

<p align="center">
  <img src="docs/screenshots/system-drawer-open.png" width="16%" alt="The app drawer at rest: a search field over a grid of app icons">
  <img src="docs/screenshots/system-drawer.png" width="16%" alt="The app drawer, filtered as you type, with the on-screen keyboard up">
  <img src="docs/screenshots/system-center.png" width="16%" alt="The control centre: quick tiles, brightness and volume, the media player and notifications">
  <img src="docs/screenshots/system-settings.png" width="16%" alt="The Settings suite's top level">
  <img src="docs/screenshots/app-web.png" width="16%" alt="GNOME Web on omarchy.org, URL bar at the bottom, keyboard up">
  <img src="docs/screenshots/app-lcl.png" width="16%" alt="Linux Command Library, an ordinary GTK app under the gesture strip">
</p>

Omarchy's look, keybindings and theming on a phone, on Arch Linux ARM, running
**Hyprland**. This is not a fork of Omarchy's installer: it is a thin overlay
that vendors Omarchy's *configuration and theme layer* (architecture-neutral)
onto an aarch64 base, and replaces the parts that cannot work on this hardware.

**Compositor: this fork runs Hyprland, upstream runs Sway.** See
[Compositor and upstream divergence](#compositor-and-upstream-divergence).

## Compositor and upstream divergence

Upstream [`SimonSchubert/moarchy`](https://github.com/SimonSchubert/moarchy) runs
**Sway**. Its original targets include the PinePhone, whose Mali GPU is GLES2-only
and cannot give Hyprland the GLES3 context its renderer needs; upstream reaches
Sway through a build-time port (`port-4x.patch` rewriting `Quickshell.Hyprland`
to `Quickshell.I3`).

**This fork runs Hyprland, on purpose.** Its target phones are Adreno-class (the
Fairphone 4's Adreno 619, the Pixel 3a's Adreno 615) and both clear GLES 3.2, so
Hyprland runs natively. The reasons:

- Omarchy is a Hyprland project, so running Hyprland is truer to "Omarchy's look"
  and gives the effects (animations, blur, `hyprlock`/`hypridle`) that Sway only
  approximates.
- It drops the Sway port: `port-4x.patch` no longer rewrites the compositor seam,
  the vendored shell keeps upstream's own `Quickshell.Hyprland`, and the config
  lives in `config/hypr/`.

**What the divergence affects, and what it does not.** It is confined to the
shell's window-management surfaces (`moarchy.gestures`, `moarchy.workspace-overview`,
and a few `bin/` helpers). Everything else is compositor-neutral: the app store
(`moarchy-store`, a standalone app that installs through pacman) and the mobile
apps (the `moarchy.*` plugins) have no runtime compositor coupling and behave
identically under either compositor, so the app ecosystem is unaffected by this
choice.

**Migration status.** The compositor move is done (`config/hypr/` is the live
config and the Sway overlay is deleted), but a few `bin/` helpers still call
`swaymsg` and are being ported to `hyprctl`. Treat any `swaymsg` under `bin/` as
leftover, not current design. Sections further down that still describe Sway
mechanics (theming, gestures, "what you get and what you don't") predate this
move and are being corrected.

## Install

Download the image for your phone from
**[Releases](https://github.com/SimonSchubert/moarchy/releases)**. There is no
installer to run on the device. tty1 autologin brings the session up without a
password; the lock screen's default PIN is **`1337`** -- change it with `passwd`
in a terminal (it asks for `1337` first). SSH never accepts a password, so the
public default does not open the phone remotely.

The bootloader must be unlocked. Unpack the sargo archive, put the phone in
fastboot (power off, hold Volume Down, tap Power), and run `flash.sh`. That
overwrites `boot` and `userdata`; the Android install does not survive it.

```bash
tar -xJf moarchy-sargo-*.tar.xz
cd moarchy-sargo-*
./flash.sh
```

## Other phones

The Pixel 3a is the phone this ships on. A **Fairphone 4** port lives in the
tree and **runs on the handset**: it boots, and it works as a phone — display,
touch and rotation, camera, sensors, the built-in microphone, both speaker
amplifiers, and cellular calls with audio in both directions.

It is not in Releases. Enough is still open — Wi-Fi latency, a boot race that
can take all audio with it, and occasional drops into the SoC's emergency
download mode — that flashing it is something to do deliberately, with the
recovery path read first.

[`docs/fairphone-4.md`](docs/fairphone-4.md) is the status: what runs, what was
verified and how. [`docs/fp4-defects.md`](docs/fp4-defects.md) is what is
still broken, and [`docs/fp4-fixes.md`](docs/fp4-fixes.md) the defects already
closed, including how to get out of EDL without touching the phone.

Three gaps that looked like port bugs turned out to be missing kernel support,
and went upstream rather than into this tree: the microphone and the speaker
amplifier as pull requests against `sm6350-mainline/linux` (#11 and #12), and
the call-audio findings onto the Fairphone 5's q6voice work, which already
covers the same ground.

```bash
./scripts/deploy-fp4.sh      # preflight, packages, image, verify, flash
```

## Why not just run Omarchy?

Two hard blockers, both verified rather than assumed.

**1. Omarchy's package repo has no usable aarch64 base.**

```
https://pkgs.omarchy.org/stable/x86_64/omarchy.db  ->  200  (211 packages)
https://pkgs.omarchy.org/stable/aarch64/omarchy.db ->  200  (34 packages, app catalog only)
```

> **Update 2026-10-16:** no longer true on the edge channel. Upstream now
> supports aarch64 (Apple Silicon, Snapdragon laptops, NVIDIA N1x/GB10, generic
> ARM), and `edge/aarch64` carries 196 packages including the `omarchy` base
> package; stable aarch64 has 80 and still no base. See
> [`docs/omarchy-arm-scan-2026-10.md`](docs/omarchy-arm-scan-2026-10.md), which
> also covers why upstream's platform detection would treat the FP4 as a
> Snapdragon laptop.

The aarch64 tree appeared after this was first measured, but it is an app
catalog (browsers, editors, a few omarchy-branded apps) with no `omarchy`
metapackage or `omarchy-config`, no keyring, and an unsigned database, so it
does not carry the config/theme layer moarchy needs.
`install/preflight/guard.sh` upstream also requires x86_64, limine, a btrfs root
and vanilla-Arch markers — none of which hold on a phone.

**2. There is no packaged device stack.** No pacman repo anywhere carries an
SDM670 kernel or the Pixel 3a's firmware, so moarchy builds and publishes both,
at pins ([`docs/devices.md`](docs/devices.md) §2).

## What ports cleanly, and why

Omarchy 4.x generates its per-app theming from one small file per theme,
`colors.toml`, expanded through `default/themed/*.tpl` by
`omarchy-theme-set-templates`; the shell reads the active theme quickshell stages
at `~/.local/state/omarchy/current/theme/`.

Because this fork runs Hyprland, the compositor theming is upstream's own:
`config/hypr/hyprland.lua` pulls the active theme's colours and `hyprctl reload`
re-reads them on every theme change (`config/hypr/autostart.lua`), so all **22**
upstream themes work with no per-theme effort. `shell.toml.tpl` (the whole
quickshell shell), `foot.ini.tpl`, `btop.theme.tpl` and the GTK templates are
reused untouched. (`alacritty.toml.tpl` is reused too, and has been unused since
the phone went to one terminal on 2026-09-08, see [docs/apps.md](docs/apps.md).)

## What runs on it

[`docs/apps.md`](docs/apps.md) — every app the phone ships with, what each one
is, and screenshots straight off the device for the ones that have been run on
it. Short version: GNOME's
libadwaita apps and KDE's Kirigami/Plasma Mobile apps both reflow to a 360px
screen and are the comfortable fit; availability is not the constraint, screen
width is.

## What it looks like

[`docs/style.md`](docs/style.md) is the style contract — the type scale, the six
colour roles, the four radii, the 44px touch-target floor and the motion
budget. It binds the shell plugins in this repo *and*
the two surfaces that are not in it: the
[keyboard](https://github.com/SimonSchubert/moarchy-keyboard) and the
[store](https://github.com/SimonSchubert/moarchy-store). Three programs, three
toolkits — quickshell/QML, standalone Qt, Python and GTK4 — one palette, read
from the theme `omarchy-theme-set` stages at
`~/.local/state/omarchy/current/theme/`.

`scripts/style-check.sh` enforces the half of it that is visible in the source.

## How this was built

[`docs/build-log.md`](docs/build-log.md) is the chronological account — every
measurement, and every dead end, including the ones that cost the most time
(RNDIS vs macOS, a write-protected SD adapter, Docker Desktop's missing Landlock,
and an assumption about Omarchy 4.x that turned out to be wrong twice over).

## Omarchy 4.x

moarchy runs **Omarchy v4.0.4** (`c668141`), pinned in
[`manifest.toml`](manifest.toml). There is no waybar, walker, mako or swayosd
in the package set: in 4.x the bar, launcher, notifications and OSD are one
**quickshell/QML** shell, and the phone UI is a set of plugins on top of it
rather than a patched copy of it.

An earlier port targeted v3.8.4 (`8fcc9d6`) — waybar, walker, mako and swayosd
— on the reading that v4.0.0 had moved to **herdr**, a bespoke shell shipped
only as an x86_64 binary. That reading was wrong twice over: herdr is neither
the shell nor closed source.
[`docs/omarchy-4x-feasibility.md`](docs/omarchy-4x-feasibility.md) is the
correction. The 3.8.4 port is gone; it exists only in git history.

**Why 4.x is portable.** The shell is quickshell/QML, architecture-neutral,
and `quickshell` builds for aarch64. Upstream's shell targets Hyprland and so
does this fork, so `pkgbuilds/omarchy-config/port-4x.patch` hosts moarchy's
plugins in the vendored shell without touching the compositor seam: it keeps
upstream's own `Quickshell.Hyprland`. (On Sway the patch also rewrote
`Quickshell.Hyprland` to `Quickshell.I3`; that half was removed when the fork
moved to Hyprland.)

## Touch gestures

A compositor's touchpad gesture bindings do not fire for a touchscreen, so the
gestures are a Quickshell plugin that owns the bottom edge as a layer surface and
reads the touch itself.
Everything follows the finger rather than firing at a threshold.

One drag up from the home pill has two stops, the way Android's does:

```
0 -------------- 50% -------------- 100% -- past the top
    closes             opens                   HOME
```

| Gesture | What it does |
| --- | --- |
| Swipe up from the pill, short | The app drawer |
| Swipe up from the pill, further | Home — a workspace with nothing on it |
| Swipe up **on the wallpaper** | The app drawer, tracking the finger 1:1 |
| Press and hold the pill | The default coding agent, in a terminal — the picker, with none chosen yet |
| Swipe left / right | Next / previous workspace, which is next / previous app |
| Swipe in from the **right edge** | The workspace overview — every workspace as a card, one under the other |
| Tap an app on a card | Switch to that app |
| Drag an app off its card | Move it to another workspace — two on one workspace tile, one above the other — or into the bin to close it |
| Pull down from the status bar | The control center: quick settings, brightness, media |

Every up-swipe raises the app drawer — over an app, over a home screen, over
nothing (`docs/gestures.md` A5). The app drawer is a launcher and nothing else:
what is already running is the workspace overview's subject, and one surface answers
"where is everything" rather than two that show the same windows in two shapes.
Nothing on the strip closes a window either: apps are closed by dragging them
into the workspace overview's bin, one at a time (C4, P12).

The two vertical edges are one gesture each, and the right one is the map. A
swipe in from it pulls the **workspace overview** across: every workspace as a card, one
under the other, each showing the windows on it. Tap a card to go there, tap an
app to go straight to it, or **drag an app onto another card** to move it —
which is the one way a workspace comes to hold two. Drag it into the bin at the
foot of the sheet and it closes, which is the one place a window is closed by
hand.

Two windows side by side on a 360px screen get 180px each, which nothing here
can use, so a workspace that holds more than one is **split vertically**, one
above the other. Hyprland's `dwindle` layout does that natively
(`config/hypr/looknfeel.lua` sets `force_split = 2`), so a keyboard user's
`$mod+Shift+2` lands the same way as the drag. Launching an app still gives it a workspace of its own, sharing one
is something you ask for, once, by dragging.

The hold is the other gesture Android spends on what its owner reaches for
most. Here that is the coding agent, and the pill **shakes** while the press
counts down — a 4px line under a motionless thumb otherwise looks exactly like
a 4px line under a thumb that is only resting, and a gesture nobody can see
happening is a gesture nobody finds (C1, C2).

Everything is reachable without a finger, which is how the selftest asserts it:

```bash
omarchy-shell workspace-overview windows      # one line per open window
omarchy-shell gestures swipe home
moarchy-selftest --gestures   # drives real synthetic touch via /dev/uinput
```

## Layout

Ten files worth knowing about. For the whole map — the eleven shell plugins and
what each owns, how the screens stack, where a given change goes, and what to run
— see **[docs/README.md § The code](docs/README.md#the-code)**.

| Path | What it is |
| --- | --- |
| `default/omarchy/plugins/` | The phone UI: thirteen quickshell plugins and the shared code under `moarchy.common/` |
| `manifest.toml` | The version pins. The only file that says what version of anything is built |
| `pkgbuilds/` | `moarchy`, `omarchy-config` (upstream shell + `port-4x.patch` hosting our plugins), `moarchy-meta`, `moarchy-keyring` |
| `pkgbuilds/moarchy-meta/PKGBUILD` | The aarch64 package set, as `depends`, with every omission explained |
| `config/hypr/` | Omarchy's Hyprland config for the phone: bindings, monitors, look-and-feel, autostart |
| `pkgbuilds/moarchy-device-<phone>/hypr-device.lua` | The one per-device value: panel size and scale |
| `bin/moarchy-*` | The phone's helpers (compositor ones migrating from `swaymsg` to `hyprctl`) |
| `bin/omarchy-*` | Shims with upstream's names, so `omarchy-menu` keeps working |
| `docker/` | aarch64 container that builds every package natively on Apple Silicon |
| `image/boot/android-bootimg.sh` | The boot backend: mkbootimg, AVB, the sparse rootfs |

## Updating

The image ships the `[moarchy]` repository, so everything updates with one
command — the kernel, firmware and modem stack from `[moarchy]` itself,
and the phone UI from moarchy:

```bash
sudo pacman -Syu
```

The database and every package are signed, and `pacman.conf` says
`SigLevel = Required`, so an unsigned or altered package is refused rather than
installed as root.

Shell files land immediately but the running shell keeps the old code until it
restarts — a pacman hook says so after an upgrade:

```bash
moarchy-restart-shell     # or reboot
```

<sub>Adding the repo to a phone that predates it, or to a stock DanctNIX
install, needs the key first — `moarchy-keyring` is itself signed, so pacman
will not install it without already trusting the key:</sub>

```bash
S=https://github.com/SimonSchubert/moarchy/releases/download/repo
curl -fsSLO $S/moarchy.asc
sudo pacman-key --init
sudo pacman-key --add moarchy.asc
sudo pacman-key --lsign-key 3CA83612E7F3108F442006B418305B893569BAD3
printf '\n[moarchy]\nSigLevel = Required\nServer = %s\n' "$S" | sudo tee -a /etc/pacman.conf
sudo pacman -Syu moarchy-meta
```

Reflashing is still needed for changes to the partition layout, to what runs on
first boot, or to the u-boot SPL — that lives outside any partition, at byte
131072.

## Building it yourself

```bash
./scripts/provision.sh build      # the packages, in an aarch64 container
./scripts/build-image.sh          # -> images/moarchy-sargo-<version>-<date>/
./scripts/verify-image.sh         # 93 checks against the image just built
```

The build runs in aarch64 containers and needs **no root**: with podman
installed it uses rootless podman by default, so there is no daemon to start
and no group to join. `MOARCHY_CONTAINER=docker` forces the other engine;
`scripts/container.sh` documents what differs between them.

Everything comes from the commits pinned in `manifest.toml`, so two runs a
month apart produce the same image. The package build produces the
components (`moarchy-keyboard`, `moarchy-store-git`, `moarchy-keep`,
`moarchy-vitals`), the AUR rebuilds (`yay`, `xdg-terminal-exec`,
`ttf-ia-writer`, `cbonsai`, `lcl-gui-bin`, `mise-bin`), and `pkgbuilds/`
(`moarchy`, `omarchy-config`, `moarchy-meta`, `moarchy-keyring`, and a
`moarchy-device-*` per phone).

For a debug image that joins your wifi on first boot and enables sshd:

```bash
WIFI_SSID='MyNetwork' WIFI_PSK='secret' \
  MOARCHY_SSH_KEY=~/.ssh/id_ed25519.pub ./scripts/build-image.sh
```

Both are optional and both mark the image as a debug build. `MOARCHY_SSH_KEY`
authorises that key for the phone's account and enables `sshd`, which saves the
round trip through the card that a reflash otherwise costs -- SSH accepts keys
only, so there is no other way back in.

Do not publish either. The PSK is a secret; the key is not, but an
`authorized_keys` in a public image would have every phone that flashes it trust
one person's key. `./scripts/verify-image.sh` fails an image carrying either.

### Getting back in after a reflash

A reflash wipes `/home/moarchy/.ssh`, and the account has no password, so a
published image locks you out of your own phone until a key is authorised
again. Rather than pulling the SD card, type one line on the phone:

```bash
curl -sL https://raw.githubusercontent.com/SimonSchubert/moarchy/main/scripts/authorize-ssh.sh | sh -s <github-user>
```

That authorises every public key on `https://github.com/<github-user>.keys`,
enables `sshd`, and prints the phone's address and host-key fingerprint. The
username is required and has no default, for the same reason a published image
carries no `authorized_keys`.

### Developing against a phone you already have

```bash
./scripts/provision.sh build
./scripts/provision.sh deploy     # scp the packages over
./scripts/provision.sh install    # one pacman transaction
```

## What you get, and what you don't

Kept: Omarchy's keybindings, all 22 themes with live switching, the whole
quickshell shell — bar, launcher, notifications, OSD — the `omarchy-menu`
system, and the themed terminal/btop/fastfetch/starship stack.

Off by choice, not by limit: blur, shadows, rounded corners, compositor
animations and gradient borders. The Adreno GPU clears GLES 3.2, so Hyprland
could drive them, but `config/hypr/looknfeel.lua` disables them: every surface
that moves on this phone is a QML sheet following a finger, and a second
animation underneath fights it and costs battery. Lock is a themed `swaylock`
rather than `hyprlock` by the same kind of choice, not because `hyprlock` cannot
run here.

Dropped for other reasons: OCR capture (`tesseract` has no aarch64 build),
dictation (`voxtype` is x86-only), and every x86-only proprietary app (1Password,
Spotify, Obsidian, Typora). See the bottom of `pkgbuilds/moarchy-meta/PKGBUILD`
for the full list with reasons.

## Measured on the device

Numbers from a real Pixel 3a (SDM670, 4 GB), not estimates:

| | |
| --- | --- |
| GPU | Adreno 615 on freedreno — GLES 3.2 and Vulkan |
| Panel | 1080x2220, `scale 3` -> 360x740 logical |
| Storage | rootfs in `userdata`, grown on first boot |
| btop minimum | 60 columns, regardless of `shown_boxes` |

That last row is why `moarchy-launch-tui` drops TUIs to font size 7 (~60
columns): at Omarchy's desktop font size, btop simply refuses to draw on this
screen. The window is a normal tiled one — the bar and the keyboard anchor to
opposite edges, so neither costs a column, and a fullscreened terminal would
only hide the keyboard.

Wi-Fi, Bluetooth, sound, camera, vibration, NFC, calls with voice on them and
SMS in both directions are all measured on the handset rather than reported;
[`docs/devices.md`](docs/devices.md) D27–D34 is the evidence.

## Known limitations

- **Telephony has only been tried on an operator with circuit-switched
  fallback.** A VoLTE-only network needs an IMS stack that is not here yet —
  [`docs/devices.md`](docs/devices.md) §10.
- **The camera's colour profile is matrix-only** — no HueSatMap and no look
  table, so colour is correct rather than pleasing.

## Out of scope for now

Video recording (Megapixels' path wants GStreamer plugins nothing declares),
power tuning beyond the idle/blank path, and rotation *sensor* handling — the
control center's Rotate tile is manual.

The camera, telephony, suspend, the package repository and the on-screen
keyboard were all on this list and are not any more. The camera entry here read
"`VIDIOC_STREAMON` fails on both sensors" until 2026-09-06, and that was never
the problem: nothing was configuring the media graph, which is what
`libmegapixels` does. See [`docs/apps.md`](docs/apps.md).

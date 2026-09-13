# Apps

What ships on the phone, and what each one is for. The list itself lives in one
place — `depends` in `pkgbuilds/moarchy-meta/PKGBUILD` (`docs/structure.md` P5)
— and this file is the readable half of it: the apps, what they are, and the
criteria the terminal, the web apps and the camera are held to.

**Keeping it true.** An app that joins or leaves that `depends` moves a row
here in the same commit. Names without versions, deliberately: a version in a
table goes stale in silence and a package name does not.

Everything below runs on a **Pine64 PinePhone Braveheart (1.1)** — Allwinner
A64, 2 GB RAM, 720×1440 at `scale 2`, so a **360×720 logical** screen.
Screenshots are straight off the device via `grim`, uncropped, so the bar is
visible in each one.

Rows marked **†** are in the set but have not been launched on the device yet.
They are there on availability and fit; the dagger comes off when someone has
seen one run and taken a screenshot.

## Ours

| App | Package | What it is |
| --- | --- | --- |
| Keep | `moarchy-keep` | Notes and checklists. Pure Python on the GTK4/libadwaita stack the rest of the set already pulls in |
| Store | `moarchy-store-git` | Install and remove packages against a signed catalogue |
| foot | `foot` | The terminal, and the only one — see [One terminal](#one-terminal) |

**Wi-Fi**, **Bluetooth** and **Device** sit in the drawer beside these and are
not apps: they are screens the shell already holds, each with a desktop entry
that toggles a plugin (`default/omarchy/plugins/moarchy.*/`). Settings and
Themes have no entry at all — they open from the shade.

## GNOME (libadwaita)

These reflow to a phone width natively and are the most comfortable fit.

| App | Package | What it is |
| --- | --- | --- |
| Clocks | `gnome-clocks` | Alarms, timers, world clocks; bottom tab bar, fully adaptive |
| Text Editor | `gnome-text-editor` | Works well with the on-screen keyboard |
| Loupe | `loupe` | Image viewer, gesture zoom |
| Papers | `papers` | PDF viewer (Evince's successor) |
| Foliate | `foliate` | E-book reader; genuinely good on this screen |
| Portfolio | `portfolio-file-manager` | File manager built for touch. From `[danctnix]` |
| Maps | `gnome-maps` | Adaptive; reflows to 360px like the rest of the set |
| Web | `epiphany` | The browser — see [Browsers](#browsers) |
| Contacts † | `gnome-contacts` | The only app here that can *write* the store Calls and Chats read, so without it both show bare numbers forever |
| Geary † | `geary` | Email. `geary-mobile` is a dummy package; the plain build is the mobile one |
| Amberol † | `amberol` | Music. No library and no indexer daemon — it opens a folder and plays it |
| Secrets † | `secrets` | KeePass v4 `.kdbx` passwords, which Keysmith is not: that holds TOTP codes only |
| SongRec † | `songrec` | Shazam, fingerprinting locally. Its microphone path **cannot** work here ([Not working](#not-working)); recognition from a file or a PipeWire source does |

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

## Plasma Mobile (Kirigami)

KDE's mobile apps are the other family designed for this form factor, and they
run without a KDE session — they are ordinary Wayland clients under Sway.

| App | Package | What it is |
| --- | --- | --- |
| Kalk | `kalk` | Calculator with unit conversion |
| KWeather | `kweather` | Weather |
| Keysmith | `keysmith` | TOTP / 2FA codes |
| Calindori | `calindori` | Calendar |
| Alligator † | `alligator` | RSS. 0.9 MB, against newsflash's much larger Rust binary for the same job |

<p align="center">
  <img src="screenshots/apps/07-kalk.png" width="30%" alt="Kalk">
  <img src="screenshots/apps/09-kweather.png" width="30%" alt="KWeather">
  <img src="screenshots/apps/10-keysmith.png" width="30%" alt="Keysmith">
</p>
<p align="center">
  <img src="screenshots/apps/11-calindori.png" width="30%" alt="Calindori">
</p>

## Telephony, camera, reference

| App | Package | What it is |
| --- | --- | --- |
| Calls | `gnome-calls` | Dialer and in-call UI |
| Chats | `chatty` | SMS/MMS |
| Megapixels | `megapixels` | The camera, and the only one that works here — see [Camera](#camera). From `[danctnix]` |
| Linux Command Library | `lcl-gui-bin` | Qt6 command reference and cheat sheets, useful on a device whose terminal is 47 columns. Built from the pin in `manifest.toml`; not in ALARM |

`callaudiod` (earpiece/speaker/headset routing) and `mmsd-tng` (MMS transport,
from `[danctnix]`) come with the first two and have no UI of their own. Their
systemd units are replaced rather than enabled: both ship
`Requisite=gnome-session-initialized.target`, which under sway never exists, so
`pkgbuilds/moarchy` installs same-named units into `/etc/systemd/user`, which
wins over the `/usr/lib` copies.

Two web apps ship as well — **X** and **Discord**, entries rather than packages.
See [Web apps](#web-apps).

## Terminal tools

This is where the hardware is genuinely comfortable, and it is the Omarchy
idiom anyway. Two measured constraints shape it:

- A **terminal is 47×41 characters** at font size 9.
- **btop refuses to draw below 60 columns**, whatever `shown_boxes` says.

So `moarchy-launch-tui` opens TUIs at font size 7, which is ~60 columns. The
window is an ordinary tiled one: the bar anchors top and the keyboard anchors
bottom, so neither costs a column, and a fullscreened terminal only bought a few
rows in exchange for hiding both. For something that fits at the *default* font
size, use **`btm`** (bottom) — it adapts, and shows CPU, memory, all three
thermal zones, disks and network.

Also installed and worth knowing: `htop`, `lazygit`, `bluetui`, `wiremix`
(audio), `s-tui` (CPU frequency/temperature graphs).

**Wi-Fi is not a TUI.** The shade's tile and Settings both open `moarchy.wifi`,
a touch screen with a passphrase field — see `docs/shade.md` S6b.
`nmtui-connect` still works from a terminal, but its buttons cannot be pressed
with a finger. `impala` looks like the wifi TUI to reach for and is wrong twice
over: its buttons have the same problem, and it is an **iwd** client on a phone
running NetworkManager with `iwd.service` disabled — iwd is D-Bus activatable,
so impala starts it to fight NetworkManager for `wlan0` rather than failing
cleanly.

## Not installed by default

Every name below is available for aarch64 and left out on purpose.
`sudo pacman -S <name>` installs any of it; the reasoning per name is the
commented block at the foot of `pkgbuilds/moarchy-meta/PKGBUILD`.

| Package | Why not |
| --- | --- |
| `alacritty`, `qmlkonsole` | The second and third terminals, dropped 2026-09-08 — [One terminal](#one-terminal) |
| `kclock`, `index-fm` | A second clock and a second file manager, dropped 2026-09-06. Index drags the whole MauiKit stack in behind it |
| `spot-client` | Spot, a native Spotify client over librespot — the reason there is no Spotify *web* app here (B3) |
| `chromium`, `signal-desktop`, `libreoffice-fresh`, `nautilus`, `mpv`, `imv`, `kdenlive`, `gpu-screen-recorder` | Each is heavy for an A64 with 2 GB of RAM; none is needed for the phone to be a phone |
| `waydroid` | Android in an LXC container. `waydroid init` pulls a ~1 GB image on first run and then shares 2 GB of RAM and a GLES 2.0 Mali-400 — not something a dependency should commit a fresh phone to |

<p align="center">
  <img src="screenshots/apps/12-qmlkonsole.png" width="30%" alt="QMLKonsole">
  <img src="screenshots/apps/08-kclock.png" width="30%" alt="KClock">
  <img src="screenshots/apps/13-index-fm.png" width="30%" alt="Index">
</p>

## What limits app choice

Availability is *not* the constraint. Essentially the whole desktop catalogue is
built for aarch64 in Arch Linux ARM — Firefox, Chromium, GIMP, Inkscape,
LibreOffice, Signal, Telegram all install fine. Three other things decide
whether an app is usable:

1. **A 360×720 logical screen.** Desktop layouts do not reflow. The apps that
   work are the ones designed to adapt — GNOME's libadwaita apps and KDE's
   Kirigami/Plasma Mobile apps. Both families were built for phones, which is
   why the set above is drawn from exactly those two.
2. **2 GB of RAM.** Electron and Chromium will run and will hurt.
3. **`*-bin` AUR packages are usually dead.** They ship prebuilt x86_64 binaries
   by definition. `braincup-bin`, for example, ships
   `Braincup-3.5.0-linux-x86_64.tar.gz` and has no source PKGBUILD — there is
   nothing to rebuild for ARM. Check for a non-`-bin` package before assuming
   an app is available.

## Removing one

Long-press an icon in the app drawer. The card that opens says what the app is
and which package it came from; Uninstall then shows what `pacman` would
actually take — every package in the transaction and the total size — before
anything runs, and Remove does it with no terminal and no prompt. The rules for
what may not go are [`gestures.md` section L](gestures.md): the shell will not
uninstall itself, and nothing another installed package needs can be removed.

Everything in the tables above is in `moarchy-meta`'s `depends`, so an upgrade
of that package pulls a removed app back in — pacman resolves an upgraded
package's dependencies. The card says so when it applies rather than letting it
be a surprise on the next `pacman -Syu`.

## One terminal

The phone shipped three until 2026-09-08, and they were not three choices so
much as one engine and two entries in the drawer beside it:
`bin/moarchy-launch-tui` execs `foot` *by name* and `pkgbuilds/moarchy` declares
it, so every TUI, every agent window, the config editor and the removal prompt
were foot already. `alacritty` cost 7.75 MiB — eight times the other two
together — to be an OpenGL terminal on a GLES 2.0 Mali-400 that nothing
launched, and `qmlkonsole`'s 935 KiB had won the xdg default by being the only
`TerminalEmulator` that claimed it, which is why `omarchy-launch-about` answers
`Unknown option 'render'`.

Verified on touch before the other two were dropped: foot turns a tap into a
left-button click (`man 1 foot`, TOUCHSCREEN), which is what the shade's TUI
cards already rely on.

**T1** One terminal is installed. `alacritty` and `qmlkonsole` are not in the
package set, and nothing pulls them in behind it.
→ `pacman -Qq foot` succeeds; `pacman -Qq alacritty qmlkonsole` finds neither

**T2** foot is the default terminal, and `xdg-terminal-exec` resolves rather
than hangs. Those are one fact, not two: the hang measured on 2026-09-07 was a
missing `~/.config/xdg-terminals.list`, and that file is exactly what naming a
default writes. Until it existed, `$mod+Return` and `bin/moarchy-launch-files`
both hung on the first candidate in their own fallback chain.
→ `omarchy-default-terminal` prints `foot`, and `xdg-terminal-exec --print-id`
prints `foot.desktop` and exits 0 rather than timing out

**T3** The drawer shows one terminal, not three — and this one is *already
true*, which is why it is written down. `foot` ships `foot.desktop`,
`footclient.desktop` and `foot-server.desktop`, all three `TerminalEmulator`
and none of them `NoDisplay`, so dropping two packages looked like it would
leave three tiles behind. Upstream Omarchy hides both by id in
`/usr/share/omarchy/default/omarchy/launcher.hides` (`btop` is in there too),
which `AppLibrary` reads into `configuredHiddenEntryIds`. Nothing here
implements it; the criterion exists because a `launcher.hides` that loses those
lines is a regression nobody would look for.
→ `omarchy-shell drawer entries` holds `foot` and holds neither `footclient`
nor `foot-server`

> A `NoDisplay` copy in `~/.local/share/applications` was written to do this job
> and then deleted, because measuring it showed it changed nothing — and the
> first measurement was broken in a way worth remembering.
> `desktopHiddenEntryIds` is recomputed only on `appsChanged`, and removing a
> `NoDisplay` file changes nothing in `DesktopEntries.applications`, so no
> rescan fires and the answer comes from a cache built while the masks existed.
> Cloning `footclient.desktop`'s bytes under a new id settled it: the clone
> appeared, so the filter is on the id.

**T4** Settings offers the terminals that exist. The Alacritty choice row hides
itself, and the Install Alacritty row stops being permanently hidden and
becomes a live offer — the same rows, guarded the same way, answering a
different truth.
→ `settings rowsOn apps.default.terminal` holds `foot` and not `alacritty`;
`settings rowsOn apps.packages.more` holds `alacritty`

**T5** The drawer still refuses to remove the terminal. `pkgbuilds/moarchy`
declares `foot`, and it is now the only terminal there is to lose.
→ `moarchy-app-remove plan foot` reports a blocker (selftest L12a)

**T6** Nothing seeds a config for a terminal that is not installed.
→ `~/.config/alacritty` is not created, and `moarchy-user-setup` logs no
missing file for it

## Browsers

**Epiphany** (`epiphany`) is the one to reach for — WebKit, ~260 MB, and it has
a genuinely adaptive mobile layout with the URL bar at the bottom. Firefox and
Chromium both install and run, but cost far more memory for no layout benefit.

Heavy SPAs are the real problem, not the browser. x.com loads but paints poorly
and leaves large black regions — that is the workload against a 1.15 GHz A53 and
a GLES 2.0 GPU, not something configuration fixes.

### Web apps

A site a phone treats as an app: its own window with no browser chrome, its own
name and icon on a recents card, its own entry in the drawer. Ids are `B<n>`.

**B1** A web app opens as a window of its own site: no tab strip, no
bookmarks, no other site reachable from it, and its own cookies and login.
Epiphany's `--application-mode` is the equivalent of the `--app=` upstream's
launcher assumes, and it needs a `--profile` with it or every launch starts
logged out.

**What it does not remove is Epiphany's own bottom bar** — the site title, the
URL, back, forward and a ⋮ menu. There is no key for it: `org.gnome.Epiphany.ui`
offers only `bottom-url-bar` (where, not whether), and `.lockdown` disables
actions rather than chrome. Epiphany *does* hide it in the fullscreen state,
which is how the Hyprland sibling gets a bare window — its compositor can tell a
client it is fullscreen while still laying it out under the bar. **Sway has no
fake fullscreen**, and the real thing is ruled out by `windows.md` W5: a
fullscreen window on sway draws above the Top layer and ignores exclusive zones,
so it takes the status bar, the launch splash, and the band the on-screen
keyboard reserves. So the win here is the window and its identity (B2), not a
bare canvas.
→ launched from the drawer, the window is Epiphany's web-app window: no tab
strip, and `org.gnome.Epiphany.WebApp_<slug>` is its own profile

**B2** Each web app is its own window identity. The profile directory's
basename becomes the window's app id — `org.gnome.Epiphany.WebApp_x_com` — and
the entry names it in `StartupWMClass`, which is what gives the recents card
and the shade's notification card (`shade.md` S25) a name and an icon to take.
Without it a web app's card reads `org.gnome.Epiphany.WebApp_x_com`, and two
web apps sharing one profile would collapse into a single card.
→ `swaymsg -t get_tree` reports one `app_id` per web app, each matching its
entry's `StartupWMClass`; `omarchy-shell recents list` names the app

**B3** The drawer carries **X** and **Discord** from first boot, with their own
artwork. Both are upstream's own entries and upstream's own icons; nothing on
this phone ever copied either into a place the drawer or an icon theme reads,
so the package installs them.

Not Spotify, which is where this parts company with the desktop and with
[omarchy-mobile](https://github.com/SimonSchubert/omarchy-mobile): there is no
Widevine for aarch64 Linux in any repo, so the web player answers "Playback
disabled" in every browser on this phone. Spotify here is **Spot**, a native
client over librespot, from the repo (`manifest.toml`, `[aur.spot-client]`).
Every other web app upstream ships an entry for — WhatsApp, YouTube, Zoom, the
Google ones — installs with `omarchy-webapp-install` and needs nothing from
this project.
→ `omarchy-shell drawer entries` lists `X` and `Discord` — the entries are
named by id, without the `.desktop`, like every other row

**B4** The phone asks the web for a phone's version of itself. WebKitGTK's own
agent says `X11; Linux aarch64`, which is a desktop, and a site that branches
on the agent rather than on a media query serves one — the layout that is
clipped on the right in a 360px window. The override is the schema's default,
not a write into anyone's dconf, and `org.gnome.Epiphany.web` is relocatable,
so one stanza reaches the browser and every web app profile at once. A user
who wants one site back on the desktop layout overrides that profile's key.

An iPhone, not an Android: Epiphany is WebKitGTK, so a site that branches on
the agent should be handed the code it tests against WebKit rather than the
Blink path.
→ `gsettings get "org.gnome.Epiphany.web:/org/gnome/epiphany/web/" user-agent`
names a Mobile agent. The path is not optional: the schema is relocatable, and
naming it without one answers "is relocatable (path must be specified)" rather
than a value — which is a check that fails for the wrong reason

**B5** Installing a Chromium-family browser gets upstream's behaviour back.
The launcher's Chrome-family branch is upstream's, unchanged and first; only
the fall-through is ours. What it must never do is upstream's own ending,
which rewrites every non-Chrome browser to `chromium.desktop` and then execs a
command with no program in it when chromium is not installed — silently, which
is how every web app tile on this phone did nothing at all.
→ with no Chromium-family browser installed, `omarchy-launch-webapp
https://x.com/` still opens a window

## Camera

**Megapixels** is the camera app. Verified on the device on 2026-09-06: both
sensors stream, the camera switch works, the flash toggles, and a shutter press
captures a three-frame burst at the rear sensor's full 2592×1944.

The reason it works where nothing else does is `libmegapixels`, which ships a
`pine64,pinephone.conf` describing this device's media graph and **configures
the links itself** before streaming. `sun6i-csi` on 6.18 requires that, and a
generic app never does — which is the whole of the old "`VIDIOC_STREAMON` fails
— pipeline links unconfigured" entry, and why **`snapshot` and `plasma-camera`
cannot work here** at all.

`megapixels-findconfig` auto-detects from the devicetree (`pine64,pinephone-1.1`):

| | Sensor | Flash | Modes |
| --- | --- | --- | --- |
| Rear | `ov5640` | LED, `/sys/class/leds/white:flash/flash_strobe` | 2592×1944@15, 1280×720@30 (BGGR8 / YUYV) |
| Front | `gc2145` | screen | 1280×720@60 BGGR8 |

The camera switch was confirmed against the media graph rather than by eye —
tapping it flips which sensor link to `sun6i-csi-bridge` is `[ENABLED]`.

Three things bite:

1. **`xdg-user-dirs` is required, and `megapixels` does not declare it.**
   Without it `~/Pictures` never exists and every photo is captured and then
   **silently thrown away** at the last step — the burst goes to `/tmp` first,
   so the failure appears only after the shutter animation and the app reports
   nothing. `moarchy-meta` declares it; a hand-built system has to add it.
2. **The flash permission does not survive a reboot on its own.** The shipped
   `90-megapixels.rules` chmods `flash_strobe` on `ACTION=="add"` only, and the
   LED is added at boot before the rule exists. `moarchy-led-perms.service` runs
   `udevadm trigger --subsystem-match=leds` after `systemd-udevd` on every boot
   rather than editing someone else's udev rule.
3. **The preview is software-rendered, by Megapixels' own choice.** It matches
   the devicetree and forces `LIBGL_ALWAYS_SOFTWARE=1`, so the GLES preview runs
   on the A53s, not the Mali. Usable, but the log fills with `Dropping frame`.

Unverified: whether the flash physically fires, and video recording. Megapixels
ships `movie.sh` → `mpegize.py`, which is GStreamer `x264enc
speed-preset=ultrafast` into `~/Videos/VID*.mkv` — software H.264, since the
A64's `cedrus` is decode-only. Audio would be silent regardless while the
microphone records RMS 0, and video needs `python-gobject`,
`gst-plugins-good` and `gst-plugins-ugly`, none of which `megapixels` declares
(they are `moarchy-meta`'s `optdepends`).

## Not working

| | |
| --- | --- |
| **Microphone** | Records digital silence (RMS 0) at PipeWire *and* raw ALSA, despite `Mic1` on, boost 7, `ADC` 144/192 and `AIF1 Slot 0 Digital ADC` enabled. This is what stops SongRec's headline feature |
| ~~Camera~~ | **Works as of 2026-09-06** — see [Camera](#camera). It still reboots the phone on the *first* launch after a boot; second and later launches are fine, and the cause is undiagnosed |
| Audio **output** | Works |
| Hardware video decode | `cedrus` present at `/dev/video1`, unexplored |

See [`build-log.md`](build-log.md) for how the device was set up and what else is
known-broken.

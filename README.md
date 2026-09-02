# mobileomarchy

Omarchy's look, keybindings and theming on an original **PinePhone**, running on
Arch Linux ARM (DanctNIX) with **Sway** in Hyprland's place.

This is not a fork of Omarchy's installer. It is a thin overlay that vendors
Omarchy's *configuration and theme layer* — which is architecture-neutral — onto
an aarch64 base, and replaces the one part that cannot work on this hardware.

## Why not just run Omarchy?

Two hard blockers, both verified rather than assumed.

**1. Hyprland cannot run on this GPU.** Hyprland's renderer includes
`<GLES3/gl32.h>` and aborts if it cannot get a GLES 3.x context:

```
src/render/OpenGL.cpp:215  WARN  "EGL: Failed to create a context with GLES3.2, retrying 3.0"
src/render/OpenGL.cpp:228  RASSERT(false, "EGL: failed to create a context with either GLES3.2 or 3.0")
```

The PinePhone's Allwinner A64 has a Mali-400 MP2 driven by Lima, which tops out
at **OpenGL ES 2.0**. That is a hardware limit, not a driver gap, and Hyprland
0.50 removed the legacy GLES2 renderer that would have been the last way around
it. Sway (wlroots, GLES2) runs fine.

*(A PinePhone **Pro** is a different story: its Mali-T860 does GLES 3.1 under
Panfrost, which clears Hyprland's floor. `install/preflight.sh` detects and says
so.)*

**2. Omarchy's package repo is x86_64-only.**

```
https://pkgs.omarchy.org/stable/x86_64/omarchy.db  ->  200  (211 packages)
https://pkgs.omarchy.org/stable/aarch64/omarchy.db ->  404
```

`install/preflight/guard.sh` upstream also requires x86_64, limine, a btrfs root
and vanilla-Arch markers — none of which hold on a PinePhone.

## What ports cleanly, and why

Omarchy 4.x generates its per-app theming from one small file per theme,
`colors.toml`, expanded through `default/themed/*.tpl` by
`omarchy-theme-set-templates`. The Hyprland template is **8 lines** — it sets a
border colour and nothing else.

So the entire theme system ports by adding **one file**:
[`default/themed/sway.conf.tpl`](default/themed/sway.conf.tpl). All **19**
upstream themes then work on Sway with no per-theme effort, and
`waybar.css.tpl`, `mako.ini.tpl`, `alacritty.toml.tpl`, `foot.ini.tpl`,
`btop.theme.tpl`, `walker.css.tpl` and `swayosd.css.tpl` are reused untouched.

Better still, that template engine already processes a *user* template directory
(`~/.config/omarchy/themed`) ahead of its own built-ins — so mobileomarchy adds
Sway theming **without patching the vendored upstream at all**.

## Pinned to Omarchy v3.8.4 (deliberately)

Omarchy 4.x rebuilt its whole shell layer. At v4.0.0 upstream dropped
`config/waybar`, `config/walker`, `config/elephant`, `config/swayosd` and
`config/fastfetch`, deleted the `waybar.css` / `mako.ini` / `walker.css` /
`swayosd.css` / `hyprland.conf` templates, and moved to **herdr** — a bespoke
shell shipped only as an x86_64 binary in `pkgs.omarchy.org` — plus a Lua-based
Hyprland config (`default/themed/hyprland.lua.tpl`).

Neither is portable to this device: herdr has no aarch64 build, and a Lua
*Hyprland* config is worthless on hardware that cannot run Hyprland.

**v3.8.4 (`8fcc9d6`) is the last release built on waybar + walker + mako +
swayosd**, all of which either ship for aarch64 or are Go programs we can build.
Tracking 4.x is a separate porting project, not a version bump.

## Layout

| Path | What it is |
| --- | --- |
| `install.sh`, `install/` | On-device installer. Never invokes upstream's. |
| `mobileomarchy-base.packages` | aarch64 package set, with every omission explained |
| `default/sway/bindings.conf` | Omarchy's bindings, translated to Sway, key-for-key |
| `default/sway/pinephone.conf` | 720×1440 @ scale 2, touch, tightened gaps |
| `default/themed/sway.conf.tpl` | The one file that themes Sway from any Omarchy theme |
| `bin/mobileomarchy-*` | Sway counterparts to Omarchy's Hyprland helpers |
| `bin/omarchy-*` | Shims with upstream's names, so `omarchy-menu` keeps working |
| `docker/` | aarch64 container that builds walker/elephant/yay natively on Apple Silicon |
| `scripts/flash-sd.sh` | Guarded SD-card flasher for macOS |

## Install

**1. Flash the card** (on the Mac):

```bash
./scripts/flash-sd.sh /dev/diskN     # run `diskutil list` first to find N
```

**2. Boot and get a shell.** The DanctNIX barebone image exposes SSH over USB
networking, so no OTG keyboard is needed:

```bash
ssh alarm@10.15.19.82        # password 123456; root password root
```

Change both passwords, then `sudo nmtui` to join wifi.

**3. Build the missing packages** (optional but recommended — on the Mac, where
an aarch64 container runs natively):

```bash
docker build --platform linux/arm64 -f docker/Dockerfile.builder -t mobileomarchy-builder .
docker run --rm -v "$PWD/packages:/out" mobileomarchy-builder
scp packages/*.pkg.tar.zst alarm@10.15.19.82:~/
```

Skip this and `install/build-src.sh` builds on the phone instead — slow, and it
falls back to `fuzzel` if `walker` will not build, so `SUPER+SPACE` is never dead.

**4. Install:**

```bash
git clone <this repo> ~/.local/share/mobileomarchy
~/.local/share/mobileomarchy/install.sh
```

## What you get, and what you don't

Kept: Omarchy's keybindings, all 19 themes with live switching, waybar (trimmed
to a phone-width module set), mako, walker, the `omarchy-menu` system, and the
themed terminal/btop/fastfetch/starship stack.

Gone, because they are Hyprland renderer features that a GLES 2.0 device could
never have driven: blur, shadows, rounded corners, animations, gradient borders,
`hyprlock` (replaced with a themed `swaylock`).

Also dropped: universal copy/paste (Hyprland `sendshortcut` has no Sway
equivalent), OCR capture (`tesseract` has no aarch64 build), dictation
(`voxtype` is x86-only), and every x86-only proprietary app — 1Password, Spotify,
Obsidian, Typora. See the bottom of `mobileomarchy-base.packages` for the full
list with reasons.

## Measured on the device

Numbers from a real PinePhone (Allwinner A64, 2 GB), not estimates:

| | |
| --- | --- |
| GPU | `Mali400`, `OpenGL ES 2.0 Mesa 26.2.1` — Hyprland's 3.0 floor is unreachable |
| Panel | DSI-1 720x1440, `scale 2` -> 360x720 logical |
| Fullscreen terminal | 47x41 characters at font size 9 |
| btop minimum | 60 columns, regardless of `shown_boxes` |

That last pair is why `mobileomarchy-launch-tui` drops TUIs to font size 7 (~60
columns) and opens them fullscreen: at Omarchy's desktop font size, btop simply
refuses to draw on this screen.

## Out of scope for now

Telephony (calls, SMS, ModemManager), auto-rotation, suspend/power tuning, and
the camera. The on-screen keyboard (`squeekboard`) is in
`mobileomarchy-extras.packages` and is the least proven piece under bare Sway.

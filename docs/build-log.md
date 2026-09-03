# Build log

How this went from a blank SD card to Omarchy running on a PinePhone, including
the parts that failed. Written after the fact but from real command output —
where a number appears, it was measured on the device.

Host: macOS on Apple Silicon. Target: **Pine64 PinePhone Braveheart (1.1)** —
Allwinner A64, 4× Cortex-A53 @ 1.15 GHz, 2 GB RAM, 720×1440.

---

## 0. The two findings that determined everything

Both were checked before any code was written, and both are the reason this is a
port rather than an install.

**Hyprland cannot run on this device.** Its renderer includes `<GLES3/gl32.h>`
and aborts without a GLES 3.x context:

```
src/render/OpenGL.cpp:  RASSERT(false, "EGL: failed to create a context with either GLES3.2 or 3.0")
```

Measured on the phone afterwards:

```
OpenGL ES profile renderer: Mali400
OpenGL ES profile version:  OpenGL ES 2.0 Mesa 26.2.1
```

GLES **2.0**. Hyprland 0.50 also removed the legacy GLES2 renderer, so there is
no version that works. The compositor had to be **Sway** (wlroots, GLES2).

**Omarchy's package repo is x86_64-only:**

```
https://pkgs.omarchy.org/stable/x86_64/omarchy.db  -> 200
https://pkgs.omarchy.org/stable/aarch64/omarchy.db -> 404
```

Its installer also requires limine, btrfs and Snapper. So none of upstream's
installer is used — only its architecture-neutral config/theme layer, vendored.

---

## 1. Base OS

DanctNIX Arch Linux ARM (`archlinux-pinephone-barebone-20251224.img.xz`) flashed
to SD, then a full upgrade: **175 packages, `linux-megi` 6.15.6 → 6.18.39**,
rebooted cleanly in ~20 s.

Two traps on the way:

- **`dd: Permission denied`, even with sudo.** Not permissions — the SD adapter's
  physical write-protect switch. `diskutil` reports `Media Read-Only: Yes` and the
  device node is mode `r--r-----`, so even root is refused. `scripts/flash-sd.sh`
  now checks this up front instead of failing after a password prompt.
- **macOS `sudo` needs a tty**, and a `read` prompt under `set -e` dies *silently*
  on EOF — indistinguishable from a flash that did nothing.

## 2. Getting a shell: USB does not work from a Mac

DanctNIX's USB gadget presents **RNDIS**, and macOS ships no RNDIS driver. The
phone enumerates (`ioreg` shows `DanctNIX / "Arch Linux Mobile"`) but no network
interface ever appears. The descriptor says it plainly:

```
UsbDeviceSignature = <... 02 02 ff ...>     02/02/ff = RNDIS
                                            02/06/00 would be CDC-ECM
```

`scripts/patch-image.sh` rewrites the gadget to CDC-ECM before flashing, editing
the image's ext4 rootfs with `debugfs` — no VM, no root, no loop mounts. It
verifies `usb_f_ecm` is in the kernel's `modules.builtin` first.

That got macOS to bind `en9` and dmesg to show a matching `HOST MAC` — but the
gadget side stays `NO-CARRIER`, because macOS never selects alt-setting 1 on the
ECM data interface. **Wifi is the working transport.** The same script can
preseed a NetworkManager profile, which is what actually got us in.

## 3. Packages

Most of the stack exists for aarch64. What does not:

| | |
| --- | --- |
| Built from source on the Mac | `walker`, `elephant`, `yay`, `xdg-terminal-exec`, `ttf-ia-writer` |
| Dropped, x86-only | 1Password, Spotify, Obsidian, Typora, dotnet |
| Dropped, no aarch64 build | `tesseract` (OCR capture) |

Docker Desktop runs `linux/arm64` natively on Apple Silicon, so these build in
minutes rather than at A53 speed. Two non-obvious requirements, both now in
`docker/Dockerfile.builder`:

- Docker Desktop's VM kernel has **no Landlock**, which pacman 7 uses to sandbox
  downloads — every `pacman -Sy` fails with `switching to sandbox user 'alpm'
  failed`. Needs `DisableSandbox`, **inserted under `[options]`**; appending puts
  it in the trailing `[aur]` section where pacman silently ignores it.
- Arch Linux ARM's `makepkg.conf` does not use `PKGEXT=.pkg.tar.zst` — output is
  `.pkg.tar.xz`. Set `PKGDEST`; never glob for an extension.

## 4. The port itself

The load-bearing discovery: Omarchy generates all per-app theming from one
`colors.toml` per theme, and `omarchy-theme-set-templates` **already reads a user
template directory** (`~/.config/omarchy/themed`) ahead of its built-ins. So
adding a single `sway.conf.tpl` themes Sway from every theme **without patching
the vendored upstream at all**.

The rest was mechanical: ~100 keybindings translated key-for-key, and Sway
counterparts for Omarchy's Hyprland helpers. One shim turned out to be
load-bearing — **`uwsm-app`**, which 16 vendored scripts invoke; without it
`SUPER+SPACE`, the editor and background switching all silently did nothing.

Result: `sway -C` passes, **19/19 themes generate valid Sway config**, session
autologins on tty1.

## 5. Omarchy 4.x

An earlier version of this document claimed 4.x was unreachable because it "moved
to herdr, an x86-only shell". **That was wrong twice over**: herdr is a Rust
terminal workspace manager, not the shell, and it is Apache-2.0 with public
source.

4.x's shell is **95 QML files in Omarchy's own repo**, rendered by
**quickshell** — which is packaged for aarch64 and *does* render on a Mali-400.
`Quickshell.I3` mirrors the Hyprland singleton for everything the shell uses, so
the translation is mechanical (`install/port-4x.sh`):

| 4.x uses | Sway equivalent |
| --- | --- |
| `import Quickshell.Hyprland` | `import Quickshell.I3` (5 files) |
| `HyprlandEvent` | `I3Event` |
| `target: Hyprland` | `target: I3` — a *bare* singleton reference a dot-anchored regex misses |
| `.workspaces`, `.focusedWorkspace`, `.focusedMonitor`, `onRawEvent` | identical names |
| `HyprlandFocusGrab` | **no counterpart** — neutralised, so popups lose click-outside-dismiss |

Plus: **`SWAYSOCK` must be exported** or the bar draws but never populates, and
the shell shells out to `hyprctl` for two layout metrics, needing a shim.

Three further bugs a bare import swap does not catch, all in the workspaces
widget:

- `occupied` read `workspace.toplevels` — Hyprland-only. Sway carries the same
  information in the IPC object's `representation`.
- `focusWorkspace` dispatched through `hyprctl`, so **tapping a workspace did
  nothing**.
- **Hyprland's workspace `.id` *is* the visible number; sway's `.id` is an
  internal handle** and the number lives in `.number`. Comparing `.id` against
  1/2/3 meant the focused workspace never matched, and the internal id leaked in
  as a phantom entry.

Omarchy's own `omarchy-update` can never work here: 4.x ships Omarchy as a
package from the x86_64-only repo, and the updater wants Snapper/btrfs.

## 6. Phone-shaped tuning

Measured, not guessed:

| | |
| --- | --- |
| Panel | 720×1440, `scale 2` → **360×720 logical** |
| Fullscreen terminal | **47×41 characters** at font size 9 |
| btop minimum | **60 columns**, regardless of `shown_boxes` |

Hence `mobileomarchy-launch-tui` runs TUIs fullscreen at font size 7. `btm`
(bottom) is the system monitor that *does* fit a normal tiled terminal, so the
bar stays visible.

The bar is centre-anchored on the clock, so the clock's width decides where every
module sits. Upstream's `dddd HH:mm` changes width with the day name and shifted
the whole bar; `HH:mm` is fixed width. `omarchy.indicators` and
`omarchy.system-update` were dropped for the same reason — they appear and vanish.

Two things worth knowing about this hardware:

- **Never `pkill swaylock`.** Under `ext-session-lock` the compositor stays locked
  with no client to authenticate against, and sway paints a solid red screen.
  Recover by restarting sway.
- **No idle lock.** A layer-shell keyboard cannot draw over an `ext-session-lock`
  surface, so an idle lock leaves a touch-only device unrecoverable.

## 7. Hardware status

| | |
| --- | --- |
| Display, touch, wifi, bluetooth | working |
| Audio **output** | working — sink present, streams play |
| **Microphone** | **not working** — records digital silence (RMS 0) at PipeWire *and* raw ALSA, despite `Mic1` on, boost 7, `ADC` 144/192 and `AIF1 Slot 0 Digital ADC` on |
| **Camera** | sensors register (`ov5640` rear, `gc2145` front) but `VIDIOC_STREAMON` fails — pipeline links unconfigured |
| Hardware video decode | `cedrus` present at `/dev/video1` |

## 8. Known-bad / open

- **Compositor renders only the background layer** in some states: sway tracks
  windows and the bar reserves its exclusive zone (`foot y=27`), but nothing above
  swaybg paints. First seen after running a browser; a reboot cleared it once,
  then it recurred and persisted. Not root-caused.
- `HyprlandFocusGrab` stubbed out — menus do not dismiss on tap-outside.
- `I3.workspaces` shape differs from Hyprland's in ways not fully explored.

The v3.8.4 (waybar-based) port on `main` ran stably for hours and is the fallback.

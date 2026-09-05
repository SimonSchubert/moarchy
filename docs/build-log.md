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

## 6b. The phone shell: bar, drawer, shade, settings, themes

Five Quickshell plugins in `default/omarchy/plugins/`, alongside the gesture
strip that was already there, and no patches to the vendored shell. The plugin
contract already covered every shape they needed.

The shape the UI settled into: **the drawer launches things, the shade changes
them.** Everything the Omarchy menu reaches that is not an app -- Setup,
Install, Remove, Update, Keybindings, About, System -- lives in a settings list
behind the shade's gear, and the drawer is a search field and a grid of apps
and nothing else. An early version put four of those routes across the top of
the drawer; on a screen that fits four icons across, a row of controls is a row
of apps you cannot see, and it put `Remove` one mis-tap from launching
something.

**Bar replacement is a first-class operation.** `shell.qml` reads
`shell.json`'s `bar.id`, loads that plugin's `bar` entry point, and deactivates
`omarchy.bar`. On a load error it logs one `console.warn` and silently falls
back. Measured: RSS drops from **414 MB to 361 MB** when the desktop bar's
thirteen widgets — four of them large popup panels — stop being instantiated.

**The two plugin kinds are enabled by different keys**, and crossing them is a
silent no-op. `PluginRegistry.isEnabled()` short-circuits for a `kind: "bar"`
plugin and answers purely from `bar.id`; everything else falls through to
`findEntryLocation()`, which only finds `{"id": ...}` entries in `plugins[]`.
A bar listed in `plugins[]` is inert; an overlay set as `bar.id` is invisible.

**Layer arrangement, measured rather than assumed.** Sway places
exclusive-zone surfaces first, top layer down, then arranges everything else
into what is left. So:

| Surface | Layer | Zone | Result |
| --- | --- | --- | --- |
| bar | Top | Auto (26px) | reserves the top |
| gestures strip | Overlay | Auto (20px) | keeps the bottom edge above squeekboard |
| drawer | Top | **Normal, 0** | arranged *into* the usable area — below the bar, above the home pill, and **above squeekboard when it rises**, with no geometry maths |
| shade | Overlay | Ignore | covers everything, which is what a pull-down is |

The drawer's zero exclusive zone is the whole reason its search field works:
focus it and the grid re-flows above the keyboard instead of being buried by
it. Confirmed with `swaymsg -t get_workspaces` — the focused workspace stays
`y=29 h=668` whether the drawer or the shade is open, so neither reserves
anything.

**The shade grows its surface rather than being permanently full-screen.** The
usual drag-to-reveal is an always-mapped full-screen surface masked down to a
strip, which leaves a 720x1440 blend in every frame forever on a Mali-400.
Instead the surface anchors top/left/right only, so `implicitHeight` owns its
size: 26px until a finger moves, then one resize to full screen, then the drag
is a child item's `y`. Wayland's implicit grab is per-surface, not
per-geometry, so the in-flight touch survives the resize.

**Why the phone bar has no tap targets.** The shade's grab strip is on Overlay
and covers the bar's top 26px, so a button on that bar would never receive a
touch and the cause would not be anywhere near it. This is forced by the
layering, not a style choice.

**Three traps, each of which fails silently:**

- A host-injected property must not be `readonly` *or* `required`. Readonly
  makes the assignment throw; required makes the component fail to instantiate,
  because a plugin is created by a `Loader` and configured afterwards in
  `onLoaded`. The first-party `omarchy.bar` can use `required` only because the
  host constructs it inline.
- `\uXXXX` in QML takes **exactly four** hex digits. Writing the wifi glyph
  as `"8"` yields U+F092 followed by a literal `8`, and `"\U000F0928"`
  -- a form JavaScript does not have -- yields a literal `U`. Every Nerd Font
  MDI glyph is above the BMP, so they go into the source as literal
  characters, the way the vendored shell's own `Model.js` does it. The
  symptom is one wrong glyph on screen and nothing in the log.
- **A property named `on<Uppercase>` is never readable.** QML reserves that
  prefix for signal handlers, so `readonly property color onSurface: ...`
  declares something that cannot be read back: the binding evaluates to
  undefined, undefined assigned to a `color` is `#000000`, and **nothing is
  logged**. Written the Material way -- `onSurface`, `onAccent` -- every glyph
  and label bound to them painted pure black on a dark tile, while `container`
  and `subdued` two lines above worked fine. Sampling the pixels is what found
  it: the glyphs were `(0,0,0)` exactly, not the theme's near-black background,
  and a colour that is *exactly* zero is a value nobody chose. They are
  `textOnSurface` / `textOnAccent` now.
- Closing a surface is not a text-input deactivate. Dismiss the drawer straight
  from its search field and squeekboard stays up over whatever is underneath.
  `focus = false` is not enough — that releases the focus *scope*. Handing
  active focus to a plain sink `Item` is what makes Qt send the disable.

**The theme picker was almost free.** `omarchy-theme-set` already ends by
calling `omarchy-shell shell applyTheme` with the new palette, and the shell's
`Color` singleton reloads in place — so the bar, drawer, shade and the picker
itself recolour live, with the picker doing nothing about it. What it does have
to handle is that regenerating every app's template takes **~7 s** on an A53:
the tapped card stays lit while the rest of the grid dims, and a second tap is
refused rather than queued behind `omarchy-theme-set`'s lock.

Each card is painted in the theme it names, from that theme's `colors.toml`.
Not from the `preview.png` every theme ships: those are 1800x1012 desktop
screenshots at ~440 KB, and twenty-two of them decoded at once is more than
this phone has spare — quite apart from being illegible at 166px wide. Two
things about the current theme are easy to get wrong: `current/theme` is a
staged **copy**, not a symlink, so its basename is always the literal string
`theme`; the slug lives in `current/theme.name`. And `omarchy-theme-set` takes
the **display** name, so the slug has to be title-cased exactly the way
`omarchy-theme-list`'s sed does it or the lookup misses.

**The drawer follows the finger, and getting there cost three mechanisms.**
The bottom strip belongs to the gestures plugin -- an edge belongs to one layer
surface -- so the drawer never sees the opening touch. The gestures plugin
resolves the drawer's live instance once per gesture through
`shell.panelLoaders[id].item` and writes its `progress` directly; a
`shell.callIfLoaded` round-trip marshals a string per call and this runs at
touch-event rate. Measured, an open drag leaves 25-45 samples: a ramp, not a
jump.

Closing needed a different mechanism, and two attempts failed for reasons worth
recording:

- **The gesture strip cannot host it.** It *is* the bottom edge of the screen,
  so a downward drag has about twenty pixels before it runs off the panel --
  the same reason the shade cannot be closed by dragging up from its handle.
- **The grid cannot supply it.** The plan was to let the GridView be dragged
  past its top and follow the overscroll. But with the apps this phone has,
  `contentHeight` measures **516** against a **598** view: a Flickable whose
  content fits does not drag at all, so `contentY` never leaves 0 and there is
  nothing to follow. It worked once by accident and never again.
- **A `DragHandler` over the sheet cannot either.** It delivers **one**
  translation event for an entire gesture here, because the app delegates'
  `MouseArea`s hold the exclusive grab and the handler only ever gets a passive
  one. It also has to be spelled `onTranslationChanged`: `activeTranslation`
  and `persistentTranslation` share a single NOTIFY signal, and QML names the
  handler after the signal, so `onActiveTranslationChanged` silently never
  runs -- the handler activates, the sheet does not move, nothing is logged.

What works is the mechanism the rest of this UI already uses: a
`MultiPointTouchArea` on a strip of its own -- a handle bar across the top of
the sheet. The surface it covers is its input region, the implicit grab keeps
the whole gesture on it, and it cannot compete with a tap on an app icon
because it does not overlap one.

**Changing `keyboard_interactivity` mid-gesture cancels the touch.** The
drawer's `keyboardFocus` was gated on `opened`, which is
`progress >= 1 && !dragging` -- so it went false on the *first frame* of the
close drag. That drops the layer surface to `None`, sway hands keyboard focus
back to a window, and the focus change cancels the touch the surface is still
holding. The drag died after one frame.

The tell was that it only failed **when a window was open for focus to return
to**: by hand on an empty workspace it worked every time, and under the
selftest -- which spawns two scratch windows first -- it failed every time.
Two environments, opposite results, same code. What made it diagnosable was a
`-1` pushed into the drag trace from `onCanceled`: a cancel and a drag that
simply did not travel far enough both leave the drawer open, and they want
opposite fixes. `trace=[99 -1]` said which in one reading.

Gating on `progress > 0` instead holds Exclusive until the sheet is all the way
down. Measured with a window present: 48-53 samples opening, 51-52 closing,
three runs out of three.

**That drag has to be 1:1, and that is not a preference.** The handle is *on*
the sheet it moves. At a third of the sheet height it moved ~3.7x finger speed,
the touch ended up above the strip it started on, and the gesture came back as
a cancel often enough to leave the drawer open on a full drag. Matching the
travel to the sheet height keeps the bar under the thumb. The opening drag can
use a shorter travel precisely because it is driven from a strip that does not
move.

**A test that cannot fail is not a test.** The first version of the selftest's
icon check asked fontconfig whether anything covered each glyph's codepoint.
It passed against a deliberately truncated escape, because Nerd Fonts cover the
low private use area too: `U+F0249` cut to `U+F024` still resolves, and still
draws the wrong glyph with a `9` after it. The check that works tests the
invariant these strings actually have -- **an icon literal is exactly one
character** -- and it was only worth keeping once it had been watched to fail
on an injected truncation and pass again when it was reverted.

**Net memory, all five plugins loaded: 361 MB RSS against a 414 MB baseline**
with the desktop bar, and 1037 MB available. The phone shell is cheaper than
what it replaced, because thirteen desktop widgets — four of them large popup
panels — stop being instantiated.

**Two things needed outside the shell:** `usermod -aG feedbackd` for the torch
(`/sys/class/leds/white:flash/brightness` is `root:feedbackd 0664` and the group
is empty on a bare install), and a real log destination —
`mobileomarchy-restart-shell` used to send the shell's stdout to `/dev/null`,
which threw away the only diagnosis a failed bar plugin ever produces.

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

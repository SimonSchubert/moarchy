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

## 6c. The bottom edge: recents, home, drawer

The top edge was finished before the bottom one was. The shade pulls down and
the drawer pulls up, but "pull up" was the only thing an upward swipe could
ever mean: no way to see what was running, no way to reach an app except
swiping sideways through workspaces one at a time, and no way to close one
except a 500 ms hold that killed whatever happened to be focused.

It is the Android arrangement now. One drag from the home pill, three stops:

```
0 ---- 40% -------- 75% ---- 100%   of a 0.45 x screen-height travel
app    RECENTS       HOME
```

**Which two stops you get is decided on press, and that is the whole design.**
An occupied workspace means the swipe is about the apps you already have open,
so it drives the recents carousel and then home. A blank workspace means the
swipe is about starting one, so it drives the drawer, exactly as it did before.
The consequence is that the drawer is one swipe from home and two from an app
-- and that a blank workspace is worth landing on, which is what makes home a
destination rather than a gap between apps.

Occupancy comes from `I3.focusedWorkspace.lastIpcObject.representation` being
non-empty. That test is not new: `install/port-4x.sh` already patches it into
the vendored Workspaces widget, because `I3Workspace` has no `toplevels` model
-- that shape is Hyprland's, and reading it throws. Sway's raw IPC workspace
carries a layout string instead, `V[foot]` or empty, and it is the only
occupancy signal the protocol offers.

**Home is a blank workspace, not a sixth surface.** One app per workspace
already makes an unoccupied workspace the thing a home screen is: wallpaper,
bar, home pill, nothing else. A real home layer would have cost another
always-mapped surface and its bindings, permanently, to draw what was already
there. Picking the target reuses the rule
`bin/mobileomarchy-one-app-per-workspace` uses -- the lowest number with
nothing on it -- so the sideways swipe order stays contiguous. `number` is the
visible workspace number; `id` is an internal Sway handle, and dispatching
against it switches somewhere else, silently.

**Distance decides home; speed is only allowed to rescue a flick.** A fling
past 0.6 logical px/ms can commit the recents band that a short fast swipe
did not quite reach, because that is a gesture people make when they already
know where they are going. It is deliberately *not* allowed to carry the drag
past a stop the finger never reached. Velocity-triggered home would mean a
quick swipe sometimes lands on the carousel and sometimes on the wallpaper
depending on how hard you flicked, and the drawer would become unreachable by
accident.

**`ToplevelManager` is the find, and it is the first thing here that reads
compositor state from QML without forking.** `zwlr-foreign-toplevel-management-v1`,
which Sway implements, hands over `appId`, `title`, which window is active, a
`closed()` signal, and the only two verbs a card needs: `activate()` and
`close()`. Tapping a card is one `activate()` -- Sway focuses the window and
switches to its workspace on its own, so there is no con_id to look up and no
`get_tree` walk. Everything else in this repo that wants compositor state
shells out to `swaymsg`; while `Quickshell.I3` was imported for the occupancy
test anyway, the workspace switches went the same way, which takes a fork off
the most common gesture on the phone.

**Cards are icons, not thumbnails, and there are two independent reasons.**
Quickshell 0.3.1's `ScreencopyView.captureSource` takes a `ShellScreen` --
through `wlr-screencopy`, which is what grim uses -- or a `Toplevel`. The
toplevel path is wired only to `hyprland-toplevel-export-v1`, which Sway does
not implement, so there is no per-window capture to be had at all. And even
given the protocol there would be nothing to capture: Sway does not render a
workspace that is not visible, so the one frame a recents card wants is the one
frame nobody is drawing. Android solves that by snapshotting each app as it is
backgrounded, which here would mean N 720x1440 textures resident inside this
budget on a Mali-400 -- the same cost that stopped the theme picker using each
theme's `preview.png`.

**Three things about the carousel that were wrong in a way nothing reported.**

- **A pitch-wide delegate, not view margins.** The obvious way to centre the
  first and last cards is `leftMargin`/`rightMargin` on the ListView. That
  fights `StrictlyEnforceRange`: the margins and the highlight range each want
  to decide `contentX`, and the view settles with one card filling the screen
  and its neighbours pushed out of sight -- no warning, no binding loop, just a
  carousel that looks like a single card. Making the delegate one *pitch* wide
  -- card plus its gap, with the card centred inside it -- and the highlight
  range the same width gives exactly one position per card, and the next app
  peeks in at the edge again. That peek is the only thing that says the row can
  be paged at all.
- **A correct card can still be invisible.** Painted flat at
  `Color.menu.background` the cards were exactly right and could not be seen:
  the scrim is that same background colour over a dark app, so an unfocused
  card matched its surroundings to the byte. Sampling settled it -- the
  neighbour at (660,700) read `#111c18` and so did the empty space next to it,
  which is not a card that failed to draw, it is a card with nowhere to stand
  out against. Cards are a tinted surface with an edge on every one now, accent
  and heavier on the active one. This is the second time here that reading
  pixels rather than looking at the screenshot is what found the bug.
- **Dismiss is vertical, paging is horizontal, and that is why both work.**
  The delegate's `MouseArea` drags on `Drag.YAxis` with `preventStealing`
  false, so the enclosing Flickable takes a horizontal drag once it passes its
  own threshold and a vertical one stays on the card. The shade rejected
  swipe-to-dismiss for its notifications for the opposite reason: there both
  gestures wanted the same axis as the scroll. A `DragHandler` is still no use
  -- over a sheet of delegates it gets one translation event for a whole
  gesture, because the delegates' MouseAreas hold the exclusive grab.

**The carousel takes the whole output, and the drawer must not.** The drawer
is on Top with a zero exclusive zone, which means it is *arranged into*
whatever the exclusive surfaces left -- and that is the feature: its search
field needs squeekboard, so the grid reflowing above the keyboard is the point.
Copying that for the carousel put it in the top two thirds of the screen
whenever the app behind happened to have a text field focused, with "Clear all"
pushed under the keyboard and untappable. Nothing was wrong in the
arrangement; it was the right arrangement applied to the wrong kind of surface.
`ExclusionMode.Ignore` takes the whole output, the way the shade does, and the
keyboard is simply behind it. It needs none of the shade's mask to keep the
home pill live either: the gesture strip is on Overlay, every Overlay surface
sits above every Top one, and so the pill stays touchable over the carousel
with no geometry at all -- which is what lets one drag carry on past the
recents stop into the home band.

Related, and only visible once the surface was full-height: the scrim has to
reach **fully opaque** at the top of the drag. Half-open, seeing the app
through it is what says the sheet is still moving. Fully open it is a switcher,
and anything showing through is noise -- with a text field focused behind, that
noise is an entire on-screen keyboard ghosting under the cards.

**The carousel never takes keyboard focus, and that is a decision.** The
drawer needs `Exclusive` for its search field and pays for it: gating
`keyboardFocus` on `opened` there dropped interactivity on the first frame of a
close drag, Sway handed focus back to a window, and the focus change cancelled
the touch the surface was still holding. A carousel has no text input, so
`None` sidesteps that whole class of bug rather than working around it. Touch
reaches a layer surface either way.

**Two things that cost an hour and were not the code.**

- **`sudo` resets PATH.** `sudo -n mobileomarchy-touch swipe ...` is
  `command not found`, and with the output redirected it is a swipe that
  silently does not happen. Every band read as "the gesture does nothing"
  while the plugin was never sent a single touch event. The selftest had this
  right all along -- it invokes the injector by absolute path.
- **A blanked screen disables touch.** `mobileomarchy-screen` turns the touch
  input off with the panel, so after an idle timeout synthetic swipes land
  nowhere, `grim` blocks with no frames to capture, and IPC calls time out
  behind a busy compositor. It looks precisely like a deadlocked shell. What
  distinguishes them is that a deadlock does not have a load average of 0.24:
  `swaymsg -t get_outputs` reporting `power: false` is the one-line answer, and
  powering the output back on is not enough -- the input has to be re-enabled
  too, which is why `mobileomarchy-screen on` exists and `swaymsg output * power
  on` is not a substitute.

**`mobileomarchy-restart-shell` needed `WAYLAND_DISPLAY`.** It already derives
`SWAYSOCK` so a restart from an ssh session works; without `WAYLAND_DISPLAY` Qt
falls through to the xcb platform plugin, fails to reach a display, and aborts
before reading a line of QML -- `FATAL: no Qt platform plugin could be
initialized`, which reads like a broken shell rather than a missing variable and
leaves the phone with no bar until someone restarts it from a terminal on the
device.

**An empty IPC answer is not a "no".** The escape-hatch check failed one run in
three, on a result it had actually got right: right after a full-screen surface
maps on this GPU the shell can be busy for long enough that `omarchy-shell`
gives up and prints nothing, and `"" == "closed"` is false. Driven by hand the
same gesture passed three times out of three, with the trace showing the
carousel lifting to 23% and springing back exactly as designed. Every state
read in the gesture suite retries now. A check that reports a transient as a
failure costs more than the bug it was looking for -- it teaches you to ignore
it.

**Measured: 315 MB RSS with all six plugins loaded and nothing opened yet,
351 MB after a session of driving every one of them, against 1118 MB
available.** Not a comparison with 6b's 361 MB -- that was measured after use,
and these two are the ends of the same range. The point is only that the sixth
plugin does not move it: the carousel holds one decoded icon per open window
and no textures. The selftest
covers all three stops with synthetic touch, and three consecutive clean runs:
55 samples opening the carousel, a card count that drops when a card is flicked
away, a focused workspace whose `representation` is empty after the home band,
and the drawer still tracking the finger at 47-49 samples -- from a blank
workspace, which is now the only place the strip can reach it from.

## 6d. Rebuilding the bottom edge against a written spec

6c described a bottom edge that passed 37/37 and was wrong. The drawer opened
from the nav strip, which is not where Android puts it, and it opened there
*most of the time* rather than only when it should have. Both of those are one
mistake, and the tests could not have caught it: they had been written to match
the code, so green only ever confirmed the inference that produced the code.

So the spec came first this time. `docs/gestures.md` is 34 numbered acceptance
criteria, each with the command that decides it, agreed before a line of QML
changed; the checks in `--gestures` name the ids they prove and the suite ends
by printing the ids it does not. That last part matters more than it sounds: a
gap nobody can see is the same as a gap nobody fixed.

**The bug and the redesign were the same fix.** The strip chose between the
carousel and the drawer by asking whether the focused workspace was empty,
through `I3.focusedWorkspace.lastIpcObject.representation`. That value is
refreshed on *workspace* events, so a workspace that was empty when it was
created and later received a window still reads empty -- which is "most of the
time". Moving the drawer onto the home screen deletes the question rather than
fixing the answer, and nothing in the gesture plugin asks about workspace
occupancy any more.

**Layer order replaced the predicate.** The home-screen surface is full-screen
on the **Bottom** layer: above the wallpaper, below every window. On a blank
workspace it receives the touch; on an occupied one the app is over it and it
receives nothing. No test, no staleness, and nothing to get wrong -- and
because it can never intercept what an app would have received, a bug in it
cannot make the touchscreen unusable. `gaps outer 0` is what makes this exact
rather than approximate: a lone window reaches the screen edge, so there is no
border for it to catch a stray swipe in.

**The back gesture is the one place that does steal input from apps.** It has
to sit above windows to work, so it is 16px on Overlay and, like the strip, it
never grows -- the worst a bug there can do is cost 16px down one side. Looking
at how Android does it was worth more for what it *cannot* lend us than for its
numbers: Android has the same tap-swallowing problem and solves it with
`setSystemGestureExclusionRects`, letting an app carve regions back out, capped
at 200dp per edge -- a limit sized explicitly as four 48dp touch targets. There
is no Wayland equivalent. So this edge is strictly more expensive here than on
Android, with no mitigation available to apps, and the fix if it bites is to
narrow it or drop it rather than to go looking for an API that does not exist.
Android also declines to publish a fixed inset at all: it is device-configurable,
user-adjustable, and queryable by apps. Three admissions that no one number is
right, so ours is a property rather than a constant in a binding.

**`ToplevelManager.activeToplevel` reads null with a window plainly focused.**
The back gesture found nothing and closed nothing while `toplevels` was
populated the whole time. The per-toplevel `activated` flag does track focus --
it is what puts the accent border on the right card -- so both the back gesture
and the carousel's ordering now prefer the singleton and fall back to the flag
that works. Worth noticing that the carousel had been leaning on the same
broken property for its "most recent first" ordering and looked fine, because
creation order happened to agree.

**Two hours went to environment, not code.** `sudo` resets PATH, so
`sudo mobileomarchy-touch ...` is `command not found` -- and with output
redirected, a swipe that silently never happens. Every band read as "the
gesture does nothing" while the plugin was never sent one touch event. Then
`foot` would not map, because an ssh session has no `WAYLAND_DISPLAY`, and the
shell reported `focus=none` -- which reads exactly like a broken plugin rather
than a missing variable. Both are fixed at the source now: `--gestures` derives
`WAYLAND_DISPLAY` the way `mobileomarchy-restart-shell` already derives
`SWAYSOCK`, and both invoke the injector by absolute path.

**A test that assumes state it could control is not a test.** G4 -- "back
closes the focused app" -- failed while the code was correct: `foot` had raised
squeekboard, and back is a priority order in which the keyboard outranks the
app, so it correctly dismissed the keyboard instead. The check now forces the
keyboard up, asserts back puts it down without closing anything (G2), forces it
down, and only then asserts the app closes (G4). Chasing that failure is what
produced the G2 check, which had not existed at all.

**16 checks over 14 ACs, three consecutive clean runs**, and seventeen ids
printed as uncovered. Two of those are worth naming: A9 needs every window on
the device closed, including the user's, so it is deliberately not run; and E5,
E6 and E1 are visual enough that a state dump would not prove them.

## 6e. Dragging the sheets shut

Two overlays could only be closed by a 26px band at the top of their own sheet.
Dragging on the body did nothing, and that was never a decision -- it was where
build-log 6b's investigation stopped once it had *a* working handle. The spec
had no ACs for it either, which is how a gap survives being written down.

**The same three-line pattern unlocked both, and it is the carousel's.** Every
tile and every app icon is a `MouseArea`, and a `MouseArea` holds the exclusive
grab for the whole gesture -- which is why 6b found a sheet-wide `DragHandler`
receiving exactly one event, and why an area placed *behind* the content never
sees a thing. So the controls do both jobs: a touch that never travels
activates, one past the slop drags the sheet shut.

**Scene coordinates, not local ones, and this is not a style preference.**
Every one of those MouseAreas is a child of the sheet, and the sheet is the
thing being moved. A delta measured in a frame that travels with the item it is
driving feeds back into itself. `mapToItem(null, ...)` is stationary, so a
finger that stops moving produces a delta that stops changing.

**`released` fires before `clicked`, and that cost an app launch.** The flag
saying "this was a drag, not a tap" was being cleared in the release handler,
so it was already false when the click arrived and the delegate launched
whatever the drag happened to start on. The symptom read as a *threshold* bug
-- a short drag that "closed" the drawer -- because launching an app dismisses
the drawer on the way out. The flag is cleared on the next press now.

**A `Flickable` swallows the press whether or not it has anything there.** Both
sheets stretched their list to fill: the drawer's `GridView` and the shade's
notification `ListView` each covered the empty sheet below their last row and
ate every drag that started in it. Capping each to `contentHeight` hands that
space back to the sheet, and gating `interactive` on overflow gives H5 for
free: while the list can scroll it owns vertical drags, and closing the shade
out from under someone reading their notifications is exactly the conflict this
gesture is not allowed to create.

**The brightness and volume sliders had to hand the gesture over rather than
share it.** They commit on *press* -- tap-to-set, which is right on a phone --
so by the time it is known whether the finger is going sideways or up, the
value has already moved. They now watch for a vertical drag, hand it to the
sheet, and put the value back, which for the live one means undoing a commit it
has already sent.

**Two edges had to be masked out of the shade.** It is on Overlay and maps when
it opens, so it lands *above* the always-mapped back-edge surface and swallowed
every left-edge swipe: back closed the drawer and the carousel and left the
shade untouched, because those two are on Top and this one is not. Its open
region already excluded the home pill's band along the bottom for the same
reason; it excludes the back edge down the left now too. A masked-out band
falls through to the next surface in the layer, which is the whole mechanism.

**Distance alone cannot commit a drag that starts near the far end.** Begin a
close 150px from the top of the shade and there is not 25% of the sheet left
above to travel through -- the gesture is unambiguous and the threshold is
unreachable. Speed settles those, the way it already did for the strip and the
grab band. Measured after: the shade closes from anywhere below the sliders on
a slow drag and from anywhere at all on a flick; the drawer closes on a long
drag from the search row, an icon, or empty sheet, and on a 90px flick; and a
60px slow drag on either still springs back.

## 6f. Three defects the first pass shipped

Found after the gesture work was committed, all three by looking at the shell
log *after* exercising the phone rather than after starting it. Nothing logs at
startup; these only speak once a finger moves.

**`var` is function-scoped, so a declaration inside an `if` is hoisted and
undefined.** `var now = Date.now()` sat inside the latched branch of
`onUpdated`, and `root.lastT = now` at the bottom ran on every touch move --
including the un-latched ones, where `now` had never been assigned. QML rejects
`undefined` for a double and logs it, so `lastT` silently kept a stale value and
the first latched frame measured its velocity over the wrong interval. Same
shape in two handlers, because the second was written from the first.

**`representation` went stale in the one place it was left.** `firstFreeWorkspace()`
asked each workspace whether its layout string was empty -- the same field, and
the same staleness, that made the strip open the drawer when it should have
opened the carousel: it changes on *window* events while I3 refreshes
workspaces on *workspace* events. Home switched onto an occupied workspace, and
the check named the bug for itself:
`the home drag left workspace 2 holding 'V[moa-selftest]'`. Existence does not
go stale the same way -- Sway destroys an empty workspace as soon as it loses
focus -- so it picks the lowest number the list does not contain, and asks
nothing about contents. The lesson is narrower than "do not use
representation": a value refreshed on one class of event cannot answer a
question about another.

Also here: home from home used to hop to a *different* empty workspace. There
is a reliable emptiness test after all, just not that one -- no toplevel is
`activated` while focus is on an empty workspace, which is the same property
the back gesture had to fall back to when `activeToplevel` read null.

**Powering the panel on does not turn touch back on.** `mobileomarchy-screen`
disables the touch input with the display, so after an idle blank every
synthetic swipe lands nowhere and the suite fails wholesale for a reason that
has nothing to do with gestures. It cost an hour once already; the suite
enables the input explicitly now.

**And one piece of polish.** The shade's gear and power glyphs sat 1.5 device
pixels left of their circles. `anchors.centerIn` shrink-wraps the Text to the
glyph and then centres *that*, which lands the item on a fractional x --
(36 - 13.39) / 2 -- and the ink with it. Filling the button and letting Text
align inside keeps the item on integer coordinates. TextMetrics was tried
first and is what ruled out the obvious suspect: it reported the ink as already
centred *within the item*, which pointed at the item's placement rather than
the font's bearings. Measured after: the gear moved from -1.5 to +0.5 device
pixels, the power glyph stayed at -1.5 because its ink genuinely overhangs its
cell to the left, and at that size both read as centred.

## 6g. One phone, three sessions

Most of an afternoon's "flaky gesture tests" were not flaky and were not
gestures. Two other Claude sessions were driving the same PinePhone: one
scp'ing plugins and restarting the shell every few minutes, one running
input-method lifetime tests that deliberately parked focus on an empty
workspace. The tells were all there and I read every one of them as my own
bug first: windows nobody in this session had spawned (`moa-kbdtest`, a KDE
Calculator), workspace numbering at **19**, and a seat where the workspace was
focused and no window inside it was -- after which `swaymsg '[app_id=...]
focus'` returns success and changes nothing.

The most expensive one: **squeekboard had been killed and replaced**, with
another implementation owning `sm.puri.OSK0`. The G2 check -- "a back swipe
dismisses the keyboard and leaves the app open" -- was therefore testing
somebody else's keyboard, and I had already started rewriting the probe to
chase what I took to be my own defect. Asking cost one message and would have
cost nothing an hour earlier.

**What that says about the suite**, beyond "coordinate": a check that fails
because of the environment must say so. Three now do.

- G4 asserts its precondition. If Sway has no focused window, it reports *that*
  rather than blaming the back gesture -- which is right to do nothing there,
  because "no toplevel activated" is also how a home screen looks (G5).
- F2 asserts what its criterion actually says. "Going home never closes
  anything" is `after >= before`, not `after == before`; the stricter version
  failed when an unrelated app finished starting mid-run.
- G2 forces the keyboard up rather than hoping. An unforced run of that check
  is what made G4 look broken while it was correctly obeying G2's priority.

**Two real defects came out of the noise**, both of which would have bitten a
real user:

- The keyboard probe could act on a stale answer. `Process.running = true` on
  a process that is already running is a no-op, so a probe still in flight
  from the previous gesture left `keyboardKnown` false and `keyboardUp`
  whatever it was last time -- and back closed an app while the keyboard was
  plainly up. It toggles `running` off first now, retries a bounded six times,
  and if it still has no answer it takes the *keyboard* branch, because
  dismissing a keyboard is reversible and closing an app is not.
- Back did nothing at all in the stranded-focus state. `focusedToplevel()`
  returns null there while a window is plainly on screen, so the gesture fell
  through to G5's "nothing to undo". It falls back to `kill` now -- the same
  close request, addressed to whatever Sway considers focused, which reaches
  the window in that state and is a no-op on a genuinely empty workspace, so
  G5 still holds.

**And one fix that was a workaround.** The suite had grown a discarded warm-up
gesture because the first real gesture of a run was sometimes swallowed. The
cause is that a fresh uinput device needs longer than `mobileomarchy-touch`
waited for Sway to map it to an output. Every caller pays that wait anyway, so
it is 2s now and the warm-up is gone. A warm-up that exists to survive a
too-short sleep is the sleep being wrong.

## 6h. Settings: the menu becomes screens

Omarchy's menu is 320 entries. The phone's Settings screen was eight rows, seven
of which summoned `omarchy.menu` at a route and handed over the desktop list.
That list is a popup, and `install/port-4x.sh` stubs out `HyprlandFocusGrab`
because Quickshell.I3 has no counterpart — so it does not dismiss on
tap-outside. The physical power button was bound straight into it.

**Classify before building.** All 320 entries went into `docs/menu-coverage.md`
first, each exactly once, as Native / Bridged / Shade / Unsupported. The table
is generated against the pinned `omarchy-menu.jsonc` rather than transcribed, so
no id can be invented or missed, and the split came out 66 / 75 / 1 / 178. The
two thirds that are dropped are Steam, twenty language runtimes behind `mise`,
six browsers with no aarch64 build, and Hyprland's own config files.

**One shim covered 128 rows.** They are all
`omarchy-launch-floating-terminal-with-presentation <script>`, every script it
names exists upstream, and our `bin/` shadows `$OMARCHY_PATH/bin` by PATH order.
Replacing that one wrapper — upstream's logo/done presentation kept verbatim,
only the terminal swapped for a fullscreen foot at font 7 — made all of them
work with nothing reimplemented. 65 of the bridged rows run a command
byte-identical to upstream's `action`; the selftest asserts it.

**Guards batch per page, not per tree.** Upstream evaluates all ~90 shell
conditions at once because a dmenu you type into must know what every row would
match before you have typed. A stack shows one page, so it asks about one:
opening the root costs three reads and no `pacman`, and eleven of the
thirty-six pages cost nothing at all. Repeated readers are captured once, the
way `MenuModel.js` does it, so the nine-row agent page forks
`omarchy-default-agent` once rather than nine times.

**A shell heredoc ate 55 icons.** Every glyph in `omarchy-menu.jsonc` below
U+FFFF is three bytes of UTF-8; the supplementary-plane ones are four. Writing
`Pages.js` through a bash heredoc dropped exactly the three-byte ones, leaving
`glyph: ""` on 55 of 141 rows — which renders as a row with no icon and a label
sitting where the icon should have been, and reads as a design choice rather
than a defect. **The existing icon check passed all 55**: it asks whether a
literal is one character and whether a font covers it, and an empty literal is
neither multi-character nor uncovered. Write glyphs from explicit codepoints
with a file write, never through a shell.

The check that catches it now was itself wrong first. Matching row objects with
a brace-matching regex skipped every row containing a nested `covers: { ... }`
— it found 6 of 55 against a deliberately broken copy. It is line-based now,
and it was verified against that broken copy rather than against the good file.
A check only proven on passing input has not been proven.

**Three switches wrote state nothing read.** `mobileomarchy-toggle-bar` did
`pkill -x quickshell`, which made sense when the bar was all the shell drew and
now takes the drawer, the shade, the gesture strip and Settings with it — from a
row labelled "Menu Bar". `omarchy-bar transparent` committed to `shell.json`
while `Bar.qml` held an unbound `property bool transparent: false`. Battery
percentage had no reader at all. And Stay Awake would have read and written its
flag correctly while `swayidle` blanked the screen anyway, because nothing under
Sway consulted it.

Negative polarity is the convention here and it is easy to get backwards:
`bar-off`, `screensaver-off`, `crash-capture-off`, `suspend-off` and now
`battery-percentage-off` all mean the feature is **off** when the file exists. An
inverted switch still toggles, still persists, still survives a restart — it is
merely wrong, and wrong-but-consistent survives review. `invert: true` lives in
the row data with a test per flag.

**The first back gesture after a shell restart is not yours.** `performBack()`
takes the keyboard branch whenever its probe has not answered, deliberately,
because hiding the keyboard is the reversible outcome. So a test that issues one
`gestures back` right after a restart is testing the probe's timing, not the
gesture — it failed once here and looked exactly like a real regression.

**Contrast has to be measured, not reasoned about — and not on one theme.**
Sampling pixels from a device screenshot: labels 9.47:1, detail lines
**4.50:1** — AA to two decimal places, with the antialiased glyph edges below
it. The cause is that subtitles sit on a raised card rather than the
background, and that 8% lift is what eats the margin.

Raising the alpha and calling it fixed was the mistake underneath the mistake.
Catppuccin happened to be on the phone, and it is one of the *forgiving* themes
for that pair. Run across all 22 `colors.toml` files, foreground at 0.7 over the
card is below AA in six of them and reaches **3.14:1 on rose-pine**;
`mobileomarchy.themes`, at a flat 0.6 on the bare background, was **2.72:1**.
One theme measured and 21 assumed.

No constant is defensible here. At 0.55 — quiet enough to read as secondary —
18 of 22 are under AA. At 0.9 — the lowest value that clears AA everywhere —
the subtitle is within ten percent of its label and the hierarchy the alpha
existed to create is gone. A constant has to be tuned for the worst theme and is
therefore wrong for the other 21. So the colour is computed per theme: start at
0.55 and walk toward the foreground only until the pair clears 4.5:1. Worst case
becomes 4.52:1 and sixteen of the twenty-two stay below 0.70.

The measurement must use the *composited* background. The card is 8% alpha over
the base, and a sweep naming two palette roles cannot express that — it reports
the base or `lighter_background`, and both overstate the contrast. The
moarchy-keyboard session and this one arrived at the same six failing themes and
the same 3.14:1 from independent implementations once its checker grew a
`mix(base;over;alpha)` form, which is better evidence than either of us checking
our own arithmetic.

### Two the Settings screens shipped, found by using them

**Confirm did nothing.** The Continue button cleared `confirmText` and then called
`activate(row)` -- and `activate` armed the sheet whenever `row.confirm` was set
and `confirmText` was empty, which it now was. So every tap re-armed the dialog
it was dismissing: the sheet stayed up, the action never ran, and the button read
as dead rather than as looping. Confirmation is a parameter now, not a reading of
the state the caller has just cleared.

**Suspend locked a phone out.** `install/config.sh` starts `sway-session.target`
so that 4.x's user units come up at all, and one of those is
`omarchy-sleep-lock`. Suspending therefore locks the session, and the lock is an
ext-session-lock surface -- under that protocol the compositor draws the locker
and nothing else, so the on-screen keyboard is hidden by the very prompt asking
for a password. Touch-only, that is unrecoverable without ssh.

This is the trap `autostart.conf` and `mobileomarchy-system-lock` already
document and defend against, and the defence did not reach here: our shim guards
`omarchy-system-lock`, the *script*, while the sleep unit and the shell's own
`omarchy.lock` service raise their locker directly. Guarding a script does not
guard the capability. `system.suspend` is Unsupported until the sleep unit is
masked and that is verified on the device -- and it is worth doing, because
suspend on a phone is worth having.

## 6i. Three fixes that came from other people's measurements

**A single alpha cannot make secondary text readable.** `subdued` was
foreground at 0.6, and against the surfaces it actually sits on -- a raised
card, a container tile, the sheet -- that measured 3.95-4.29:1 where 4.5:1 is
the threshold. Raising it to 0.75 cleared all three, and that fix was still
wrong: it was calibrated against one theme. Measured across all 22, foreground
at 0.7 over a lifted card fails in six of them and reaches **3.14:1 on
rose-pine**, while Catppuccin passes the same pair at 5.44 -- so the theme I
happened to be running is one of the most forgiving for it. The constant that
clears AA everywhere is 0.9, at which point a subtitle is within ten percent of
its label and the hierarchy the alpha existed to create is gone.

So it is computed per theme now: start at 0.55 and walk toward the foreground
only until the pair clears 4.5:1, measured against the **composited**
background rather than the surface, because `container` is painted with alpha
and measuring against the surface alone overstates the contrast by the width of
that lift. Every theme ends up as quiet as it can afford. Verified on rendered
pixels, not arithmetic: 6.97:1 for the shade's date line.

**The first back gesture after a shell restart was being eaten by its own
probe.** `performBack` takes the keyboard branch whenever the probe has not
answered -- correct, because that branch is the reversible one -- but the DBus
path is cold on the first call and the whole retry budget goes on it. The probe
is warmed once at startup now, so the first real gesture is not the one that
pays for the connection.

**A suite that inherits the last session's state is measuring the last
session.** One run in three failed A1/A3 with "0 samples", which reads as a
dead gesture and was nothing of the kind: a shade left open from an earlier
screenshot meant the strip's up-drag correctly meant "put that away" (A8), so
the recents drag never latched. The gesture was behaving exactly as specified
and failing a check that assumed a bare screen. A4 then passed *because* it
closed the shade, which is how the failure looked intermittent rather than
positional. The gesture block now closes every overlay before it starts, and
that is verified the only way worth verifying it: by running three passes from
a deliberately dirty start, with the shade open, and getting 43/43 three times.

All three came from someone else looking. The contrast sweep started in another
session; the probe timing was reported by a third; the dirty-state failure was
mine, found only because the other two had already cleared the noise around it.

## 6j. A cleanup pass that deleted the phone

Plugins are installed by copying every directory under
`default/omarchy/plugins/` into `~/.config/omarchy/plugins/`, and a plugin that
ships a `.desktop` has it moved into `~/.local/share/applications` so the drawer
lists it like an app. Nothing removed either one when a plugin left the repo. The
loop only iterates what the repo still ships, so a deleted plugin is never
visited: its directory stayed, the shell went on loading it, its id stayed in
`shell.json`, and its icon stayed in the drawer launching nothing. Another
session spotted the orphaned icon; checking it found the other two.

The sweep that fixes it derives the set of plugins the repo ships and removes any
installed `mobileomarchy.*` not in that set. Desktop entries carry an
`X-MobileOmarchy-Plugin=<id>` marker and are matched on it rather than on
filename, so an entry named after something else is still caught and an entry we
never installed is never touched.

**Then the interesting part.** I scoped the sweep to the `mobileomarchy.*`
namespace so a user's third-party plugins could not be caught by it, dry-ran
exactly that -- stale one goes, third-party one stays -- and shipped it. What I
never ran was the branch that deletes. If `MOBILEOMARCHY_PATH` is unset or wrong,
or `default/omarchy/plugins/` is missing or caught half-written by another
session's checkout in this shared worktree, the glob does not expand and the
derived set is **empty**. Every installed plugin then fails the membership test.
Reproduced against the committed version: bar, drawer, shade, recents, gestures,
settings, themes and device all deleted in one pass, leaving only the
third-party plugin the namespace scoping had so carefully protected. The copy
loop that would restore them iterates the same empty glob, so it restores
nothing. The phone comes up with no UI at all, recoverable only over ssh.

An empty derived list is not "everything is stale", it is "I could not read the
repo", and the two must not share a code path when one of them ends in `rm -rf`.
The sweep is skipped with a warning now. Skipping it leaves a stale icon, which
is the whole bug it was written to fix; running it on a half-read repo leaves no
phone. Same reasoning as upstream `omarchy-menu` discarding an incomplete batch
rather than acting on it.

Two things worth carrying forward. The first is that I dry-ran the branch that
was already correct and shipped the branch that deletes -- the safe path passing
says nothing about the destructive one, and this is the only `rm -rf` in the repo
aimed at a directory the user owns. `scripts/test-plugin-sweep.sh` now covers all
four branches over a fake `HOME`, needs no device, and extracts the sweep from
`install/config.sh` between marker comments so it tests the shipping code rather
than a copy of it. Against the unguarded version it fails three of four.

The second is a trap the sweep introduces: **provisioning is authoritative, so a
plugin hand-copied to the phone for testing is now deleted by the next
provision** rather than merely overwritten. That is correct behaviour and it is
silent. `mobileomarchy.device` spent a day in exactly that state -- scp'd,
uncommitted, live -- and the next provision would have removed it. Commit a
plugin before you rely on it surviving.

## 6i. Two surfaces, one edge

The on-screen keyboard was replaced, and the new one landed on the **Overlay**
layer -- the same layer as the gesture strip. Both reserve space, and the total
was right: 23 for the strip plus 200 for the keyboard, 223 reserved, nothing
lost. What a correct total does not say is *which surface gets the edge*, and
the keyboard was getting it: keys ran to y=720 and the home pill was displaced
to 497..520, stranded between the app and the keys.

**Exclusive zones resolve layer by layer, Overlay downward.** That is why the
strip beat squeekboard without anyone having to think about it -- squeekboard
was on Top, so the strip's zone was always resolved first and the edge was free.
Putting a second surface on Overlay replaced that guarantee with intra-layer
map order, which is a race. The fix was for the keyboard to go back to Top,
where the ordering is decided by the layer rather than by who happened to map
first.

**Six failures, identical across three runs, and none of them were the
gestures.** B1, A1/A3, A4 and D1 all swipe at y=710 logical, which used to be
the strip and had become the middle of the keyboard; E3 cascaded from A1/A3.
The gestures were behaving correctly the whole time and the tests were aiming
at where the strip used to be. Worth separating from the day's other failures:
those were contention and leftover state, this one was reproducible, and the
difference between "fails three times identically" and "fails one run in three"
is the difference between a regression and an environment.

**A correct total is not evidence of a correct arrangement**, and that mistake
was mine twice over. I warned that sharing a layer turns the exclusion into a
race, was shown a measurement proving both surfaces reserved the right amount,
and retracted -- when the measurement was compatible with either order and
never addressed the question. The screenshot is what settled it, because a
screenshot cannot be compatible with both.

**Assert the interface, not the implementation.** The session check asserted
`squeekboard` by process name and went red the moment the keyboard changed,
reporting a working phone as broken and naming the wrong cause. It asks whether
*something* owns `sm.puri.OSK0` now -- which is the actual contract, the one
`mobileomarchy-toggle-keyboard` and the back gesture both drive. The same error
in the other direction cost a peer session an afternoon: its suite reported
confidently on squeekboard while a different implementation owned the name.

46/0, three consecutive runs, against the replacement keyboard.

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
- `HyprlandFocusGrab` stubbed out — menus do not dismiss on tap-outside. The
  back gesture now reaches them: `mobileomarchy.gestures` walks the host's
  `openPanelIds` for `omarchy.` surfaces after its own, so a vendored popup can
  at least be dismissed. Tapping outside one still does nothing.
- `I3.workspaces` shape differs from Hyprland's in ways not fully explored.
- **Browser-policy theming fails on every `omarchy-theme-set`.** Upstream's
  `omarchy-theme-set-browser-policy` runs its privileged half from
  `/usr/bin/...` because that is the path `/etc/sudoers.d/omarchy-theme-browser`
  names, and we vendor a checkout rather than installing the package, so nothing
  is there: `Error accessing /usr/bin/omarchy-theme-set-browser-policy`. The
  caller sets `failed=1` and carries on, so only Chromium's managed-policy
  colour is lost. Harmless, but it prints on every theme change and looks like a
  real failure.

The v3.8.4 (waybar-based) port on `main` ran stably for hours and is the fallback.

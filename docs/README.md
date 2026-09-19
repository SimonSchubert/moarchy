# How these documents are written

Two genres live here, and the difference decides what belongs in a file.

**Contract docs** say what the phone must do. Behaviour, present tense, with a
check a terminal can run: `gestures.md`, `settings.md`, `control-center.md`,
`volume.md`, `windows.md`, `style.md`, and the T-series in `apps.md`.
`bin/moarchy-selftest` cites their ids, so a criterion with no test is visible.

**Decision records** say how the project is built and why it is built that way:
`structure.md`, `devices.md`, `upstream.md`. They have no checks. Rationale is
their content, not an intrusion into it.

`refactor.md` is a contract doc about the *shape of the code* rather than about
what the phone does, so its criteria are greppable rather than runnable on the
device. It is the only file with an end: every section is either done or the
work that is left, and when the last one is done it goes. Twenty-nine comments
across the tree cite it by section id, so it cannot simply be deleted — the
citations go first.

`build-log.md` is neither — it is the chronological account, and it is where the
archaeology belongs.

**Orientation** is the third genre and there are two of it, answering two halves
of the same question: [`naming-convention.md`](naming-convention.md) gives every
part of the screen its one name, and [the code](#the-code) at the bottom of this
file says which file draws it. No criteria, no rationale — just so that a
stranger, or this project six months from now, can find the thing that owns a
behaviour without reading 9,000 lines of contract first. Both are a map and not a
second copy of the territory: every row points at the document that governs it,
because a map that restates a rule is a map that will contradict it.

## A criterion is three things

```
**B3** The swipe lands on a workspace with nothing of the shell's drawn over it.
The control center, the app drawer and the theme picker are put away on the way (A8). A shell
app is a window (K1), so it stays where it is and the swipe back returns to it
(K2).
→ with the control center down over an app, a sideways swipe leaves `control-center state` ==
`closed` and a focused workspace that is not the one it started on
```

1. **One present-tense statement** of required behaviour. No dates. Not `until
   2026-…`, `used to`, `previously`, `the first pass`, `it was N until`.
2. **The `→` check** — the command whose output settles it. Mechanism belongs
   here: QML property names, `swaymsg -t get_tree`, a grep pattern. Not in the
   statement above it.
3. **At most one clause of why**, and only if it passes the test below.

### The re-break test

A *why* survives only if deleting it would let someone undo the constraint
without realising. G10's note that sway resolves exclusive zones Overlay-down
passes: without it, `ExclusionMode.Normal` looks like the obvious fix and gets
tried again. S6d-8's note that BlueZ will not power an adapter up underneath a
soft block passes: without it, the 700ms wait looks like superstition and gets
deleted.

A post-mortem of a fixed defect does not pass. Neither does the story of what
the code did before the commit that changed it. `git log -S` finds both,
alongside the change that made them untrue.

### Three rules that follow

- **An annulled criterion is deleted**, not kept with the argument for its own
  removal attached. If the failure it named must not return, it becomes one
  dated line in that document's `Known-bad` list.
- **A measurement keeps its number and loses its session.** `73px, measured
  against libadwaita's 47px header` stays; the write-up of the ssh session that
  measured it does not.
- **An answered question is deleted.** The criterion that now states the answer
  is the record.

## What must not change

- **Ids are never renumbered and never reused.** They are transcribed by hand
  into ~300 code comments and 220 assertion strings in `bin/moarchy-selftest`,
  and no tool notices when one moves.
- **A check cites a pattern, not a line number.** The `→` line names a grep,
  a symbol or an IPC verb. `refactor.md` was written with `file:line` citations
  and they did not survive a week: of the ten it carried, one still landed on its
  target, one named a file that had been deleted, and two counted copies that had
  gone away on their own — so the section read as remaining debt while the work
  was done, and as done where it was not. A grep that matches nothing is a
  criterion that has been met or a criterion that has moved, and either way it
  says so out loud.
- **Ids are not unique across files.** `L1`–`L13` is long-press in
  `gestures.md` and the launch splash in `windows.md`; `I*`, `D*` and `B*`
  collide across four files each. A new citation names the file —
  `gestures.md L12`, not a bare `L12`.
- **`**?**` means "my reading of the code, not your decision."** It flags
  unratified content. It is not decoration.
- **The table rows in `menu-coverage.md` are parsed** by
  `bin/moarchy-selftest` (G5, G6) against the pattern
  ``^| `id` | label | Native|Bridged|Control Center |``. Their format is code. The prose
  around them is not.

## The files

| File | What it is |
| --- | --- |
| [`naming-convention.md`](naming-convention.md) | Orientation — what each part of the screen is called, the four swipes, and the four kinds of thing quickshell draws |
| [`gestures.md`](gestures.md) | Contract — every touch gesture: the strip, the edges, the app drawer, long-press |
| [`settings.md`](settings.md) | Contract — the Settings screens, their rows, and the IPC they answer on |
| [`control-center.md`](control-center.md) | Contract — the pull-down: tiles, sliders, media, notifications |
| [`volume.md`](volume.md) | Contract — the hardware volume keys and the panel they raise |
| [`windows.md`](windows.md) | Contract — the window area and the launch splash |
| [`style.md`](style.md) | Contract — type, colour, shape, touch targets, motion. Binds the keyboard and store repos too |
| [`apps.md`](apps.md) | What ships on the phone and what each app is for, with screenshots off the device |
| [`menu-coverage.md`](menu-coverage.md) | All 333 upstream menu entries, classified Native / Bridged / Control Center / Unsupported |
| [`structure.md`](structure.md) | Decisions — repos, packages, the package repository, the image |
| [`devices.md`](devices.md) | Decisions — what a second device would need, and what is device-specific |
| [`upstream.md`](upstream.md) | Decisions — the boundary with Omarchy, and what a version bump may break |
| [`refactor.md`](refactor.md) | Contract — what has to be true when the duplication is gone. Cited by ~29 comments |
| [`build-log.md`](build-log.md) | How this went, including the dead ends. The archaeology lives here |

---

# The code

Orientation, in the sense above: where things are. Nothing here is a criterion.
Where a rule is mentioned, the file that owns it is named and that file wins.
[`naming-convention.md`](naming-convention.md) is the other half — the same
surfaces seen from the screen rather than from the tree, under the names
[Words used precisely](#words-used-precisely) fixes.

## What the phone is running

Omarchy on Arch ARM, with sway in place of Hyprland, and **one overlay package**
on top rather than a fork ([`upstream.md`](upstream.md) has the boundary). Three
kinds of thing make up the phone UI:

| | What it is | Where |
| --- | --- | --- |
| **The compositor layer** | sway config, split by lifetime: device-independent here, per-device in the device package, theme-generated at runtime | `default/sway/*.conf`, entered through `config/sway/config` |
| **The shell** | Omarchy 4.x's quickshell/QML shell, unmodified except for a patch, hosting our screens as plugins | `pkgbuilds/omarchy-config/port-4x.patch`, `default/omarchy/plugins/` |
| **The commands** | everything a tap ends up running, plus the shims that answer upstream's names | `bin/` |

Nothing in this repo is the shell itself. The shell is upstream's, fetched at a
pinned ref, ported to sway at build time by a patch that must apply with no fuzz.

## The shell plugins

Thirteen plugins and one directory that is not a plugin, all under
`default/omarchy/plugins/`, installed to `/usr/share/moarchy/plugins`.

| Plugin | Kind | What it owns | Contract |
| --- | --- | --- | --- |
| `moarchy.gestures` | panel | the bottom strip, the home pill, the back edge — every touch gesture, and the shell's only compositor-dispatch seam | [`gestures.md`](gestures.md) |
| `moarchy.app-app drawer` | overlay | the app grid, its search field, the uninstall card | [`gestures.md`](gestures.md) §N, [`apps.md`](apps.md) |
| `moarchy.workspace-workspace overview` | overlay | every workspace as a card, dragging a window from one to another, and the bin that closes one | [`gestures.md`](gestures.md) §P |
| `moarchy.control-center` | overlay | the pull-down: quick tiles, brightness and volume, media, notification history | [`control-center.md`](control-center.md) |
| `moarchy.settings` | overlay | the settings screen tree and the IPC it answers on | [`settings.md`](settings.md) |
| `moarchy.themes` | overlay | the theme picker, as a grid of live swatches | [`settings.md`](settings.md) §theme |
| `moarchy.wifi` | overlay | pick a network, type a passphrase | [`settings.md`](settings.md) |
| `moarchy.bluetooth` | overlay | pair and connect a device | [`settings.md`](settings.md) |
| `moarchy.sim` | overlay | unlock the SIM, and how many tries are left | [`settings.md`](settings.md) |
| `moarchy.device` | overlay | live hardware: battery, thermals, CPU, memory, storage | [`devices.md`](devices.md) |
| `moarchy.bar` | bar | the status bar, display-only | [`style.md`](style.md) |
| `moarchy.splash` | panel | the launching app's icon, from the tap until its window appears | [`windows.md`](windows.md) §L |
| `moarchy.volume` | panel | the vertical volume track the hardware rocker raises, and mute | [`volume.md`](volume.md) |
| `moarchy.common` | **not a plugin** | the shared code below. No `manifest.json`, so the registry skips it | [`refactor.md`](refactor.md) §E8 |

### What is shared, and the rule about it

`moarchy.common/` is reached as a plain directory import — `import
"../moarchy.common" as Shared` — which needs no `qmldir`.

| File | What it is |
| --- | --- |
| `DragTracker.qml` | one touch sequence → progress, velocity, a latch, and a watchdog. Every gesture on the phone is an instance of it |
| `SheetDragArea.qml` | a control that also drags the sheet it sits on |
| `SheetHeader.qml` | the back-and-title row at the top of a sheet |
| `AppWindow.qml` | a screen that maps as an ordinary window rather than a layer surface |
| `PressVeil.qml` | the pressed state |
| `Probe.qml` | a `Process` that hands back what the command printed |
| `Osk.qml` | the one place the on-screen keyboard is asked to show or hide |
| `Sheet.js` | the one list of sheets, how they stack, and what every `open()` does identically |
| `Edge.js` | which axis an edge is, which way it opens, and where a sheet sits part-way in. The one place a sheet's entry edge is arithmetic rather than an `if` |
| `TrailingSquare.qml` | the rectangle that squares off a sheet's trailing corners, on whichever edge is trailing |
| `Apps.js` | a window → its icon, its name, its glyph. The workspace overview's cards draw their tiles from it, and the app drawer asks it whether an app is already running |
| `ShellApps.js` | which of our screens are windows, and the compositor helpers |
| `Theme.js` | the colour arithmetic: luminance, contrast, mix, readableOn |

**A second copy of any of these fails `scripts/style-check.sh`.** That is the
point of the directory: the rule is checked, not written down. The checker's own
header comment is the authoritative list of what it enforces.

## How the screens stack

The thing to know before touching any of them, and the reason a sheet that opens
puts some of its neighbours away and not others:

```
 Overlay   the control center · the gesture strip · the back edge · the right edge ·
           the launch splash · the volume panel
 Top       the app drawer · the workspace overview · the theme picker · the status bar ·
           moarchy.device
           the on-screen keyboard (moarchy-keyboard, its own package)
 windows   Settings · Wi-Fi · Bluetooth · SIM — and every app
 Bottom    the home catcher, under everything
```

Two consequences that are easy to get wrong, and have been:

- **A sheet opening puts away every sheet on its own layer or above it, and none
  below.** So the control center covers nothing (nothing is above it), the app drawer and the
  picker cover each other and the control center, and a *window* is under all three and
  clears all three. One implementation, `Sheet.js`; the rule is
  [`refactor.md`](refactor.md) §B6 and `node scripts/sheet-test.js` runs it.
- **Our four screens that are windows are windows.** The compositor puts them
  away and brings them back, they live on workspaces, and the back gesture asks
  which window is focused rather than walking a list ([`gestures.md`](gestures.md)
  K1, K7).

## Words used precisely

| Term | Meaning |
| --- | --- |
| **strip** | the 20px band along the bottom edge that `moarchy.gestures` reserves off every window, permanently |
| **edge** | one of the two 16px bands `moarchy.gestures` takes touch in ahead of an app: the left one is back, the right one raises whichever sheet is set for it ([`gestures.md`](gestures.md) Q1). A swipe in from one is a **left-edge** or **right-edge swipe** — the edge is the band, the swipe is the gesture |
| **sheet** | a full-screen surface that is dismissed rather than left running: the control center, the app drawer, the workspace overview, the theme picker |
| **shell app** | a screen this shell draws and maps as an ordinary window: Settings, Wi-Fi, Bluetooth, SIM |
| **overlay / panel / bar** | the three plugin *kinds* the host knows. A "sheet" is our word; `kind` is the host's |
| **travel** | the distance in scene pixels that carries a drag's progress from 0 to 1 |
| **the common dir** | `default/omarchy/plugins/moarchy.common/` — shared code, and not a plugin |

## Where a change goes

| If you are changing… | …the file is |
| --- | --- |
| what a swipe does | `moarchy.gestures/Service.qml`, and `gestures.md` first |
| which sheet an edge raises | nothing in the shell — it is `~/.config/omarchy/ui.toml`, written by Settings ([`gestures.md`](gestures.md) Q1) |
| how a drag feels — thresholds, flings, slop | the *surface's* own properties. `DragTracker` deliberately owns no threshold |
| what a sheet covers when it opens | `moarchy.common/Sheet.js`, nowhere else |
| a settings row | `moarchy.settings/Pages.js` — the tree is data |
| what ships on the phone | `pkgbuilds/moarchy-meta/PKGBUILD`'s `depends`, with `apps.md` as its readable half |
| the version of anything | `manifest.toml`, and nowhere else |
| what a tap runs | `bin/` — and `bin/omarchy-*` only to answer a name upstream calls |
| a per-device fact | the device package. Nothing else in the tree may name hardware ([`devices.md`](devices.md) D2) |

## The rest of the tree

| Path | What it is |
| --- | --- |
| `bin/` | everything installed to `/usr/lib/moarchy/bin`, which precedes `/usr/bin` on PATH. `moarchy-*` are ours; `omarchy-*` shadow upstream commands we have ported or redirected |
| `default/` | files installed under `/usr/share/moarchy` and `/etc`: sway config, plugins, systemd units, udev rules, theme templates, fontconfig |
| `config/sway/config` | the entry point sway is started with; it includes everything else |
| `pkgbuilds/` | one directory per package we build. `moarchy` is the overlay, `moarchy-meta` is what the image installs, `moarchy-device-*` is where hardware is named |
| `manifest.toml` | every version pin in the project. Read by `scripts/manifest.sh`, which 14 PKGBUILDs source |
| `image/` | the flashable image: a Dockerfile, a build, and per-device boot backends |
| `scripts/` | the host side — build, flash, provision, verify, style-check |
| `docker/`, `repo/` | the aarch64 package builder, and publishing the pacman repository |
| `docs/` | this directory. Contracts, decisions, the log |

## Three copies of everything, which is the usual way to lose an afternoon

The worktree is not what the phone is running. There are three trees, and a
stale one fails exactly like the bug you were chasing:

1. this repo,
2. `/usr/share/moarchy/plugins/` on the phone — what the shell loads,
3. `/usr/lib/moarchy/bin/` on the phone — what a tap runs.

and a fourth that outranks the second: `~/.config/omarchy/plugins/`, where a
user copy of a plugin *wins over the packaged one*, for the whole directory.

The shell does not watch its files: quickshell reads its QML once, at startup, so
a plugin edit does nothing until it restarts — and it has to restart in a way
that keeps its seat, or polkit starts asking for a password this image has not
got. `default/pacman-hooks/50-moarchy-shell-reload.hook` says so after an
upgrade rather than doing it, for exactly that reason.

## What to run

| | |
| --- | --- |
| `scripts/style-check.sh` | the whole static half: tokens, type, colour, shape, press states, the shared-code rules, the sheet rule, and that every shipped SVG parses. Runs anywhere |
| `node scripts/sheet-test.js` | the stacking rule, against the shipped `Sheet.js` |
| `python3 scripts/test-workspace-layout.py` | the workspace-layout rule ([`gestures.md`](gestures.md) P7), against the shipped daemon with `swaymsg` stubbed |
| `bin/moarchy-selftest` | on the phone. `--gestures`, `--settings`, `--surfaces`, `--windows` are opt-in suites, and they cite the criterion ids in these documents |
| `scripts/provision.sh` | the dev loop, one step per verb: `steps` lists them, no argument runs prereqs → image → build → flash, then `deploy`, `install`, `watch`, `verify` once the phone is up |
| `scripts/build-image.sh`, `scripts/verify-image.sh` | the flashable image, and the checks against it |

A criterion with no runnable check is visible on purpose:
[`gestures.md`](gestures.md)'s `## Coverage` lists which ones a suite actually
executes, and `style-check.sh` prints what it is not able to check.

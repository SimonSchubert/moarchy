# Refactor — specification

What has to be true when the duplication in the sway layer and the shell plugins
is gone. Present tense, normative. The archaeology of *why* the duplication is
there lives in [build-log.md](build-log.md); the behaviour that must survive it
is [gestures.md](gestures.md) and [style.md](style.md); this file is the
contract for the shape of the code underneath both.

This is a refactor, so every AC is one of two kinds: something that must become
true, or something that must **stay** true while it does. §G is the second kind
and is not optional — a refactor that quietly changes a gesture is a rewrite.

Two of the duplicates have already drifted, and one of those is a defect
(§B4, §C1). Those come first: they are the argument for the rest of the file.

## Vocabulary

| Term | What it means |
| --- | --- |
| **copy** | The same code written out in two files. Not a call to shared code — a second text of it. |
| **canonical list** | A list of surface ids written once and read everywhere. `gestures.md` A8 already says why: "Three hand-kept lists of overlay ids is how Settings and Themes came to be missing from the back gesture." |
| **shell app** | `gestures.md` K10: a screen this shell draws and maps as an ordinary window. Four of them — Settings, Wi-Fi, Bluetooth and SIM. |
| **sheet** | A full-screen surface that is dismissed rather than left running: shade, drawer, themes. |
| **the common dir** | `default/omarchy/plugins/moarchy.common/`, proposed in §E. It has no `manifest.json` and is not a plugin. |

---

## A. Delete what nothing runs

**A1** `bin/moarchy-gestures` is gone. Nothing starts it — `default/sway/autostart.conf:76-80`
says so in a comment, and the plugin that replaced it has been the only gesture
source since. "Kept for reference" is what git history is for.

**A2** `lisgd` is off the package set (`pkgbuilds/moarchy-meta/PKGBUILD:116-119`).
It is in it *only* to satisfy A1's script, and it is one of the three packages
that force `[danctnix]` into `image/Dockerfile:14-18` and into
`docs/structure.md:621`. Dropping it is one fewer foreign package, not one
fewer repo: `mmsd-tng` and `portfolio-file-manager` still need `[danctnix]`.
→ `grep -rn lisgd pkgbuilds/ image/ bin/ default/` matches only prose. A name
in a comment explaining what a thing replaced is history and stays; a
`depends` entry, an `exec` line or a `pgrep` is what has to be gone.

**A3** `bin/moarchy-selftest:136-141` stops asserting that lisgd is not running.
A check that a deleted script's dependency is absent is a check with nothing
left to catch.

**A4** `bin/moarchy-touch:17` no longer explains its coordinate convention by
pointing at a file that does not exist. The convention stays; the citation
becomes the panel resolution it always meant.

---

## B. One list of surfaces

Six files hand-keep an answer to "which surfaces are there", and they give four
different answers. This is the exact failure `gestures.md` A8 records as already
having happened once.

**B1** There is one canonical list of overlay ids and one canonical list of
shell apps, and neither is written twice.

**Done, 2026-09-08.** The shell-app list is
`moarchy.common/ShellApps.js`, imported by both plugins that need it; the
overlay list stays `moarchy.gestures`' `overlayIds` and is now sheets only,
because a shell app is a window and not an overlay at all (`gestures.md` K1).

It had already drifted exactly as this section predicted. `Service.qml` held an
`isShellApp()` that answered `moarchy.settings` and nothing else, under a
comment reading "One, and deliberately so", while `moarchy.recents` held
`shellApps: [settingsApp, wifiApp, bluetoothApp]` and the specification said
three. The carousel was right and the gestures plugin was a version behind it.

**B2** The "put the other surfaces away" guard in each plugin's `open()` derives
from B1's list rather than naming ids. Four spellings exist today:

| Plugin | What it puts away |
| --- | --- |
| `Device.qml:94`, `Wifi.qml:369`, `Themes.qml:158`, `Bluetooth.qml:522`, `Recents.qml:731` | shade, drawer |
| `Drawer.qml:463` | shade |
| `Settings.qml:373` | shade, drawer, recents, themes |

**B3** No file answers "is this a shell app" from a list of its own.

**Done, and by deletion.** `isShellApp()` is gone rather than corrected: a shell
app is a window, so the questions that used to be asked of that list — is one on
screen, which workspace is it on, does the back gesture belong to it — are asked
of the compositor instead. The one thing still resolved by id is which *plugin*
owns a given window, and `ShellApps.forToplevel()` answers it by comparing
handles rather than by matching ids or titles a second time.

**B4 — the defect.** A back swipe over Wi-Fi or Bluetooth reaches that surface,
not the app behind it.

`topmostOverlay()` (`Service.qml:272`) walks `overlayIds`, which omits both. So
back over Wi-Fi finds no overlay, then finds no `omarchy.` popup, then asks
`focusedToplevel()` — which reads null, because Wi-Fi is a layer surface holding
keyboard focus and every window under it reads deactivated — and falls through
to `dispatch("kill")`. That closes whatever sway considers focused while the
Wi-Fi sheet is still on screen. It is word for word the failure the `overlayIds`
comment says the list was introduced to fix, reappearing in the two surfaces
added after it. Both plugins define `quit()` (`Wifi.qml:395`,
`Bluetooth.qml:547`) and `backTopmostOverlay()` would call it — it is never
reached.

→ On the phone: `omarchy-shell wifi open`, then `omarchy-shell gestures back`.
It must answer with Wi-Fi closing and the app behind it still open.

> **Reproduced on the device, 2026-09-07.** One `foot` on workspace 1, Wi-Fi
> opened over it, `gestures back`:
>
> | Build | Wi-Fi after back | Windows |
> | --- | --- | --- |
> | pre-fix (`c8e07e4`) | still **open** | 1 → **0** |
> | post-fix | **closed** | 1 → 1 |
>
> The pre-fix run is the failing branch, run deliberately: a check that only
> ever sees the fixed build cannot tell a fix from a check that measures
> nothing.

**B5** Back over a shell app *ends* it rather than parking it, and does not
return to whatever opened it. This is K6 already, and it is what Settings has
always done. Stated here because it applies to all three screens, and it is the
kind of thing that reads as an oversight the first time it is noticed. Whether a
back swipe out of Wi-Fi *should* land back on the Settings row that opened it is
a real question and a separate one; today all three answer it the same way.

The route changed with `gestures.md` K7 and the answer did not. Back no longer
walks a list of open overlays looking for one that owns a page stack; it asks
which window is focused, and hands the gesture to that window's plugin. The
same `goBack()`-then-close pair, keyed on something the compositor knows.

**B6** A sheet opening puts away every sheet on **its own layer or above it**,
and none of the ones below it. The shade is the only sheet on Overlay, so it
puts nothing away; the drawer and the theme picker are both Top, so each puts
away the other and the shade above them.

*Done, 2026-09-15.* B2's table asked which ids each `open()` should name and
took the answer to be one list. It is not a list — it is the layer the sheet
sits on — and reading it as a list produced a defect in each direction. The
shade dismissed the drawer it was about to draw over, which cost you the sheet
you were reading; the drawer did not dismiss the theme picker, so two Top
surfaces with `Exclusive` keyboard focus stacked in map order, the same fault
`gestures.md` G10b records for two Overlay surfaces contesting a corner.
→ `grep -n 'hide("moarchy' moarchy.shade/Shade.qml` matches nothing; the same
grep matches `moarchy.shade` and `moarchy.themes` in `Drawer.qml`, and
`moarchy.shade` and `moarchy.drawer` in `Themes.qml`

---

## C. One workspace policy

**C1** "The lowest workspace number sway does not have" has one answer.

It is implemented twice, and both implementations are commented as being the
same rule:

| | `Service.qml:389` (QML) | `moarchy-one-app-per-workspace:90` (Python) |
| --- | --- | --- |
| keys on | `workspace.number` | `int(workspace["name"])` — named workspaces silently skipped |
| when 1–10 are taken | `return 10` — **an occupied workspace** | returns 11 |

So with ten workspaces in use, the home gesture switches onto one that already
has an app on it. That is the same class of bug `Service.qml:370-388` documents
at length for a different cause, and it fails the same way: home lands on an app.

**C2** Whichever answer survives, the cap is removed or justified. Sway's
bindings only reach 1–10 (`default/sway/bindings.conf:56-65`), but the home
gesture is not a binding and has no reason to stop there.

**C3** One process owns the policy. If the two implementations stay separate —
forking `swaymsg` at touch rate is not acceptable, and only the `home` action
needs the answer — then they cite each other and a selftest case runs both and
compares. Two copies with a test is a defensible answer; two copies with a
comment is what is there now.

---

## D. One way to blank the screen

**D1** Every path that powers the panel off or on goes through `bin/moarchy-screen`,
so the lock flag is the single gate.

Three call sites today, honouring two different flags between them:

| Site | Honours |
| --- | --- |
| `bin/moarchy-screen:46,51,62` | `screen-locked` |
| `bin/moarchy-idle-blank:15` | `stay-awake` |
| `bin/omarchy-brightness-display:15,18` | neither |

**D2** `omarchy-brightness-display off` and `on` route to `moarchy-screen blank`
and `moarchy-screen wake`. The `on` half is the behaviour change and is the
point of it: today that branch lights the panel behind a lock. Our own bindings
never pass `off`/`on` (`bindings.conf:208-209` pass only `+5%` and `5%-`), so
this is latent rather than live — it is reachable from upstream Omarchy callers,
which is exactly what a shim exists to catch.

> **`blank`, not `lock`, and `moarchy-screen` gains the verb.** This AC first
> said `off` → `lock`, which is wrong and the implementation is what showed it:
> `lock` sets the flag, and `wake` refuses to power on while the flag is set.
> An idle timeout or a plain "display off" routed through `lock` would leave
> the panel dark with its own resume hook declining to undo it. `blank` is the
> dark-panel-live-touchscreen-no-flag verb both callers actually mean; `lock`
> stays what the power button does.

**D3** `moarchy-idle-blank` keeps its own flag check and calls `moarchy-screen
blank`. The stay-awake condition belongs where swayidle can see it; the
blanking does not.

**D4** The selftest's own panel recovery goes through `moarchy-screen unlock`
rather than two `swaymsg` lines. It wanted power on *and* touch back, which is
what `unlock` is, and it left the lock flag set behind a lit panel — so the
next `wake` would have refused.
→ `grep -rn 'output \* power' bin/ default/` matches only inside
`bin/moarchy-screen`

---

## E. Shared plugin code

**E1** A plugin can import from a sibling directory. **Answered on the device,
2026-09-07: yes, in both forms.** `moarchy.device` was given a probe against a
throwaway `/usr/share/moarchy/plugins/moarchy.common/`, the shell restarted
through `swaymsg exec` so it kept its seat, and `omarchy-shell device geometry`
came back `common=common-ok veil=ok`:

| Form | Import | Result |
| --- | --- | --- |
| JS library | `import "../moarchy.common/Theme.js" as Common` | `Common.marker()` ran |
| QML component | `import "../moarchy.common" as Shared` | `Shared.PressVeil {}` constructed |

Two things fell out of the same run and both matter. The directory has no
`manifest.json` and the patched `PluginRegistry` skipped it silently — all
eleven plugins still answered their IPC, and `~/.local/state/moarchy/shell.log`
carried no scan warning. And a directory import needs no `qmldir`: the
component is named by its filename.

→ the probe is not in the repo; it was created, read and removed on the device.
Anything §E lands has to re-prove this, because the packaged path is what
matters and a `/usr/share` edit is not a package.

**E2** `PressVeil` is defined once, in `moarchy.common/PressVeil.qml`. *Done for
seven of nine plugins.*

Each plugin keeps a one-line inline component rather than importing the type at
every call site:

```qml
component PressVeil: Shared.PressVeil { ink: root.textOnSurface }
```

That shape is forced and is the better answer. `ink` must default to the
*surface's own* text colour (`style.md` H2), which a shared type cannot know —
and 20 of the 29 call sites relied on that default. Binding it once per plugin
leaves all 29 untouched, so 27 duplicated lines become one line that says
something true about its own screen. `SettingsRow`'s default is `card.textColor`
rather than `root.textOnSurface`, which is exactly the per-plugin fact this
line exists to carry.

**E3** `luminance`, `contrastRatio`, `mix` and `readableOn` are defined once, in
`moarchy.common/Theme.js`. *Done for six of six plugins that had them;* the ten
external call sites now read `Theme.readableOn(…)` / `Theme.mix(…)`.

`.pragma library`, so there is one instance rather than a copy per importing
component. That was the risk in this AC: a library script has no QML component
scope, and `mix()` returns `Qt.rgba(…)`. **Verified on the device** — the shade
and the drawer both draw their `subdued` greys legibly, and a `mix()` that threw
would leave `subdued` undefined, which paints black on a dark surface rather
than failing loudly.

> **322 lines removed from seven files, 43 added.** `Settings.qml` and
> `SettingsRow.qml` are not migrated: another session owns them and had them
> open. They are named in `style-check.sh`'s `E7_EXEMPT`, so the debt is
> counted rather than invisible, and E7 fails the day that list stops
> describing reality.

**E4** *Not done, and not by omission.* The strip height is one number. Seven
declarations of `Style.space(20)`
— `stripHeight` in `moarchy.gestures`, `gestureStrip` in the shade, the drawer
and the theme picker — each carrying a comment saying it must match the others.
The comments are right, which is the problem: a constraint stated four times is
not enforced once.

> **Amended 2026-09-15: four, not seven.** This AC named seven and listed
> Wi-Fi, Bluetooth and Settings among them. Those three became windows (§B3) and
> dropped their declarations with the layer surface that needed them, so three
> of the seven went away without anyone closing anything. The count is the
> claim, so the claim is corrected here rather than restated in §M — and the
> line numbers are gone, because all seven of them had moved by the time this
> was read back.

> **Blocked on a mechanism E1 did not test.** This number is
> `Style.space(20)`, and `Style` is a QML singleton from `qs.Commons` — which a
> `.pragma library` script cannot reach, so `Theme.js` is the wrong home for
> it. The options are a `qmldir` declaring a singleton in `moarchy.common`, or
> a plain item each plugin instantiates. E1 verified a *directory import with
> no qmldir*; adding one changes the shape and has to be proved on the device
> before six files depend on it. Deliberately left rather than guessed.

**E5** The extended-sheet margin (`gestures.md` I5a) is written once. **Closed
by §I4**, which is the same block of the same files: the margin belongs to the
sheet header, and a second component for it would be a second place to forget.

> **Amended 2026-09-15: two, not five.** As with E4, three of the five named
> here are shell apps now and have no margin to write. What is left is the theme
> picker and the drawer.

**E6** `style.md` C2 is amended to match. It currently justifies per-surface
palette blocks with "a shared singleton can only serve one of them" — true of a
singleton, false of a component taking the layer as a property. The six *role
declarations* stay per-surface, because C1's two palettes are real; the
arithmetic underneath them stops being copied six times, and C3 points at the
one implementation.

**E7** `scripts/style-check.sh` gains a duplication check. *Done.* No plugin
outside `moarchy.common` defines `PressVeil` or any of the four colour
functions. A rule that only lives in this file is a rule the tenth plugin
breaks — the same argument `style.md` opens with.

The exemption list is part of the check, not a hole in it. `E7_EXEMPT` names
the two un-migrated files, and the check **also fails when an exemption stops
describing anything** — a stale entry reads as remaining debt and would
silence a real regression in that file. Both failing branches were run: a
`PressVeil` put back into `Device.qml` fails it, and adding `Wifi.qml` to the
exemption list fails it.

**E8** The common dir is not a plugin. *Done.* It carries no `manifest.json`, so
the patched `PluginRegistry` scan (`pkgbuilds/omarchy-config/port-4x.patch:436`)
skips it — verified on the device, all eleven plugins still load and the scan
logs nothing — and `pkgbuilds/moarchy/PKGBUILD` copies it with everything else
in `default/omarchy/plugins/` because `cp -a` takes the tree. That last part is
load-bearing rather than incidental: a plugin whose import target did not ship
would fail to load, so the PKGBUILD now says so where the copy happens.

**E9** The press veil is still drawn under a finger. **Not verified.** The
plugins load, the surfaces render and no `ink` binding failed, but a veil is
invisible at rest by construction (`visible: color.a > 0`), so a screenshot of
an idle screen proves nothing about it. Two synthetic-touch attempts measured
zero difference and both were the *test* failing, not the code: `sudo` resets
PATH, so `sudo moarchy-touch` was never found, and the error went into a
`/dev/null` I had put there. With the absolute path it ran — and by then
another session had the phone with an app focused, so the touch went into their
surface. It needs the device to itself.
→ `sudo /usr/lib/moarchy/bin/moarchy-touch hold 130 330 5000` over an open
shade, `grim` mid-hold, and the Silent tile lifts by 12% of its own ink

---

## F. One drag tracker

**Done, 2026-09-15**, across six input areas on four surfaces: the strip and
the wallpaper in `moarchy.gestures`, the sheet and the handle strip in
`moarchy.drawer`, the sheet and the status-bar band in `moarchy.shade`. The
component is `moarchy.common/DragTracker.qml`.

**F1** There is one component that turns a touch sequence into `progress`,
`velocity` and a latch, and every surface that needs one uses it.
→ `scripts/style-check.sh` finds `velocity * 0.6` in one file, and that file
is the tracker

**F2** The watchdog comes with it, so a stranded touch cannot park a sheet
half-open on any of them.
→ a touch held on the drawer's handle past the watchdog leaves
`omarchy-shell drawer state` == `open` and `drawer dragTrace` ending `-2`; a
real cancel ends `-1`

**F3** Thresholds stay with the surface, not the tracker. `homeCommit`,
`drawerCommit`, `closeCommit`, `openFraction`, `closeFraction` and the fling
limits are per-gesture decisions recorded in `gestures.md`, and `finished`
hands back two numbers and says nothing about what they mean.
→ `grep -nE 'Commit|Fraction|fling|homeExtra'` over `DragTracker.qml` matches
only comments, which `scripts/style-check.sh` asserts

**F4** `targetTravel()` survives unchanged in meaning: the drawer divides by
its own `closeTravel` and the strip by `pullTravel`, and the tracker takes the
travel as an input rather than choosing it.
→ `grep -nE 'closeTravel|sheetHeight|pullTravel|screen\.height'` over
`DragTracker.qml` matches only comments

**F5** The tracker publishes both a clamped `progress` and an unclamped
`travelled`. A6's second stop is *past* a full sheet, at pull 1.15, so a
tracker that clamped would leave every sheet working and the home gesture
unreachable — which is the shape of defect that is found by hand a week later
rather than by a check.
→ `omarchy-shell gestures status` mid-drag reports `pull` above 100 when the
finger is past a full sheet

**F6** The tracker publishes; it never assigns another surface's `progress` and
never reaches for the host. The gestures plugin drives the drawer through a
direct object reference frame by frame, and a shared component that went
through `shell.callIfLoaded` would marshal a string per touch event on the one
path that cannot afford it.
→ `grep -nE 'panelLoaders|shell\.|execDetached|Quickshell\.'` over
`DragTracker.qml` matches only comments

**F8** A control that presses a tracker ends that touch on every path out,
with a release or a cancel. The press arms the watchdog, so one that returns
without ending leaves it running — and four seconds later the tracker concludes
the touch was stranded and puts `progress` back, which lands on whatever
gesture comes *next*.

Two controls did exactly this and had done for as long as they existed: the
drawer's shelf-tile flick and the shade's brightness slider both returned early
on their own branch. Neither cost anything before F2, because there was no
watchdog to strand — which is why the imbalance survived to be found.
→ with no finger on the screen, `omarchy-shell drawer geometry` and
`omarchy-shell shade sheet` both report `drag=idle`; `bin/moarchy-selftest
--gestures` asserts it after every gesture it drives

**F7** Latching and moving are separate. A surface whose whole area is a
handle — the drawer's grab bar, the shade's band — claims the gesture on the
press, because `dragging` from the touch is what keeps the shade's input mask
off and the drawer's `opened` honest for the length of the pull; it still
crosses a slop before anything moves. Collapsing the two lets a 2px wobble on
the status bar start opening the shade.

### Still open

The drawer's handle commits on distance alone where its sheet also takes a
fling (`gestures.md` A3). The two are separate tracker instances, which is what
lets them differ; whether the handle *should* differ is a real question and
not one a refactor may answer (G4).

The four-line quartet each control on a sheet opts into —
`onPressed`/`onPositionChanged`/`onReleased`/`onCanceled` — is written out
eight times in `Shade.qml` and four in `Drawer.qml`. A control that omits it
silently cannot be dragged, which is a live failure mode and not a tidiness
question. A sheet-wide handler cannot replace it: `Drawer.qml` and `Shade.qml`
both record, from measurement, that a `DragHandler` over the content gets one
translation event per gesture because every content `MouseArea` holds the
exclusive grab. **Taken up as §H3**, which keeps the twelve areas and shares
what each of them forwards.

Three more copies of the tracker's own arithmetic were found outside the six
areas §F converted, one of them a whole gesture with no watchdog. **§H.**

---

## G. What must not change

**G1** Every AC in `gestures.md` still holds, and `bin/moarchy-selftest --gestures`
still cites them. §B and §F touch the gesture code; they are the sections most
able to break it silently.

**G2** Every AC in `style.md` still holds and `scripts/style-check.sh` passes.
§E moves the code the checker reads, so the checker's globs move with it.

**G3** The selftest's line coverage does not fall. `10719e4` made O7 count
coverage lines specifically so a refactor could not pass by measuring nothing
(`green-is-not-verified`).

**G4** No behaviour changes except D2 and B6, each named as a change and given a
reason. A refactor that fixes B4 and C1 is fixing defects against the existing
specification, not changing it.

**G5** The three copies stay in step. Worktree, phone plugin dir and phone bin
are three trees (`three-trees-stale-copy`), and §E adds a directory that must
arrive in all of them — a stale common dir fails exactly like the missing import
E1 tests for.

---

## H. One drag tracker, for every gesture

§F unified six input areas on four surfaces and stopped. Four copies of the same
arithmetic stand outside them, one of them a whole gesture. This is the rest of
§F rather than a new idea, and the citations below are greppable rather than
line-numbered, because every line number §E4 and §B2 carry went stale inside a
week.

**H1** The back edge is a `DragTracker` instance. It keeps its own start
coordinates, its own 0..1 clamp, its own axis-dominance test, its own trace ring
— and alone among the five gestures **no watchdog**, which is the one thing §F2
exists to guarantee. A back swipe interrupted by a lost seat leaves the drawn
cue on screen with nothing to retire it.
→ `grep -n edgeStart moarchy.gestures/Service.qml` matches nothing, and a touch
held on the back edge past the watchdog leaves `omarchy-shell gestures
backTrace` ending `-2`

**H2** The tracker measures one axis, named by the surface. `openDirection`
already reduced four surfaces to one signed factor; the back edge travels on X
and takes the same reduction rather than a second implementation.
→ `grep -nE 'sceneX|\.x\b' moarchy.common/DragTracker.qml` matches the axis
input and its comments, and nothing that assumes Y

**H3** A control that presses a tracker declares it, rather than writing out the
four handlers. The quartet stands twelve times — eight in `Shade.qml`, four in
`Drawer.qml` — and a control that omits one of the four silently cannot be
dragged, or strands the watchdog §F2 added (§F8).
→ `grep -rn 'onPressed: mouse => root.sheetPress' default/omarchy/plugins/`
matches nothing, and `scripts/style-check.sh` fails when a `SheetArea` instance
declares one of the four handlers the shared component forwards -- which
replaces it rather than adding to it, and is the one way back to the failure
above

**H4** *Not done, and the measurement is the reason.* The drawer's shelf-tile
flick and the shade's brightness slider each carry their own slop-and-axis test
against the sheet tracker's sampled origin, and neither becomes a tracker
instance for less than it costs.

> **Both were written and both were reverted.** The slider's hand-over is the
> sheet's latch *plus* an axis-dominance term, applied by a control that must not
> feed the sheet's tracker at all before it hands over -- so sharing the test
> means a second tracker instance on the same touch, which measured **+9 code
> lines** to remove two lines of arithmetic. The tile flick's two tests are each
> a *different* half of the tracker's condition -- a 3px dominance check with no
> slop for the axis arbitration, and a slop check with no dominance for the flick
> -- so there is no single copy to remove; converting it came out size-neutral
> across three criteria (M6, M7, M8) that cannot be re-run without the phone.
>
> F3 already says the commit rule belongs to the surface. These two are commit
> rules, and the honest reading is that H4 mistook them for copies of the latch
> because they are spelled like it. What remains true, and is H5, is that the
> *trace* had to be marked on every surface; that landed.
→ `grep -n dyScene moarchy.shade/Shade.qml` matches the slider's hand-over and
`grep -n 'tileArea.preventStealing' moarchy.drawer/Drawer.qml` the tile's axis
arbitration; nothing else in either file carries a slop-and-axis test of its own

**H5** A cancel marks the trace on every surface that has one. §F2's evidence
sentence — "a real cancel ends `-1`" — is true of the drawer's handle and of
nothing else: the drawer's sheet and both of the shade's trackers leave the
trace unmarked, so that check passes today for three surfaces that cannot fail
it (`green-is-not-verified`).
→ after a cancel on either surface, `omarchy-shell drawer dragTrace` and
`omarchy-shell shade sheet` both end `-1`

---

## I. One sheet

Seven plugins write out the same lifecycle, and five of them write out the same
guard inside it. §B2 tabulated the guard and §B6 found its rule — the layer a
sheet sits on, not a list of ids — and both were held for §E1 to answer. It is
answered.

**I1** The sheet lifecycle is one component. `open`, `close`, `dismiss` and
`returnTo` live in the common dir, and a sheet declares which layer it is on
rather than naming the sheets it displaces.
→ `grep -rn 'hide("moarchy' default/omarchy/plugins/` matches only the common
dir

**I2** No plugin spells another sheet's id inside its own `open()`. §B2's table
is four spellings of one rule; this closes it by deriving the answer rather than
by correcting the four.
→ the same grep as I1, and `omarchy-shell themes open` with the drawer up leaves
`drawer state` == `closed` while `shade open` over the drawer leaves it `open`
(§B6, both directions)

**I3** The sheet header is one component — the title, the circular back button,
its veil and its glyph. Four copies at about thirty-five lines each.
→ `grep -rn 'id: backButton' default/omarchy/plugins/` matches only the common
dir

**I4** The extended-sheet margin arrives with the header. This is **E5**, which
is the same block of the same four files; it is closed here rather than beside
here.
→ `grep -rn 'extendedMargin\|Style.space(20) +' default/omarchy/plugins/`
matches only the common dir

---

## J. One set of shared parts

Not one abstraction — a list of them, each small, each removing a class rather
than an instance. They are one section because they are one pass over the same
nine files.

**J1** The colour roles are declared once. Eight plugins write out six to eight
role bindings over the two palettes `style.md` C1 records, and the arithmetic
under them is `Theme.js` already. A component taking the layer as a property
serves both palettes, which is the thing a singleton could not do — **E6** and
`style.md` C2 are amended to say so.
→ `grep -rlc 'property color containerHigh' default/omarchy/plugins/` matches
only the common dir

**J2** A shell probe is one component. The `Process` + `StdioCollector` +
`bash -c` idiom stands about fifteen times, and the generation guard that keeps
a stale answer from landing on a new question is copied five more.
→ `grep -rn 'StdioCollector' default/omarchy/plugins/` matches only the common
dir

**J3** Long-press is one component. Three implementations today, each carrying
the same "cleared on press, never on release, because `released` precedes
`clicked`" rule in its own words.
→ `grep -rn 'holdFired\|heldFired' default/omarchy/plugins/` matches only the
common dir

**J4** One resolver answers "which app is this". Three implementations today,
and the shade's walks every app entry per notification card where the drawer
built an index precisely so it would not have to.
→ `grep -n 'function entryFor' moarchy.shade/Shade.qml` matches nothing

**J5** A tile is one component and a row is one component. The shade's two tiles
differ in layout and two flags; the drawer draws an icon-and-label cell twice
and a settings row its own comment calls "the same row drawn in
moarchy.settings".
→ `grep -c 'component WideTile\|component SmallTile' moarchy.shade/Shade.qml`
is 1

**J6** `E7_EXEMPT` is empty. `Settings.qml` and `SettingsRow.qml` are the two
files §E2 and §E3 could not take, and the check in `scripts/style-check.sh` was
written so that removing the last exemption tightens it.
→ `grep -n 'E7_EXEMPT=' scripts/style-check.sh` shows an empty string, and the
check passes

**J7** The drawer imports nothing out of another plugin. `Search.js` and
`Guards.js` are pure libraries living in `moarchy.settings`, so the drawer today
will not load unless a sibling plugin's internals are beside it — the header
already warns that a user-directory copy of one and not the other breaks the
path.
→ `grep -n 'moarchy.settings' moarchy.drawer/Drawer.qml` matches only comments

**J8** A host-contract property a plugin never reads is not declared. Four
plugins declare five of them apiece and read one; the host assigns by name into
the plugin root, so an unread declaration buys nothing. The one that is
deliberately unread keeps its comment saying so.
→ each `property var manifest`, `pluginRegistry` and `barWidgetRegistry` left in
the tree has a second reference in its own file, or a comment saying why it has
none

---

## K. One connect-list

**K1** Wi-Fi and Bluetooth share their skeleton. 273 of about 600 normalised
code lines are identical and in the same order: a list of things to connect to,
a row that expands, an error line under it, a field for a secret. Two screens,
one shape, and the second was written by copying the first.
→ `grep -c 'Shared.ConnectList' moarchy.wifi/Wifi.qml
moarchy.bluetooth/Bluetooth.qml` is 1 apiece

**K2** What differs stays with the plugin: NetworkManager against BlueZ, the
scan lifecycle, the glyphs, and the wait BlueZ needs before it will power an
adapter up under a soft block (`shade.md` S6d-8, whose 700ms is an AC and is not
a candidate for anything).
→ `grep -n '700' moarchy.bluetooth/Bluetooth.qml` still matches, and
`bin/moarchy-selftest --settings` still passes its Wi-Fi and Bluetooth blocks

---

## L. One script layer

`bin/` has no sourced library. `scripts/manifest.sh` proved the pattern at build
time and nothing carried it to runtime, so the session environment, the paths
and the notification tool are each re-derived by hand — and one of the
re-derivations names a binary this image does not carry.

**L1** There is one sourced helper under `bin/`, and the things every device
script re-derives come from it: the session environment, the moarchy and omarchy
path roots, the state directory, `osk get`/`set`, a shell refresh, a
first-present resolver and the usage dispatch.
→ `grep -rln 'XDG_RUNTIME_DIR' bin/` matches the helper and
`bin/moarchy-selftest`

**L2** One notification tool, and it is one that is installed. `notify-send` is
absent from this image (`phone-has-no-notify-send`), so the call in
`bin/moarchy-launch-browser` has been a swallowed no-op for as long as it has
existed — the selftest already wraps both tools and records why.
→ `grep -rn 'notify-send' bin/` matches only comments and the selftest's wrapper

**L3** `MOARCHY_PATH` has one spelling. Three today, and one of them defaults to
the installer path that was deleted — the exact failure the selftest's own PATH
check was written about.
→ `grep -rn 'MOARCHY_PATH' bin/ | grep -v '/usr/share/moarchy'` matches nothing

**L4** The twelve shims that only forward to a `moarchy-` twin are one
dispatcher on `${0##*/}`. None of the shims is dead: every one of the
twenty-four names is still called by upstream at the pinned ref, which is why
they are collapsed rather than deleted — and why `docs/upstream.md`'s "shadows
16" is a stale count and not a shorter list.
→ `wc -l bin/omarchy-*` shows no forwarder over three lines, and
`docs/upstream.md` names the measured count

**L5** Our own configuration never calls through a shadow. `bindings.conf`
reaches for both namespaces for the same capability today, which makes the shim
load-bearing for us as well as for upstream.
→ `grep -n 'omarchy-' default/sway/bindings.conf` matches only the commands we
have no twin for

**L6** The recorded editor has one owner. The state path, the fallback and the
ten-entry MIME list are written out across three files, two of them carrying a
comment asking the reader to keep them in step.
→ `grep -rln 'gnome-text-editor' bin/` matches one file

---

## M. The numbers that are still written twice

**M1** The strip height is one number. **This amends E4**, whose list is stale:
Wi-Fi, Bluetooth and Settings became windows and dropped theirs, so there are
four declarations rather than seven. The blocked mechanism is still the blocker
— `Style.space()` is a `qs.Commons` singleton a `.pragma library` cannot reach —
so this lands as a component the plugins instantiate, or it does not land and
says why.
→ `grep -rn 'Style.space(20)' default/omarchy/plugins/` matches the one
declaration, the three `radiusTile` uses that are a different constant with the
same value, and nothing else

**M2** "Is the keyboard up" is answered in one place per question. There are
three answers today: a busctl probe the back gesture waits on, and two copies of
a surface-height threshold with two copies of the `200` it compares against.
The probe and the threshold answer different questions and both stay; the two
copies of the threshold do not.
→ `grep -rn 'keyboardPanelHeight' default/omarchy/plugins/` matches one
declaration

**M3** The fling limit, the hold delay and the slop are held against each other
rather than retyped. Thresholds belong to the surface that decided them (**F3**,
and that does not change) — but three surfaces independently typing `0.6` and
`500` is not three decisions, and the four slop declarations carry three values
with no record of which difference is meant.
→ `bin/moarchy-selftest --gestures` reports the three values it read and fails
when a surface's differs without a comment saying why

---

## N. Defects this survey found

Four, all silent, all found by reading rather than by use. §G4 permits no
behaviour change except the ones named — these are named, and each is a fix
against the existing specification rather than a change to it.

**N1** `openPanelIds` is a set and is read as one. The gestures plugin tests
`open.length` and then indexes it; the host declares `property var
openPanelIds: ({})` and its own comment says "a plain object treated as a set",
so `.length` is `undefined` and **the branch has never run**. A back swipe over
a vendored popup — the menu, the emoji picker, the speed tests, the image
selector — therefore falls past it to the focused window and closes the app
behind the popup. It is §B4's failure on the one path §B4 did not cover, and
`Splash.qml` reads the same property correctly, as a map.
→ with `omarchy.menu` up, `omarchy-shell gestures back` leaves the menu closed
and the window count unchanged; pre-fix it leaves the menu up and the count one
lower

**N2** `rotate()` names no output. It reads the current transform from the first
output and writes the new one to `DSI-1` by name, so it is the only hardcoded
output name in the tree and it silently does nothing on any device whose panel
is called something else. This is `devices.md` §4 row 6, ruled **probe, no key**
by D3.
→ `grep -rn 'DSI-1' default/ bin/` matches nothing, and the shade's rotate tile
turns the screen on the attached device

**N3** The battery path is probed. `Device.qml` reads
`/sys/class/power_supply/axp20x-battery` — the PinePhone's PMIC — behind a
`2>/dev/null` that turns a wrong path into an empty reading rather than an
error, so the Device screen reports no battery at all on sargo. `devices.md` §4
row 5, same rule, same verdict.
→ `grep -rn 'axp20x' default/` matches nothing, and `omarchy-shell device
battery` answers a number on the attached device

**N4** The comment above the back-overlay ladder is true. It states that no
sheet in `overlayIds` owns a page stack and that the `goBack()` branch below it
is therefore kept for a future surface — and the drawer has owned one since its
detail card landed, so that branch fires on every back swipe over an open card.
A comment claiming a live branch is dormant is worse than no comment: it invites
the next reader to delete it.

> **Amended before implementing: the `quit()` guard stays.** This AC first said
> the dead branch was to go, and reading it settled that there are two things
> here, not one. `quit()` is genuinely unreachable — the three surfaces defining
> it are windows and none is in `overlayIds` — but the line above it says so, and
> says it is kept as the same escape hatch `goBack()` is. That is a stated
> decision about an escape hatch, not an oversight, and G4 is not a licence to
> overturn one. What was wrong is the *other* half of the same comment.
→ `grep -n 'No sheet in overlayIds' moarchy.gestures/Service.qml` matches
nothing, and the sentence that replaces it names the drawer

---

## Sequencing

Ordered by value over risk, not by section number.

1. **§A** — deletion, no behaviour, one package fewer in the image. *Done.*
2. **§C**, **§B3–B5** — the two defects, small diffs, both testable from the
   IPC. *Done, unverified on the device.*
3. **§D** — every panel-power call behind one script. *Done, unverified on the
   device.*
4. **§B1–B2** — the per-plugin `open()` guards. Held back deliberately: the
   canonical list now lives in `moarchy.gestures`, and eight plugins reading it
   across a plugin boundary is the cross-directory question §E1 exists to
   answer. Doing it before E1 would build the coupling twice.
5. **§E2, E3, E7, E8** — the shared module and seven of nine plugins. *Done;
   E9 unverified.* **§E4, E5** and the last two plugins remain: E4 needs a
   singleton mechanism nothing has tested, E5 and the two files need the
   session that owns them.
6. **§B6** — the layer rule, and the two defects on either side of it.
   *Done 2026-09-15.*
7. **§F** — the largest win and the largest risk; last, on top of a green G1.
   *Done 2026-09-15*, in the order shade, drawer, gestures: the shade first
   because it is the only surface exercising both latch directions, a non-zero
   start, a freeze-on-begin and a hand-over, so it proves the component before
   anything irreversible; the gestures plugin last because every `gestures.md`
   criterion runs through it.
8. **§N** — the four defects. First of the second pass, for the same reason §B4
   and §C1 came first in the first one: they are small, they are independently
   checkable, and they are the argument for the rest.
9. **§H** — the three tracker copies and the twelve quartets, on top of a green
   §G1. The back edge first: it is the copy with no watchdog, so it is the one
   where the shared component is worth something the day it lands.
10. **§I**, then **§J** — the sheet, then the parts. This order because §I moves
    the block §J's header and colour work would otherwise have to move twice.
11. **§K** — Wi-Fi and Bluetooth. Last of the QML, because it is the largest
    single diff over two screens that are verified today and cheap to break.
12. **§L**, **§M** — the script layer and the numbers. Independent of all of the
    above; they go whenever the phone is not needed for something else.
13. The code map in `docs/README.md`, and the durable content §B6 is holding.
    Before this file can be deleted, not after: `refactor.md` is the only record
    of the layer rule, and this file has an end.

**Verified on the device, 2026-09-07** (192.168.0.18, plugin and bins deployed
into `/usr/share/moarchy` and `/usr/lib/moarchy/bin`, shell restarted through
`swaymsg exec`):

| | Result |
| --- | --- |
| B4 | pre-fix kills the app behind Wi-Fi and leaves the sheet up; post-fix closes Wi-Fi and the window survives |
| C1 | both implementations answer 1, then 3, then 4 as workspaces are taken — including `3:web`, where the old `int(name)` rule picks 3, which is occupied |
| C3 | selftest: *both free-workspace implementations answer 2* |
| D1–D3 | `blank` darkens without setting the flag; `wake` restores; `brightness-display on` under a lock leaves the panel dark and the flag set; unlocked, the same call lights it |
| A1, A3 | `moarchy-gestures` is off PATH; the selftest no longer greps for lisgd |
| E1 | both import forms resolve; eleven plugins still load |

The whole non-opt-in suite is 33 passed, 3 failed. All three failures are
pre-existing and outside this work — `omarchy-menu is missing from
$OMARCHY_PATH/bin` (that directory does not exist on this image; upstream's
bins are installed to `/usr/bin`), and two gsettings reads. None of them appear
in this change's diff.

## Constraints

Not acceptance criteria — the boundaries any implementation works inside.

- **A user plugin override shadows a whole directory, not a file.**
  `~/.config/omarchy/plugins/moarchy.drawer` wins over the packaged one
  (`user-plugin-dir-overrides`), and a `../moarchy.common` import from inside it
  resolves against `~/.config/omarchy/plugins/`, where the common dir may not
  be. §E either ships the common dir to both roots or accepts that an override
  now takes two directories. This is the cost of E1 and it is not avoidable by
  writing the import differently.
- **Nothing here may fork a process at touch-event rate.** `Service.qml:179`
  already records why the gesture holds a direct object reference rather than
  marshalling a string per call. §C3 and §F inherit that limit.
- **The strip reserves 20px off every window, permanently.** §E4 changes where
  the number lives, never what it is.
- **`Style.space()` is theme-scaled** (`style-space-is-scaled`). Every number in
  this file is the source value, not the drawn one, and no AC here may be
  checked by measuring pixels on the panel.
- **`Style` itself does not move or get renamed.** §M1 puts the strip height
  somewhere; it does not touch the singleton the number comes from. The plugin
  kit in the apps repo reaches `Style.font.body` and
  `Style.effectiveSpacingScale` by compiling `import qs.Commons` as a string, and
  a rename there falls back to a default silently rather than failing — so plugin
  text would quietly stop following Settings with nothing on stderr.

## Open questions

- ~~**E1 is unanswered.**~~ *Answered 2026-09-07: yes, both forms, no `qmldir`,
  and a manifest-less directory does not disturb the registry.* §E is unblocked.
- **§E collides with another session's files.** Seven of the nine `PressVeil`
  copies and four of the six colour-maths copies are in `Settings.qml`,
  `SettingsRow.qml`, `Themes.qml`, `Shade.qml` and `Drawer.qml`, and the
  worktree ownership split puts settings and themes on another session's side
  ([[shared-worktree-and-phone]]). §E is one change that touches nine files at
  once, which is the shape that does not divide. It needs agreeing before it
  starts, not merging afterwards.
- ~~**§C3's shape.**~~ *Settled: two implementations, held against each other.*
  One owner would mean the gesture forking `swaymsg` and parsing its JSON
  before `home` can dispatch, which the touch-rate constraint rules out. So
  `moarchy-one-app-per-workspace --free` prints the daemon's own answer,
  `omarchy-shell gestures status` publishes the plugin's as `free=`, and the
  selftest compares them. The check calls the daemon's function rather than
  restating the rule, because a check that reimplements what it checks passes
  against itself.
- **Whether a back swipe out of Wi-Fi should land on the Settings row that
  opened it** (B5). All three shell apps say no today, by taking `quit()`
  rather than `dismiss()`. Consistent, and not obviously right.
- **Whether `overlayIds` should live in the gestures plugin at all.** It is read
  by gestures and needed by eight plugins' `open()`. The host's `shell` object
  is the other candidate, and it is not ours to extend without growing
  `port-4x.patch`.

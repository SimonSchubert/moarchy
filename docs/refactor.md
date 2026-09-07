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
| **shell app** | `gestures.md` K11: a screen this shell draws that behaves like an app. Three of them — Settings, Wi-Fi, Bluetooth. |
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

Today `moarchy.gestures/Service.qml:228` holds `overlayIds` — shade, drawer,
recents, themes, settings — and `Service.qml:239` holds `isShellApp()`, which
answers `moarchy.settings` and nothing else, under a comment reading "One, and
deliberately so". Meanwhile `moarchy.recents/Recents.qml:486` holds
`shellApps: [settingsApp, wifiApp, bluetoothApp]`, and `gestures.md` K11 says
three. The carousel is right and the gestures plugin is a version behind it.

**B2** The "put the other surfaces away" guard in each plugin's `open()` derives
from B1's list rather than naming ids. Four spellings exist today:

| Plugin | What it puts away |
| --- | --- |
| `Device.qml:94`, `Wifi.qml:369`, `Themes.qml:158`, `Bluetooth.qml:522`, `Recents.qml:731` | shade, drawer |
| `Drawer.qml:463` | shade |
| `Settings.qml:373` | shade, drawer, recents, themes |

**B3** `isShellApp()` answers true for all three of K11's shell apps, or the
mechanism and the specification disagree in the file that implements the
specification.

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
always done — `backTopmostOverlay()` calls `quit()`, and `quit()` is the half
that does not summon `returnTo`; only `dismiss()`, which the header chevron
calls, does. Stated here because putting Wi-Fi and Bluetooth on that path makes
it apply to two more screens, and it is the kind of thing that reads as an
oversight the first time it is noticed. Whether a back swipe out of Wi-Fi
*should* land back on the Settings row that opened it is a real question and a
separate one; today all three shell apps answer it the same way.

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

**E2** `PressVeil` is defined once. Nine copies today, 27 lines each counting
the banner comment they all share — 243 lines of one text:
`Device.qml:70`, `Recents.qml:289`, `Themes.qml:118`, `Wifi.qml:122`,
`Drawer.qml:281`, `Bluetooth.qml:146`, `Settings.qml:204`, `SettingsRow.qml:60`,
`Shade.qml:231`. Eight are byte-identical; `SettingsRow`'s differs in one line,
the default for `ink`, which is already a property.

**E3** `luminance`, `contrastRatio`, `mix` and `readableOn` are defined once.
Six copies, byte-identical function bodies, 24–40 lines per file counting
banners: `Bluetooth.qml:157`, `Drawer.qml:292`, `Recents.qml:300`,
`Settings.qml:236`, `Shade.qml:242`, `Themes.qml:133`.

**E4** The strip height is one number. Seven declarations of `Style.space(20)`
today — `Service.qml:68` as `stripHeight`, and `gestureStrip` in `Shade.qml:89`,
`Themes.qml:76`, `Wifi.qml:88`, `Bluetooth.qml:108`, `Drawer.qml:223`,
`Settings.qml:158` — each carrying a comment saying it must match the others.
The comments are right, which is the problem: a constraint stated six times is
not enforced once.

**E5** The extended-sheet margin (`gestures.md` I5a) is written once. Five
copies, three spellings of the focus condition: `Wifi.qml:479`,
`Bluetooth.qml:631`, `Themes.qml:358`, `Drawer.qml:756`, `Settings.qml:1130`.

**E6** `style.md` C2 is amended to match. It currently justifies per-surface
palette blocks with "a shared singleton can only serve one of them" — true of a
singleton, false of a component taking the layer as a property. The six *role
declarations* stay per-surface, because C1's two palettes are real; the
arithmetic underneath them stops being copied six times, and C3 points at the
one implementation.

**E7** `scripts/style-check.sh` gains a duplication check: no two plugin files
contain the same function body. A rule that only lives in this file is a rule
the tenth plugin breaks — the same argument `style.md` opens with.

**E8** The common dir is not a plugin. It carries no `manifest.json`, so the
patched `PluginRegistry` scan (`pkgbuilds/omarchy-config/port-4x.patch:436`)
skips it, and `pkgbuilds/moarchy/PKGBUILD` copies it with everything else in
`default/omarchy/plugins/`.

---

## F. One drag tracker

**F1** There is one component that turns a touch sequence into `progress`,
`velocity` and a latch, and the four surfaces that need one use it:
`Service.qml:803` (strip), `Service.qml:951` (home), `Drawer.qml:864` (handle),
`Shade.qml:1885` (band).

Each re-derives the same machinery: start coordinates, `lastY`/`lastT`, the
identical smoothing `v * 0.6 + (dy / dt) * 0.4`, a slop latch, a 0..1 clamp, a
fling threshold, and commit-versus-spring-back.

**F2** The watchdog comes with it. Two of the four have one (`Service.qml:672`,
`Shade.qml:494`) and two do not, so a stranded touch leaves the drawer parked
where a stranded touch on the shade does not. `Drawer.qml:887` handles cancel
but not the touch that never ends.

**F3** Thresholds stay with the surface, not the tracker. `recentsFull`,
`homeCommit`, `drawerCommit`, `closeCommit`, `openFraction`, `closeFraction`
are per-gesture decisions recorded in `gestures.md`; the tracker owns none of
them.

**F4** `targetTravel()` (`Service.qml:151`) survives unchanged in meaning: the
drawer divides by its own `closeTravel` and the strip by `pullTravel`, and the
tracker takes the travel as an input rather than choosing it.

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

**G4** No behaviour changes except D2, which is named as a change and given a
reason. A refactor that fixes B4 and C1 is fixing defects against the existing
specification, not changing it.

**G5** The three copies stay in step. Worktree, phone plugin dir and phone bin
are three trees (`three-trees-stale-copy`), and §E adds a directory that must
arrive in all of them — a stale common dir fails exactly like the missing import
E1 tests for.

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
5. **§E** — blocked on E1, which needs the phone.
6. **§F** — the largest win and the largest risk; last, on top of a green G1.

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

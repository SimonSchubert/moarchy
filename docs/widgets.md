# Widgets — specification

A widget is a reusable piece of a surface: the brightness slider, the volume
slider, the media card. The **host** decides where it goes; the **user** decides
whether it is there at all and in what order. Present tense, normative.

**What each widget does is not here.** The control center's contents are
`control-center.md`, and that file stays the authority on what the Wi-Fi tile
does and when the media card appears. This one says only how a widget gets onto
a surface, so the two cannot end up as two descriptions of the same slider.

`naming-convention.md` names **widget** as its fourth kind and marks it **?** —
one instance, nothing ratifying it. This is the ratification, and it moves the
kind from "content somebody hardcoded into a layout" to "content the user
arranges".

Lines marked **?** are a decision I am recommending, not one you have made.

Ids are `W<n>`, cited by any check that proves one.

## Vocabulary

| Term | What it means |
| --- | --- |
| **widget** | Content drawn inside a surface someone else owns. No window, no layer, no gesture, no entry in the plugin registry. |
| **host** | A surface that draws widgets. The control center is the first. A lock screen is the second, and is the reason this is a mechanism rather than six more properties on `ControlCenter.qml`. |
| **the catalogue** | `moarchy.common/Widgets.js` — every widget that exists, written once. |
| **the arrangement** | Which widgets one host shows, and in what order. One line per host in `~/.config/omarchy/widgets.toml`. |
| **off** | Named in the arrangement, kept in its place in the order, not drawn. As opposed to **absent**, which is the widget saying there is nothing to draw (W6). |

---

## A. What a widget is

**W1** A widget is one QML file under `moarchy.common/widgets/`. It carries no
`manifest.json`, so the patched `PluginRegistry` scan never sees it
(`refactor.md` E8) and `naming-convention.md`'s four kinds stay three plugin
directories plus a kit.
→ `find default/omarchy/plugins/moarchy.common/widgets -name manifest.json`
prints nothing, and `omarchy-shell shell listPlugins | jq -r '.[].id'` names no
widget

**W2** The catalogue names the id and the file name follows from it —
`mobile-data` is `MobileData.qml` — so the id is written in one place and a
rename cannot leave the two disagreeing.
→ every `id` in `Widgets.js` has a file, and every file in `widgets/` has an
`id`; `scripts/style-check.sh` asserts both directions

**W3** A widget owns its own service wiring. The brightness widget runs the
brightness process, the volume widget holds its own sink. A widget that took
its value from the host would be reusable only where that host had already
written the plumbing — which is the whole of what is being fixed, since
brightness and volume exist today as 90 lines of `ControlCenter.qml` that a
lock screen cannot reach.

The cost is that two hosts drawing the same widget hold two sets of services.
Accepted: a widget is only constructed when it is in that host's arrangement,
and two hosts are not on screen at once.

**W4** A widget draws with what the host hands it and reads no `Color.*`
inline: the six roles of `style.md` C2, the radii of D1, `shell`, and the host
itself. This is the rule `SettingsRow` already follows, and for the same reason
C2 gives — the control center wants `Color.popups` and a lock screen over the
wallpaper will not.
→ `scripts/style-check.sh` finds no `Color.` outside a property declaration in
`widgets/`, and no widget declares one of the six roles for itself

**W5** A widget takes no action a surface owns. It does not summon, hide or
close anything, and it does not dispatch to the compositor. Opening the Wi-Fi
screen from a long press is `host.openScreen("moarchy.wifi")`, and what that
means is the host's answer — the control center closes itself on the way
(`control-center.md` S6b); a lock screen must be able to refuse.
→ `grep -nE 'shell\.(summon|hide|isPluginOpen)|dispatch\(' widgets/` matches
nothing

**W6** A widget publishes `available`. False means the row is not there at all
and the host closes the gap — no disabled tile, no blank card. That is S10's
rule for the torch, and it is what lets the media card and the mobile-data tile
be widgets rather than exceptions.
→ with nothing playing, `omarchy-shell control-center widgets` reports `media
available=0`, and `sheet` reports a height that does not include it

**W7** A widget publishes `implicitHeight` and takes its width from the host.
It sets no `x`, no `y`, no anchors against the sheet, and asks for no position
in the order. The host places it — that is the entire difference between this
kind and the other three (`naming-convention.md`).
→ `grep -nE '^\s*(x|y|anchors\.(top|bottom|left|right|fill|centerIn))\s*:'`
over each widget's root item matches nothing

---

## B. The catalogue

**W8** One list: `moarchy.common/Widgets.js`. Each entry is an id, a display
name, a glyph for the Settings row, the hosts it may appear in, and whether it
is on by default. Nothing else in the tree keeps a list of widgets — `B1`'s
rule, and `gestures.md` A8 already records what a second hand-kept list costs.
→ `git grep -l brightness -- default/omarchy/plugins | grep -v Brightness.qml`
names no file that enumerates widgets

**W9** A widget missing from the catalogue is unreachable, and adding one is a
file plus a row.

**W9a** A **surface** missing from `SURFACES` arranges nothing, and says so.
An unregistered host resolves to an empty catalogue, which draws exactly like a
host whose widgets are all switched off — so the column warns once, naming the
host, rather than leaving "my new surface renders nothing" to be found by
reading.
→ a `WidgetColumn` with an unknown `hostId` logs
`is not in Widgets.js SURFACES` There is no scan of the directory: a directory listing as a
registry makes an id out of a file name and a half-finished file into a
shipped feature.

---

## C. The host contract

**W10** A host draws `Shared.WidgetColumn`, hands it a `hostId` and itself, and
gets its widgets in order. Everything a widget draws with comes off the host by
name — the six roles, the radii, the metrics, the sheet, `openScreen()` — so
the contract is a property list and not an argument list that grows by one
every time a widget wants something. A host writes no `Repeater` of its own and
names no widget id in its layout.
→ `grep -n 'WidgetHost' ControlCenter.qml` matches once, and no widget id
appears anywhere else in the file

**W11** The host resolves the arrangement; the widget is constructed only if it
is on and available. An off widget costs one catalogue entry and no QML object.
→ with `volume` off, `omarchy-shell control-center widgets` reports it and
`sheet` reports a height smaller by the slider

**W11a** The column measures its rows from the **model**, never from a row's
`visible`. In QML `visible` is inherited, so every row reads false while the
surface is down — and the surface is measured while it is down: the control
center reads this column's height to decide what height to open at, and latches
it before the first frame of a pull.

Bound to `visible`, the column measured 0 whenever the sheet was shut, so the
sheet latched a header-sized 70px, dragged down empty with everything clipped,
and snapped to full height on release. It looked like a rendering fault in the
drag and was a measurement taken in the wrong state
(`qml-visible-is-inherited`).
→ `omarchy-shell control-center sheet` reports the same `wanted` with the sheet
**closed** as it does open; `scripts/style-check.sh` fails any size bound to a
child's `visible`

**W12** A widget that fails to load leaves its row empty and the surface
standing. The host logs the id and the error and draws the rest. A broken
widget that took the sheet with it would be the failure
`quickshell-ipc-blocking-fileview` already records in another form — a plugin
that dies on open, with a clean log.
→ a widget file with a syntax error in it still leaves `omarchy-shell
control-center state` answering `open`, and the journal names the id

**W13** The host gives the widget its sheet-drag seam, or null. Every control a
widget draws goes through `Shared.SheetDragArea` (`refactor.md` H3) with the
sheet the host handed it, and `SheetDragArea` tolerates a null sheet so the
same widget works on a host that is not dragged.
→ `omarchy-shell control-center dragTrace` after a drag begun on the brightness
slider ends `-1`, not `-2`

**W14** A host's IPC verb that names a widget answers `absent` when the widget
is not in the arrangement. Not `""` and not `ok`: an empty answer coerces to 0
in the selftest's `[[ ]]` comparisons and reads as a pass
(`empty-ipc-answer-coerces-to-zero`).
→ with `connectivity` off, `omarchy-shell control-center wifiTap` prints
`absent` and the radio is untouched

**W15** `omarchy-shell <host> widgets` prints the resolved arrangement, one per
line: `id on|off available=0|1`. It is the check the rest of this file leans
on, and it is the host's answer rather than the file's, so a file the shell has
not re-read is visible as a disagreement with `moarchy-widgets list`.
`widgetRows` is the same list as JSON with the names and glyphs on it, which is
what the Settings page is built from — one catalogue, asked, rather than a
second one kept in bash.

**W15a** A *write* reads the order from `widgets.toml` and not from that verb.
The shell re-reads the file through a watch, so for a moment after a write its
answer is the arrangement from before it — and two taps in a row on the same
Settings page are well inside that moment. Read back from the shell, the second
tap computes from the pre-write order and undoes the first.
→ `moarchy-widgets hide control-center volume` immediately followed by
`moarchy-widgets up control-center volume` leaves volume both moved and hidden

**W15b** No path writes an empty arrangement. An empty answer is a shell that is
not running or a host that is not loaded, never a surface with no widgets on it,
and a write would turn "I could not read it" into "the user turned everything
off" — which is `empty-list-means-unreadable` with a file at the end of it. The
guard is in the caller and not in a `$(...)` helper, where an `exit 1` ends only
the subshell: written that way it printed its refusal and the write happened
underneath it, leaving `control_center = ""`.
→ with the shell stopped and no `widgets.toml`, `moarchy-widgets hide
control-center volume` exits 1 and creates no file

---

## D. The arrangement

**W16** The arrangement is `~/.config/omarchy/widgets.toml`, one key per host,
value a comma-separated list of ids in the order they are drawn. A leading `-`
keeps a widget in the order and turns it off.

```toml
control_center = "connectivity, mobile-data, toggles, brightness, volume, -media"
```

**W17 — why not `ui.toml`.** `moarchy-ui write_file` rewrites that file whole
from a fixed set of variables, and `Ui.js serialize()` is written to do the
same, so a key neither of them knows is deleted the next time anybody changes a
corner radius. An arrangement grows a key per host and a name per widget; a
file rewritten from a fixed list is the wrong container for one, and the
failure would be silent and a week late.
→ `moarchy-ui corners modest` leaves `widgets.toml` untouched

**W18** Absent is not empty. A missing file, a missing key or an unparseable
line is the catalogue's default order in its default states — the control
center exactly as it ships. `structure.md` P1's rule: the package never writes
a file into a home, so absence is the shipping state and must be the good one.
→ `mv ~/.config/omarchy/widgets.toml{,.bak}` and the control center is
unchanged

**W19** A catalogued widget the key does not name is appended in catalogue
order, in its default state. This is what makes an upgrade that adds a widget
visible to somebody who has already arranged theirs, and what stops a key
written by an older version from freezing the list.
→ delete `volume` from the key, reload: it is back, last, and on

**W20** An id in the key that no widget answers to is dropped without
complaint, and the next write does not preserve it. A hand-edited file and a
widget removed by an upgrade are the same case.

**W21** `bin/moarchy-widgets` is the only writer: `list`, `rows`, `show`,
`hide`, `up`, `down`, `reset`, `summary`. Settings writes through it and so
does an agent editing the phone. Writers that rewrite a file whole are how W17
happened; this one is the only one, so there is nothing to keep in step.
→ `git grep -l 'widgets\.toml' bin/ default/` names `moarchy-widgets`, the
kit's file watcher, and prose

**W22** A change lands with no restart. The file is watched the way `ui.toml`
is (`UiFile.qml`), and the host rebuilds its column on the change.
→ `moarchy-widgets up control-center volume` with the control center open and
the slider moves while it is on screen

---

## E. Settings

**W23** `Settings > Appearance > Control Center` **is** the widget arrangement.
There is no page of nav rows in front of it: a menu whose whole content is the
thing you asked for is a tap nobody wanted.

The quick toggles are a second arrangement page, reached from the **Edit tile
in the toggles widget itself** rather than from a row in Settings — which is
where somebody looking at the toggles already is. It keeps its dotted id, so
back from it walks up to the widgets page.
→ `omarchy-shell settings goto appearance.control-center` then `settings rows`
lists the widgets, not two nav rows

**W24** An arrangement page is declared by `arrange: "<surface>"` in `Pages.js`
and drawn by `ArrangeView`, in place of the row list rather than beside it.
Settings adds a page and no machinery; a third surface is a third line.
→ `grep -c 'arrange:' Pages.js` is 2

**W24a** An arrangement page answers `settings rows` with **its cards**, one per
line as `id  shown|hidden|divider  height`, in the order they are drawn. The
divider is a row like any other, so which side of the line something is on is
answerable from a terminal.

It exists because the first version could only be checked by looking at a
screenshot and counting rectangles, and a collapsed preview looks exactly like
a missing widget. Two separate faults were chased that way before this verb
printed the truth in one line.
→ `omarchy-shell settings goto appearance.control-center.widgets` then
`settings rows` lists seven widgets and a `--divider--`

**W24c** A widget that arranges a list of its own carries a **way in to it on
its card**, under the drag handle — and **nowhere else**. The toggles are the
only one: their catalogue entry names the surface (`arranges`), the page that
arranges that surface is found by asking `Pages.js` which page declares it, and
the view emits `navigate` for Settings to push.

It was a tile in the control center's own toggle grid first, and that was
wrong: a control you only want while rearranging does not belong on the thing
being rearranged, and it cost the default grid a whole row.
→ the toggles card on `appearance.control-center` has a pencil under its
handle; the control center's own toggle grid has four tiles in one row

**W24b** The view re-seeds when its **surface** changes, not only when the file
does. Settings keeps one `ArrangeView` and hands it a new `surface` when you
navigate between the two pages, so without this the model still holds the
previous surface's ids — and since none of them is in the new catalogue, every
card collapses to a bare handle. That reads as "the previews are broken" rather
than "this is the wrong list". The measured heights are dropped with it: they
are keyed by id, and the ids are what just changed.

### W25–W27. What a card shows

**W25** A card is **a drag handle and the real widget**, with mock data. Nothing
else: no name over it and no switch beside it. A name tells you nothing about
what a widget looks like or how much room it takes — the two things somebody
arranging them is deciding — and both it and the switch were chrome between the
reader and the picture. The list should read as the surface it is arranging.
→ `Settings > Appearance > Control Center > Widgets` shows a working-looking
brightness slider, a tile pair and a media card, in the order the sheet draws
them, each with a grip on its left

**W26** A preview is **inert**. `preview: true` cans every value the widget
would read and makes every action a no-op, and Settings hosts it with
`dryRun: true`, a null `sheet` and an `openScreen()` that does nothing. A
settings page that could switch the radio off by being scrolled past is not a
preview of anything.
→ tapping the Wi-Fi tile in the arrangement list leaves
`omarchy-shell control-center wifi` reading exactly what it read before

**W27 — where it is, is whether it is on.** A divider labelled `Hidden` sits in
the list. Everything above it is drawn on the surface, in that order;
everything below it is not. Dragging a card across the line is how a widget
goes away and how it comes back, so the page has one gesture rather than a
gesture and a control.

Below the line a card is still drawn, faded: the list is about where things
are, and a blank card would lose the one thing that says what you are about to
bring back.

**W27a** The divider is a **row in the model**, not a flag on each card and a
line drawn between the groups. "Shown" is `index < dividerAt`, and a plain
`ListModel.move()` across that index both reorders and hides in one operation,
with no case analysis about which group a card is leaving and which it is
joining.
→ `moarchy-widgets list control-center` reports `off` for exactly the ids below
the line, in the order they appear under it

**W27b** `dividerAt` is a property, updated after every move — not a function
walking the model from inside a binding, which QML cannot track as a
dependency. It would re-evaluate only when a row's own index happened to
change, which is true today and stops being true the first time a card is added
rather than moved.

### W28–W30. Moving them

**W28** The **handle is the only way to move a card**, and dragging from it
starts at once. A long press on the card body did it too for one version, and
that is a trap with a preview under the finger: the card is a working-looking
slider, and holding a slider to move a row is the one gesture somebody would
expect to set the brightness instead.

Chevrons were the version before that, and were wrong twice over: they describe
rather than show, and putting the bottom widget at the top was five taps and
five writes.
→ a drag from the handle lifts the card immediately, and dragging it past its
neighbour's middle swaps the two; a drag from anywhere else scrolls the list

**W28e** Held against the top or bottom of the window, the list **scrolls
under the card**, so any card can reach any position in one drag. Without it a
drag could only reach as far as the screen: moving the last widget to the top
meant dragging as far as it would go, letting go, scrolling, and picking it up
again — three gestures for one decision, and the file written twice on the way.

The speed is proportional to how far into the 64px edge band the card has
reached, and it stops when the list is already at that end rather than ticking
sixty times a second moving nothing. Each tick moves the viewport and the card
by the same amount, so the card stays under a finger that has not moved — and
re-slots, which is what makes the reorder continue while the finger is still.
→ pick up the bottom card, hold it at the top of the window, and the list
scrolls until it can be dropped first

**W28c** The handle is drawn at 34 with 24px of ink, in a target of at least
52 — the largest control on the page, and deliberately larger than the 44 of
`style.md` E1. It is the one thing here that is held rather than tapped, and a
thumb that slips off a drag handle drops the card somewhere it was not meant to
go.

Sizing it from `glyphSlot` does **not** work and looks like it should: that
slot is `iconLarge * 1.35` = 24, which is exactly what the handle already had.

**W28a** The handle sets `preventStealing`, so the Flickable underneath cannot
take the gesture back part-way through a drag.

**W28b** A drag that ends where it started **writes nothing**. Otherwise a tap
on the handle would write the file and set the whole watch-and-re-read cycle
going for nothing.

**W28d** There is no reset button on the page. `moarchy-widgets reset` still
drops the key for anyone at a terminal, but a destructive action sitting under
a list you are dragging things around in is the wrong thing to put a thumb
near.

**W29** The order is held in a `ListModel` and moved with `move()`, never in a
JS array. A `Repeater` over an array rebuilds every delegate when the array
changes, so the first reorder destroys the card under the thumb — the drag dies
on its own first success.

The cards are also positioned by hand rather than by a `Column`. A positioner
assigns `y` to its children, so a dragged card cannot also follow a finger: the
positioner wins and the binding is gone on the first frame. A `ListView`
repositions delegates underneath a drag for the same reason.

**W30** The **release** writes, once, through `moarchy-widgets set`. A drag
that ends four places down is one decision, not four: four `up` calls would
each race the file watch and each leave a frame of a different arrangement on
screen. A cancel — the compositor or a second touch taking the gesture — writes
nothing and re-reads the file.
→ `moarchy-widgets set control-center "volume, brightness"` is one line in
`widgets.toml` and one re-read by the shell

**W30a** `set` is the one verb that writes an order nobody derived from a
listing, so it is the one that checks every token names something the surface
has. `resolve()` would drop an unknown id silently (W20) and the order would
come back short with no complaint.
→ `moarchy-widgets set control-center "connectivity, nonesuch"` exits 1, names
`nonesuch`, and leaves the file alone — **including when `nonesuch` is last in
the line**, which is where a plain `while read` drops it

**W30b** A change **does not move the scroll**. Every commit comes back through
the file watch as a change, so re-seeding on it ran after every switch and every
drop — and rebuilding the model takes the content height to zero, which makes
the Flickable clamp `contentY` to 0 before the rows are put back. The list was
right and the scroll was gone.

So a seed that would produce the model already on screen returns without
touching it, which covers every change the page makes itself; a genuine
external change — another session, a hand edit, a reset — rebuilds and puts the
viewport back where it was.
→ switch a widget off with the list scrolled down and the list stays where it is

**W31** The parent rows read `6 of 7 shown` and `4 of 8 shown`, from
`moarchy-widgets summary`. One listing answers for every row rather than a read
per row — `moarchy-plugins` records why: a read apiece is a fork apiece on a
1.15GHz A53.

---

## F. What stays the host's

**W32** The control center's header — clock, date, gear, power — is not a
widget. S1 is the sheet's answer to covering the status bar, and S2 and S3 are
ways out of the sheet. None of the three is content a user would reorder.

**W33 ?** The notification list is not a widget in this cut. It is the only
scrolling region on the sheet, the sheet's height and its 90% cap are derived
from it (S21, S22), and a lock screen's notification list is a different thing
anyway — no clear-all, no tap-through to the app. Making it a widget means
giving the widget contract a way to say "I am the one that scrolls", which is
worth doing once there is a second host that wants it and not before.

**W34** The drag, the scrim, the mask and the height arithmetic stay with the
host. A widget cannot change the size of the surface except by its own
`implicitHeight`.

---

## F2. The quick toggles

The `toggles` widget is a row of tiles, and which tiles is the user's too. It
is the same shape one level down — a catalogue, an order, an on/off per entry,
one key in the same file — resolved by the same code under the surface name
`quick-toggles`.

**W42** A toggle is **not a widget**. It has no file, no `available` of its
own, and it cannot be hosted alone: it is four lines of data in `Widgets.js`
that `Toggles.qml` draws as a `SmallTile`. What it shares with a widget is only
that the user arranges it, which is exactly the code it shares.
→ `scripts/style-check.sh` requires a file for every entry in `WIDGETS` and for
none in `TOGGLES`

**W43** A toggle carries a name, a glyph, and either `native: true` or a
command. Native means the state is something the shell already holds — do not
disturb, rfkill, the LED, the compositor's transform — and those four stay in
QML. Everything else is a `read` that prints true/false and one or two
commands, so a ninth toggle is a row in the catalogue and no QML at all.
→ `scripts/style-check.sh` fails a toggle that is neither native nor has a
`cmdOn`, because its tile would draw and do nothing — S10's rule for the torch

**W44** The eight are Silent, Airplane, Torch and Rotate, on by default and
exactly what the row has always held, plus **Night light**, **Stay awake**,
**Keyboard** and **Screenshot**, off by default. A phone nobody has touched
shows the four it always showed.
→ with no `widgets.toml`, `omarchy-shell control-center toggles` reports the
first four `on` and the last four `off`

**W45** The row is four across and **wraps**, with the cells a quarter of the
width — except that a row which is not full still fills it, which is what the
three-tile case has always looked like on a phone with no torch and what one
tile would look absurd not doing.
→ with six toggles on, the widget draws two rows and the sheet grows by one
tile's height

**W46** One probe per shell-backed tile **that is on**. A toggle the user has
not added costs nothing: the row used to be four fixed tiles, and a fifth would
have been a fifth fork on every open whether anybody wanted it or not.

**W47** A tile whose phone cannot honour it is **absent, not drawn dead** —
W6's rule one level down, and the torch is the only one that has ever been in
that position.

---

## G. What must stay true

This is a refactor of where the code lives, so §G is the half that does not
change.

**W35** Every criterion in `control-center.md` still passes, unchanged, with
the default arrangement. The widgets are where the behaviour moved to, not a
change to it — S4, S5, S6, S6a, S8, S9, S10, S13, S14, S16 and S29 are the
ones with code on both sides of the move.
→ the control center suite of `bin/moarchy-selftest` is green with no
`widgets.toml` present

**W36** `style.md` C1–C3 hold: no widget declares a palette, computes a
`subdued` of its own, or writes a literal hex.

**W37** `refactor.md` H3 holds: every control on a sheet still drags it, in the
widgets as it did inline, and `scripts/style-check.sh` still fails an instance
that declares one of `SheetDragArea`'s four handlers.

**W38** `refactor.md` E7's duplication check covers `widgets/` too. A widget is
the most likely place for the tenth copy of `PressVeil` or a colour function,
because it is the newest directory and the one a stranger writes in.

**W39** The packaged tree ships the new directory. `pkgbuilds/moarchy` copies
`default/omarchy/plugins/` with `cp -a`, so `widgets/` rides along — the same
load-bearing fact E8 records about the common dir, now with a subdirectory
under it.
→ `pacman -Ql moarchy | grep -c 'plugins/moarchy.common/widgets/'` equals the
number of widgets

---

## H. The first cut

Six widgets, all of them lifted out of `ControlCenter.qml` with their service
code:

| Id | Was | Contract |
| --- | --- | --- |
| `connectivity` | the Wi-Fi and Bluetooth pair | `control-center.md` S4–S6d |
| `mobile-data` | the full-width data tile | S29–S29d |
| `toggles` | the tiles, now arranged (§F2) | S7–S11 |
| `brightness` | the upper fat slider | S12, S13, S15 |
| `volume` | the lower fat slider | S14, S15 |
| `media` | the now-playing card | S16, S17 |
| `calendar` | the next upcoming event — **new**, off by default | §H2 |

**W40** None of the six leaves drawing or service code behind. `WideTile`,
`SmallTile` and `FatSlider` move with them.
→ `grep -cE 'component (WideTile|SmallTile|FatSlider)|brightnessProbe|brightnessctl'
ControlCenter.qml` == 0

**W41** `moarchy.volume`, the volume panel, is not rewired onto the volume
widget in this cut. It is an OSD on a timer with a different shape, and the
first thing a shared component would need is a horizontal mode — which is a
second widget wearing the first one's name.

## H2. The calendar widget

**W48** `calendar` shows the **next upcoming event**: its title, and the day
when the day is not today, plus whatever the Calendar app would say about the
time. Off by default — it is new, and a phone nobody has configured should look
the way it did.

**W49** It is a **view of the Calendar app's own file**, read through that
plugin's `Store.js` and `Events.js`. A recurrence rule, an all-day event and
the wording of a span are decided in one place, and this shows whatever the app
would have shown. A second parser for that file is the duplication `refactor.md`
E7 exists to stop, and it would have drifted the first time a repeat rule was
added.

The cost is an import across plugin directories, so the widget needs
`moarchy.calendar` installed. Without it the widget fails to load, the column
logs its id and the row is empty (W12) — which is the right outcome: a "next
event" with no calendar behind it has nothing to say.
→ `grep -c '^import .*moarchy.calendar' widgets/Calendar.qml` is 3, and
`grep -rl '^import "../../' widgets/` names only that file

**W50** Today counts. An event at 09:00 is still the next thing at 08:55, and a
card that skipped to tomorrow at one minute past would be wrong for the whole
of the day it was about.

**W51** Nothing in the diary is **nothing to draw** (W6). A card reading "No
events" is a row you have to read to learn there is nothing; the absent row
says it without being read.

**W52** It ticks on the **day boundary and no faster**. The card prints a span,
never a countdown, so a per-minute timer would repaint the same two strings
1,440 times a day on an A53.

**W53** Tapping it opens the Calendar, through `host.openScreen` (W5) — so the
control center closes on the way and a host that must not open an app can
refuse.

---

## What is not here yet

The lock screen. It is the reason for the mechanism and it is not part of it:
when it arrives it declares `hostId: "lock-screen"`, refuses `openScreen`, and
its arrangement is a second key in the same file. Nothing in §A–§F needs to
change for it, and if something does, that is the bug this file is for.

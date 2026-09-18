# Touch gestures — specification

What the phone's touch gestures must do. Written to the rule in
[`README.md`](README.md).

`bin/moarchy-selftest --gestures` and `--surfaces` cite these ids. A criterion
is in one of three states, and the difference matters: **run** — it has a `→`
check and a suite executes it; **written** — it has a `→` check that nothing
runs; **stated** — it has no check at all. 66 of the 134 below are run. The
other 68, and the five the suites run without a `→` line here, are listed under
[Coverage](#coverage) at the foot.

## Vocabulary

| Term | What it means |
| --- | --- |
| **strip** | The reserved 20px band at the very bottom holding the home pill. Owned by `moarchy.gestures`. |
| **home screen** | A sway workspace with no windows on it: wallpaper, bar, pill. One app per workspace, so an empty workspace *is* the home screen. |
| **app** | A workspace with a window on it, or Settings, which is treated as one (K). |
| **shell app** | A screen this shell draws itself and maps as an ordinary window, so every criterion about apps applies to it. Four of them: Settings, Wi-Fi, Bluetooth and SIM (K). |
| **drawer** | The searchable app grid (`moarchy.drawer`). The strip's sheet as shipped. |
| **overview** | The vertical list of workspace cards (`moarchy.overview`). The right edge's sheet as shipped. It is the one surface that can put two apps on one workspace, and the one place a window is closed by hand. |
| **shade** | The pull-down from the top edge (`moarchy.shade`). |
| **the strip's sheet** | What an up-swipe from the strip raises. Named by a setting (Q1), so §A says *the drawer* where it means *this*, and its checks run against the pairing that ships. |
| **the edge's sheet** | What a swipe in from the right edge raises. Named by the same setting, and §P reads the same way. |
| **trigger** | Any of the four things a setting can point at something: the two edges, the strip's hold (C), and the power button's double press (Q11). |
| **travel** | Drag distance as a fraction of the sheet being dragged, along the axis it arrives on — the drawer's own height, ~694 logical px. One pixel of finger is one pixel of sheet, on every surface that drags it (D2a). |

---

## A. Strip — swipe up

One drag, two stops, and the first one is the same sheet from everywhere:

```
0 ---------------- 50% ---------------- 100% -- past the top
      closes              opens                    HOME
```

**A1** Dragging up from the strip raises the drawer, and it follows the finger
rather than appearing at a threshold. From an app, from a home screen, with
nothing open anywhere: one gesture, one meaning.
→ `omarchy-shell drawer dragTrace` leaves ≥ 8 samples

**A2** Released below halfway, the sheet animates back down and disappears.
→ `omarchy-shell drawer state` == `closed`

**A3** Released above halfway, the sheet animates the rest of the way up and
stays. Half the sheet decides, because the sheet is the thing being positioned
and the question is which end it is nearer. A fling overrides the distance in
both directions — a short fast flick up opens the drawer, a fast flick down
closes it — because a flick is not an unfinished drag.
→ the same travel at two speeds, 35% of the sheet either way: a 250ms flick
leaves `omarchy-shell drawer state` == `open` and a 2000ms drag leaves it
`closed`. One distance and one threshold, so equal outcomes mean the fling term
is not being read at all

**A3a** The strip's drag is the home screen's drag: same 1:1 ratio against the
sheet's own travel on the axis it entered from (Q2), same halfway commit, same
fling rule in both directions.
The only thing the strip adds is the second stop.
→ a drag of *n* logical px from the strip leaves `drawer dragTrace` ending
within a few percent of *n* / 694, the same figure D2a asserts for the
wallpaper drag

**A3b** The same swipe commits the same way every time. Speed is read across an
interval long enough to be one, and from the press when the gesture has not
produced one — never between two consecutive position events, because the shell
delivers a fast flick as two of those and a slow drag as twenty-four, so a
frame-to-frame reading is a reading of the load rather than of the finger.
→ the same 35% flick, eight times over, leaves `omarchy-shell drawer state` ==
`open` eight times out of eight

**A4** Home is **past a full sheet**, never inside the travel that opens one.
From an app that means a sweep to the very top of the screen; from an
already-open drawer it is one short pull more (A6), which is the path that
actually gets used. Released there, focus lands on a home screen and the drawer
is not shown. The sheet lifts through the last 15% before the stop rather than
standing still, so it announces itself before you let go, and the pill goes
accent where the lift completes.

The stop is out at the top because no threshold inside 0..1 separates "show me
the launcher" from "go home": measured on the device, an unremarkable flick up
from the strip runs to **92% of the sheet at 2.5 px/ms**.
→ focused workspace `representation` is empty; `drawer state` == `closed`

**A5** One sheet is all the strip opens — the one Q1 names — from an app, from a
home screen, with nothing open anywhere. The one exception is a sheet already
covering the screen, which the same swipe clears instead of opening anything
over it (A8).
→ `drawer state` goes `closed` → `open` across a strip up-gesture, from an app
and from a home screen alike; with the shade down it stays `closed` and
`shade state` goes to `closed`

**A6** With the drawer already open, dragging up from the strip again carries on
to home: **15% of the sheet further up**, measured from where the drag began.
This is the ordinary way to reach the wallpaper — app, swipe, launcher, swipe,
home — and it is why A4's stop can afford to be out at the top of the screen.
→ from an open drawer, a 20% drag leaves `representation` empty and
`drawer state` == `closed`

**A7** A short up-swipe with the drawer already open leaves it open. The strip
does not toggle it: up means "forward" — to the drawer, then to home — and
never "back". What closes the drawer is a drag *down* on the sheet itself (H1)
or the back gesture (G3). This is what A6's "measured from where the drag
began" buys: against a fixed threshold an open drawer is already past the stop
before the finger moves, so every touch on the strip would go home.
→ from an open drawer, a 5% drag leaves `drawer state` == `open`

**A8** With the shade down, an up-swipe from the strip puts the shade away and
does nothing else. Whatever is covering the screen, this gesture clears it —
every sheet this shell can put over an app *except the strip's own*, which a
second drag continues rather than clears (A6). Settings is out of it: it is an
app (K), so the strip raises its sheet over it and leaves it running on its
workspace when the drag goes home (K4).

The list is derived from the one the back gesture already walks, minus the
strip's own sheet and minus the shell apps — which are excluded by being
windows rather than by being named (K1). Three hand-kept lists of overlay ids
is how Settings and Themes came to be missing from the back gesture.

The exemption is read off the setting (Q1) and not off an id. Naming the
drawer here is what would make a second drag clear the overview instead of
carrying it on into the home band, the moment somebody put the overview on
this edge.
→ `omarchy-shell shade state` == `closed`; nothing else opened, and a drawer
that was open under the shade is still open

**A10** An up-swipe from the strip with the shade over an open drawer puts the
shade away and leaves the drawer where it is. One gesture clears one covering
sheet, so what is on screen afterwards is the drawer the shade was over.
→ with both open, a strip up-flick leaves `omarchy-shell shade state` ==
`closed` and `omarchy-shell drawer state` == `open`

`run("clear")` puts away the topmost sheet where `hideCoveringSurfaces()` sweeps
every one of them, and beside each other the narrower call reads as the
oversight. It is the deliberate one; collapsing the two takes the drawer with
the shade.

## B. Strip — swipe sideways

**B1** Swipe left goes to the next workspace; swipe right goes to the previous
one. With one app per workspace, that is next/previous app.
→ focused workspace name changes and changes back

**B2** A swipe that curves — as a thumb does — still resolves to whichever
direction dominates, and does not fall through to doing nothing.

**B3** The swipe lands on a workspace with nothing of the shell's drawn over
it. The shade, the drawer and the theme picker are put away on the way, the way
an up-swipe puts the shade away (A8).

Sheets only. A shell app is a window (K1), so the swipe passes it the way it
passes `foot` — it stays mapped on the workspace it is on, and the swipe back
returns to it (K2). Sweeping it here is what makes a shell app impossible to
swipe back to.
→ with the shade down over an app, a sideways swipe leaves `shade state` ==
`closed` and a focused workspace that is not the one it started on

## C. Strip — press and hold

The hold is the one press on this strip that nothing else wants, and every
phone spends it on the thing its owner reaches for most. What that is is a
setting (Q10), and it ships as the coding agent: that already has exactly one
definition (`settings.md` P1), and is otherwise reachable only by finding its
tile in a 64-entry grid. The asymmetry is what makes the hold safe to spend —
it opens a window, and the back gesture closes it (G4).

**C1** A press that stays on the strip for **500ms** without travelling past
the drag slop fires the hold's trigger (Q10). Shipped that is the **default
coding agent**: the agent the drawer's one tile names, in a terminal, on its
own workspace like any other app. With no agent picked yet it opens the picker
instead — the same two states as that tile, read from the same one answer
(`settings.md` P12), so the gesture and the icon can never name different
agents. 500ms is L1's number, because a phone has one hold and not two.
→ `moarchy-trigger fire hold` with `gesture_hold` == `agent` runs
`moarchy-agent launch`, which with `codex` picked execs `omarchy-default-agent
codex` and with nothing picked execs `omarchy-shell settings openAt
apps.default.agent` and installs nothing

**C2** The pill **shakes** while the hold is counting, and stops the moment it
fires. The strip is a 4px line with no label on it, and a press that is going
somewhere looks exactly like a thumb resting on the bottom edge.

It starts **150ms** in, not on contact. Every gesture on this strip opens with
a press — A's drag, B's swipe, a tap that means nothing — so a pill that jumps
on contact jumps on all of them, and a cue that fires on everything says
nothing.
→ `omarchy-shell gestures status` reports `hold=armed` for the first 150ms of a
stationary press, `hold=shaking` until it fires, `hold=fired` from then until
the next press, and `hold=idle` at rest

**C3** Travel cancels the hold, and a fired hold cancels the release. Past the
slop the touch is A's drag or B's workspace change from that pixel on, whether
or not 500ms has passed on the way — L3's rule, for the grid's hold, and the
same rule here. A hold that has fired then takes the rest of that touch with
it: a finger that wanders afterwards raises nothing and the lift commits
nothing, so one press never both starts the agent and changes workspace (L2).
→ a 1200ms press that travels 500px up leaves the drawer open, `hold=idle`,
and no agent window

**C4** Nothing on the strip closes a window. An edge a thumb rests on is the
wrong place to destroy something: what it closed would be invisible at the
moment it closed, and it would have no undo. `$mod+w` still closes the focused
window for anyone with a keyboard, and the overview's bin closes one you can
see (P12).
→ no press on the strip, of any duration, lowers the open-window count

**C5** The hold reaches the agent from wherever the strip does. The shell's own
sheets are put away on the way, the way a sideways swipe puts them away (B3): a
window that opens underneath the drawer is a gesture that appears to have done
nothing. The keyboard is left up, like everything else now (G14) — what opens is a
terminal, and it is entitled to the input an empty workspace was not.
→ with the drawer open, `omarchy-shell gestures hold` leaves `drawer state` ==
`closed` and the agent focused

**The IPC really launches.** `omarchy-shell gestures hold` has nothing behind
it to stub: on a phone that has picked an agent but never installed it, the
first call downloads it through mise. So `bin/moarchy-selftest --gestures` does
not fire it — a suite that installs a package to prove a gesture works has
changed the phone it was measuring. C1 is checked against `moarchy-agent
launch` in a scratch HOME (`settings.md` P12); C2, C3 and C5 are hand checks on
glass.

## D. Home screen — the workspace itself

**D1** On a home screen, dragging up **on the workspace** — the wallpaper, not
the strip — opens the strip's sheet, following the finger. One setting answers
for both surfaces (Q1): the wallpaper is the strip's drag without the second
stop, not a gesture with a destination of its own.
→ `omarchy-shell drawer state` == `open`, `drawer dragTrace` ≥ 8 samples

**D2** Released below halfway the drawer animates back down; above halfway it
animates up and stays (A2, A3). One rule, both surfaces, and a fling in either
direction overrides it.

**D2a** The open drag is 1:1 with the finger: one pixel of travel is one pixel
of sheet, measured against the sheet's own extent along the axis it arrives on
(Q2) — from this edge, its height. Both drags measure against
the sheet, as the close drag always has — its handle *is* the sheet it moves
(H1) — and as Android's launcher tracks in both directions.
→ a drag of *n* logical px leaves `drawer dragTrace` ending within a few
percent of `n / 694`; measured 300px→42%, 435px→63%, 635px→91%

**D2b** The number that drag divides by is right **while the drawer is
closed**, which is the only state an opening drag can start in. An unmapped
layer-shell surface reports Qt's placeholder size, not the size it will have:
`drawer geometry` answers `h=100` with the drawer down and `h=694` with it up,
so a travel read straight off the window moves the sheet seven times finger
speed until it maps — a jump on the first frames and then a visible retreat as
the divisor corrects itself. It is invisible from outside, and the check above
only reads where a drag *ends*.

The drawer remembers its height the first time it is up and falls back to the
screen's before that, so the first drag of a session is 3.6% off 1:1 — the
bar's exclusive zone — and every one after it is exact.
→ `omarchy-shell drawer geometry` reports `travel=720` before the drawer has
ever been opened, and `travel=694` from then on, closed or open. It must never
report 100

**D3** On a workspace with an app, dragging on the app does nothing to the
shell. The app receives the touch — everywhere except the left edge band, which
belongs to the back gesture (G).

**D4** Sideways and downward swipes on the home screen do nothing, for now. The
home screen handles the up-drag and nothing else; the strip still changes
workspace and the top edge still opens the shade.

## F. Going home

**F1** Home is the lowest-numbered workspace with nothing on it, so the sideways
swipe order stays contiguous. There is no ceiling on the search: sway's
*bindings* stop at ten and this is not a binding, and
`bin/moarchy-one-app-per-workspace` — the same rule in Python, the pair this
must not drift from — never had one.

**F2** Going home never closes anything. Every app is still on the workspace it
was on afterwards, with the overview still drawing a card that holds it.
→ `overview windows` count unchanged across a home gesture

**F4** The sheet does not snap back on its way out. What signals the home band
-- the sheet travelling on past the first stop -- is at its *furthest* there,
because that is the cue that letting go goes past the launcher to the
wallpaper. So the drawer has to leave from that travelled state and not from
its fully-open one: `progress` carries a Behavior and `homeHint` must carry one
too, or the sheet drops its `space(80)` and the scrim jumps to full alpha for
the length of the fade.
→ `omarchy-shell drawer retireTrace` reports `progress:homeHint` per frame
across the release; `homeHint` must not be 0 in the first frame. Measured
without the fix `100:0 63:0 46:0 33:0 ...`, and with it
`100:73 73:54 54:40 40:27 ...` -- so peak scrim alpha goes from 1.0 to 0.56,
falling monotonically from there instead of jumping

**F5** Going home works **while a sheet of ours is on screen**, and that is
not free: the drawer takes exclusive keyboard focus for its search field, and
an exclusive-focus layer surface deactivates the window beneath it. Every
toplevel then reads unfocused, so "is a window focused" cannot decide whether
this gesture is already home.

The workspace's own `representation` is the signal that cannot be perturbed by
a layer surface, and it is consulted alongside the focused toplevel. It is the
one I3 refreshes late, which is the right way round here: a stale empty reading
costs one skipped hop, where a stale focus reading costs the gesture.
→ `omarchy-shell gestures status` with the drawer up over an app reports
`focus=none` and `rep="V[…]"` in the same line; a home gesture from there
leaves the focused workspace's `representation` empty

---

## G. Left edge — back

**G1** The back swipe undoes the **topmost thing on screen**, in this order:

1. the on-screen keyboard, if it is up
2. each open overlay — drawer, shade or theme picker — topmost first, one
   per swipe
3. the focused app
4. nothing, on a bare home screen

One gesture, and it always undoes the most recent thing. G2–G5 are that list,
one rung at a time.

**G2** Keyboard up → the swipe dismisses the keyboard and changes nothing else.
→ `sm.puri.OSK0` `Visible` is false; open-window count unchanged

**G3** An overlay open and no keyboard → the swipe closes that overlay and
leaves the app underneath alone.
→ that plugin's `state` == `closed`; open-window count unchanged

**G4** An app focused with nothing over it → the app is asked to close.
→ `omarchy-shell overview windows` is one line shorter

**G5** A bare home screen with nothing over it → the swipe does nothing.

**G6** The swipe has to travel far enough to be deliberate. A short drag in from
the edge does nothing, so brushing the edge never closes an app.

**G7** Closing is a *request* — the app is asked to close and may prompt, so an
editor with unsaved work is never lost. Closing the only window on a workspace
leaves you on that workspace, which is now a home screen.

**G8** The edge band is **16 logical px** wide — about 3mm on this panel, which
is roughly what Android's back edge feels like at its default sensitivity. It
is a settable property, not a constant baked into a binding: Android makes this
device-configurable and exposes a per-edge sensitivity slider, which is an
admission that no single value is right.

**G9** The left edge is back and the right edge is the overview (P1) — one 16px
band each, and no third. Android puts back on both edges; the second one is spent
here on the map instead, because a phone that already has one way back does not
need two.

**G10** The band does not run the full height of the screen. It stops **one
strip plus one keyboard panel** short of the bottom — 220 logical px — and
everything below that belongs to whoever is drawing there. Without the inset
the band swallows the leftmost key column: `a`, shift and `123` answer nothing,
and a tap there travels zero px so it commits no back swipe either (G6).

Geometry has to fix it, because arrangement cannot. Sway resolves exclusive
zones **layer by layer from Overlay down**, so the keyboard's zone is
subtracted after this surface has already been placed; `ExclusionMode.Normal`
here would move nothing. Nor can a short tap be handed back to the surface
underneath — Wayland picks the recipient from the input region before the touch
is delivered, and there is no returning it on release. The input region is the
only knob.

The keyboard's 200 is measured and not ours to choose (it is the same
`panelHeight` I5b pins the drawer's reflow to), so unlike G8 it does **not** go
through the theme's spacing scale. The keyboard is a separate client that never
sees this theme; scaling our inset with it would cut the edge shorter than the
keys it exists to avoid.
→ `omarchy-shell gestures geometry` reports `h` == `screen - inset - topInset`,
`inset` == 220

**G10b** It stops short of the **top** as well, by the status bar plus one
header bar — **73 logical px** — so an app's own top-left control is tappable.
That is where GTK puts the control the user reaches for most: libadwaita's back
chevron, a hamburger, Geary's folder button.

**The number is measured, not chosen.** On this panel the status bar is 26
logical px and libadwaita's `AdwHeaderBar` is 47 — Spot's white header runs
from y=52 to y=144 physical, which is 46.5 plus its divider — so an app's
header ends at 73. Like the keyboard's 200 in G10 and unlike G8's band width,
the header half does **not** go through the theme's spacing scale: it is
another toolkit's chrome and it does not know this theme exists. The bar half
does, because that one is ours.

It also hands back the top-left corner, which was contested rather than
allocated: the shade's grab strip is Overlay too and covers the same 16x26, and
which of two Overlay surfaces got a touch there was decided by map order rather
than by anything this spec says. Above 73 the shade has it outright (A8).
→ `omarchy-shell gestures geometry` reports `h` == `screen - inset - topInset`
and `topInset` == 73

**G10a** The dead column is otherwise unchanged: between those two insets the
leftmost 16px of every app still belongs to the back gesture (D3), and G8's
property is still the only knob for its width. This is an edge gesture, and
Android pays the same price — `getMandatorySystemGestureInsets()` exists
precisely so apps can move their own controls out of the way.

**G11** With two sheets on screen the swipe closes the one on top and leaves the
one under it. That is G1's rung 2 taken one at a time, and the order is the
layer order — the shade is Overlay, the drawer and the theme picker are Top —
so the sheet that goes is always the one being looked at.

`overlayIds` leads with the shade for that reason and not by accident, so
reordering it changes which sheet a back swipe reaches first.
→ with the shade over an open drawer, one `omarchy-shell gestures back` leaves
`shade state` == `closed` and `drawer state` == `open`; a second leaves both
`closed` with the open-window count unchanged

**G12** The back swipe shows where it has got to. A circle carrying the same
chevron Settings' own back button wears comes in from the edge under the thumb,
following the finger rather than appearing at the threshold, and takes the
accent at the point where letting go would commit — the strip's own vocabulary
for "this is about to do something" (A4, C2).

It is the one gesture on this phone with nothing to look at: the edge surface
is transparent and reserves nothing, so where it stops is invisible from
outside and unmeasurable with a finger.
→ `omarchy-shell gestures backTrace` leaves ≥ 8 samples across a slow drag in
from the edge, rising monotonically, and ends `-1` on a cancel or `-2` on a
touch the watchdog retired; a drag that never commits leaves samples and closes
nothing

**G13** The surface is wider than the band it takes touches in, and the extra
width is masked out of its input region. Everything right of the 16px falls
through to the app, exactly as it did when the surface was 16px wide.

This is on `Overlay` and sits over every window, so an unmasked widening takes
the leftmost strip of every app on the phone — silently, because a dead column
and a column that answers a gesture look the same until you try to use it.
→ `omarchy-shell gestures geometry` reports `w` == `backEdgeWidth` and
`surfaceW` > `w`; `w` keeps meaning the input band, so G8's number is still
what it was

**G14** The keyboard comes up only when a person asks, and three things can ask: its own
restore handle, `$mod+i`, and **a tap on a text field**. Nothing puts it down except the
back swipe (G2). Opening the drawer, closing it, and switching apps leave it where it was.

An app asking for text input is not an app asking for a keyboard. Focus arriving on its
own — a window mapping, an overlay taking Exclusive, a field the host focused for you —
raises nothing and lowers nothing. It used to be read as a request, so the keyboard
appeared over half the screen whenever anything took focus and left again just as often,
which is the worse half: it moves the layout under a thumb already on its way to a key.

A tap on a field is a person asking, the same way the restore handle is. The tap is the
signal, not the focus that follows it, so a field that is already focused from an earlier
tap does not raise the keyboard again when its window is focused.
`moarchy-keyboard`'s AC 49 is what makes a dismissal safe to let stick — the handle is on
screen whenever the keyboard is not, and AC 52 keeps it above this shell's overlays.
→ with an app's text field focused and the keyboard down, `sm.puri.OSK0`
`Visible` stays false across ~3s of sampling; going home, opening the drawer
without touching its field, and switching apps leave it wherever it was

**G14a** Tapping the drawer's search field raises the keyboard. Closing the drawer does
not lower it.

What G14 refused was *focus* as the signal, because Exclusive keyboard focus is granted
as soon as the sheet starts moving and Qt hands it to the first StrongFocus control —
this field — before `open()` can park it in `focusSink` (N4). Reading that as a request
is what raised the keyboard on every drawer open, and hiding on close is what put it
away again on every launch.

The raise is a press on a ClickFocus field, taken only while the sheet is at rest open,
so the swipe that brought the pill up under a finger does not ask. At rest however it
got there: released at the top, released part-way and finished by the animation, or
opened with `drawer open`. The keyboard that tap raised stays up when the drawer goes
down: back (G2) is the one way down.
→ with the keyboard down, `omarchy-shell drawer open` then a tap at
`drawer searchTarget`'s field centre leaves the focused workspace's `rect.height`
lower by the keyboard's reservation, and `searchTarget` reports `focused=true`;
closing the drawer leaves the rect lowered. Open and close without touching the
field leaves the rect where it was. **The rect, not `sm.puri.OSK0` `Visible`** — that
property reports the keyboard's own intent and has been observed true with
nothing drawn

## H. Closing an overlay by dragging it

**H1** Dragging **down** anywhere on the drawer closes it, following the finger.
→ `omarchy-shell drawer dragTrace` leaves ≥ 8 samples; `drawer state` == `closed`

**H2** Dragging **up** anywhere on the shade closes it, following the finger.
"Anywhere" includes the band of scrim below the sheet, which is where a thumb
starts an up-swipe. That band is not a fixed height: the sheet is as tall as
its content and stops at 90% of the usable height (`shade.md` S21, S22), so the
band is ~70px with the shade full and several hundred with it near empty.

`state` alone cannot check this. A shade that jumps shut reaches `closed`
exactly as fast as one that followed the finger the whole way, which is why the
criterion is the trace — and the trace records only what the finger drove, not
the 220ms fall after release.
→ `omarchy-shell shade dragTrace` leaves ≥ 8 samples; `shade state` == `closed`

**H3** A drag that stops short springs the sheet back and changes nothing.

**H4** A tap is still a tap. Touching an app icon and letting go launches it;
only a drag past the slop becomes a close.
→ launching from the drawer still works after H1 is implemented

**H5** Where the sheet's own content scrolls — the drawer's grid when it has
more apps than fit, the shade's notification list — that content gets the drag
first, and the sheet only follows once the content is at its end. A list you
are scrolling must never close the sheet out from under you.

**H6** The existing 26px handle bands keep working. They are the affordance
that says the sheet is draggable at all.

**H7** Swiping a notification card sideways dismisses that notification. It is
the **only** way to dismiss one — there is no close button on the card.
→ the card leaves the list, and the notification is still absent after the
shade is closed and reopened

**H7a** A short swipe dismisses nothing and springs back. Measured: 100px of
travel leaves the notification in place, 340px removes it. Without this,
"swiping dismisses" is satisfied by a card that fires on any horizontal
movement at all, which would make scrolling a minefield.

**H7b** Neither a swipe nor a vertical drag over the list closes the shade.
Measured: seven notifications, a vertical drag across them, nothing dismissed
and the sheet still open.

Sideways, not vertical, and that is the whole reason a swipe is allowed here at
all: the list scrolls vertically and keeps vertical drags (H5), so claiming one
axis rather than the gesture is what stops a scroll that wanders sideways from
throwing away something you were reading.

**H8** Clear-all remains reachable by tap. A swipe is invisible where a glyph
is self-evident, so removing the close button makes per-card dismissal
something you have to know about; the bulk control is what keeps emptying the
shade from depending on a gesture nobody told you about.

## I. What the strip is drawn over

The strip reserves its band off every *window*. The shell's own sheets are not
windows and extend under it. Nothing about what the strip *reserves* changes —
that half is what keeps the keyboard from burying the pill.

Settings is not in that list: it is a window (K1), so it cannot extend under
anything — sway arranges a window into what the exclusive surfaces left, which
is the whole point of the strip reserving. I1a is what covers it instead.

**Sizes are never written as numbers here.** `Style.space(20)` rounds a
*scaled* value, and the scale comes from the theme's `shell.toml`: measured 20
on the default theme and 23 on a larger one, and it has read higher again.
Every check below takes the height from `geometry`'s `strip` field rather than
assuming one — including the ones in `bin/moarchy-selftest`, whose comments
quote a number they measured on the theme of the day and not a constant.

**I1** With the drawer, the theme picker or the keyboard up, the surface
reaches the bottom row of the screen. No band of wallpaper, and no band
of the app underneath, shows beneath it. The keyboard is `moarchy-keyboard`'s
own surface and gets there its own way -- see its SPEC.md 45-48 -- but the
result this asks for is the same.
→ one `grim` capture: the pixel a strip-height above the last row equals the
pixel in the last row, sampled left of the centred pill

**I1a** Behind a window, the band the strip reserves is filled with the theme's
background instead of the wallpaper. Every window, not only this shell's own
screens: what I1 does for a sheet by extending it, this does for an app by
filling in underneath it.

Filled from the Bottom layer, and that is what makes it cost nothing anywhere
else. Bottom is below every window, so the fill can only be seen in the band no
window is drawn in; and it is below every sheet, so the drawer, the shade and
the theme picker draw over it exactly as they did. Filling the band from the
*strip* instead — the obvious place, since the strip is what reserves it —
would have painted over all three.

Two states keep the wallpaper **in the strip band**, and each is a case where
the wallpaper is the answer for that band:

- **an empty workspace**, which *is* the home screen (vocabulary, D). Asked as
  "is any window focused", which is the question `run("home")` already trusts
  for this and which K1 made honest: the shell's own screens are windows and
  answer it themselves.
- **the keyboard up**, when the band sits under the keyboard rather than under
  the app. `gestures geometry` still reports `band=0` then; I1b is what paints
  the window area above it.

Whether the keyboard is up is read off the `moarchy-home` surface's own height
rather than from `sm.puri.OSK0`. Sway resolves exclusive zones from Overlay
down, so a Bottom surface is arranged after the keyboard's Top zone has been
subtracted and shrinks with it — measured 694 with the keyboard down and 494
with it up, on a 720 screen. The bus property is the wrong instrument twice
over: it is stale between back gestures, and I5d records it reading `Visible
true` with nothing drawn.
→ with an app focused and the keyboard down, the pixel in the last row left of
the pill is the theme's `background`; on an empty workspace it is not, and
`gestures geometry` reports `band=0`

**I1b** An occupied workspace fills `moarchy-home` with the theme's background,
not only the strip band. A strip swipe therefore does not flash wallpaper in
the hole the window leaves — including the hole above a still-mapped keyboard,
which I1a deliberately does not paint.

The fill is already up before the switch: it follows whether the focused
workspace has a window (`representation`, the same signal as home), not the
press. A latch covers the frames where that signal flickers false between
workspaces. An empty workspace is still the home screen and still shows the
wallpaper.
→ with a terminal on one workspace and another app on the next, a strip swipe
from one to the other does not show the wallpaper between them

**I2** Each sheet that extends is exactly one strip taller than a Top surface
with the same zero exclusive zone and no margin. That is the negative margin
having taken effect, and it is the only way to know it did: sway's IPC does not
list layer surfaces, so this cannot be read from the compositor. Two of them:
the drawer and the theme picker. The `moarchy-home` surface takes the same
margin for I1a and is not asserted here — it has no content to keep clear of
the pill.

`moarchy.device` is the control, and is deliberately left unchanged for that
purpose: same layer, same zero zone, no margin. An absolute assertion against
the workspace rect would not do -- the rect has the bar's and the strip's
exclusive zones taken out of it and an `ExclusionMode.Ignore` surface does not,
so it would fail on arithmetic rather than on behaviour.
→ `omarchy-shell {drawer,themes} geometry` each report `h` equal to
`omarchy-shell device geometry`'s `h` plus `strip`

**I3** Extending a surface reserves nothing. The strip still takes its band off
every window and the bar still takes its own off the top, with any sheet open.
→ the focused workspace's rect is byte-identical open and closed

**I4** Nothing tappable comes to rest under the pill. On every sheet the last
content pixel settles at least one strip above the bottom of the surface,
however its list is scrolled. Content may *pass* under the pill mid-scroll; it
may not stop there. Settings is out of this one by construction: a window stops
at the top of the strip, so nothing it draws can reach under the pill at all.
→ `... geometry` reports `gap` >= `strip` on both sheets

**I5** The drawer still reflows above the on-screen keyboard -- the reason its
exclusive zone is zero in the first place. Raising the keyboard shortens the
drawer's surface, and the grid ends the same distance above the keyboard as it
did before the surface grew.
→ `drawer geometry` `h` is smaller with the keyboard up than with it down, and
`gap` is identical between the two

**I5a** The drawer's bottom inset is dropped while the keyboard is up, and this
is not an optimisation. A negative margin does not extend a surface "under the
strip" -- it extends it past the bottom of the *usable area*, and what sits
there is whatever is reserving. With the keyboard down that is the strip, which
is on Overlay and draws over us. With the keyboard up it is the keyboard, which
is on Top like the drawer and mapped earlier, so the drawer wins the overlap and
paints over it — the whole `qwertyuiop` row reduced to a sliver under the
drawer's app labels.

The signal is the compositor's own configure, read off the surface's height
(I5e), and it is the only one. `searchField.activeFocus` used to lead it as a
stand-in for "the keyboard is up"; with G14 a focused field raises nothing, so
the stand-in stands for nothing and would drop the inset on every tap in the
search box with no keyboard under it.
→ `drawer geometry` reports `margin=0` with the keyboard up and
`margin=-<strip>` with it down, whatever has focus

**I5b** The keyboard reserves the same space whether or not it draws under the
strip. sway reduces the usable area by `exclusive_zone + margin.bottom`, so a
surface with a negative bottom margin has to add it back to its zone or it
quietly under-reserves by exactly that much.
→ with the keyboard up, `drawer geometry` `h` is `screen - bar - panelHeight`;
at 176 rather than 200 the drawer settles over the top key row

**I5d** Closing an overlay never *raises* the on-screen keyboard. It may leave
it down; it may not put it up.

True by construction since G14, and it was not before. An overlay declaring
`WlrKeyboardFocus.Exclusive` takes the seat's keyboard while it is up, which
deactivates the window underneath and lowers the keyboard with it; on unmap
sway re-activates that window and its `zwp_text_input_v3` re-enters. Nothing
listens to that any more, so the re-entry raises nothing and the shell needs no
hide on any dismissal path.
→ with an app focused and the keyboard up, open and close each of the drawer,
Settings and the theme picker: `sm.puri.OSK0` `Visible` is still true
afterwards, and the focused workspace's `rect.height` is unchanged across the
close at 6 samples over 3s

**I5e** The bottom inset follows the keyboard and not the field, and that is
now the only signal there is (I5a). The compositor's own configure is what
answers: on this panel the granted height is 694 or 674 with the keyboard down
and 494 or 474 with it up, so the two clusters are 180px apart and no threshold
between them can be walked into by the 20px the inset itself moves.

`searchField.activeFocus` was the leading term, as a stand-in for "the keyboard
is up" on the reasoning that focusing the field is what raised it. It is not a
worse signal now, it is a wrong one: a focused field raises nothing (G14), so a
gate that read it would drop the inset with no keyboard underneath and show a
band of the app through the sheet with the home pill on it.
→ with the drawer open, the keyboard forced up on `sm.puri.OSK0` and the search
field never tapped, `drawer geometry` reports `margin=0` while `searchTarget`
reports `focused=false`; tapping the field leaves `margin=0` unchanged

**I6** The pill still works over all three, and none of them needs a mask to
manage it. All three are on Top -- the keyboard included, deliberately, because
on Overlay it would map before the strip and take the bottom exclusive zone the
pill needs (`windows.md` W5, `moarchy-keyboard/src/panel.cpp`) -- the strip is
on Overlay, and every Overlay surface sits above every Top one. So the strip
takes those touches before any of the three sees them. A shell app needs no
clause here: it is a window, and the strip reserves its band off every window.

The mask the keyboard does carry is for the **left** edge, not this one: the
back-gesture band is on Overlay with `ExclusionMode.Ignore`, and the keyboard
excludes that column from its input region so the gesture that dismisses it is
never swallowed. The shade is the surface that needs a mask for the pill, and
only because it is on Overlay itself.
→ A7 with the drawer; `omarchy-shell themes state` == `closed` after an
up-flick from the strip; and, with the keyboard up, an up-flick still goes home.
Not `settings` — an up-flick leaves a shell app running on its workspace (K4)

**I7** Drawing a sheet under the pill does not make the pill harder to see than
it already was.

Measured on tokyo-night, at rest: over the wallpaper the pill composites to
`4A3E53` on `150D20`, and over the drawer's sheet to `45485B` on `1A1B26`. Both
are **1.90:1**. That equality is the point of this criterion: the pill is
`Util.alpha(Color.foreground, 0.3)`, and a constant-alpha overlay's contrast
against its *own* backdrop is set by the alpha and the foreground-to-background
gap, very nearly independent of what is behind. So this moves the pill from an
unbounded backdrop to a known one without moving the number.

It also means **3:1 (WCAG 1.4.11) is unreachable at 0.3**, so asserting it here
would be asserting something no version of this UI has satisfied. The resting
alpha is a decision about the pill, not about what is drawn behind it.
→ the pill's composited colour over a sheet is within 0.1 of its composited
colour over the wallpaper, for the same theme

## K. Settings is an app

Settings is a screen you spend time in — ten pages deep in places, with a stack
you navigate — so it behaves like the apps beside it. A layer surface has no
workspace, and every attempt to give it one is a re-implementation of window
management inside a shell plugin.

So **Settings, Wi-Fi, Bluetooth and SIM are ordinary Wayland toplevels**, drawn by
the shell process and mapped as windows. This section is short because that is
the whole of it: A, B, F, G and M apply to them unchanged, with no clause of
their own.

**K1** The three shell screens are xdg toplevels. Sway tiles them,
`bin/moarchy-one-app-per-workspace` moves each one to a workspace of its own and
focuses it, and `ToplevelManager` reports them — which is what makes the tile
the overview draws for one a real window rather than a stand-in.

Quickshell's `FloatingWindow` is what this rests on: a window the shell's own
process owns, which the compositor treats as any other client's. It carries no
server-side decoration (`deco_rect` is zero under `default_border pixel 2` with
`hide_edge_borders smart`), so a shell app alone on its workspace fills it edge
to edge, under the bar and above the strip, exactly as `foot` does.
→ with Settings open, `swaymsg -t get_tree` has an `app_id == "org.quickshell"`
node that is the only window on its workspace, and `overview windows` names
`moarchy.settings`

**K2** Swiping sideways off a shell app and back again arrives back *on* it, on
the page it was left on. A window does not have to be put back: it was never
taken away.
→ from `settings page` == `appearance.bar`, `gestures swipe left` then
`gestures swipe right` leaves `settings state` == `open` and `settings page`
== `appearance.bar`

**K3** Everything else that moves the workspace does the same, and none of it is
this shell's code: `swaymsg workspace`, a keybinding on a paired keyboard, a
launcher that lands an app somewhere else. The screen stays where it was put.
→ with Settings up, `swaymsg workspace next_on_output` then
`swaymsg workspace prev_on_output` leaves `settings state` == `open`

**K4** Going home (A4, F1) leaves a shell app running on its workspace, the way
it leaves any app running. Its tile is on its card in the overview and tapping
it comes back to the page it was on. There is no hidden state: a shell app is on
screen, on another workspace, or gone.
→ after the home band, the focused workspace's `representation` is empty,
`overview windows` still names `moarchy.settings`, and `settings state` == `open`

**K5** A shell app names and draws itself: the glyph the shade opens it by, the
app's name, and — where there is room for a third line, which on a tile there is
not (P5) — the page it is on. None of it comes from a desktop entry, because
there is none to find (K9). It comes from the plugin, which is the one place
that knows, and `overview windows` prints the pair.

The glyph is declared, not derived: an empty one falls through to an `Image`
with an empty source, and the tile is a blank box under a correct label — which
no check that counted tiles would see.
→ `scripts/style-check.sh` reports every `AppWindow` declaring a non-empty
`glyph`, counted, and names the file and line of one that does not;
`overview windows` prints that plugin's id and the page it is on

**K6** Two things close a shell app, and both drop its tile and reset the page
stack: dropping the tile in the overview's bin (P12), and the back gesture with
nothing left to go back to (K7). That pairing is exactly what those two gestures
already do to a window — P12 closes the window a tile stands for, G4 closes the
focused app — and here they *are* those two gestures rather than a copy of them.
→ after either, `overview windows` has no `moarchy.settings` line and
`settings stack` is one line

**K7** The back gesture over a shell app walks its page stack first, and closes
the window only from the root page. G3's "an overlay that owns a page stack gets
first refusal" reads off the *focused window* rather than off a list of open
overlays, because a shell app is not an overlay.

Ordering matters and is the whole of the criterion: back inside Settings must
never reach G4 and close the app underneath, and back on the root page must not
be swallowed into doing nothing.
→ from depth 2, one back leaves `settings page` one page up and the window
count unchanged; from the root, one back leaves `settings state` == `closed`

**K8** A row that ends in a terminal needs nothing to get out of its way. A
tiled terminal is moved to a free workspace and focused
(`bin/moarchy-one-app-per-workspace`); a floating one maps above the window it
was launched from. Either way it is on screen and typeable.

There is no `hides` mechanism, and there must not be one again. It existed
because a full-screen *layer surface* is above every window on the output, so a
terminal launched from Settings mapped underneath it and was indistinguishable
from a tap that did nothing — which is how a phone ended up with sshd enabled
and an empty `authorized_keys`. A window is not above other windows, so the
failure has no mechanism left.
→ `settings activate ssh` leaves `settings state` == `open` and a new window
focused

**K9** All three carry `app_id == "org.quickshell"`, which is the shell process's
app id and not something this port chooses: Qt sets the xdg-toplevel app id once
per process from `QGuiApplication::desktopFileName`, and there is no per-window
override in Qt 6.11. Identity is therefore the window *title*, which each screen
sets to its own name and page. Everything that resolves a shell app — its tile's
icon, the back gesture's page stack — depends on it, and a window whose title
this shell did not set is somebody else's window and gets an ordinary tile.
→ `swaymsg -t get_tree` reports `app_id == "org.quickshell"` and a `name` of
`Settings` for the root page

**K10** Three shell screens: **Settings**, **Wi-Fi** and **Bluetooth**, and
nothing else. The shade and the drawer stay transient sheets with no tile of
their own: they are summoned and dismissed in one motion, and A6/A8 already say
what the strip does with them. The theme picker stays out too — it is a page
reached from Settings that returns to the page it was opened from
(`settings.md` B7), not a screen of its own.

The test is whether it is a screen you *sit in* — Wi-Fi because joining a
network means retyping a passphrase and coming back; Bluetooth (`shade.md` S6d)
because pairing means waiting for a device to appear, putting it in pairing
mode, and trying again.

**K12** Summoning a shell app that is already running focuses its window rather
than opening a second one, and leaves it on the page it was on. There is one
window per screen, and the ways in are many — the shade's gear, a Settings row,
the drawer, an IPC verb. Naming a page still navigates (`settings.md` A7); it is
the summon that names none that means "the screen I was on".
→ with Settings running on another workspace at `appearance.bar`, `settings
open` leaves the focused workspace holding it, `settings page` unchanged, and
`overview windows` with one `moarchy.settings` line

---

## L. Long-press on an app

A tap on an app icon launches it (H4), and that is the whole vocabulary the
grid has: there is no way to reach anything *about* an app — what it is, what
it came from, or how to be rid of it — and the phone ships 64 desktop entries
nobody chose one at a time. Upstream's answer is keyboard-shaped (Ctrl+D on a
highlighted row in the Omarchy menu), which is not a thing a thumb can do.

**Removal is the drawer's, not a terminal's.** Upstream's
`omarchy-remove-launcher-entry` ends its package branch by handing
`sudo pacman -Rns` to a floating terminal, so the answer to "what will this
take with it" is pacman's `[Y/n]` prompt in a 60-column foot window, typed on
the on-screen keyboard. That is the only place the consequence is stated, and
it is stated in the one surface that costs a keyboard to answer. So the drawer
asks the same question itself, from the same `pacman` output, before anything
runs (L7), and the run itself is silent (L9).

### The gesture

**L1** A press that stays on one app cell for **500ms** without travelling past
the drag slop (H1) opens that app's detail sheet. Nothing else in the grid
changes: below the hold, a tap is still a launch (H4); past the slop, the touch
is still a close drag (H1).
→ `sudo moarchy-touch hold <x> <y> 900` over a cell, aimed with
`omarchy-shell drawer cellTarget 0`, leaves `omarchy-shell drawer detail`
naming that cell's entry

**L2** The hold does not also launch. Qt delivers `released` and then `clicked`
to the same `MouseArea` the timer fired from, so the flag that swallows the
click is cleared on the *next* press, exactly as `sheetWasDrag` is: cleared on
release it is already false when the click arrives, and the app you asked about
is the app that starts.
→ after the hold, `omarchy-shell overview windows` gained no line

**L3** Travel cancels the hold; the hold does not cancel travel. A finger that
goes down on an icon and then drags is a close drag from the first pixel past
the slop, whether or not 500ms has passed on the way — the timer stops when
`sheetDragging` latches.
→ a 1200ms drag down from a cell leaves `drawer state` == `closed`,
`drawer detail` empty, and `drawer dragTrace` ≥ 8 samples

**L4** Scrolling the grid opens nothing. A `Flickable` steals the grab and Qt
clears `pressed` before it emits `canceled()` (`style.md` H6), so the timer has
the same cancel path a press veil has, and a thumb resting mid-scroll does not
arrive at a detail sheet.

### The sheet

**L5** The detail sheet is a **card over the drawer**, not a surface and not a
page. The drawer keeps its keyboard focus, its scroll position and its progress;
closing the card leaves the grid exactly as it was. A phone that answers "what
is this" by replacing the screen you asked from has lost your place to tell you
something you could have read in a card.

Two ways out, and neither is a button: a tap on the scrim beside it, and the
back gesture. Back walks the levels one at a time the way it does in Settings
(G3) — from the plan to the card, from the card to the grid, and only then out
of the drawer — because the plan is a step you took and back is the step you
take to undo one.
→ from an armed plan, three `omarchy-shell gestures back` calls give stage
`info`, then no card with `drawer state` == `open`, then `closed`

**L6** The card says what the app is and where it came from: its icon and name,
its `.desktop` id, and the package that owns it with that package's version and
installed size. An entry no package owns says which kind it is instead — a
personal entry, a web app, or a terminal app — because "no package" is an answer
and a blank field is not.
→ `omarchy-shell drawer detail` prints `id`, `kind`, and for a package
`package`, `version` and `size`

**L7** Uninstall never acts on the first tap. Tapping it replaces the card's
body with the **plan**: every package the removal would take, how many there
are, and their total size — read out of `pacman -Rs --print`, not guessed and
not summarised from the one package that was asked for.

`-Rs` and not `-Rns`: pacman rejects `--nosave` together with `--print`
outright ("invalid option: '--nosave' and '--print' may not be used together"),
so the plan is computed without it and the removal that follows carries it, the
way upstream's does.

**L8** A removal pacman would refuse is refused **here**, naming what refused
it, and the Remove button is not drawn at all. There is no path from this card
to a failed transaction the user has to read out of a notification.
→ a `plan` for a package with a dependent outside the set answers `blocked`
with pacman's own line, and `omarchy-shell drawer canRemove` is `no`

**L9** Confirming removes, with no terminal and no prompt: the result arrives as
a notification (`omarchy-notification-send`, which is what this image has —
there is no `notify-send` on it) and the sheet closes. Failure is a
notification too, carrying pacman's last line rather than "failed".

**L10** The grid drops the app when it is gone, without reopening the drawer.
`appLibrary` already emits `appsChanged()` when the desktop-entry set moves, and
`appRows` already re-reads on it — this criterion is that nothing here defeats
that.

### What may not be removed

The grid is 64 entries and some of them are the phone. Two rules decide, and
both are answers pacman gives rather than a list kept here — a second list of
what matters is the failure `structure.md` P5 exists to prevent.

**L11** **The shell will not uninstall itself.** No package whose name begins
`moarchy` or `omarchy` can be removed from this card, whatever pacman says
about it. That is `moarchy`, `moarchy-meta`, `moarchy-qml-apps`, `moarchy-store-git`
and `omarchy-config` today, and it is whatever else this project ships later
without anyone remembering to come back here.
→ a hold on `moarchy.device` reports `info.protected=1`, `drawer uninstall` ==
`protected` and `drawer canRemove` == `no`

**L12** **Anything another installed package needs is refused** — with one
exception, and the exception is the whole reason this section needs stating.
`moarchy-meta` is a package with no files whose entire content is a `depends`
line (`structure.md` P5), so *every* app on this phone has it as a dependent and
a plain `pacman -Rs gnome-maps` fails with

```
:: removing gnome-maps breaks dependency 'gnome-maps' required by moarchy-meta
```

That is the record of the set objecting, not a package that needs the app. So
when `moarchy-meta` is the **only** thing blocking a removal, the plan is
recomputed with `--assume-installed <pkg>`, which waives the check for that one
name and leaves every other dependency check standing. When anything else is
also blocking — `quickshell` is required by `omarchy-config` as well, `sway` by
`moarchy` as well — the removal is refused (L8).
→ a `plan` for an entry with a dependent outside `moarchy-meta` answers
`blocked`

**L12a** The rule protects only what the metadata declares, and that is a
standing claim on `pkgbuilds/moarchy`'s `depends`, not a list kept here.
Measured against all 34 entries the drawer lists, three undeclared dependencies
were reachable through L12:

| Entry | What the plan said | Why |
| --- | --- | --- |
| Foot | Removes 2 packages | `bin/moarchy-launch-tui` execs `foot`, undeclared |
| KWeather | Removes 40 packages, `upower` among them | `moarchy.bar`'s battery is `Quickshell.Services.UPower`, undeclared — and `upower` is on the phone only as KWeather's own transitive dependency, so `-Rs` takes it |
| (not listed) | — | `default/sway/autostart.conf` execs `polkit-gnome-authentication-agent-1`, undeclared |

So the drawer would have offered to remove the terminal every TUI opens in, and
would have taken the battery indicator away with the weather app. `upower` is
the one to keep in mind: it is not exec'd anywhere, so no grep for a binary name
finds it, and it was reached by a *cascade* rather than named as a target.

A browser is deliberately not protected. `bin/moarchy-launch-browser` is a
fallback chain over four of them, so Epiphany stays removable — which is the
test that this rule is about dependencies and not about a list of favourites.
→ `moarchy-app-remove plan foot` reports a blocker (`apps.md` T5)

**L13** The plan says when the exception was used. A package the set declares is
one a later `moarchy-meta` upgrade will pull back in — pacman resolves an
upgraded package's dependencies — so the card says so rather than letting the
app reappear on a `pacman -Syu` as if the removal had not worked.

---

## N. Opening the drawer

The sheet is dragged open by a finger at 60Hz on a Mali-400, and everything the
open path does lands on the frames the sheet is arriving on. The shade is the
comparison that makes this measurable rather than a feeling: it does none of
it, and it is the surface people say comes up instantly. N4 is not about cost
but about what state it opens in, which is the other half of the same path.

**N1** Opening the drawer starts no filesystem scan. The icon index refreshes
itself — `AppLibrary` watches `DesktopEntries` and restarts a 750ms
`iconIndexDebounce` on every change — so an app installed while the shell is
running has its icon without the drawer asking. One scan per shell start
remains, on the first open, for the first-boot race where a package places its
icons after the shell has read them and touches no `.desktop` file afterwards.
→ `grep -c 'appLibrary.refreshIcons()' moarchy.drawer/Drawer.qml` is 1, and
that call sits behind a flag `open()` sets; on the device, a second
`omarchy-shell drawer open` spawns no `find` under the shell —
`pgrep -af 'find .*icons' -P $(pgrep -x quickshell)` during the open is empty

**N3** The drawer's surface is never unmapped. Shut, it is a one-pixel band along
the bottom edge that takes no input; it grows to the sheet when an **upward** drag
latches, not on press, and takes no input until the sheet is being drawn.

A press on the strip is usually a workspace swipe (B1, horizontal wins). Growing
the full grid on that press laid it out and left it composited on Top for the
duration of the switch — the hitch that vanished when this plugin failed to
load. Latch is 8px up, still inside the slop of a real open, so the configure
still lands before the sheet is on screen. A press that never latches never grows.

It used to be mapped at latch and unmapped on close, and Quickshell deletes a
layer-shell window that goes invisible: every open built a new window, render
thread, GL context and scene graph, and stalled the screen for ~200 ms on the
Pixel 3a (omarchy-test's `docs/drawer-open-stall-results.md`). As a band, an
open is a resize — one configure — and the sheet keeps the height it last had, so
the grid is not laid out again at one pixel.
→ a sideways swipe with `drawer state` == `closed` leaves `drawer geometry` at
`h=1`; an up-swipe past slop reports real dimensions; a tap anywhere but the
strip still reaches the app underneath

**N4** The drawer opens with its search field unfocused and its query empty,
however it was closed. The field has to be made to let go *before* the surface
unmaps: `focus = false` releases the focus scope and not the active focus, so
the field keeps its `focus` flag across the unmap and takes activeFocus back on
the next map — and an item outside the window cannot be given active focus at
all, which is how a `forceActiveFocus()` on an orphan silently took nothing
away for a release.
→ tap the search field, close the drawer, open it again:
`omarchy-shell drawer searchTarget` reports `focused=false`

---

## P. Right edge — the overview

The sideways swipe steps one workspace at a time (B1), and on a phone where a
workspace *is* an app, stepping cannot answer "where is everything". §P is the
map that does: every window the phone has, on the workspace holding it. It is
the one place a workspace can be given a second app, and the one place a window
is closed by hand.

**P1** Swiping in from the **right edge** raises the edge's sheet — the overview
as shipped (Q1), and §P is written about it: every workspace as a card, newest
number last, scrolling vertically. The band is **16 logical px**,
the same width and for the same reason as the back edge (G8), and like it the
surface never grows.

Nothing is drawn on the band. The back edge shows an arc because a back swipe has
nothing else to look at (G12); this one pulls a sheet in under the finger, so the
gesture's own result is the cue — which is also why this surface needs no wider
drawing band and no input mask (G13).
→ `omarchy-shell gestures geometry` reports `overviewW` == 16 scaled and
`overviewSurfaceW` == `overviewW`

**P2** The sheet follows the finger: one pixel of finger is one pixel of sheet
(D2a), released past halfway it opens and short of it springs back, and a fling
either way decides whatever the travel. That is the drawer's release rule read on
the other axis, through the same `sheetCommit`.
→ `omarchy-shell overview dragTrace` leaves ≥ 8 samples across a slow drag in
from the edge, rising monotonically, and ends `-1` on a cancel or `-2` on a touch
the watchdog retired

**P3** The cards are what sway is holding: every numbered workspace, in number
order, each showing the windows on it. The scratchpad is not one of them.

Read from `swaymsg -t get_tree` and not from `Quickshell.I3`, which publishes no
window list at all — and a con_id, which P6 moves windows by, appears nowhere
else.
→ `omarchy-shell overview grid` prints one `ws=` line per numbered workspace with
its `apps=` and `ids=` in layout order, and a final `free=` line

**P4** Tapping a card goes to that workspace; tapping a tile goes to that window;
both close the overview. The focused workspace's card and the card a drop would
land on are marked the same way, in the accent — this shell's existing word for
"this is where you would end up" (A4, C2).
→ tapping a tile leaves `omarchy-shell overview state` == `closed` and the
focused workspace holding that window

**P5** A tile is an icon and a name, and for a shell app the glyph it declares
(K5) — there being no desktop entry to take an icon from. Two lines and not
three: a tile is a quarter of a card's width, and a third line on one that had
room for it is a tile that reads differently from the three beside it.

The resolvers are `moarchy.common/Apps.js`, which is also the appId index the
drawer asks whether an app is already running before it hops a workspace to
launch it (`windows.md` L10). One index, because two that answer the same
question disagree the day one of them goes stale.
→ `grep -c 'Apps\.' moarchy.drawer/Drawer.qml moarchy.overview/Overview.qml` is
non-zero for both, and neither file builds its own appId index

**P6** **Drag a tile to pick the window up**, then drop it on another card to
move it there or in the bin to close it (P12). The window rides under the
finger; what a release would land on is marked; a release on the card it came
from, or in the gap between two cards, changes nothing.

There is no hold. The lift is claimed on the first travel past the drag slop,
and it takes the rest of that touch: the list does not scroll under a window in
the air and the sheet does not close out from under one. A drag that starts on a
tile is the window's on every axis, so there is nothing left to arbitrate —
which is the only thing a hold buys, and the reason there is none rather than a
shorter one.

The cost is a tile as a place to start a scroll from, and it is small because a
card is scrolled from anywhere its tiles are not: one app per workspace (F1)
leaves three slots of every four empty, beside a card-sized gap and the free
card at the end.
→ `omarchy-shell overview lift <ws> <index>` then `overview dropOn <ws>` moves
that window, and `overview move <con_id> <ws>` is the same call without the
gesture: `overview grid` shows it under the second `ws=` and no longer under the
first. With a finger, aimed with `overview tileTarget <ws> <index>`:
`sudo moarchy-touch drag X1 Y1 X2 Y2 0 500` — a 0ms dwell, so a lift that still
wanted one would not fire — moves the window. And `sudo moarchy-touch hold
X1 Y1 900` on a tile is a *tap* (P4): `overview state` == `closed` with the
focus on that window, where a lift would have swallowed the click and left the
sheet up with nothing moved

**P7** A workspace holding **more than one window is split vertically** — one
above the other, both on screen. Half of 360 logical px is 180, which no app on
this phone can use, where half of 740 is 370 and every app here already reflows
to it. That is the same measurement that makes a *launch* go to a free workspace
instead (F1); the difference is that a drag is somebody asking for two.

The direction is named rather than left to sway. `default_orientation auto`
picks vertical for a container this shape on its own, but a window moved onto an
occupied workspace joins the container that is already there and keeps *its*
direction — so an inherited `splith` puts the pair side by side at 180px each
unless something says otherwise.

The layout asked about is the **container that holds the windows**, not the
workspace. That same joining is why: the tree reads `workspace splitv > con
splith > [foot, foot]`, so the workspace says `splitv` — the answer wanted —
over a pair that is side by side, and a check against it reports success while
the phone is unusable.

A workspace with one window is left exactly as sway made it, and one somebody
has made `tabbed` or `stacked` by hand keeps that: sway has those layouts and
this is not a policy about which the phone may be in.

`bin/moarchy-one-app-per-workspace` reconciles it on sway's own event stream, so
a keyboard user's `$mod+Shift+2` lands the same way as the drag. The overview
only moves the window.
→ with two windows moved onto one workspace, `swaymsg -t get_workspaces | jq
'.[].representation'` shows them inside `V[...]` and their two `rect`s divide the
workspace's height, not its width;
`moarchy-one-app-per-workspace --reconcile` forces one pass without the daemon,
and `python3 scripts/test-workspace-layout.py` settles the rule, the direction,
the nesting and the focus-restoring fallback without a phone at all

**P7a** Cards are all one height, and a workspace with more windows than fit gets
a count in the last slot rather than a taller card. A drop is aimed by
arithmetic — while a window is in the air the tile holds the exclusive grab, so
no card underneath ever sees a touch to answer with — and that arithmetic is what
fixes the height.

**P7b** The last card is the next free workspace, so "somewhere else" is a place
on screen rather than a gesture you have to know. It is the number the home swipe
would take you to and the number a new window would land on (F1).
→ `omarchy-shell overview grid`'s `free=` equals
`moarchy-one-app-per-workspace --free` and `gestures status`'s `free=`

**P7c** A card says `TABS` or `STACKED` only when the windows on it are hidden
behind each other. Tiled is the ordinary case and a label on every multi-window
card would be a word that never varies; what a glance at the phone cannot tell
you is that a workspace holds two apps and shows one.

**P8** The surface is never unmapped: shut it is a one-pixel band along the edge
it enters from — a column on this one — grown when the drag latches and not on
press. The drawer's
measurement, on the other axis — a layer-shell window that goes invisible is
deleted, so every open would rebuild a scene graph while the finger was already
moving (N3).

The band stops short of the same two ends as the back edge and for the same
reasons: one strip plus one keyboard panel at the bottom (G10), the status bar
plus one header bar at the top (G10b). Both numbers are shared rather than
mirrored — what they clear runs the full width of the screen, and the keyboard's
outermost key column is at both edges.
→ `omarchy-shell gestures geometry` reports `overviewH` == `h`

**P9** Shut, this plugin runs nothing: no `swaymsg`, no timer, no subscription.
It reads the tree when the sheet comes up and when sway says something changed
while it is up.
→ `grep -c 'surfaceUp' moarchy.overview/Overview.qml` guards both the refresh and
the two `Connections`

**P10** The overview is reachable without a finger.
→ `omarchy-shell overview open|close|toggle|state|progress|grid|move|lift|dropOn`,
and `omarchy-shell gestures overview` for the summon the edge performs

**P11** The overview is a sheet, so the rules about sheets are the rules about it:
it puts away the drawer and the theme picker beside it and the shade above it
(B6), a back swipe closes it before it closes the app under it (G1), a sideways
swipe sweeps it (B3), and an app's window opening leaves none of it behind.
→ with the overview up, one `omarchy-shell gestures back` leaves
`overview state` == `closed` with the open-window count unchanged

**P12** While a window is in the air a **bin** is drawn across the foot of the
sheet, and a drop on it closes that window. It is there for the length of the
lift and at no other time: there is nothing to put in it otherwise, and a
standing target that destroys something is a target a thumb finds by accident
(C4).

Its band is **reserved off the list** whether or not anything is in the air, so
the bin covers no card. Drawn over the list instead it hides the card at the
bottom of the sheet, which is the free workspace (P7b) — the drop a drag is most
often aimed at. The list pays about a card's height for that permanently, and
the alternative is worse in both directions: reserving the band on the lift
would relayout the list on the frame a window leaves the ground, moving every
card out from under the finger that just picked one up.

It is marked in **`urgent`** where a card is marked in the accent. The accent is
this shell's word for "this is where you would end up" (A4, C2, P4) and the bin
is not a place you end up — it is the one drop on this sheet that cannot be
undone, and the theme already keeps one colour for that (`style.md` C1).

A window over the bin is over nothing else: the bin takes the point the moment
it holds it, so no card is lit underneath and a release can only mean one thing.
Which it is is arithmetic over the finger's position, like every other drop
here — the tile holds the exclusive grab while a window is in the air, so the
bin never sees a touch of its own to answer with (P7a).
→ `omarchy-shell overview binTarget` reports `drawn=false` and the rect the
bin will occupy while nothing is lifted, and `drawn=true` after
`overview lift <ws> <index>`; `overview aim <x> <y>` into that rect leaves
`overview lifted` ending `over bin`, and a point over a card leaves it ending
`over <n>`

**P13** A drop in the bin is a **close request** and not a kill: it is
dispatched as `[con_id=N] kill`, which is sway's name for `xdg_toplevel.close`,
so an editor with unsaved work prompts rather than dies — which is what makes
firing it from a drag acceptable at all. By con_id and not through the
foreign-toplevel handle, because a con_id names one window where the handle is
matched on app id and title (P5) — and under that, two terminals are one
window twice.

The tile goes as soon as the window is dropped — a card that waited for the app
to answer would put the tile back under the finger that had just thrown it away
— and it is gone from *this* opening of the sheet only: an app that refuses to
quit is still running and has its tile again the next time the overview comes
up.

Closing the last window on a card leaves the card. A workspace with nothing on
it is a home screen (P3), which is a place you can go to and not a dead end.
→ `overview lift <ws> <index>` then `overview trash` leaves
`overview tileTarget <ws> <index>` == `no tile` before the app has answered and
`overview windows` one line shorter once it has, with `overview grid` still
printing a `ws=` line for the workspace it was on. With a finger, a
`sudo moarchy-touch drag` from `overview tileTarget` to `overview binTarget`'s
rect closes the window it started on

**P14** There is no "close everything". Windows go one at a time — into the bin
(P12), or with the back gesture on the app itself (G4). One control that closed
every open window is one mis-tap from losing all of them, and like the hold C4
refuses, it would have no undo.

---

## Q. Choosing what a trigger opens

Four things point somewhere, and until this section all four pointed at a name
written in the code: the strip raised `moarchy.drawer`, the right edge raised
`moarchy.overview`, the hold started the coding agent, and the power button had
no second meaning at all. Everything else about a drag was already general --
the travel comes off the target, the progress is written onto it frame by
frame, the commit goes through the host -- so what was missing was where the id
comes from.

Two of the four drag a sheet and two are a tap, and the difference decides what
each may name. An edge has to follow a finger, so it may only name something
that can be dragged. A tap has nothing to follow, so it may name anything that
opens.

### The two edges

**Q1** Each of the two edges opens the sheet a setting names: `gesture_bottom`
for the strip and the wallpaper under it, `gesture_right` for the right edge.
The values are words -- `none`, `drawer`, `overview`, `shade` -- and not plugin
ids, so `ui.toml`, `bin/moarchy-ui` and the Settings rows never spell one and
`Sheet.js` stays the only place the ids live. Shipped they are the drawer and
the overview, so a phone nobody has touched behaves exactly as §A and §P
describe.
→ with no `ui.toml`, `moarchy-ui get gesture-bottom` == `drawer` and
`moarchy-ui get gesture-right` == `overview`; `omarchy-shell gestures status`
reports `bottom=moarchy.drawer right=moarchy.overview`

**Q2** A sheet arrives from the edge that raised it, and its own close drag runs
back along the same axis. The overview on the strip rises from the bottom rather
than sliding in from the right, and one pixel of finger is one pixel of sheet on
whichever axis that is (D2a) -- measured against the sheet's own extent along
it, which is what makes the divisor right on both.
→ with `gesture_right` == `drawer`, a drag in from the right edge leaves
`omarchy-shell drawer dragTrace` with ≥ 8 samples rising monotonically, and
`drawer geometry` reports a `travel` of the screen's width where the same sheet
on the strip reports its height

**Q2a** Only the entry axis moves. A sheet keeps the size it has and the anchor
it keeps on the cross axis, and comes to rest against the edge it entered from.
The shade is what this is for: it is as tall as its content (`shade.md` S21) and
a mirrored width would be a relayout of every tile on it, where a full-width
sheet arriving from the right is the same sheet on a different path.
→ with `gesture_right` == `shade`, `omarchy-shell shade geometry` reports the
same `height` it reports on the top edge

**Q3** A sheet's edge is fixed for as long as it is up. It is taken when the
sheet is at rest shut and never while it is moving, so a setting changed with a
sheet on screen reaches it on the next open rather than re-anchoring it
mid-flight. Half a sheet held to one edge and half to another is not a state
this shell has a name for.
→ with the drawer open, `moarchy-ui gesture-bottom overview` leaves
`omarchy-shell drawer geometry` unchanged; the next strip drag raises the
overview

**Q3a** The edge belongs to **whatever raises the sheet**, not to the
setting. An edge gesture sets its own edge; a sheet's own handle sets the
sheet's own -- the shade's grab band means *down from the status bar* whatever
the strip is pointed at; and a summon that carries no direction at all (an IPC
verb, the shade's gear, a tap trigger) uses the sheet's natural edge. All
three only from rest, which is Q3.

Reading the edge off the setting alone is what the first implementation did,
and it is wrong in the hand rather than on paper: with the strip set to raise
the shade, `entryEdge` was left at `bottom` by the last strip press, so a pull
*down* from the status bar slid the sheet up off the floor and left the top
two thirds of the screen empty.
→ with `gesture_bottom` == `shade`, a pull down from the status bar leaves the
sheet's top edge at the top of the screen, and a swipe up from the strip
leaves it against the bottom

**Q3b** A sheet dragged from an edge is dragged against **its own** travel,
whatever is driving it. A sheet that measures itself only when its own handle
starts a drag measures nothing when an edge does, and this is not a scaling
error that degrades gracefully: the shade froze its height on `beginDrag()`,
which an edge drag never calls, so `closeTravel` fell to 1, `targetTravel()`
rejected it as unset and divided by 45% of the screen instead. The sheet drew
at zero height behind a live scrim and an ordinary pull landed past the home
stop -- so the gesture showed a dim screen and then went home.
→ with `gesture_bottom` == `shade`, an up-swipe from the strip at 400ms, 900ms
and 1500ms each leave `omarchy-shell shade state` == `open`, and
`shade dragTrace` rises to ≈ 100

**Q4** `none` takes the sheet off that edge and nothing else. The swipe raises
nothing, and everything on that edge that is not a sheet is untouched: the strip
still changes workspace (B1), still holds for its trigger (C1), and **a sweep up
still goes home** (A4).

Home is not a sheet, so an edge that raises no sheet still has the stop. It is
not free -- `commit()`'s vertical branch is `clear` and never `home`, so the
gesture reaches `releaseStrip()` only through a latch, and a latch today needs a
target. Without the clause a user who quiets the bottom edge loses the only
route to the wallpaper there is.
→ with `gesture_bottom` == `none`, a full strip sweep up leaves the focused
workspace's `representation` empty and every sheet `closed`; a short one opens
nothing; a sideways swipe still changes workspace

**Q4a** That sweep is measured against the screen, not against the startup
fallback. `pullTravel` is 45% of the screen and would put home inside an
ordinary swipe -- the very thing A4's stop was moved past 1.0 to avoid.
→ with `gesture_bottom` == `none`, `omarchy-shell gestures geometry` reports
`travel` equal to the screen's height

**Q5** A target the shell has not loaded behaves as `none` rather than as an
error. A plugin turned off on `shell.plugins`, or a word the file does not
know, resolves to no target, and every tracker already tests for one before it
latches.
→ with the overview disabled and `gesture_right` == `overview`, a drag in from
the right edge opens nothing and leaves nothing in the shell's journal

**Q6** Both edges may name one sheet. Whichever edge raised it, the other finds
it already open and does nothing -- the rule P8 already relies on, where a
second right-edge drag on an open overview has nowhere further to go. The strip
stays the exception it already is: a second drag there runs on into the home
band (A6).
→ with both keys == `drawer` and the drawer open, a right-edge drag leaves
`drawer dragTrace` empty and `drawer state` == `open`; a strip drag from there
leaves `representation` empty

**Q7** The shade keeps its own way in. Its grab band across the status bar
(`shade.md` H2) raises it whatever edge it is configured on, and raises it
*from the top* (Q3a) -- so a shade set on an edge has two ways up, each
arriving from the edge the finger started on, and a setting meant to add one
takes none away.
→ with `gesture_bottom` == `shade`, a pull-down on the status bar leaves
`omarchy-shell shade state` == `open`

**Q8** A changed setting is live on the next gesture, with nothing restarted.
`ui.toml` is watched -- the same file and the same watch the corner radii
already arrive through.
→ `moarchy-ui gesture-right shade`, then with no restart a right-edge drag
leaves `omarchy-shell shade state` == `open`

**Q9** Every trigger is a row in Settings, not a file anyone is expected to
edit, and what the rows offer is what the shell accepts. `settings.md` §Q is
the other half of this criterion.
→ `omarchy-shell settings openAt shell.gestures` lists four rows; each edge
page has exactly one ticked row, whose value is one of the four
`omarchy-shell gestures targets` resolves

### The two taps

Two triggers are a press rather than a pull: the strip's hold (C1) and the
power button's double press. Nothing about either follows a finger, so the
sheet contract Q2 is built on does not apply to them -- and that frees them to
name things an edge cannot.

**Q10** A tap trigger opens anything that opens: `none`, a sheet, the coding
agent, or **any app the drawer lists**. The value is a word for the first
three and a desktop entry id for the fourth, and `moarchy-trigger` is the one
place that decides which it is -- the hold fires from QML and the power button
from a sway binding, and a rule written at both ends is the defect B1 records
with the ids of the sheets.

The list cannot be a table the way an edge's is, because the fourth kind is
every app on the phone and it changes when somebody installs one. So an unknown
value is passed through as an id rather than replaced by a default, which is
the opposite of Q1's rule and for the opposite reason: an edge has four possible
values and a typo in one is a mistake, where a tap has sixty and a word this
file has not heard of is the ordinary case.
→ `moarchy-trigger rows hold` is `none`, `agent`, the three sheets and one row
per line of `omarchy-shell drawer entryRows`; with `gesture_hold` == `overview`,
`moarchy-trigger fire hold` leaves `omarchy-shell overview state` == `open`

**Q10a** An app opens the way the drawer opens it. `omarchy-shell drawer
launch` is what runs, so the workspace hop, the splash and the dismissal all
happen exactly once and in one place (`windows.md` L1-L7) -- a trigger that ran
`gtk-launch` itself would be a second copy of all three, and the missing splash
would read as a press the phone had ignored.
→ firing an app trigger leaves `overview windows` one line longer, with the new
window alone on a free workspace

**Q10b** The names on the list are the drawer's names. `drawer entryRows`
answers id and name together from the same walk `drawer entries` makes, so a
trigger can neither offer an app the grid hides nor call one something the grid
does not.
→ `omarchy-shell drawer entryRows | cut -f1` equals `omarchy-shell drawer
entries`

**Q11** **Two presses of the power button** inside **400ms** fire the power
trigger. One press still blanks the panel and stops the touchscreen, or undoes
that (`moarchy-screen toggle`), and it still does so the instant it lands.

The first press acts and the second undoes it, rather than every press waiting
to see whether a second is coming. The waiting version buys a double press with
no blink and costs ~350ms on the only button this device has, paid on every
press including the pocket ones -- and a button that hesitates is worse than a
screen that blinks. Android makes the same trade.
→ `scripts/test-power-press.sh`: one `moarchy-power-press` calls
`moarchy-screen toggle` and fires nothing; two inside 400ms call `unlock` and
then `moarchy-trigger fire power`

**Q11a** The second press unlocks rather than toggles. The first may have been
an unlock -- waking the phone and pressing again -- and a toggle there would put
the screen back out from under the thing that is about to open.
→ the same script: across a double press `moarchy-screen toggle` is called
exactly once

**Q11b** Three presses are a double and then a single, not two overlapping
doubles. The stamp is cleared when a double fires, so the third press is
measured from nothing.
→ the same script: three calls inside 400ms fire the trigger once

**Q11c** The power trigger ships as `none`. It is a gesture nobody has asked
for yet on a button everybody already knows the meaning of, and a phone that
opened something the first time its owner double-pressed out of habit would
have surprised them with it.
→ `moarchy-ui get gesture-power` == `none` on a home with no `ui.toml`

---

## Constraints

Not acceptance criteria — the boundaries any implementation works inside.

- **The strip reserves 20px off every window, permanently.** That is what keeps
  the on-screen keyboard from burying the pill. It reserves that band off
  *windows*; the shell's own full-screen surfaces deliberately draw under it
  (I1-I4), so the pill always has a known, flat backdrop instead of whatever
  wallpaper happens to be behind. Reserving and drawing-under are separate
  questions, and only the first is what the keyboard depends on.
- **Only the left edge may take touch ahead of an app, and only 16px of it.**
  The home-screen surface (D) sits *below* windows, so it can never intercept
  anything an app would have received and a bug in it cannot make the
  touchscreen unusable. The back gesture (G) is the one deliberate exception:
  it has to sit above windows to work at all. It is bounded the same way the
  bottom strip is — a fixed width that never grows mid-gesture — so the worst a
  bug there can do is cost 16px down one side.
- **No window thumbnails.** Quickshell 0.3.1 wires per-*toplevel* capture only
  to `hyprland-toplevel-export-v1`, so a tile for a window that is not on screen
  cannot have a picture -- and sway does not render an invisible workspace, so
  there would be nothing to capture anyway. Tiles are icon + name (P5).

  The *focused* window is a different case, and it is worth recording because
  the mechanism still exists and will look like an opportunity again: it is on
  screen and being rendered, and `ScreencopyView` takes a **monitor** through
  `wlr-screencopy-unstable`, which sway has and `grim` already uses here.
  Measured on the device, a 720x1440 capture arrives as a zero-copy dmabuf
  (`AR24`/`LINEAR`) imported straight into the scene graph, costing 60fps ->
  43-47fps for the length of one gesture. It is not used: an app you leave by
  opening the launcher over it has not gone anywhere — it is still on its
  workspace, still running, one tile away.
- **The left edge belongs to the shell, and that costs something real.**
  Everything else here avoided claiming a side edge because libadwaita's
  `AdwSwipeTracker` and Kirigami both implement back-swipe *inside* the app on
  touch, so every GNOME and Plasma Mobile app already had swipe-to-go-back. A
  layer surface on that edge takes the touch first, so those apps lose it: you
  can close an app, but you can no longer go back a page within one. Chosen
  deliberately (G) — a back gesture that is always there beats one that only
  some apps implement.
- **A claimed edge also swallows taps, and we cannot soften that the way
  Android does.** The band cannot forward a touch it decides not to use, so any
  app control within it stops being tappable. Android has the same problem and
  solved it with `View.setSystemGestureExclusionRects()`, which lets an app
  carve regions back out of the system gesture. **Wayland has no equivalent** —
  there is no protocol for a client to tell a layer-shell surface not to take
  touches in a region, so our edge is strictly more expensive than Android's.
  The answer is to carve the region out from *our* side, since the app cannot:
  G10b stops the band below the header bar, the same lever G10 already used for
  the keyboard. What is left is a narrower claim rather than a softer one — a
  control in the leftmost 16px *between* the two insets is still dead.

---

## Coverage

Not criteria — the record of which criteria are actually verified, so that
"written down" is never mistaken for "checked". Regenerate with:

```sh
grep -ohE '\b(okac|noac|skipac) +([A-Z][0-9]+[a-z]?)\b' bin/moarchy-selftest |
  awk '{print $2}' | sort -u
```

That over the whole file rather than over two hand-copied line ranges, which
went stale the first time a check was added above them and then silently
reported a different document's ids. Ids are not unique across files, so the
list it prints is a superset: take from it only what this file defines.

**Written, but nothing runs it** (46). Each has a `→` check that no
suite executes, so it is as unverified as one with no check at all:

> A3a · A8 · A10 · C1 · C3 · C4 · C5 · G10b · G11 · G12 · G13 · G14a · H1 ·
> H4 · I1 · I1a · I1b · I2 · I3 · I4 · I5 · I5a · I5b · I5d · I5e · I6 ·
> I7 · K8 · L8 · N1 · N3 · N4 · P2 · P5 · P9 · Q2 · Q2a · Q3 · Q3a · Q3b ·
> Q4a · Q5 · Q7 · Q9 · Q10a · Q11c

§Q's unrun half divides the way §P's does — P2 and P5 are what is left of it. Q2, Q2a and Q4a are the geometry --
where the sheet travels and what the drag divides by -- and settling any of them
needs a finger the suite can only synthesise through `/dev/uinput`, which is
where P2 has sat since it was written. Q3, Q5 and Q7 need a state the suite
would have to manufacture: a sheet open across a setting change, a plugin turned
off, a pull on the status bar. C1 and Q10a both end in a launch, and §C's note
says why a suite must not fire the one that installs an agent.

Q11, Q11a and Q11b are **run, and not by anything the command below greps** --
`scripts/test-power-press.sh` checks them on the host with `moarchy-screen` and
`moarchy-trigger` stubbed, because the double press is arithmetic over one
timestamp file. They are held out of this list by hand for that reason, and so
is K5: `scripts/style-check.sh` settles the glyph half of it by reading a
declaration, which no suite the command greps can do.

All of §I's assertable half is here too, and that is not deliberate -- I6 is
covered in substance by A7 (`bin/moarchy-selftest` notes this at the
`--surfaces` end), but I5a, I5b, I7 and I1's companions are simply unrun.

**Stated, with no check** (22). Behavioural claims with nothing to
settle them from a terminal; several are hand checks on glass by nature:

> B2 · D2 · D3 · D4 · F1 · G1 · G5 · G7 · G8 · G9 · G10a · H3 · H5 · H6 ·
> H7a · H7b · H8 · K10 · L4 · P7a · P7c · P14

The command above regenerates these lists from `bin/moarchy-selftest` alone, so
a criterion checked anywhere else has to be moved by hand.

**Run, with no `→` line here** (5). The suites check these; the doc
understates itself, and each should gain the check it is already being held to:

> G6 · L7 · L9 · L10 · L13

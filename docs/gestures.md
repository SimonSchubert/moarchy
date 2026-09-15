# Touch gestures — specification

What the phone's touch gestures must do. Written to the rule in
[`README.md`](README.md).

`bin/moarchy-selftest --gestures` and `--surfaces` cite these ids. A criterion
is in one of three states, and the difference matters: **run** — it has a `→`
check and a suite executes it; **written** — it has a `→` check that nothing
runs; **stated** — it has no check at all. 62 of the 101 below are run. The
other 39, and the six the suites run without a `→` line here, are listed under
[Coverage](#coverage) at the foot.

## Vocabulary

| Term | What it means |
| --- | --- |
| **strip** | The reserved 20px band at the very bottom holding the home pill. Owned by `moarchy.gestures`. |
| **home screen** | A sway workspace with no windows on it: wallpaper, bar, pill. One app per workspace, so an empty workspace *is* the home screen. |
| **app** | A workspace with a window on it, or Settings, which is treated as one (K). |
| **shell app** | A screen this shell draws itself and maps as an ordinary window, so every criterion about apps applies to it. Four of them: Settings, Wi-Fi, Bluetooth and SIM (K). |
| **drawer** | The searchable app grid, with a shelf of open apps along its top (`moarchy.drawer`). Every up-swipe raises this. |
| **shade** | The pull-down from the top edge (`moarchy.shade`). |
| **travel** | Drag distance as a fraction of the sheet being dragged — the drawer's own height, ~694 logical px. One pixel of finger is one pixel of sheet, on every surface that drags it (D2a). |

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
→ `omarchy-shell drawer state` == `open`

**A3a** The strip's drag is the home screen's drag: same 1:1 ratio against the
sheet's own height, same halfway commit, same fling rule in both directions.
The only thing the strip adds is the second stop.
→ a drag of *n* logical px from the strip leaves `drawer dragTrace` ending
within a few percent of *n* / 694, the same figure D2a asserts for the
wallpaper drag

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

**A5** The drawer is the only thing the strip opens — from an app, from a home
screen, with nothing open anywhere. The one exception is a sheet already
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
every sheet this shell can put over an app *except the drawer*, which a second
drag continues rather than clears (A6). Settings is out of it: it is an app
(K), so the strip raises the drawer over it and leaves it running on its
workspace when the drag goes home (K4).

The list is derived from the one the back gesture already walks, minus the
drawer and minus the shell apps — which are excluded by being windows rather
than by being named (K1). Three hand-kept lists of overlay ids is how Settings
and Themes came to be missing from the back gesture.
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
phone spends it on the thing its owner reaches for most. Here that is the
coding agent: it already has exactly one definition (`settings.md` P1), and
otherwise it is reachable only by finding its tile in a 64-entry grid. The
asymmetry is what makes it safe to spend — a hold that fires by accident opens
a window, and the back gesture closes it (G4).

**C1** A press that stays on the strip for **500ms** without travelling past
the drag slop starts the **default coding agent**: the agent the drawer's one
tile names, in a terminal, on its own workspace like any other app. With no
agent picked yet it opens the picker instead — the same two states as that
tile, read from the same one answer (`settings.md` P12), so the gesture and the
icon can never name different agents. 500ms is L1's number, because a phone has
one hold and not two.
→ with `codex` picked, `moarchy-agent launch` execs `omarchy-default-agent
codex`; with nothing picked it execs `omarchy-shell settings openAt
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
window for anyone with a keyboard, and the shelf closes one you can see (M6).
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
the strip — opens the drawer, following the finger.
→ `omarchy-shell drawer state` == `open`, `drawer dragTrace` ≥ 8 samples

**D2** Released below halfway the drawer animates back down; above halfway it
animates up and stays (A2, A3). One rule, both surfaces, and a fling in either
direction overrides it.

**D2a** The open drag is 1:1 with the finger: one pixel of travel is one pixel
of sheet, measured against the drawer's own height. Both drags measure against
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

**F2** Going home never closes anything. Every app still has its tile on the
drawer's shelf afterwards.
→ `drawer openApps` count unchanged across a home gesture

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
→ `omarchy-shell drawer openApps` is one line shorter

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

**G9** Only the left edge is claimed. Android takes both; the right edge stays
with apps here, which halves what this costs them.

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
from the edge, rising monotonically; a drag that never commits leaves samples
and closes nothing

**G13** The surface is wider than the band it takes touches in, and the extra
width is masked out of its input region. Everything right of the 16px falls
through to the app, exactly as it did when the surface was 16px wide.

This is on `Overlay` and sits over every window, so an unmasked widening takes
the leftmost strip of every app on the phone — silently, because a dead column
and a column that answers a gesture look the same until you try to use it.
→ `omarchy-shell gestures geometry` reports `w` == `backEdgeWidth` and
`surfaceW` > `w`; `w` keeps meaning the input band, so G8's number is still
what it was

**G14** The keyboard comes up only when asked, and only two things can ask: its
own restore handle, and `$mod+i`. Text focus raises nothing — not an app's
field, not the drawer's search box — and nothing in this shell puts it down
except the back swipe (G2), which is the same `SetVisible` call.

An app asking for text input is not an app asking for a keyboard. It used to be
read as one, so the keyboard appeared over half the screen whenever anything
took focus and left again just as often, which is the worse half: it moves the
layout under a thumb already on its way to a key. `moarchy-keyboard`'s AC 49 is
what makes a dismissal safe to let stick — the handle is on screen whenever the
keyboard is not, and AC 52 keeps it above this shell's overlays.
→ with an app's text field focused and the keyboard down, `sm.puri.OSK0`
`Visible` stays false across ~3s of sampling; going home, opening the drawer
and closing it again all leave it wherever it was

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
would have painted over all three. Only the band, and not the whole surface
underneath: a workspace with gaps on, or two windows tiled side by side, leaves
gutters where the wallpaper is meant to show.

Two states keep the wallpaper, and each is a case where the wallpaper is the
answer:

- **an empty workspace**, which *is* the home screen (vocabulary, D). Asked as
  "is any window focused", which is the question `run("home")` already trusts
  for this and which K1 made honest: the shell's own screens are windows and
  answer it themselves.
- **the keyboard up**, when the band sits under the keyboard rather than under
  the app.

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
on the drawer's shelf a real one rather than a stand-in.

Quickshell's `FloatingWindow` is what this rests on: a window the shell's own
process owns, which the compositor treats as any other client's. It carries no
server-side decoration (`deco_rect` is zero under `default_border pixel 2` with
`hide_edge_borders smart`), so a shell app alone on its workspace fills it edge
to edge, under the bar and above the strip, exactly as `foot` does.
→ with Settings open, `swaymsg -t get_tree` has an `app_id == "org.quickshell"`
node that is the only window on its workspace, and `drawer openApps` names
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
it leaves any app running. Its tile is on the drawer's shelf and tapping it
comes back to the page it was on. There is no hidden state: a shell app is on
screen, on another workspace, or gone.
→ after the home band, the focused workspace's `representation` is empty,
`drawer openApps` still names `moarchy.settings`, and `settings state` == `open`

**K5** A shell app names and draws itself: the glyph the shade opens it by, the
app's name, and — where there is room for a third line, which on a tile there is
not (M4) — the page it is on. None of it comes from a desktop entry, because
there is none to find (K9). It comes from the plugin, which is the one place
that knows, and `drawer openApps` prints the pair.

**K6** Two things close a shell app, and both drop its tile and reset the page
stack: flicking the tile away (M6), and the back gesture with nothing left to go
back to (K7). That pairing is exactly what those two gestures already do to a
window — M6 closes the window a tile stands for, G4 closes the focused app —
and here they *are* those two gestures rather than a copy of them.
→ after either, `drawer openApps` has no `moarchy.settings` line and
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
`drawer openApps` with one `moarchy.settings` line

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
→ after the hold, `omarchy-shell drawer openApps` gained no line

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
about it. That is `moarchy`, `moarchy-meta`, `moarchy-keep`, `moarchy-store-git`
and `omarchy-config` today, and it is whatever else this project ships later
without anyone remembering to come back here.
→ a hold on `moarchy.device` reports `info.protected=1`, `drawer uninstall` ==
`protected` and `drawer canRemove` == `no`

**L12** **Anything another installed package needs is refused** — with one
exception, and the exception is the whole reason this section needs stating.
`moarchy-meta` is a package with no files whose entire content is a `depends`
line (`structure.md` P5), so *every* app on this phone has it as a dependent and
a plain `pacman -Rs gnome-clocks` fails with

```
:: removing gnome-clocks breaks dependency 'gnome-clocks' required by moarchy-meta
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

## M. Open apps in the drawer

One app per workspace means every app that is running is running somewhere you
cannot see from the surface you are standing on. So the top of the sheet says
what is already open: four tiles of the grid's own size, most recent first,
with one dot each to say they are running.

This is the one thing the drawer's header note says it will not do — "a row of
controls at the top is a row of apps you cannot see". A row of open apps is not
controls. It is content, it is drawn only when there is any (M2), and the apps
it costs you are four you can still scroll to.

**M1** The row sits between the search field and the first row of apps, and
**scrolls with them**: it is the grid's own header, not a shelf pinned above a
moving grid, so dragging the apps up carries it off the top the way it carries
the first row of icons. One tile per open **window**, most-recently-used first,
left to right, with the app you just left leading.

One `ToplevelManager` walk, one appId → desktop-entry index, one MRU, living in
the one surface that draws it. Two windows of one app are two tiles. A shell app
— Settings, Wi-Fi, Bluetooth (K10) — is a window and gets a tile on exactly
those terms, with no branch of its own anywhere on the shelf (K1).
→ `omarchy-shell drawer openApps` has one line per open window, the first line
is the app just left, and a shell app's line names its plugin id

**M2** The row is drawn only when there is something in it. With nothing open
anywhere the drawer is a search field and a grid, unchanged.
→ with no windows open, `omarchy-shell drawer openTarget 0` is `no row`

**M3** Typing hides it. A query turns the sheet into a ranked answer — apps,
then settings (O) — and a shelf that ignores the query is not part of that
answer.
→ after `omarchy-shell drawer type fire`, `drawer openTarget 0` is `no row`

**M4** A tile says it is running, and says it with something no grid cell has:
an accent dot under the label. Everything else about it is a grid cell — same
icon size, same column pitch, same label — because it is the same app, and a
shelf drawn in a second visual language reads as a second kind of thing.
A shell app (K) has no desktop entry to take an icon from, so its tile wears
its own glyph, the way its card does (K5). That glyph is declared, not derived:
an empty one falls through to an `Image` with an empty source and the tile is a
blank box under a correct label, which no check that counted tiles would see.
→ `scripts/style-check.sh` reports every `AppWindow` declaring a non-empty
`glyph`, counted, and names the file and line of one that does not

**M5** Tapping a tile switches to that window and closes the drawer. It does
not launch a second copy. The same `swaymsg` dispatch a card's tap takes, for
the reason recorded there: `foreign-toplevel activate()` does nothing on this
compositor.
→ the focused workspace is the one holding that window; `drawer state` ==
`closed`

**M6** Flicking a tile **up** closes that app and the tile leaves the row. It is
`xdg_toplevel.close` — a close *request*, so an editor with unsaved work prompts
rather than dies, which is what makes firing it from a flick acceptable. On a
Settings tile it is that same request like any other, so the page stack resets
with the window (K6).

Nothing on the tile advertises the gesture, and that is the cost of not having a
control. The alternatives were a ✕ badge — which `style.md` E1/E3 rule out,
because a 44px target inside an 86px tile sits on top of the tile's own tap
target, and a mis-tap would close what you meant to open — and a hold menu,
which M8 rules out for its own reasons.
→ after a flick over `drawer openTarget 0`, `drawer openApps` is one line
shorter

**M7** A drag **down** from a tile still closes the drawer (H1). The two
directions are read separately and the sheet's own drag latches on downward
travel alone (H5), so neither gesture can be reached by overshooting the other.
→ a 1200ms drag down from a tile leaves `drawer state` == `closed` and every
window still open

**M7a** A finger that starts on a tile never scrolls the grid. Three things
want that drag once the shelf is inside the scroll — the row pages sideways,
the grid scrolls, the tile flicks away — so the tile claims the axis on the
first few pixels of movement rather than leaving it to whichever threshold
fires first, which would resolve one way on a slow finger and the other on a
fast one. Vertical is the tile's and horizontal is the row's.

The cost is one 86px row you cannot start a scroll from. The alternative is
worse: letting the grid win the vertical axis leaves a flick that closes an app
only while the grid happens to be at its top, which is a gesture that works
until it silently does not.
→ a slow 1200ms drag up from a tile closes that app; `drawer geometry` shows
the grid did not scroll

**M8** A hold on a tile does nothing. The detail card (L) is about a *desktop
entry* — its package, its size, what removing it would take — and a tile is a
window: a shell app has no entry at all (K9), and two windows of one app would
open one card twice. The grid below still holds every one of these apps, and
the hold there still answers.
→ a 900ms hold over a tile leaves `omarchy-shell drawer detail` empty

**M9** Closing the last one leaves the drawer open with no row. An empty shelf
is a launcher with nothing running, which is the ordinary state of a phone at
boot and not a dead end.
→ `drawer state` == `open`, `drawer openTarget 0` == `no row`

**M10** A close is a request, and this row does not pretend otherwise. The tile
goes as soon as it is flicked — an app that stops to ask about unsaved work
would otherwise leave a tile mid-animation — but it is gone from *this* opening
of the drawer only, not from the model: an app that refuses to quit is still
running and has its tile again the next time the drawer comes up.

**M11** The grid is unchanged. An open app keeps its cell there, and tapping
that cell still launches, because the shelf is a shortcut and not a filter — a
grid that removed what was running would move under you every time something
started.

**M12** There is deliberately no bulk "clear all". Apps are closed one at a
time — by flicking a tile away (M6), or with the back gesture (G4). A single
control that closes every open app is one mis-tap from losing all of them, and
like the hold-to-close C4 refuses, it has no undo.

---

## N. What opening the drawer costs

The sheet is dragged open by a finger at 60Hz on a Mali-400, and everything the
open path does lands on the frames the sheet is arriving on. The shade is the
comparison that makes this measurable rather than a feeling: it does none of
it, and it is the surface people say comes up instantly.

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

**N2** Opening the drawer rebuilds the open-apps shelf only when the shelf has
changed. `openApps` is a binding, so assigning its dependency notifies whether
or not the value moved, and the `ListView` then discards and rebuilds every
delegate — icon, glyph and name resolved again per tile, for a list that is
usually identical.
→ `open()`'s reset of `closingApps` is guarded by a test of its own length —
the other assignment is `closeOpen()` adding to it, which is the change M10 is
about; on the device, opening the drawer twice with nothing closed in between
leaves `omarchy-shell drawer openApps` byte-identical and the tiles' icons
already drawn on the first frame of the second open

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
  there would be nothing to capture anyway. Tiles are icon + name (M4).

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
- **The right edge stays unclaimed.**

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

**Written, but nothing runs it** (28). Each has a `→` check that no suite
executes, so it is as unverified as one with no check at all:

> A3 · A3a · A8 · A10 · C1 · C3 · C4 · C5 · G10b · G11 · G12 · G13 · H1 · H4 ·
> I5a · I5b · I6 · I7 · K8 · L8 · M2 · M3 · M7 · M7a · M8 · M9 · N1 · N2

All of §C is here: the hold cannot be fired by a suite without installing an
agent, which is C's own note. All of §I's assertable half is here too, and that
is not deliberate — I6 is covered in substance by A7 (`bin/moarchy-selftest`
notes this at the `--surfaces` end), but I5a, I5b, I7 and I1's companions are
simply unrun.

**Stated, with no check** (22). Behavioural claims with nothing to settle them
from a terminal; several are hand checks on glass by nature:

> B2 · D2 · D3 · D4 · F1 · G1 · G5 · G7 · G8 · G9 · G10a · H3 · H5 · H6 · H7a ·
> H7b · H8 · K10 · L4 · M10 · M11 · M12

M4 left this list by being split: the accent dot is still a hand check on glass,
and the glyph beside it is a declaration `scripts/style-check.sh` can read. The
command above regenerates the three lists from `bin/moarchy-selftest` alone, so
a criterion checked anywhere else has to be moved by hand.

**Run, with no `→` line here** (6). The suites check these; the doc understates
itself, and each should gain the check it is already being held to:

> G6 · K5 · L7 · L9 · L10 · L13

# Touch gestures — specification

What the phone's touch gestures must do. Present tense, normative. The
archaeology of *why* lives in `docs/build-log.md`; this file is the contract.

Every line here is agreed. Nothing is inferred — where a choice was open it was
put to a decision, and the ones that removed capability (C1, E7) record why.

Each AC is checkable from a terminal. `bin/moarchy-selftest --gestures`
cites these ids, so an AC with no test is visible.

## Vocabulary

| Term | What it means |
| --- | --- |
| **strip** | The reserved 20px band at the very bottom holding the home pill. Owned by `moarchy.gestures`. |
| **home screen** | A sway workspace with no windows on it: wallpaper, bar, pill. One app per workspace, so an empty workspace *is* the home screen. |
| **app** | A workspace with a window on it, or Settings, which is treated as one (K). |
| **shell app** | A screen this shell draws itself and maps as an ordinary window, so every criterion about apps applies to it. Three of them: Settings, Wi-Fi and Bluetooth (K). |
| **carousel** | The recent-apps switcher (`moarchy.recents`). |
| **drawer** | The searchable app grid (`moarchy.drawer`). |
| **shade** | The pull-down from the top edge (`moarchy.shade`). |
| **travel** | Drag distance as a fraction of 0.45 × screen height (~324 logical px). |

---

## A. Strip — swipe up

**A1** With an app open, dragging up from the strip raises the carousel, and it
follows the finger rather than appearing at a threshold.
→ `omarchy-shell recents dragTrace` leaves ≥ 8 samples

**A2** Released under 15% travel, nothing happens and the carousel springs back.
→ `omarchy-shell recents state` == `closed`

**A3** Released between 15% and 75% travel, the carousel stays open.
→ `omarchy-shell recents state` == `open`

**A4** Released past 75% travel, focus lands on a home screen and the carousel
is not shown.
→ focused workspace `representation` is empty; `recents state` == `closed`

**A5** No gesture on the strip ever *opens* the drawer, in any state.
→ `drawer state` never goes `closed` → `open` across a strip gesture

**A6** With the carousel already open, dragging up from the strip again goes
home.

**A7** With the drawer open, an up-swipe from the strip closes it. Together with
A5 this means the strip can put the drawer away but can never bring it up — the
gesture is "get me out of here", not a toggle.
→ `omarchy-shell drawer state` == `closed`

**A8** With the shade down, an up-swipe from the strip puts the shade away and
does nothing else. Whatever is covering the screen, this gesture clears it.
→ `omarchy-shell shade state` == `closed`; nothing else opened

"Whatever" is now every sheet this shell can put over an app, and no longer
just those two. Settings comes *out* of it — it is an app (K), so the strip
raises the carousel over it and leaves it running on its workspace when the
drag goes home (K4) — and the theme picker goes *in*, which it had never
actually been: the gate named the
shade and the drawer by hand, so a swipe from the theme picker fell through to
the carousel whenever a window happened to be open. It is a page reached from
Settings and returned to it (K10), not a screen of its own, so clearing it is
what this criterion always meant.

The list is derived from the one the back gesture already walks, minus the
carousel — which a second drag continues rather than clears (A6) — and minus
the shell apps — which are not overlays at all any more, and are excluded by
being windows rather than by being named (K1). Three hand-kept lists of overlay
ids is how Settings and Themes came to be missing from the back gesture, and
this is the third one not being written.

**A9** With nothing open anywhere, an up-swipe from the strip does nothing. An
empty switcher is a dead end you would only have to dismiss.

*Nothing* means no windows, and a shell app is a window (K1): a phone whose
only running thing is Settings has one card, so the strip has a carousel worth
raising. This used to be two questions and one of them was asked of the
carousel, because a shell app was not a toplevel and `ToplevelManager` could not
see it.

With E6, this means **the carousel has no empty state**: it can never be on
screen with zero cards, so that state is not built. `Recents.qml` had a
"No open apps" label; it became unreachable and was removed.

## B. Strip — swipe sideways

**B1** Swipe left goes to the next workspace; swipe right goes to the previous
one. With one app per workspace, that is next/previous app.
→ focused workspace name changes and changes back

**B2** A swipe that curves — as a thumb does — still resolves to whichever
direction dominates, and does not fall through to doing nothing.

**B3** The swipe lands on a workspace with nothing of the shell's drawn over
it. The shade, the drawer, the carousel and the theme picker are put away on
the way, the way an up-swipe puts them away (A7, A8).

Sheets only. A shell app is a window (K1), so the swipe passes it the way it
passes `foot` — it stays mapped on the workspace it is on, and the swipe back
returns to it (K2). Sweeping it here is what the previous design did, and doing
so is exactly what made a shell app impossible to swipe back to.

Until 2026-09-08 this gesture consulted nothing at all. It dispatched
`workspace next_on_output` and left every one of those surfaces exactly where
it was, so the switch happened invisibly underneath them: you swiped back
towards the terminal you came from and arrived with Settings still drawn over
the screen, on a workspace you had not asked for. Measured on hardware that
day, the shade, the drawer and the carousel all did the same.
→ with the shade down over an app, a sideways swipe leaves `shade state` ==
`closed` and a focused workspace that is not the one it started on

## C. Strip — press and hold

**C1** Pressing and holding on the strip does nothing. Resting a thumb on the
pill does nothing. There is no gesture on the strip that closes a window.
→ open-window count unchanged after a 2s press

Apps are closed from the carousel instead — one at a time, by flicking a card
away (E3). That is a screen where you can see what you are closing, which an
edge you rest a thumb on is not.

Unaffected: `$mod+w` still closes the focused window for anyone with a
keyboard, and the `omarchy-shell gestures close` IPC goes away with the hold it
existed to stand in for.

## D. Home screen — the workspace itself

**D1** On a home screen, dragging up **on the workspace** — the wallpaper, not
the strip — opens the drawer, following the finger.
→ `omarchy-shell drawer state` == `open`, `drawer dragTrace` ≥ 8 samples

**D2** Released short of the threshold, the drawer springs back and nothing
happens.

**D2a** The open drag is 1:1 with the finger: one pixel of travel is one pixel
of sheet, measured against the drawer's own height. Not a preference — the
close drag has always been 1:1, because its handle is the sheet it moves (H1),
and the open drag was measuring against 45% of the screen instead. The same
finger movement therefore opened the drawer 2.2x faster than it closed it, and
a drag from mid-screen arrived fully open with half the screen still to go.
Android's launcher tracks 1:1 in both directions.
→ a drag of *n* logical px leaves `drawer dragTrace` ending within a few
percent of `n / 720`; measured 300px→42%, 435px→63%, 635px→91%

The strip keeps its shorter travel. It is a fixed band that does not move under
the thumb, so a full-screen reach there would be a cost with nothing bought —
the pill is not the thing being dragged.

**D3** On a workspace with an app, dragging on the app does nothing to the
shell. The app receives the touch — everywhere except the left edge band, which
belongs to the back gesture (G).

**D4** Sideways and downward swipes on the home screen do nothing, for now. The
home screen handles the up-drag and nothing else; the strip still changes
workspace and the top edge still opens the shade.

## E. The carousel

**E1** One card per open app, most recent first, with the app you just left
leading and marked. The row is drawn from the **right**: the leading card sits
at the right-hand end, under the thumb that raised the carousel, and older apps
run away to the left — the direction Android's overview uses. Only the painting
is mirrored; the order itself is unchanged, so the leading card is still the
first line of `recents list`. A shell app — Settings, Wi-Fi, Bluetooth (K10) —
is a window and has a card on exactly those terms, with no branch of its own
anywhere in the carousel (K1).
→ `omarchy-shell recents list` has one line per open window, the first line is
the app just left, and a shell app's line names its plugin id; `recents cardX`
puts card 1 to the *left* of card 0. That second check is the one that bites:
`list` is model order and reads the same whichever end the row is drawn from,
so it would pass a mirroring that silently did not happen.

**E2** Tapping a card focuses that app and closes the carousel.
→ focused workspace holds that window; `recents state` == `closed`

**E3** Swiping a card up closes that app, and its card leaves the row. On the
Settings card that is `xdg_toplevel.close` like any other, so the page stack
resets with the window (K6).
→ `recents list` is one line shorter

**E4** Swiping sideways pages the row. The next card is partly visible, so it is
obvious the row can be paged.

**E5** Dismissing the carousel without picking anything returns you to whatever
was on screen before it opened — the app you came from, or the home screen if
that is where you were. Dismissing never changes what is focused.
→ focused workspace is the one focused before the carousel opened

**E6** Closing the last card leaves you on a home screen, rather than on an
empty carousel you then have to dismiss.
→ `recents list` empty; focused workspace `representation` empty

**E7** There is deliberately no bulk "clear all". Apps are closed one at a time
— by flicking a card away (E3), or with the back gesture (G4). A single control
that closes every open app is one mis-tap from losing all of them, and like the
hold-to-close it removed in C, it has no undo.

## F. Going home

**F1** Home is the lowest-numbered workspace with nothing on it, so the sideways
swipe order stays contiguous.

**Fixed defect, kept because of how it read.** `firstFreeWorkspace()` used to
scan 1..10 and then fall through to `return 10` — a number `taken` had just
recorded as occupied — so once ten workspaces existed, going home landed on an
app instead of a home screen.

It is worth writing down because it did not look like one bug. A4 and the home
criterion in K both end in that call, so the two traded an intermittent failure
between them depending on how many workspaces happened to be occupied, and on a
phone shared between sessions that is luck. Measured, same build, minutes apart:
one failed with `workspace 10 holding 'V[moa-selftest]'` while the other passed,
then the other failed with the identical message. Both sessions working on this
suite read it as churn for a day. The ceiling is gone: sway's *bindings* stop at
ten and this is not a binding, and `bin/moarchy-one-app-per-workspace` — the
same rule in Python, the pair this must not drift from — never had one.

**F2** Going home never closes anything. Every app is still in the carousel
afterwards.
→ `recents list` count unchanged across a home gesture

**F3** Going home puts the on-screen keyboard away. A home screen has nothing
to type into, so the keyboard leaves with the app it belonged to.

Reported as "the keyboard pops up when I navigate out of an app to the home
screen", which is the opposite of what happens: it fails to go *down*. Sway
sends the text-input leave when focus moves off the app, but home is an *empty*
workspace and there is no window there to take the input state over, so nothing
lowers it -- and standing alone on the wallpaper it reads as having just
appeared. Measured: up after 3 of 5 homes, down in exactly the two that landed
on a workspace which still had a window; and with the keyboard already down, 6
of 6 homes left it down, so nothing on this path raises it.

Confirmed at the mechanism after the fix: forced up, then home, then `Visible`
false at 8 of 8 samples over 4s. Hiding before the workspace switch and after
it both stick, and `SetVisible false` sticks even with the text field still
focused, so the call needs no ordering against the switch.
→ with the keyboard up, `omarchy-shell gestures swipe home`, then
`sm.puri.OSK0` `Visible` is false and *stays* false across ~3s of sampling. One
late reading cannot tell "never went down" from "went down and something raised
it again", which on a shared phone is a real second case.

**F4** The carousel does not flash on its way out. Everything that signals the
home band -- the scrim thinning, the cards fading, the row travelling up -- is
at its *weakest* there, because that is the cue that letting go returns to the
wallpaper. So the carousel has to leave from that weakened state and not from
its fully-open one.

Reported as "the carousel goes to full alpha before it disappears", and that is
exactly what it did: `homeHint` was zeroed instantly on release while `progress`
still had 200ms of animation left, so the scrim went 0.4 -> 1.0, the cards
0.45 -> 1.0 and the sheet jumped down a `space(80)`, all held for the length of
the fade. Three separate snaps, one cause -- `progress` had a Behavior and
`homeHint` did not.
→ `omarchy-shell recents retireTrace` reports `progress:homeHint` per frame
across the release; `homeHint` must not be 0 in the first frame. Measured
without the fix `100:0 63:0 46:0 33:0 ...`, and with it
`100:73 73:54 54:40 40:27 ...` -- so peak scrim alpha goes from 1.0 to 0.56,
falling monotonically from there instead of jumping

## G. Left edge — back

**G1** The back swipe undoes the **topmost thing on screen**, in this order:

1. the on-screen keyboard, if it is up
2. any open overlay — drawer, carousel or shade
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
→ `omarchy-shell recents list` is one line shorter

**G5** A bare home screen with nothing over it → the swipe does nothing.

**G6** The swipe has to travel far enough to be deliberate. A short drag in from
the edge does nothing, so brushing the edge never closes an app.

**G7** Closing is a *request* — the app is asked to close and may prompt, so an
editor with unsaved work is never lost. Closing the only window on a workspace
leaves you on that workspace, which is now a home screen.

**G8** The edge band is **16 logical px** wide — about 3mm on this panel, which
is roughly what Android's back edge feels like at its default sensitivity.

It is a settable property, not a constant baked into a binding. Android makes
this device-configurable, exposes a per-edge sensitivity slider to the user,
and lets apps *query* it through `getMandatorySystemGestureInsets()` rather
than publishing a fixed number — three separate admissions that no single value
is right. Ours should at least be changeable in one place after the first week
of using it.

**G9** Only the left edge is claimed. Android takes both; the right edge stays
with apps here, which halves what this costs them.

**G10** The band does not run the full height of the screen. It stops **one
strip plus one keyboard panel** short of the bottom — 220 logical px — and
everything below that belongs to whoever is drawing there.
→ `omarchy-shell gestures geometry` reports `h` == `screen - inset - topInset`,
`inset` == 220

The bottom-left corner was the one place this surface took a touch that was
never a gesture. The on-screen keyboard is on Top and this band is on Overlay,
so the band won the overlap and swallowed the leftmost key column: `a`, shift,
and the `123` key answered nothing at all. A tap there travelled zero px, so it
committed no back swipe either (G6) — the touch simply went nowhere.

Geometry has to fix it, because arrangement cannot. Sway resolves exclusive
zones **layer by layer from Overlay down**, so the keyboard's zone is
subtracted after this surface has already been placed; `ExclusionMode.Normal`
here would move nothing. Nor can a short tap be handed back to the surface
underneath — Wayland picks the recipient from the input region before the touch
is delivered, and there is no returning it on release. The input region is the
only knob, and cutting it is the only way to turn it.

The cost is that a back swipe cannot *start* in the bottom 220px of the edge.
That is the reach a thumb has least need of: it is where the strip and the keys
already live, and G2 is unaffected — with the keyboard up, the edge above it is
still 470px tall and still dismisses the keyboard.

The keyboard's 200 is measured and not ours to choose (it is the same
`panelHeight` I5b pins the drawer's reflow to), so unlike G8 it does **not** go
through the theme's spacing scale. The keyboard is a separate client that never
sees this theme; scaling our inset with it would cut the edge shorter than the
keys it exists to avoid.

**G10b** It stops short of the **top** as well, by the status bar plus one
header bar — **73 logical px** — so an app's own top-left control is tappable.
→ `omarchy-shell gestures geometry` reports `h` == `screen - inset - topInset`
and `topInset` == 73

This is G10's problem at the other end, and it is the one that bites daily. The
top-left of a GTK window is where the toolkit puts the control the user reaches
for most: libadwaita's back chevron, a hamburger, Geary's folder button. The
band is on Overlay, so it takes that touch first and the button answers
nothing — measured on the device with Spot, whose `<` sits at x=22, y=49
logical, inside a band that runs the full height.

The number is measured, not chosen. On this panel the status bar is 26 logical
px and libadwaita's `AdwHeaderBar` is 47 — Spot's white header runs from y=52
to y=144 physical, which is 46.5 plus its divider — so an app's header ends at
73. Like the keyboard's 200 in G10 and unlike G8's band width, the header half
does **not** go through the theme's spacing scale: it is another toolkit's
chrome and it does not know this theme exists. The bar half does, because that
one is ours.

What it costs is that a back swipe cannot *start* in the top 73px, which is
the reach a thumb has least need of at the top of a 720px screen — and the
gesture is unchanged everywhere else: the band is still 427px tall between the
two insets, and a swipe that starts below the header still closes the app it
belongs to (G4).

It also hands back the top-left corner, which was contested rather than
allocated: the shade's grab strip is Overlay too and covers the same 16x26,
and which of two Overlay surfaces got a touch there was decided by map order
rather than by anything this spec says. Above 73 the shade now has it outright
(A8), which is what a pull-down from any point along the status bar already
implied.

**G10a** The dead column is otherwise unchanged: between those two insets the
leftmost 16px of every app still belongs to the back gesture (D3), and G8's
property is still the only knob for its width. This is an edge gesture, and
Android pays the same price — `getMandatorySystemGestureInsets()` exists
precisely so apps can move their own controls out of the way.

## H. Closing an overlay by dragging it

The drawer and the shade each came up before this spec existed, and each could
only be dragged shut by a 26px band at the top of its own sheet. Dragging on
the sheet *body* did nothing. That was never a decision -- it was where an
implementation stopped.

**H1** Dragging **down** anywhere on the drawer closes it, following the finger.
→ `omarchy-shell drawer dragTrace` leaves ≥ 8 samples; `drawer state` == `closed`

**H2** Dragging **up** anywhere on the shade closes it, following the finger.
"Anywhere" includes the band of scrim below the sheet, which is where a thumb
starts an up-swipe. That band is not a fixed height: the sheet is as tall as
its content and stops at 90% of the usable height (`shade.md` S21, S22), so
the band is ~70px with the shade full and several hundred with it near empty
-- never less, which is what the cap is protecting. That band used to answer
`clicked` and nothing else, so a drag begun there moved nothing and then
dismissed the shade outright on release: it looked like a shade with no close
animation, and it was one being shut by a tap that happened to have travelled
250px.
→ `omarchy-shell shade dragTrace` leaves ≥ 8 samples; `shade state` == `closed`

`state` alone cannot check this and never could. A shade that jumps shut
reaches `closed` exactly as fast as one that followed the finger the whole way,
which is why the criterion is the trace. The trace records only what the finger
drove -- not the 220ms fall after release, which happens either way.

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
windows, and until this section they were treated as if they were: the drawer
and the theme picker are Top with a zero exclusive zone, so sway arranges them
into the usable area and each stopped short of the bottom edge, leaving a band
of wallpaper with the pill drawn on it. The keyboard stopped there too. They now
extend under the strip. Nothing about what the strip *reserves* changes -- that
half is what keeps the keyboard from burying the pill, and it stays exactly as
it was.

Settings used to be in that list and is not any more. It is a window now (K1),
so it cannot extend under anything: sway arranges a window into what the
exclusive surfaces left, which is the whole point of the strip reserving. I1a is
what replaces it, and it is a better answer than the one it replaces — the band
under `foot` was wallpaper too, and always had been.

Sizes are never written as numbers here. `Style.space(20)` rounds a *scaled*
value, and the scale comes from the theme's `shell.toml`: measured 20 on the
default theme and 23 on a larger one, and it has read higher again. Every check
below takes the height from `geometry`'s `strip` field rather than assuming one
— including the ones in `bin/moarchy-selftest`, whose comments quote a number
they measured on the theme of the day and not a constant.

**I1** With the drawer, Settings, the theme picker or the keyboard up, the
surface reaches the bottom row of the screen. No band of wallpaper, and no band
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
window is drawn in; and it is below every sheet, so the drawer, the shade, the
carousel and the theme picker draw over it exactly as they did. Filling the band
from the *strip* instead — the obvious place, since the strip is what reserves
it — would have painted over all four.

Only the band, and not the whole surface underneath. A workspace with gaps
turned on, or two windows tiled side by side, leaves gutters where the wallpaper
is meant to show.

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
list layer surfaces, so this cannot be read from the compositor.

Two of them since Settings became a window: the drawer and the theme picker. The
`moarchy-home` surface takes the same margin for I1a, and is not asserted here —
it has no content to keep clear of the pill and nothing to compare against.
→ `omarchy-shell {drawer,themes} geometry` each report `h` equal to
`omarchy-shell device geometry`'s `h` plus `strip`

`moarchy.device` is the control, and is deliberately left unchanged for
that purpose: same layer, same zero zone, no margin. An absolute assertion
against the workspace rect would not do -- the rect has the bar's and the
strip's exclusive zones taken out of it and an `ExclusionMode.Ignore` surface
does not, so it would fail on arithmetic rather than on behaviour. (It carried a
`gaps inner 3` inset too, until docs/windows.md W1 took the gaps to zero; the
exclusive zones are still there and the argument is unchanged.)

**I3** Extending a surface reserves nothing. The strip still takes its band off
every window and the bar still takes its own off the top, with any sheet open.
→ the focused workspace's rect is byte-identical open and closed

**I4** Nothing tappable comes to rest under the pill. On every sheet the last
content pixel settles at least one strip above the bottom of the surface,
however its list is scrolled. Content may *pass* under the pill mid-scroll; it
may not stop there.

Settings is out of this one too, and by construction rather than by padding: a
window stops at the top of the strip, so nothing it draws can reach under the
pill at all. It used to carry a strip of scroll padding for exactly this, and
that padding is gone with the inset that made it necessary.
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
paints over it. Measured before the gate existed: the whole `qwertyuiop` row
reduced to a sliver under the drawer's app labels.
→ `drawer geometry` reports `margin=0` while the search field has focus and
`margin=-<strip>` otherwise

**I5b** The keyboard reserves the same space whether or not it draws under the
strip. sway reduces the usable area by `exclusive_zone + margin.bottom`, so a
surface with a negative bottom margin has to add it back to its zone or it
quietly under-reserves by exactly that much.
→ with the keyboard up, `drawer geometry` `h` is `screen - bar - panelHeight`;
at 176 rather than 200 the drawer settles over the top key row

**I5c** The gate cannot get stuck. `activeFocus` only stands in for "the
keyboard is up" (I5a) while the two actually move together, so anything that
leaves the search field focused with the keyboard down drops the inset for the
rest of the session: the surface maps with the field not yet focused and draws
its one correct frame under the strip, then sway activates it, Qt hands the
focus back, and the band under the pill goes to wallpaper for as long as the
drawer is up.

Closing the drawer therefore has to *release* the field's focus rather than
merely deactivate the window, which means handing active focus to an item
inside the same surface -- an item that belongs to no window holds nothing, so
the field keeps its `focus` flag across the unmap and takes activeFocus back on
the next map. The second symptom is the tell, and it is the one that was seen
first: a tap on a field that is already focused changes no focus and re-enables
no text input, so a session that has had the drawer open for a while stops
raising the keyboard at all.
→ tap the search field, close the drawer, open it again: `drawer searchTarget`
reports `focused=false` and `drawer geometry` reports `margin` equal to
`-<strip>`

**I5d** Closing an overlay never *raises* the on-screen keyboard. It may leave
it down and it may put it down; it may not put it up.

Reported as "sometimes when I close the app drawer the keyboard shows up", and
it is F3 one rung down: the keyboard does not pop up, it fails to go down. An
overlay that declares `WlrKeyboardFocus.Exclusive` takes the seat's keyboard
while it is up, which deactivates the window underneath and lowers the keyboard
with it. On unmap sway re-activates that window, its `zwp_text_input_v3`
re-enters, and the keyboard rises -- so the drawer hands back a keyboard the
user had not asked for, standing on whatever is now on screen.

The cause is the exclusive grab and not the drawer, and the four sheets separate
on exactly that line. Measured 2026-09-07 on 0.1.1-1, three closes each with a
focused `foot` underneath:

| | `keyboardFocus` | raised |
| --- | --- | --- |
| drawer | `Exclusive` while up | 3/3 |
| Settings | `Exclusive` while up | 3/3 |
| theme picker | `Exclusive` while up | 3/3 |
| shade | `None` | 0/3 |

With nothing focused underneath it never fires -- 0 of 4 on a bare home screen,
4 of 4 with an app -- which is the whole of the "sometimes" and the reason a
home-screen test reads as "not reproducible". The drawer is the one that gets
reported because it is the one you dismiss most, and because a blank workspace
is where you open it: the app that takes the keyboard back is the one left
running on another workspace.

The fix is F3's, for F3's reason -- an unconditional `SetVisible false` on the
dismissal path, which F3 measured as sticking even with a text field still
focused. It is deliberately *not* conditional on the keyboard having been down
beforehand: that question needs the DBus probe's round trip, and G2's comment
already records what acting on a stale answer costs. The cost of the
unconditional call is that dismissing an overlay over an app you were typing in
puts the keyboard away, and you tap the field again. That is the same trade F3
made and the same one G1 makes -- on this phone a dismissal puts things away.

Hand-offs are the exception, and they are why the call cannot simply live in
every `close()`. `activateSetting` and `launch` on the drawer, and `dismiss`
on Settings and the theme picker, close one surface in order to open another;
firing the hide there robs the successor of a keyboard it may be about to want.
→ with an app focused, open and close each of the drawer, Settings and the theme
picker: the focused workspace's `rect.height` is unchanged across the close, at
6 samples over 3s. One late reading cannot tell "never went up" from "went up
and something put it down"

**I5e** The bottom inset follows the keyboard rather than the field. I5a gates
it on `activeFocus` as a stand-in for "the keyboard is up", and I5d is the proof
that the stand-in can be wrong in the direction I5a cannot see: keyboard up,
field not focused. The inset then stays at `-<strip>` with the keyboard under
it, and the sheet's last row paints over the top key row -- the same
`qwertyuiop`-reduced-to-a-sliver picture I5a records from before the gate
existed, reached by a different road.

The signal is the compositor's own configure, which is already what `geometry`
reports and already what makes that field evidence. On this panel the granted
height is 694 or 674 with the keyboard down and 494 or 474 with it up -- the two
clusters are 180px apart, so no threshold between them can be walked into by the
20px the inset itself moves. `activeFocus` is not merely a worse signal here, it
is a *lagging* one: it answers about the field, and the field is only one of the
things that raises a keyboard.

It matters even with I5d fixed. The hide is `execDetached` and the keyboard
takes time to retract, so every close with the keyboard up spends the slide
animation in exactly this state.
→ with the drawer open and the keyboard forced up on `sm.puri.OSK0` rather than
by a tap, `drawer geometry` reports `margin=0` while `searchTarget` reports
`focused=false`. Forced, because a tap would focus the field and hand the answer
to the term this AC exists to check the *other* one against

**I6** The pill still works over all four, and none of them needs a mask to
manage it. All four are on Top -- the keyboard included, deliberately, because
on Overlay it would map before the strip and take the bottom exclusive zone the
pill needs (`windows.md` W5, `moarchy-keyboard/src/panel.cpp`) -- the strip is
on Overlay, and every Overlay surface sits above every Top one. So the strip
takes those touches before any of the four sees them.

The mask the keyboard does carry is for the **left** edge, not this one: the
back-gesture band is on Overlay with `ExclusionMode.Ignore`, and the keyboard
excludes that column from its input region so the gesture that dismisses it is
never swallowed. The shade is the surface that needs a mask for the pill, and
only because it is on Overlay itself.
→ A7 with the drawer; `omarchy-shell {settings,themes} state` == `closed` after
an up-flick from the strip; and, with the keyboard up, an up-flick still goes
home

**I7** Drawing a sheet under the pill does not make the pill harder to see than
it already was.

Measured on tokyo-night, at rest: over the wallpaper the pill composites to
`4A3E53` on `150D20`, and over the drawer's sheet to `45485B` on `1A1B26`. Both
are **1.90:1**. That equality is not a coincidence and is the point of this AC:
the pill is `Util.alpha(Color.foreground, 0.3)`, and a constant-alpha overlay's
contrast against its *own* backdrop is set by the alpha and the
foreground-to-background gap, very nearly independent of what is behind. So this
change moves the pill from an unbounded backdrop to a known one without moving
the number.

It also means **3:1 (WCAG 1.4.11) is unreachable at 0.3 and never was reached**
-- asserting it here would be asserting something no version of this UI has ever
satisfied. Whether 0.3 is the right resting alpha is a live question, and a real
one at 1.90:1, but it is a decision about the pill and not about what is drawn
behind it. It is deliberately not smuggled in here.
→ the pill's composited colour over a sheet is within 0.1 of its composited
colour over the wallpaper, for the same theme

## J. The app you are leaving

A4 hides an app and E3 closes one, and until this section nothing on screen
said which was about to happen: the app vanished behind a rising sheet either
way. Android answers that by shrinking the app into the card it becomes, so
the gesture shows you where the app went instead of just removing it. This
section is that shrink.

It is the one place the shell draws a picture of a window, and it is only
possible for *one* window -- see the amended thumbnails constraint below.

Measured on the device at 720x1440, 2026-09-05:

| | |
| --- | --- |
| fresh capture, window already mapped | 107ms median (77-112) |
| fresh capture from an unmapped window | 145ms median (137-173) |
| full-screen capture blit | 60fps -> 43-47fps |
| animating its scale as well | 44-46fps, i.e. free |

**J1** During a strip up-drag with an app focused, a still image of that app
follows the finger, shrinking as the drag travels, and comes to rest on the
leading card's slot at the carousel's stop.
→ `omarchy-shell recents preview` reports `scale` falling as `progress` rises

**J2** The image is a still, captured once per gesture, never a live feed. A
continuous full-screen capture costs a quarter of the frame budget for the
whole drag on this GPU, and buys nothing: the app is not being interacted with
while it is being put away.

**J3** At the carousel's stop the image is over card 0's slot, and hands off to
that card. Cards stay icon + title (E1) -- the preview is the thing that
travels, not a new kind of card.
→ `recents preview` reports `scale` and the card slot's height agreeing within
2px at `progress` == 1

**J4** The capture takes ~145ms and the preview does not pretend otherwise. It
enters at scale 1.0, geometrically identical to the app already on screen, and
shrinks from there. Its arrival part-way into the drag is a fade between two
images of the same thing at the same size, not a jump to a smaller one.
→ `recents preview` never reports `scale` > 0 before `hasContent`

**J5** Released short of the carousel (A2), the image returns to full size and
fades out. Nothing was hidden, so nothing may look like it was.

**J6** A drag that carries on into the home band (A4) finds the preview
already landed and faded out. The shrink finishes at the carousel's stop --
that is where the card it hands to lives -- so the home band is the row's
business, not the preview's. Going home still closes nothing (F2): this section
is about what the gesture looks like and F2 is what it does.

**J7** With the screen blanked, nothing is armed. `wlr-screencopy` on a
DPMS-off output never delivers a frame and never reports one is not coming:
no `stopped()`, no warning, `hasContent` simply stays false forever. (`grim`
hangs on the same output -- measured, killed at a 15s cap.) Arming there would
leave a gesture waiting on a frame that cannot arrive.

**J8** If the capture has not arrived by the time the gesture ends, the gesture
does exactly what it does today. The shrink is decoration on A1-A4 and never a
precondition for them: no frame, no animation, same outcome.
→ A2-A4 still pass with the capture forced off

**J9** The scrim dims the app, not the preview. The preview is the thing being
moved and stays at full brightness; what dims behind it is the workspace it is
leaving. Ordering the two the other way round makes the preview appear to
brighten the screen when it arrives mid-drag.

**J10** Only the app you are leaving gets a picture. Every other card is icon
and title, because sway does not render an unfocused workspace and there is
nothing to capture -- see the constraint.

## K. Settings is an app

Settings is a screen you spend time in — ten pages deep in places, with a stack
you navigate — so it has to behave like the apps beside it. For two releases the
shell *emulated* that: a carousel card built by hand out of a QtObject, a
workspace claimed on its behalf, a hide fired from a focus watcher, and a list
of three plugin ids kept in four files. Each piece answered a question sway
already answers for every window on the phone, and the emulation always stopped
one gesture short of the real thing.

The last of those was the one that ended it. K13 gave Settings a workspace and
K14 took the screen away when focus left it, which meant you could swipe *out*
of Settings and never swipe back *in* — the workspace it had claimed was empty
by the time the swipe returned to it, because the surface it was standing for
had been unmapped on the way out. A layer surface has no workspace, and every
attempt to give it one is a re-implementation of window management inside a
shell plugin.

So it is not a layer surface any more. **Settings, Wi-Fi and Bluetooth are
ordinary Wayland toplevels**, drawn by the shell process and mapped as windows.
This section is short because that is the whole of it: A, B, E, F, G and J apply
to them unchanged, with no clause of their own, and the criteria that used to be
written here are deleted rather than restated.

**K1** The three shell screens are xdg toplevels. Sway tiles them,
`bin/moarchy-one-app-per-workspace` moves each one to a workspace of its own and
focuses it, and `ToplevelManager` reports them — which is what makes the
carousel card a real card rather than a stand-in, and what makes B, E, F, G and
J apply with nothing added.

Quickshell's `FloatingWindow` is what this rests on: a window the shell's own
process owns, which the compositor treats as any other client's. Nothing about
it is privileged. It carries no server-side decoration (`deco_rect` is zero
under `default_border pixel 2` with `hide_edge_borders smart`), so a shell app
alone on its workspace fills it edge to edge, under the bar and above the strip,
exactly as `foot` does.
→ with Settings open, `swaymsg -t get_tree` has an `app_id == "org.quickshell"`
node that is the only window on its workspace, and `recents list` names
`moarchy.settings`

**K2** Swiping sideways off a shell app and back again arrives back *on* it, on
the page it was left on.

This is the criterion the emulation could not meet, and it is the reason for the
change. A window does not have to be put back: it was never taken away.
→ from `settings page` == `appearance.bar`, `gestures swipe left` then
`gestures swipe right` leaves `settings state` == `open` and `settings page`
== `appearance.bar`

**K3** Everything else that moves the workspace does the same, and none of it is
this shell's code: `swaymsg workspace`, a keybinding on a paired keyboard, a
launcher that lands an app somewhere else. The screen stays where it was put.
→ with Settings up, `swaymsg workspace next_on_output` then
`swaymsg workspace prev_on_output` leaves `settings state` == `open`

**K4** Going home (A4, F1) leaves a shell app running on its workspace, the way
it leaves any app running. Its card is in the carousel and tapping the card
comes back to the page it was on.
→ after the home band, the focused workspace's `representation` is empty,
`recents list` still names `moarchy.settings`, and `settings state` == `open`

Note what `settings state` says here and did not before. It answers whether the
window is mapped, and going home does not unmap it — so the old reading, where
`closed` meant "hidden but running", has no state left to describe. There is no
hidden. A shell app is on screen, on another workspace, or gone.

**K5** The card is icon, name and title, the same three lines a window's card
has (E1): the glyph the shade opens it by, the app's name, and the page it is
on. At the root the title line is absent, the way it is for a window whose title
is its own name.

The icon and name do not come from a desktop entry, because there is none to
find — see K9. They come from the plugin, which is the one place that knows.

**K6** Two things close a shell app, and both drop the card and reset the page
stack: flicking the card away (E3), and the back gesture with nothing left to go
back to (K7). That pairing is exactly what those two gestures already do to a
window — E3 closes a card, G4 closes the focused app — and here they *are* those
two gestures rather than a copy of them.
→ after either, `recents list` has no `moarchy.settings` line and
`settings stack` is one line

**K7** The back gesture over a shell app walks its page stack first, and closes
the window only from the root page. G3's "an overlay that owns a page stack gets
first refusal" now reads off the *focused window* rather than off a list of open
overlays, because a shell app is no longer an overlay.

Ordering matters and is the whole of the criterion: back inside Settings must
never reach G4 and close the app underneath, and back on the root page must not
be swallowed into doing nothing.
→ from depth 2, one back leaves `settings page` one page up and the window
count unchanged; from the root, one back leaves `settings state` == `closed`

**K8** A row that ends in a terminal needs nothing to get out of its way. A
tiled terminal is moved to a free workspace and focused
(`bin/moarchy-one-app-per-workspace`); a floating one maps above the window it
was launched from. Either way it is on screen and typeable.

This deletes the `hides` mechanism and the two criteria that carried it
(`settings.md` C9, D8). Both existed because a full-screen *layer surface* is
above every window on the output, so a terminal launched from Settings mapped
underneath it and was indistinguishable from a tap that did nothing — which is
how a phone ended up with sshd enabled and an empty `authorized_keys`
(2026-09-08). A window is not above other windows, so the failure has no
mechanism left.
→ `settings activate ssh` leaves `settings state` == `open` and a new window
focused

**K9** All three carry `app_id == "org.quickshell"`, which is the shell process's
app id and not something this port chooses: Qt sets the xdg-toplevel app id once
per process from `QGuiApplication::desktopFileName`, and there is no per-window
override in Qt 6.11. Identity is therefore the window *title*, which each screen
sets to its own name and page.

Recorded as a criterion because it is the one place a reader will expect a
different answer, and because everything that resolves a shell app — the card's
icon, the back gesture's page stack — depends on it. A window whose title this
shell did not set is somebody else's window and gets an ordinary card.
→ `swaymsg -t get_tree` reports `app_id == "org.quickshell"` and a `name` of
`Settings` for the root page

**K10** Three shell screens: **Settings**, **Wi-Fi** and **Bluetooth**, and
nothing else. The shade and the drawer stay transient sheets with no card: they
are summoned and dismissed in one motion, Android gives neither a recents entry,
and A7/A8 already say the strip clears them. The theme picker stays out too — it
is a page reached from Settings that returns to the page it was opened from
(`settings.md` B7), not a screen of its own.

Stated as a criterion because "a shell screen that is a window" is a mechanism,
and a mechanism with one user looks like an oversight rather than a decision.
The test is whether it is a screen you *sit in* — Wi-Fi (2026-09-06) because
joining a network means retyping a passphrase and coming back; Bluetooth
(`shade.md` S6d) because pairing means waiting for a device to appear, putting
it in pairing mode, and trying again.

**K11** A shell app gets the shrink (J) like any app, with nothing said here:
it is on screen, it is a toplevel, and J10's "only the app you are leaving gets
a picture" is satisfied by the same reasoning it is for `foot`.

**K12** Summoning a shell app that is already running focuses its window rather
than opening a second one, and leaves it on the page it was on. There is one
window per screen, and the ways in are many — the shade's gear, a Settings row,
the drawer, an IPC verb. Naming a page still navigates (`settings.md` A7); it is
the summon that names none that means "the screen I was on".
→ with Settings running on another workspace at `appearance.bar`, `settings
open` leaves the focused workspace holding it, `settings page` unchanged, and
`recents list` with one `moarchy.settings` line

---

## L. Long-press on an app

A tap on an app icon launches it (H4) and that is the whole vocabulary the grid
has. There is no way to reach anything *about* an app -- what it is, what it
came from, or how to be rid of it -- and the phone ships 64 desktop entries
nobody chose one at a time.

Upstream has an answer and it is keyboard-shaped: in the Omarchy menu, Ctrl+D on
a highlighted row arms a confirm and calls `appLibrary.remove()`. A modifier on
a highlighted row is not a thing a thumb can do. The gesture that means "tell me
about this one" on every phone is a long press, and this section is that gesture
plus the screen it opens.

**Removal is the drawer's, not a terminal's.** Upstream's
`omarchy-remove-launcher-entry` ends its package branch by handing
`sudo pacman -Rns` to a floating terminal, so the answer to "what will this
take with it" is pacman's `[Y/n]` prompt in a 60-column foot window, typed on
the on-screen keyboard. That prompt is the right control on a desktop and the
wrong one here: it is the only place the consequence is stated, and it is
stated in the one surface that costs a keyboard to answer. So the drawer asks
the same question itself, from the same `pacman` output, before anything runs
(L7), and the run itself is silent (L9).

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
click is cleared on the *next* press, exactly as `sheetWasDrag` is and for the
same reason -- cleared on release it is already false when the click arrives,
and the app you asked about is the app that starts.
→ after the hold, `omarchy-shell recents list` gained no card

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

`-Rs` and not `-Rns`: pacman rejects `--nosave` together with `--print` outright
("invalid option: '--nosave' and '--print' may not be used together"), so the
plan is computed without it and the removal that follows carries it, the way
upstream's does. The two differ by which config files survive, which is not
something the plan needs to state.

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

Measured on the device against all 34 entries the drawer lists, which is what
turned this from a rule into a section. L12 alone let three things through, and
none of them because the rule is wrong:

| Entry | What the plan said | Why |
| --- | --- | --- |
| Foot | Removes 2 packages | `bin/moarchy-launch-tui` execs `foot`, undeclared |
| KWeather | Removes 40 packages, `upower` among them | `moarchy.bar`'s battery is `Quickshell.Services.UPower`, undeclared — and `upower` is on the phone only as KWeather's own transitive dependency, so `-Rs` takes it |
| (not listed) | — | `default/sway/autostart.conf` execs `polkit-gnome-authentication-agent-1`, undeclared |

So the drawer would have offered to remove the terminal every TUI opens in, and
would have taken the battery indicator away with the weather app. In all three
cases `moarchy`'s own `depends` was wrong and this feature is what asked the
question; `pkgbuilds/moarchy` declares all three now, so L12 protects them by
knowing something true rather than by holding a list. The `upower` one is worth
keeping in mind: it is not exec'd anywhere, so no grep for a binary name finds
it, and it was reached by a *cascade* rather than named as a target.

A browser is deliberately not in that list. `bin/moarchy-launch-browser` is a
fallback chain over four of them and says so in its own comment, so Epiphany
stays removable — which is the right answer for a browser and the test that
this rule is about dependencies rather than about a list of favourites.

**L13** The plan says when the exception was used. A package the set declares is
one a later `moarchy-meta` upgrade will pull back in — pacman resolves an
upgraded package's dependencies — so the card says so rather than letting the
app reappear on a `pacman -Syu` as if the removal had not worked.

---

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
- **No window thumbnails, except the app you are leaving.** Quickshell 0.3.1
  wires per-*toplevel* capture only to `hyprland-toplevel-export-v1`, so a card
  for a window that is not on screen cannot have a picture -- and sway does not
  render an invisible workspace, so there would be nothing to capture anyway.
  Cards are icon + title (E1).
  What that argument never covered is the *focused* window, which is on screen
  and is being rendered. `ScreencopyView` takes a **monitor** through
  `wlr-screencopy-unstable`, which sway has and `grim` already uses here, and
  Arch's `quickshell` enables it. Measured on the device: a 720x1440 capture
  arrives as a zero-copy dmabuf (`AR24`/`LINEAR`) imported straight into the
  scene graph. That is one still of one window, held for the length of one
  gesture (J), and it is the only picture of a window the shell ever draws.
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
  carve regions back out of the system gesture, capped at 200dp per edge
  (sized, explicitly, as four 48dp touch targets plus padding). **Wayland has
  no equivalent** — there is no protocol for a client to tell a layer-shell
  surface not to take touches in a region. So our edge is strictly more
  expensive than Android's, with no mitigation available to apps.

  It did bite in daily use, and the control it took was the one this paragraph
  named first: the hamburger or back chevron at an app's top-left. The answer
  was to carve the region out from *our* side, since the app cannot — G10b,
  which stops the band below the header bar, the same lever G10 already used
  for the keyboard. What is left is a narrower claim rather than a softer one:
  a control that sits in the leftmost 16px *between* the two insets is still
  dead, and there is still no API that would let an app say so.
- **The right edge stays unclaimed.**
- **One app per workspace** is assumed throughout: workspace ≈ app.

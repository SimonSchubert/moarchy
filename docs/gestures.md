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
| **shell app** | A screen this shell draws itself that behaves like an app: it has a carousel card and the strip hides it. Settings is the only one (K11). |
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
raises the carousel over it (K3) and hides it on the way home (K4) — and the
theme picker goes *in*, which it had never actually been: the gate named the
shade and the drawer by hand, so a swipe from the theme picker fell through to
the carousel whenever a window happened to be open. It is a page reached from
Settings and returned to it (K11), not a screen of its own, so clearing it is
what this criterion always meant.

The list is derived from the one the back gesture already walks, minus the
carousel — which a second drag continues rather than clears (A6) — and minus
the shell apps. Three hand-kept lists of overlay ids is how Settings and Themes
came to be missing from the back gesture, and this is the third one not being
written.

**A9** With nothing open anywhere, an up-swipe from the strip does nothing. An
empty switcher is a dead end you would only have to dismiss.

*Nothing* means no windows **and** no shell app: a phone whose only running
thing is Settings has one card, so the strip has a carousel worth raising (K1).

With E6, this means **the carousel has no empty state**: it can never be on
screen with zero cards, so that state is not built. (`Recents.qml` currently
has a "No open apps" label — it becomes unreachable and comes out.)

## B. Strip — swipe sideways

**B1** Swipe left goes to the next workspace; swipe right goes to the previous
one. With one app per workspace, that is next/previous app.
→ focused workspace name changes and changes back

**B2** A swipe that curves — as a thumb does — still resolves to whichever
direction dominates, and does not fall through to doing nothing.

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
leading and marked. Settings has a card here on the same terms as a window
(K1); everything E says about a card applies to it unchanged.
→ `omarchy-shell recents list` has one line per open window, plus one for
Settings while it is running

**E2** Tapping a card focuses that app and closes the carousel.
→ focused workspace holds that window; `recents state` == `closed`

**E3** Swiping a card up closes that app, and its card leaves the row. On the
Settings card that is a close and not a hide, so the page stack resets (K6).
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

**Known defect, recorded and deliberately not fixed.** `firstFreeWorkspace()`
scans 1..10 and then falls through to `return 10` — a number `taken` has just
recorded as occupied — so once ten workspaces exist, going home lands on an app
instead of a home screen.

It is worth writing down because it does not look like one bug. A4 and K4 both
end in that fall-through, so the two trade an intermittent failure between them
depending on how many workspaces happen to be occupied, and on a phone shared
between sessions that is luck. Measured, same build, minutes apart: K4 failed
with `workspace 10 holding 'V[moa-selftest]'` while A4 passed, then A4 failed
with the identical message while K4 passed. Both sessions working on this
suite read it as churn for a day. Confirmed at the mechanism rather than
inferred from runs — filling workspaces 1-12 and going home from an occupied
one leaves you where you were, with Settings open and with it closed alike, so
it is F1's implementation and has nothing to do with K4a.

Not patched here on purpose. What home should do when nothing is free is a
question about F1 itself: raising the ceiling past ten only moves the wall,
since one app per workspace will exhaust any ceiling, and dropping the "with
nothing on it" clause makes home land on an app, which is not what a home
screen is. That is a decision about the spec, not a constant to change quietly
on the way past.

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

## H. Closing an overlay by dragging it

The drawer and the shade each came up before this spec existed, and each could
only be dragged shut by a 26px band at the top of its own sheet. Dragging on
the sheet *body* did nothing. That was never a decision -- it was where an
implementation stopped.

**H1** Dragging **down** anywhere on the drawer closes it, following the finger.
→ `omarchy-shell drawer dragTrace` leaves ≥ 8 samples; `drawer state` == `closed`

**H2** Dragging **up** anywhere on the shade closes it, following the finger.
"Anywhere" includes the band of scrim below the sheet -- the bottom ~70px of
the screen, which is where a thumb starts an up-swipe. That band used to answer
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

The strip reserves its band off every *window*. The shell's own full-screen
surfaces are not windows, and until this section they were treated as if they
were: the drawer, Settings and the theme picker are Top with a zero exclusive
zone, so sway arranges them into the usable area and each stopped short of the
bottom edge, leaving a band of wallpaper with the pill drawn on it. The keyboard
stopped there too. They now extend under the strip. Nothing about what the strip
*reserves* changes -- that half is what keeps the keyboard from burying the pill,
and it stays exactly as it was.

Sizes are never written as numbers here. `Style.space(20)` rounds a *scaled*
value, and the scale comes from the theme's `shell.toml`: at the default ~1.15
the nominal-20 strip actually reserves 23. Every check below takes the height
from `geometry`'s `strip` field rather than assuming one.

**I1** With the drawer, Settings, the theme picker or the keyboard up, the
surface reaches the bottom row of the screen. No band of wallpaper, and no band
of the app underneath, shows beneath it. The keyboard is `moarchy-keyboard`'s
own surface and gets there its own way -- see its SPEC.md 45-48 -- but the
result this asks for is the same.
→ one `grim` capture: the pixel a strip-height above the last row equals the
pixel in the last row, sampled left of the centred pill

**I2** Each of the three sheets is exactly one strip taller than a Top surface
with the same zero exclusive zone and no margin. That is the negative margin
having taken effect, and it is the only way to know it did: sway's IPC does not
list layer surfaces, so this cannot be read from the compositor.
→ `omarchy-shell {drawer,settings,themes} geometry` each report `h` equal to
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
→ `... geometry` reports `gap` >= `strip` on all three

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

**I6** The pill still works over all four. The three sheets need no mask for
this: they are on Top, the strip is on Overlay, and every Overlay surface sits
above every Top one. **The keyboard is the exception and needs one** -- it is on
Overlay itself and maps after the strip, so an unmasked keyboard extended under
the strip lands above the pill and swallows every touch meant for it.
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
you navigate — and until this section the shell treated it as a sheet you
summon and dismiss in one motion, like the shade. That produced a gesture that
did two different things depending on what else happened to be running: with
nothing else open the strip's up-swipe cleared it (A8), and with an app open
the same swipe raised the carousel *over* it and left it there, so it was still
on screen when the carousel went away. The two cases were disagreeing about
whether Settings is an app. This section answers that it is.

Only the card model changes. Everything in A, E and J applies to Settings
unchanged once it has a card, which is why this section is short and mostly
points at criteria that already exist.

**K1** Settings has a card in the carousel for exactly as long as it is
running: from the summon that opened it until it is closed (K6). Hiding it does
not end that — a hidden app is still in the switcher, which is the whole
purpose of the switcher.
→ `omarchy-shell recents list` has a `moarchy.settings` line while
Settings is running and no such line when it is not

**K2** The card is icon, name and title, the same three lines a window's card
has (E1). The icon is the gear the shade opens it by, the name is "Settings",
and the title is the page it is on — so a card parked three pages into
Appearance says which page it will come back to. At the root page the title
line is absent, the way it is for a window whose title is its own name.

**K3** With Settings on screen, an up-swipe from the strip does what it does
from an app: the carousel rises, following the finger, with the Settings card
leading and marked (A1, E1). It is not A8's "clear whatever is covering the
screen" any more — that criterion keeps the shade and the drawer.
→ `recents state` == `open` and `recents list`'s first line is
`moarchy.settings`

**K4** Carried on into the home band, that same drag hides Settings and lands
on a home screen (A4). Hidden, not closed: the card is still in the carousel.
→ `settings state` == `closed`, the focused workspace's `representation` is
empty, and `recents list` still has its `moarchy.settings` line

**K4a** Reaching a home screen from Settings takes a workspace switch whenever
*any* window is open, not only when one is on the workspace underneath.

This is a concession and worth naming as one. Sway gives an exclusive-focus
layer surface the keyboard and deactivates the window beneath it, so for the
whole time Settings is on screen every toplevel reads unfocused and
`focusedToplevel()` — the question F1's switch is gated on — cannot tell an app
under the sheet from a bare home screen under it. The same fact is already
recorded in the drawer's keyboard-focus note, where sway "handed focus back to
a window" on the drawer's first close frame.

Of the two ways to be wrong, this picks the harmless one. Switching when the
workspace was already empty hops to another empty workspace and costs a
workspace number, which F1 immediately makes contiguous again. Not switching
when it was occupied leaves a *home* gesture looking at the app it was supposed
to leave, which is the bug this whole section exists to fix.
→ with Settings over a bare home screen and one app on another workspace, the
home band still ends on an empty workspace

**K5** Tapping the Settings card resumes the page it was hidden on, not the
root. That is the difference between hidden and closed, and it is why
`settings.md` A6 is amended rather than dropped: a *closed* Settings still
reopens at the root.
→ from `settings page` == `appearance.bar`, an up-swipe and a tap on the card
leaves `settings page` == `appearance.bar`

**K6** Two things close Settings, and both drop the card and reset the stack:
flicking the card away (E3), and the back gesture on the root page (G, and
`settings.md` B3). That pairing is not new — it is exactly what those two
gestures already do to a window, where E3 closes a card and G4 closes the
focused app.
→ after either, `recents list` has no `moarchy.settings` line and
`settings stack` is one line

**K7** Closing the Settings card when it is the only card leaves a home screen,
the way E6 has it for a window. The carousel still has no empty state.

**K8** Dismissing the carousel without picking anything puts you back on
Settings (E5). Nothing has to restore it, because the carousel covered Settings
rather than hiding it — hiding is what the home band does (K4) and what tapping
another card does (K9).
→ `settings state` == `open` after a dismiss tap

**K9** Tapping a *window's* card hides Settings on the way to that window. A
card that focuses an app must not hand it over with a full-screen sheet still
drawn on top.
→ `settings state` == `closed` and the tapped window is focused

**K10** Settings gets the shrink (J) like any app: the still captured when the
drag latches is of Settings, and it lands on the Settings card. J10's "only the
app you are leaving gets a picture" is satisfied the same way — Settings is on
screen and is being rendered, which is the whole of that constraint's
reasoning.

**K11** Settings, and nothing else. The shade and the drawer stay transient
sheets with no card: they are summoned and dismissed in one motion, Android
gives neither a recents entry, and A7/A8 already say the strip clears them. The
theme picker stays out too — it is a page reached from Settings that returns to
the page it was opened from (`settings.md` B7), not a screen of its own.

Stated as a criterion because "shell app" is a mechanism, and a mechanism with
one user looks like an oversight rather than a decision. Adding a second one is
a decision to take deliberately, not by noticing that the machinery would allow
it.

**K12** A bridged launch still puts Settings away first (`settings.md` E6) and
leaves it running, so the terminal it opened and the Settings page behind it
are both cards and the row you came from is one tap away.

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
  app control within it — a hamburger at the top-left, a back button — stops
  being tappable. Android has the same problem and solved it with
  `View.setSystemGestureExclusionRects()`, which lets an app carve regions back
  out of the system gesture, capped at 200dp per edge (sized, explicitly, as
  four 48dp touch targets plus padding). **Wayland has no equivalent** — there
  is no protocol for a client to tell a layer-shell surface not to take touches
  in a region. So our edge is strictly more expensive than Android's, with no
  mitigation available to apps. If the back gesture turns out to bite in daily
  use, this is the reason, and the fix is to narrow G8 or drop the gesture —
  not to look for an API that does not exist.
- **The right edge stays unclaimed.**
- **One app per workspace** is assumed throughout: workspace ≈ app.

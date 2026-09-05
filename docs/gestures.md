# Touch gestures — specification

What the phone's touch gestures must do. Present tense, normative. The
archaeology of *why* lives in `docs/build-log.md`; this file is the contract.

Every line here is agreed. Nothing is inferred — where a choice was open it was
put to a decision, and the ones that removed capability (C1, E7) record why.

Each AC is checkable from a terminal. `bin/mobileomarchy-selftest --gestures`
cites these ids, so an AC with no test is visible.

## Vocabulary

| Term | What it means |
| --- | --- |
| **strip** | The reserved 20px band at the very bottom holding the home pill. Owned by `mobileomarchy.gestures`. |
| **home screen** | A sway workspace with no windows on it: wallpaper, bar, pill. One app per workspace, so an empty workspace *is* the home screen. |
| **app** | A workspace with a window on it. |
| **carousel** | The recent-apps switcher (`mobileomarchy.recents`). |
| **drawer** | The searchable app grid (`mobileomarchy.drawer`). |
| **shade** | The pull-down from the top edge (`mobileomarchy.shade`). |
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

**A9** With no apps open anywhere, an up-swipe from the strip does nothing. An
empty switcher is a dead end you would only have to dismiss.

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

**D3** On a workspace with an app, dragging on the app does nothing to the
shell. The app receives the touch — everywhere except the left edge band, which
belongs to the back gesture (G).

**D4** Sideways and downward swipes on the home screen do nothing, for now. The
home screen handles the up-drag and nothing else; the strip still changes
workspace and the top edge still opens the shade.

## E. The carousel

**E1** One card per open app, most recent first, with the app you just left
leading and marked.
→ `omarchy-shell recents list` has one line per open window

**E2** Tapping a card focuses that app and closes the carousel.
→ focused workspace holds that window; `recents state` == `closed`

**E3** Swiping a card up closes that app, and its card leaves the row.
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

**F2** Going home never closes anything. Every app is still in the carousel
afterwards.
→ `recents list` count unchanged across a home gesture

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
→ `omarchy-shell shade state` == `closed`

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

---

## Constraints

Not acceptance criteria — the boundaries any implementation works inside.

- **The strip reserves 20px off every window, permanently.** That is what keeps
  the on-screen keyboard from burying the pill.
- **Only the left edge may take touch ahead of an app, and only 16px of it.**
  The home-screen surface (D) sits *below* windows, so it can never intercept
  anything an app would have received and a bug in it cannot make the
  touchscreen unusable. The back gesture (G) is the one deliberate exception:
  it has to sit above windows to work at all. It is bounded the same way the
  bottom strip is — a fixed width that never grows mid-gesture — so the worst a
  bug there can do is cost 16px down one side.
- **No window thumbnails.** Quickshell 0.3.1 wires per-toplevel capture only to
  a Hyprland-only protocol, and sway does not render an invisible workspace, so
  there would be nothing to capture. Cards are icon + title.
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

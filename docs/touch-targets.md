# Touch targets — specification

What has to be tappable, and how big. Present tense, normative. The archaeology
of *why* lives in `docs/build-log.md`; `docs/gestures.md` owns the gestures
themselves. This file owns the **static** targets: the things you put a thumb on
once and let go of.

A gesture and a target fail differently. A gesture that misses does nothing and
you try again; a target that misses is invisible — the pill is right there, it
looks pressable, and the tap lands on nothing. So the failures this file exists
to prevent are the ones where the drawn control and the control that answers are
not the same shape.

Each AC is checkable from a terminal. Where a check needs a real touch it goes
through `sudo moarchy-touch tap`, the way `--gestures` already does, because a
hit area is exactly the thing that cannot be proved by reading a property.

## Vocabulary

| Term | What it means |
| --- | --- |
| **target** | The region that answers a tap: a `MouseArea`, or a control with its own input handling such as `Ui.TextField`. |
| **chrome** | What is drawn to say a target is there: the pill, the circle, the track. |
| **dead band** | Chrome with no target under it. The bug this file is about. |
| **44** | 44 logical px, this shell's floor for a target's shorter side. At the PinePhone's scale 2 that is 88 device px, ~7.7mm — the low end of the usual 7–10mm guidance, and the size the existing Join/Cancel/Continue buttons already are. |

---

## A. The floor

**A1** Every target is at least 44 logical px on its shorter side.
→ no `MouseArea` in `default/omarchy/plugins/` resolves smaller than 44 in
either axis

**A2** Chrome keeps whatever size it was drawn at. Where A1 needs more room than
the chrome has, the *target* grows and the drawing does not — `anchors.margins`
goes negative on the `MouseArea`, which is what the shade's media buttons and
its Clear-all already do. A 36px circle that answers over 44px is right; a 44px
circle that used to be 36 is a redesign nobody asked for.

**A3** Grown targets do not overlap. Two controls in a row 8px apart may each
take 4px of that gap and no more, or the later sibling silently eats the earlier
one's edge and one of two adjacent buttons stops working near its border.

---

## B. Text inputs

The reported bug, and the reason this file exists. Both text fields in this
shell are an `Ui.TextField` drawn *inside* a pill rather than as the pill:
`background: null`, so the pill is a sibling `Rectangle`, and the field is
positioned by `anchors.verticalCenter` with `verticalPadding: 0`.

That makes the field exactly one line of text tall — 16–22 logical px, from
`Style.font.body` — sitting on the centre line of a 46px (drawer) or 44px
(Wi-Fi) pill. The insets are anchor margins, so they are outside the field too:
the drawer's magnifier glyph and its 16px lead-in, and the 16px lead-in on the
Wi-Fi passphrase, are all dead band. Derived from the geometry rather than
measured on glass: **roughly a third** of the drawn search pill focuses the
field, and the rest of it looks identical and does nothing.

**B1** Tapping anywhere inside the drawn pill focuses the field and raises the
keyboard. Anywhere means the corners, the leading glyph, and both insets.
→ `omarchy-shell drawer searchTarget` gives the pill's rect; a
`sudo moarchy-touch tap` inside its top-left corner makes the same call report
`focused=true`

**B2** The chrome does not move. The text sits where it sat, the glyph sits
where it sat, the pill is the same pill. The inset becomes `leftPadding` on the
field instead of an anchor margin — which draws identically, and is inside the
hit area rather than outside it.
→ a `grim` capture of the drawer differs from the previous one only where the
caret is

**B3** The field never extends past its pill. A field that fills a pill and a
field that spills out of one are the same edit here and only one of them is
right.
→ in `omarchy-shell drawer searchTarget`, `field=` is contained by `pill=`

**B4** In Wi-Fi, the reveal (eye) button keeps its own 44px target, and a tap on
it does not focus the passphrase field.
→ `omarchy-shell wifi passTarget` after `sudo moarchy-touch tap` on the eye
reads `focused=false revealed=true`

**B5** The text does not move when the field takes focus. Both fields left
`leftPadding` bound to the base type's `horizontalPadding + Border.left(spec)`,
and that spec is `focus` or `normal` — so on any theme whose focus border is a
different width from its normal one, the placeholder and the caret shifted
sideways at the moment of the tap. Pinning the padding is what settles it.
→ `omarchy-shell drawer searchTarget` reports the same `field=` rect focused
and unfocused

---

## C. The rest of the audit

Every static target in the shell, measured off the source. Sizes are logical px
and `Style.space()` is scale 1.0 today, so they are also the drawn numbers.

| Where | Target | Now | Verdict |
| --- | --- | --- | --- |
| `moarchy.settings` | row (any type, incl. the switch) | full row, 58 | ok |
| `moarchy.settings` | Cancel / Continue in the confirm card | 110 × 44 | ok |
| `moarchy.shade` | wide + small tiles, sliders, notification cards | ≥ 48 | ok |
| `moarchy.drawer` | app icon cell | 90 × 86 | ok |
| `moarchy.themes` | theme cell | half-width grid cell | ok |
| `moarchy.recents` | carousel card | card-sized | ok |
| `moarchy.wifi` | network row, Join / Disconnect / Forget | ≥ 44 | ok |
| `moarchy.settings` | header back button | 38 | **under** |
| `moarchy.themes` | header back button | 38 | **under** |
| `moarchy.wifi` | header back button | 38 | **under** |
| `moarchy.device` | header back button | 40 | **under** |
| `moarchy.shade` | header gear / power `RoundButton` | 36 | **under** |
| `moarchy.shade` | media prev / play / next | ~27 + 12 = 39 | **under** |
| `moarchy.shade` | notification "Clear all" | ~14 + 16 = 30 | **under** |
| `moarchy.wifi` | header radio switch | 52 × 30 | **under** in y |

**C1** The four header back buttons answer over 44 and stay drawn at their
current diameter. They already sit in a 44px header row, so the height is there
for free and only the width is new. `-3` on the three 38s, `-2` on Device's 40.

**C2** The shade's `RoundButton` answers over 44, drawn at 36. The pair is 8px
apart, so each takes 4 (A3) — and 4 is exactly what 36 needs.

**C3** The shade's three media buttons answer over 44, drawn at `glyphSlot`.
This is the one AC in this file that could not be met by growing a hit area, and
the only one that changes a layout.

Grown outward they top out at 34: the glyphs sit on 34px centres (a 24px glyph
plus the Row's 10px spacing), so the middle button may claim 5 a side before it
starts eating its neighbours. The gap has to move *inside* the target instead —
each glyph is centred in a `tapSlot` square, `tapSlot` being
`Math.max(Style.space(44), glyphSlot)` so a theme with a bigger base font keeps
the bigger slot rather than being pulled back down to 44.

The cost, stated because it is real: the transport block is 40px wider, so the
track title beside it elides 40px sooner, and the three glyphs sit 10px further
apart than they did. That is the trade — a title that truncates a little earlier
against a play button that can actually be hit.

**C4** "Clear all" answers over 44 tall. Its row goes 20 → 24, because the
Column leaves a 10px gap either side and 24 + 10 + 10 is the first height whose
overhang does not run into a neighbour (A3). The label itself does not change
size; the row around it is 4px taller, and the sheet is a fixed fraction of the
screen so nothing overflows.

**C5** The Wi-Fi radio switch answers over 44 tall, drawn at 52 × 30. `-7` fills
the 44px header it sits in; the only thing within reach is the title, which is
text.

**C6** `moarchy.device` was written in raw pixel literals — `width: 40`,
`font.pixelSize: 22`, `anchors.margins: 16` — where every other plugin uses
`Style.space()` and `Style.font.*`. It was the one screen that followed neither
the theme's spacing scale nor its font size, and it would have been the one
screen that looked wrong the moment a theme changed either.

Converted by role rather than by number, so three things move: the title was
22px and is now `Style.font.heading` like every other header; every `Text` now
names `Style.font.family` and `root.textWeight`, where the file previously left
the family to Qt's default and said `font.bold` on two lines out of nine; and
the back chevron was a typographic `‹` at 30px where the other three headers
draw the Nerd Font chevron through `Ui.OpticalGlyph`. The header's own comment
claimed it mirrored every other screen in the shell. Now it does.
→ `grep -n 'pixelSize: [0-9]\|margins: [0-9]\|spacing: [0-9]\|radius: [0-9]'
default/omarchy/plugins/moarchy.device/Device.qml` matches only `spacing: 0`

---

## D. State

**Agreed and written:** all of it. B1–B4 are the request that opened this file,
B5 is a second defect found in the same four lines while fixing it, and A1–A3
and C1–C6 are the audit next to it, taken in full.

**Not yet verified on glass.** The accessors B1–B5 cite are new — `drawer
searchTarget` and `wifi passTarget` — and there is no `moarchy-selftest --touch`
suite calling them yet. Until one exists, or until the checks above have been
run against the phone by hand, this is the honest record: the code is written
and the geometry says it is right, and nothing has put a finger on it.

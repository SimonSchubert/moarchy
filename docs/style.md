# Style — specification

One UI across every surface of this phone. Present tense, normative. The
archaeology of *why* lives in [build-log.md](build-log.md); the gestures are
[gestures.md](gestures.md); this file is the contract for what things look like
and how big they are.

It covers the shell plugins in `default/omarchy/plugins/`, and — through §I —
the surfaces that are not in this repo at all: the on-screen keyboard and the
store. A phone whose keyboard is themed by one rule and whose settings screen is
themed by another is two phones, and the user is holding both.

Each AC is checkable, and §A–§D and §H are checkable without the phone:

```
scripts/style-check.sh
```

That is deliberate. A rule that needs a screenshot to enforce is a rule the
fourth screen breaks and nobody notices — which is exactly how `moarchy.device`
came to be written in raw pixels, at a font the theme does not set, while the
comment in its header claimed it mirrored every other screen in the shell.

## Vocabulary

| Term | What it means |
| --- | --- |
| **surface** | One screen this shell draws: the bar, the drawer, the shade, Settings, Themes, Wi-Fi, Device, the carousel, the splash. |
| **token** | A value read from `Style` or `Color` rather than written as a number. |
| **chrome** | What is drawn to say a control is there: the pill, the circle, the track. |
| **target** | The region that answers a tap. Not the same object as the chrome, and this file spends §E on the difference. |
| **logical px** | Sway's coordinate space, 360×720 here. The panel is 720×1440, so a device pixel is half a logical one. |
| **44** | The floor for a target's shorter side, in logical px. At scale 2 that is 88 device px, ~7.7mm — the low end of the usual 7–10mm guidance, and the size the Join / Cancel / Continue buttons already were. |

---

## A. Where the numbers come from

**A1** No surface writes a dimension, a font size or a colour as a literal. The
theme owns all three, and a literal is a value that silently stops following it.
→ `grep -rn 'pixelSize: [0-9]\|margins: [0-9]\|Margin: [0-9]\|spacing: [1-9]\|radius: [0-9]'
default/omarchy/plugins/` matches nothing

**A2** Lengths go through `Style.space(px)`. It is the shell's `rem`: the number
stays the pixel value the design was drawn at, and the theme's `[spacing] scale`
multiplies it. Writing `16` instead of `Style.space(16)` is not a shortcut to
the same thing — it is an opt-out of the scale, and it shows up as one screen
that does not grow with the rest.

**A3** Font sizes go through `Style.font.*`, chosen **by role and not by
number**. The tokens and their values at the default base size:

| Token | Default | What it is for |
| --- | --- | --- |
| `caption` | 10 | Secondary line under a label; footnotes. |
| `bodySmall` | 11 | A tile's label. |
| `body` | 12 | Row labels, buttons, field text. |
| `subtitle` | 13 | A line of detail under a heading. |
| `title` | 14 | Key/value rows. |
| `heading` | 16 | A screen's title, in its header. |
| `display` | 24 | A number that is the point of the screen. |
| `displayLarge` | 28 | Reserved; nothing uses it. |
| `icon` | = `title` | A glyph at text size. |
| `iconLarge` | 18 | A glyph that is a control. |

Picking the token whose default happens to equal the old literal is the wrong
move: `22` is not a token, and the answer to "what was 22?" is `heading`, which
is what every other header on the phone already uses.

**A4** Colours come from `Color`, through the per-surface role block in §C.

---

## B. Type

**B1** Every `Text` names `font.family: Style.font.family`. Omitting it does not
inherit the shell's font — it falls through to Qt's default, which is a
different typeface, and the screen reads as another app.
→ every `Text {` in a plugin has a `font.family` line

**B2** Sizes by role, per A3.

**B3** Weight is `Font.DemiBold`, held per surface as `readonly property int
textWeight`, on every `Text` that renders words. Light text on a dark ground
reads thinner than it measures, and a Regular settings list next to a DemiBold
bar looked like two different phones stacked on top of each other. `font.bold`
is not this: it asks for Bold.

**B4** Any text that can outgrow its box says so — `elide: Text.ElideRight`, or
`ElideLeft` where the tail carries the meaning (a path, a kernel version) — and
the box's width is computed from what is beside it rather than estimated. A
label that runs under a switch reads as a layout bug even when the elide is
doing its job, and one that stops short of it wastes the only line it has.

**B5** A glyph is not text. It takes no weight — weight on an icon font means
nothing — and it gets a fixed square slot, `Math.round(Style.font.iconLarge *
1.35)`, rather than its own advance width: advances differ per glyph in a Nerd
Font, so intrinsic widths leave a list ragged down its left edge.

A glyph that has to land **centred in a slot** goes through
`Ui.OpticalGlyph`, which measures the painted bounds and shifts by the
difference. Neither obvious alternative gets there: a filled `Text` with
`AlignHCenter` aligns the advance of the *primary* family while painting a
fallback glyph of a different width, and `anchors.centerIn` centres the box the
font reserves — measured on the shade's gear, 3.9 and 1.7 device pixels off a
72px circle respectively, against 0.3 for `OpticalGlyph`. A glyph anchored to an
edge rather than centred may stay a plain `Text`.

---

## C. Colour

**C1** A surface reads the palette for the *layer it is on*, not the global one:

| Layer | Source | Surfaces |
| --- | --- | --- |
| bar | `Color.bar.*` | `moarchy.bar` |
| full-screen | `Color.menu.*` | drawer, Settings, Themes, carousel |
| popup / pull-down | `Color.popups.*` | shade, Wi-Fi, Bluetooth |

**C2** Each surface declares the same six roles at the top of the file, and the
body refers only to those — never to `Color.*` inline. The recipe:

```qml
readonly property color surface:       Color.menu.background
readonly property color textOnSurface: Color.menu.text
readonly property color container:     Util.alpha(Color.menu.text, 0.08)
readonly property color containerHigh: Util.alpha(Color.menu.text, 0.14)
readonly property color accent:        Color.accent
readonly property color textOnAccent:  Color.background
```

Two blocks, not one, is the whole reason this is a per-surface property block
rather than a shared singleton: the shade wants `popups` and the drawer wants
`menu`, and a component that picks for itself can serve only one of them. That
is also why `SettingsRow` takes its colours as *properties* — it is used from
both.

**C3** `subdued` is computed against the surface it will be read on, through the
surface's own `readableOn()` helper, and never fixed at an alpha. A theme whose
menu text is already low-contrast turns a flat `alpha(text, 0.62)` into
unreadable.

**C4** Literal hex appears in exactly one place: the fallback in a `typeof Color
!== "undefined"` guard, for a surface that must draw before the theme singleton
is available. Anywhere else it is a colour that will not follow a theme change.

---

## D. Shape

**D1** Four radii, by what the thing is:

| Radius | Value | What it is |
| --- | --- | --- |
| sheet | `Style.space(28)` | A full-width surface that slides in: the shade sheet, the drawer sheet. |
| tile | `Style.space(20)` | Something in a grid or a row that you tap as a unit: shade tiles, theme cells, carousel cards. |
| card | `Style.space(18)` | A stacked panel or list row: Settings rows, Wi-Fi rows, notification cards, the confirm card, Device's panels. |
| pill / circle | `height / 2`, `width / 2` | Anything fully rounded: search field, switches, action buttons, the back chevron. |

Held as `readonly property int radiusSheet / radiusTile / radiusCard` on the
surface, so the name says which of the four was meant. A bare `Style.space(14)`
on a card is a fifth radius nobody chose.

**D2** A rounded rectangle drawn over a rounded corner squares it back off with
a second rectangle rather than being left with notches — the drawer sheet and
the shade sheet both do this at their top edge, which is off screen.

---

## E. Touch targets

A gesture and a target fail differently. A gesture that misses does nothing and
you try again; a target that misses is invisible — the pill is right there, it
looks pressable, and the tap lands on nothing. So the failures this section
exists to prevent are the ones where the drawn control and the control that
answers are not the same shape.

**E1** Every target is at least 44 logical px on its shorter side.
→ no `MouseArea` in `default/omarchy/plugins/` resolves smaller than 44 in
either axis

**E2** Chrome keeps whatever size it was drawn at. Where E1 needs more room than
the chrome has, the **target** grows and the drawing does not —
`anchors.margins` goes negative on the `MouseArea`. A 36px circle that answers
over 44 is right; a 44px circle that used to be 36 is a redesign nobody asked
for.

**E3** Grown targets do not overlap. Two controls in a row 8px apart may each
take 4px of that gap and no more, or the later sibling silently eats the earlier
one's edge and one of two adjacent buttons stops working near its border.

**E4** Where E1 cannot be reached by growing — because the neighbours are too
close for E3 — the gap moves *inside* the target instead: the control is centred
in a slot of its own, and the layout gives up the width. That is a real cost and
it gets written down where it is paid, not waved through. The shade's three
transport buttons are the only place in this shell that needed it; the note in
`Shade.qml` says what the track title lost.

**E5** A slot is derived from the glyph it holds, not fixed at 44 —
`Math.max(Style.space(44), glyphSlot)`. `glyphSlot` follows the theme's font
size, so on a theme with a larger base font the glyph is already over the floor,
and a hard 44 would shrink its target back down to meet it.

**E6** A drag area declared before its siblings sits *under* them: later
siblings take input first. That ordering is how the shade and the drawer let a
drag that starts on empty sheet reach the sheet while a tile still gets its own
taps, and it is load-bearing in both files.

---

## F. Text inputs

Both text fields in this shell are a `Ui.TextField` drawn *inside* a pill rather
than as the pill: `background: null`, so the pill is a sibling `Rectangle`.

That shape has a trap in it, and both fields were in it. Positioned by
`anchors.verticalCenter` with `verticalPadding: 0` and no background, the
control is exactly one line of text tall — 16–22 logical px of a 46px pill — and
the insets were anchor margins, which puts them outside the control too. The
drawer's magnifier and its 16px lead-in, and the Wi-Fi passphrase's lead-in,
were chrome with nothing under them. Derived from the geometry rather than
measured on glass: **roughly a third** of the drawn search pill focused the
field, and the rest of it looked identical and did nothing.

**F1** Tapping anywhere inside the drawn pill focuses the field and raises the
keyboard. Anywhere means the corners, the leading glyph, and both insets.
→ `omarchy-shell drawer searchTarget` gives the pill's rect; a
`sudo moarchy-touch tap` inside its top-left corner makes the same call report
`focused=true`

**F2** The chrome does not move. The inset is `leftPadding` on the field instead
of an anchor margin — which draws identically, and is inside the hit area rather
than outside it.
→ a `grim` capture of the drawer differs from the previous one only where the
caret is

**F3** The field never extends past its pill.
→ in `omarchy-shell drawer searchTarget`, `field=` is contained by `pill=`

**F4** A control at the end of a field — Wi-Fi's reveal eye — keeps its own 44px
target, and a tap on it does not focus the field.
→ `omarchy-shell wifi passTarget` after `sudo moarchy-touch tap` on the eye
reads `focused=false revealed=true`

**F5** The text does not move when the field takes focus. Left to the base
type, `leftPadding` is `horizontalPadding + Border.left(spec)`, and that spec is
`focus` or `normal` — so on any theme whose focus border is a different width
from its normal one, the placeholder and the caret shift sideways at the moment
of the tap. Pinning the four paddings is what settles it.
→ `omarchy-shell drawer searchTarget` reports the same `field=` rect focused
and unfocused

---

## G. Motion

This is a Mali-400 at GLES 2.0. Half of these rules are about what the GPU can
afford, and the other half about not making the phone feel slower than it is.

**G1** Durations by travel:

| ms | For |
| --- | --- |
| 120 | A knob sliding in a switch; a colour swap inside a control. |
| 140 | The default state change — a tile lighting up, a card fading. |
| 160 | A small element leaving: a dismissed card, the splash. |
| 200–220 | A whole surface arriving or leaving. |

**G2** Easing is `Easing.OutCubic` for anything that travels, so it arrives
rather than stops. `InOutSine` is for a loop that never arrives — the splash's
breathing pulse is the only one.

**G3** Never put `opacity` on a subtree to fade it. The renderer groups and
composites the whole subtree off-screen first, which on this GPU is the frame
budget. Animate the alpha of one blended quad instead; the shade's scrim is the
worked example.

**G4** Move things with `y`/`x`, not `scale`. A translation is free and a scale
re-rasters every glyph and icon under it. The one exception is a single textured
quad with nothing to re-raster — the carousel's app preview — where the cost is
the blit and a shrinking quad blits less.

**G5** A `Behavior` on a property that a finger is currently driving is turned
off for the duration of the drag. Otherwise the animation and the finger fight,
and the finger loses by one frame, every frame.

---

## H. Feedback

§E makes the target the right shape. This section makes the shape say it was hit,
because those two failures are one step apart and identical from the outside: the
tap landed, nothing moved, and the only way to learn whether it worked is to wait
for the consequence. Twenty-eight controls in this shell. One of them answered.

**H1** Every control shows a pressed state for as long as the finger is on it. A
control is a `MouseArea` that answers `onClicked`.
→ every `MouseArea` block containing `onClicked` declares an `id`, and that id's
`.pressed` is read somewhere in the same file

**H2** The pressed state is one blended quad the size of the chrome: the control's
own ink at 12%, composited over the resting fill rather than replacing it. Not a
pressed variant of each fill — half of these controls already carry a state
expression as their colour (`on ? accent : container`, `isExpanded ? containerHigh
: container`, `ready ? accent : containerHigh`), and a second one per state is two
expressions to keep in step instead of one layer over both. Composited, 12% lands
`container` (0.08) at 0.19 and `containerHigh` (0.14) at 0.24 — a step past the
next tone up, in whichever direction the theme's ink runs, and no surface has to
know which fill it is over. It needs no seventh colour role (C2): the ink is one
the control already draws with.
→ the veil is culled at rest rather than drawn transparent: `visible: color.a > 0`.
Nothing in the scene graph culls an alpha-0 rectangle, and the shade alone carries
thirteen of them — two tiles at 328×128 panel px, four at 212×124, two sliders at
672×100, and the rest — which is about a third of a 720×1440 panel left blended
into every frame, forever, to say nothing.

**H3** The veil's two ends are one colour at two alphas — `Util.alpha(ink, 0.12)`
and `Util.alpha(ink, 0)` — never `"transparent"`. `"transparent"` is `#00000000`
and it carries black, so a `ColorAnimation` to it interpolates that black alongside
the alpha and the fade detours through a grey wash. The same arithmetic rules out
the tidier-looking `Qt.tint(fill, Util.alpha(ink, 0.12))`: tint lerps
`tint.rgb·a + base.rgb·(1−a)`, weighting the base's RGB *without* its alpha, so
over a transparent base it returns 12% grey rather than 12% ink — a press that
darkens on a dark theme. It is right over `container` only because base and tint
happen to share an RGB there.
→ no press state names `"transparent"` at either end

**H4** The ink is the control's own foreground, not the surface's. A lit tile veils
toward `textOnAccent`; a theme cell painted in the theme it names veils toward its
own `modelData.foreground`; Clear all veils toward `accent`, which its label
already is. A surface-wide ink over a control drawn from another palette is a wash
of the wrong colour, and on the themes grid that is half the screen. It is also
the only thing that stops a theme whose accent equals its text from having a press
state that does nothing.

**H5** Instant in, 120 out (G1). A symmetric 120 reaches 67% of the veil on an 80ms
tap and peaks *after* the finger has left — Qt restarts a `Behavior` at its full
duration from wherever the value is, it does not shorten it — so the strongest
frame of the acknowledgement is one nobody is touching. The asymmetry is read off
the value being *replaced* rather than off `pressed`: `QQmlBehavior::write()`
evaluates `enabled` at the moment of the write, when the property still holds the
old colour, so `enabled: veil.color.a > 0` is false arriving and true leaving.
Gating on `pressed` cannot work — `enabled` and `color` are then two bindings on
one notify signal, and QML runs them in the order the notifier list was built,
which is the reverse of the order they are written in.

**H6** A press that becomes a drag is not a press. On the shade and the drawer the
tiles *are* the sheet's drag handle (E6), so `MouseArea.pressed` stays true for the
whole gesture and a scrolling thumb would light every tile it crossed. Those bind
`pressed && !root.sheetDragging`. A `MouseArea` inside a `Flickable` needs no
guard: the grab is stolen, `QQuickMouseArea::ungrabMouse()` clears `pressed`
*before* it emits `canceled()`, and the state leaves by itself. One with a
`drag.target` of its own guards on `drag.active`.
→ in `Shade.qml` and `Drawer.qml`, no `.pressed` is read on a line that does not
also name the guard

**H7** Four kinds of `MouseArea` are not controls, and each says which it is where
it sits: a drag catcher under the content, a scrim that dismisses, a tap swallower
behind a modal, a swipe area with no `onClicked`. Each carries
`// no press state (style.md H7): <what it is>` — spelled with the filename,
because a bare `(H7)` in `Shade.qml` or `Drawer.qml` already means `gestures.md`.
The exemption is a comment and not an absence, because an absence is exactly what
a forgotten control looks like.
→ the comment is *inside* the `MouseArea` block, which is where the check reads
and where the next person does

**H8** The veil sits over the fill and under the content. Over the content it is a
12% contrast loss on the one line of text the control has; under the fill it is
invisible. In practice that is a `Rectangle` declared as the chrome's first child,
which also leaves E6's ordering intact — the veil takes no input, and every
`MouseArea` stays the last sibling. It is sized to the **chrome** and never to the
grown target (E2): a 36px circle answering over 44 highlights 36. Where a control
has no chrome at all, one is drawn at the size the control was always meant to
look rather than at the size of its hit area — the shade's three transport buttons
highlight `tapSlot − 10`, handing back the gap E4 moved inside them.

---

## I. Surfaces outside this repo

Three programs draw this phone's UI and only one of them is here. They cannot
share code — one is a quickshell plugin set, one is a standalone Qt app, one is
Python and GTK4 — so what they share is this file and the palette underneath it.

**I1 One palette, three readers.** The source of truth is the active theme's
`colors.toml`, staged by `omarchy-theme-set` at
`~/.local/state/omarchy/current/theme/`. Following the staged copy means a theme
switch is picked up with no knowledge of where themes are installed.

| Surface | Repo | Toolkit | How it reads the palette |
| --- | --- | --- | --- |
| shell plugins | this one | quickshell / QML | `qs.Commons` `Color.*`, per §C |
| keyboard | [`moarchy-keyboard`](https://github.com/SimonSchubert/moarchy-keyboard) | Qt / QML, standalone | its own theme load; `scripts/fetch-themes.sh` |
| store | [`moarchy-store`](https://github.com/SimonSchubert/moarchy-store) | Python / GTK4 / libadwaita | `moarchy_store/theme.py` reads `colors.toml` and injects a stylesheet |

**I2** Every surface degrades to its toolkit's own defaults when the palette is
absent — a desktop with no Omarchy, a theme with no `colors.toml`, a malformed
one. Themed by the file's presence, never broken by its absence. `theme.py`'s
docstring is the statement of this and the behaviour to copy.

**I3** §A–§H bind every surface, restated in toolkit-neutral terms, because a
GTK app has no `Style.space()` and a standalone QML app has no `qs.Commons`:

- The **44 floor** (E1–E3) applies to a GTK button and a `KeyCap` exactly as it
  applies to a `MouseArea`. `moarchy-keyboard` already carries this as its own
  AC 29 — hit areas tessellate the panel, the visible gap between keys belongs
  to a key — which is E1 and E2 arrived at independently. That is the wording to
  keep; this file does not renumber it.
- The **type roles** (A3, B1–B5) are role names, not pixel values. A surface
  that cannot import `Style` picks its own ladder and maps it to the same roles,
  and it uses one family throughout at a single demi-bold weight.
- The **colour roles** (C2) are six names — surface, textOnSurface, container,
  containerHigh, accent, textOnAccent. `theme.py`'s `Palette` is the same idea
  under different names; a surface adding a seventh role should say why here.
- The **radii** (D1) are four names, and 360 logical px is the width every
  surface is designed at first rather than scaled down to.

**I4** A new surface joins by linking to this file from its own spec and saying
which of §A–§H it cannot meet and why. "It is a different toolkit" is not one of
the answers — all three of these already are.

---

## J. Conformance

Where the shell stands against the above, measured off the source. Sizes are
logical px; `Style.space()` is scale 1.0 today, so they are also the drawn
numbers.

| Surface | Element | Target | Verdict |
| --- | --- | --- | --- |
| `moarchy.settings` | row, any type | 58 full-width | ok |
| `moarchy.settings` | Cancel / Continue | 110 × 44 | ok |
| `moarchy.settings` | header back | 38 drawn, 44 answering | ok, E2 |
| `moarchy.shade` | tiles, sliders, notification cards | ≥ 48 | ok |
| `moarchy.shade` | gear / power | 36 drawn, 44 answering | ok, E2 |
| `moarchy.shade` | media prev / play / next | `tapSlot` ≥ 44 | ok, E4 E5 |
| `moarchy.shade` | Clear all | 44 tall | ok, E2 |
| `moarchy.drawer` | app cell | 90 × 86 | ok |
| `moarchy.drawer` | search field | fills its pill | ok, F1–F5 |
| `moarchy.themes` | theme cell | half-width grid cell | ok |
| `moarchy.themes` | header back | 38 drawn, 44 answering | ok, E2 |
| `moarchy.recents` | carousel card | card-sized | ok |
| `moarchy.wifi` | network row, Join / Disconnect / Forget | ≥ 44 | ok |
| `moarchy.wifi` | header back | 38 drawn, 44 answering | ok, E2 |
| `moarchy.wifi` | radio switch | 52 × 30 drawn, 44 tall answering | ok, E2 |
| `moarchy.wifi` | passphrase field / reveal | fills its half; eye 44 | ok, F1–F5 |
| `moarchy.bluetooth` | device row, Connect / Disconnect / Forget | ≥ 44 | ok |
| `moarchy.bluetooth` | header back | 38 drawn, 44 answering | ok, E2 |
| `moarchy.bluetooth` | radio switch | 52 × 30 drawn, 44 tall answering | ok, E2 |
| `moarchy.device` | header back | 40 drawn, 44 answering | ok, E2 |

**State.** `scripts/style-check.sh` passes: 5 checks, 0 failures. Each of the
eight rules it enforces has been broken on a copy of the tree and seen to fail, so
the green is a measurement rather than an absence.

§H holds across all 28 controls. One of them had a press state before it was
written — `moarchy.device`'s back chevron, which snapped between `container` and
`"transparent"` with no fade and is now the same veil as everything else.

**§H verified on glass**, 2026-09-07, on the PinePhone. Method: `grim` a full
frame with nothing pressed, another with `moarchy-touch hold` on the control, and
diff the two — the bounding box of what changed *is* the highlight, so it needs no
accessor to say where it should be. Panel px throughout; the synthetic finger
lands 2.6s after launch, which is worth knowing before timing a capture against
it.

| control | changed region | logical | drawn at |
| --- | --- | --- | --- |
| shade gear (`RoundButton`) | 72 × 73 | **36 × 36.5** | 36, answering over 44 |
| shade Silent (`SmallTile`) | 212 × 124 | **106 × 62** | tile height 62 |
| Settings row (`SettingsRow`) | 672 × 116 | **336 × 58** | row height 58 |

*H8 and E2, in one measurement.* The gear answers over 44 and is drawn at 36, and
what changed is 36 — the pixel 4px outside the circle is byte-identical pressed
and unpressed. The drawing did not grow; only the answering did.

*H1, both halves.* The gear's rect is byte-identical before the press and after
the press-and-release, so nothing is left lit. A check that only proves the veil
appears passes a stuck press state.

*H2 and H4, and the direction.* On an unlit control the fill lifts, `(38,39,52)`
→ `(54,55,72)`. On a *lit* one it goes the other way — the Silent tile switched on
reads `(122,162,247)` and `(110,145,222)` under a thumb — because H4 veils toward
the control's own ink and an accent tile's ink is `textOnAccent`, which is the
dark background. Both directions are "pressed" on this theme, and neither had to
be written per control.

*H6, in one gesture.* A slow 100px drag begun on a tile, sampled twice. Counting
pixels of the pressed fill: 43 with nothing pressed, 10,288 with the finger down
and still inside the 10px slop, 4 once the drag latched. The tile lights the
instant the finger lands and lets go the instant the gesture becomes the sheet's.

*What the diff also settled.* Nothing else on the screen moves. The Settings row
press changed 336 × 58 and the row above it was byte-identical, so a veil does not
leak into a neighbour — which is E3's failure one layer up, and the reason the
Wi-Fi and Bluetooth row veils are sized to the head rather than to the delegate.

§E and §F are written and hold across every surface. §A–§D were brought into
line at the same time, and five things moved:

- `moarchy.device` was raw pixel literals throughout — no `font.family` at all,
  a 22px title where every other header is `heading`, and a typographic `‹`
  where the other three draw the Nerd Font chevron.
- Three surfaces carried a fifth radius, `Style.space(14)`, which D1 does not
  have: Wi-Fi's rows and Device's two panels are `card` (18) now, next to
  Settings' rows rather than 4px off them.
- Two more wrote their radius as a bare number where the name says which of the
  four was meant: the drawer's sheet, the carousel's card. Themes called its
  grid cell a `card` at the tile radius; it is a `radiusTile`, same value.
- The drawer's app labels and the carousel's two lines were the last text in the
  shell still at Regular. Both surfaces now carry `textWeight`.
- Wi-Fi's reveal eye was a plain `Text` centred in a 44px circle, which is the
  case B5 exists for. It is an `Ui.OpticalGlyph` now, like the gear and the four
  back chevrons.

**Verified on glass**, 2026-09-06, on the PinePhone over ssh with taps
synthesised through `/usr/lib/moarchy/bin/moarchy-touch` (panel pixels, so twice
the logical coordinate).

*E1–E3, on the shade's gear.* Drawn at 36 logical px, spanning x 268–304; the
grown target adds 4, so 264–308. A tap at **265.5** — outside the drawn circle,
inside the target — opened Settings. The control tap at **257.5**, outside both,
left it closed. That is E2 in two taps: the drawing did not change and the
answering region did.

*F1.* Six points across the search pill focus the field, including the two that
were categorically dead before — the magnifier glyph, which sat *outside* the
old field rather than merely near its edge, and the 16px right inset. Repeated
three times each: 8 of 9 trials focused, the one miss a tap that landed while
the sheet was still animating open.

*F3.* `omarchy-shell drawer searchTarget` reports `pill=10,26 340x46
field=10,26 340x46` — the field is not merely inside the pill, it *is* the pill.

*E1, on `moarchy.bluetooth`'s action strip*, 2026-09-07.
`omarchy-shell bluetooth actionTarget` reports `actions=226,152 110x44` — 44 on
the shorter side, read off the running surface rather than off `Style.space(44)`
in the source, which is the distinction §J exists to make.

Getting that reading is what found the bug behind it. The strip registers itself
in `onVisibleChanged`, and the fixture used to force a row open pinned
`isExpanded` to `true` — so the delegate was built already visible, the signal
never fired, and the accessor answered the empty string while the strip was
plainly on screen at the right size. Real taps never hit it, because the list is
frozen while a row is open and no delegate is rebuilt. It is registered on
completion as well now.

*F5.* That `field=` rect is identical focused and unfocused, in every reading.

**Still unverified: F4.** It needs a secured network that is not the connected
one, and the phone cannot scan: quickshell's polkit agent fails to register
("An authentication agent already exists for the given subject"), NetworkManager
falls through to `auth_admin`, and the account password is locked, so the prompt
that appears can never be answered. The plugin itself is live — `wifi
passTarget` answers with the empty string its no-row-expanded branch returns —
there is simply no row to expand.

**One trap worth writing down**, because it cost the most time here: a plugin's
surface coordinates are not screen coordinates. The drawer's layer surface
starts at screen y=26, below the bar, so the first taps aimed straight at
`searchTarget`'s y landed 26 logical px high and hit nothing, with no error
anywhere — the same silent-failure shape this file exists for. Read the offset
from `drawer geometry` (`h=494` = 720 − 26 bar − 200 keyboard); never assume it.

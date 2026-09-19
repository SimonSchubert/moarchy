# Shared Quickshell chrome

Phone chrome for moarchy plugins: the box system every screen is built from,
plus app bar, pill field, button, chip, icon button, back chevron, checkbox,
type roles, FAB, context menu, bottom nav and the empty state. Palette comes
from the same `colors.toml` the rest of the device reads.

A third-party plugin cannot import `moarchy.common`, so this directory is
**copied into the plugin** as `ui/` at install time. There is no runtime
package and no import from the shell.

```qml
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
```

`plugins/org.moarchy.ui.catalog` is the review surface: every control on one
window, and a second page that draws the box system itself -- the elevation
ramp, the radius scale and the nesting rule -- so a change to any of them is
looked at rather than reasoned about. Install it with that plugin's
`install-on-device.sh`, which copies this tree into `ui/` on the phone, or run
it on a laptop with that plugin's `run-local.sh`.

## Everything is in a box

One rule decides most of what a screen here looks like: **content is in a box,
and the only loose text is the label above one.** A grey sentence floating on
the window is how a screen stops looking designed, and it is also how every one
of these apps looked before the boxes arrived.

The second rule is what a box is made of. Not a border -- a *fill*, one step up
a five-step ramp, and a corner off a four-step scale.

- **`Theme.surface(colours, level)`** is the ramp: `well`, `card`, `raised`,
  `pressed`, `edge`. Each is the theme's own foreground mixed into the theme's
  own background, which is what makes a light theme's boxes come out *darker*
  rather than foggier. `Theme.tint(colours, hue, level)` is the same ramp in a
  colour, for a row that is an event or a warning. Every step is a distance
  from the page background, so a box inside a box takes the next one up.
- **`Metrics.RADIUS_XXS/XS/SM/MD/LG`** is the scale, and `Metrics.CARD_RADIUS`
  is `RADIUS_MD` -- what a box on the page gets. The scale is drawn at the
  phone's `large` corners, and it is never drawn with directly: see *Corners*
  below.
- **`Metrics.inner(outer, pad)`** is the nesting rule: a box inset inside
  another keeps the two curves concentric only if its radius is the outer one
  less the inset. `inner(RADIUS_LG, GROUP_PAD)` is `RADIUS_MD`, and
  `inner(RADIUS_MD, GROUP_PAD)` is `RADIUS_SM`, so the three shapes on a screen
  nest exactly. Anything else leaves a crescent of the outer fill in every
  corner, which is the tell that a card was dropped into a list rather than
  designed into it.
- **`Metrics.GUTTER/PAD/GAP/GROUP_PAD/LABEL_GAP`** are the five spacings, and
  they nest the same way: the page insets its content by `GUTTER`, a box insets
  its own by `PAD`, two boxes sit `GAP` apart, and a box that holds boxes insets
  them by `GROUP_PAD` -- which is the number `inner()` subtracts.

**There are no dividers.** A hairline between two rows is a gap that has been
drawn instead of left, it is the first thing to disappear on a phone screen in
sunlight, and it is what made every list in this repository read as a
spreadsheet. Where two things need separating, the space between them does it;
where a group needs an edge, the group is a box.

The components that follow from this:

| | |
| --- | --- |
| `Card` | A box. Children go in a vertical stack; it sizes itself to them. |
| `Section` | A label and the box it labels -- the one place loose text is right. |
| `Group` | A `Card` at group spacing: a box that holds rows or boxes. |
| `ListFrame` | A `Group` for something that sizes itself, so a `ListView` scrolls inside it. |
| `ListRow` | One row in either: leading slot, two lines, trailing slot, a press that lights the whole thing. |
| `Tile` | A fact in a box -- what it is, small and dim, over what it says. Two across a 360px screen. |
| `EmptyState` | What a screen says when there is nothing on it, in a box with a glyph. |
| `Button` | A word you can press, at three weights: `filled`, `tonal`, `plain`. |
| `Chip` | One choice in a strip of them, carrying a state rather than an action. |

### Corners

`~/.config/omarchy/ui.toml` says how round the phone is -- `corners = "large"`,
`"modest"` or `"square"` -- and the shell's sheets, tiles and cards follow it
(moarchy's `docs/style.md` D1). An app that drew `radius: Metrics.RADIUS_LG`
was the one rounded thing left on a square phone, so no app does:

- **`Metrics.radius(colours, px)`** is a box: a card, a group, a key, a
  heat-map cell. `px` is the large number off the scale; modest scales it by the
  ratio of the two tile radii, which lands a group on the shell's modest tile
  (8) and a card on its modest card (6), and square is 0.
- **`Metrics.round(colours, size)`** is a capsule or a circle: a button, a
  field, a chip, a progress track, the disc behind today's date. Fully round at
  large; a box with the tile's corner at modest, capped at half the side the way
  the shell's `Pill` is; square at square.
- **Neither is for artwork.** A sun, a clock face, a reversi disc, a mine and
  the O in noughts and crosses are round because the thing drawn is round.

The shape reaches both through `colours`: `ThemeFile` watches ui.toml with
`UiFile` and folds it in, because `colours` is the one object every box on every
screen is already handed. The kit's own `Card`, `Group`, `ListFrame`,
`ListRow`, `Section`, `Tile`, `Button`, `Chip`, `TextField`, `EmptyState`,
`ContextMenu` and `Toast` need nothing more. `IconButton`, `BackButton`, `Fab`,
`Check` and `MenuItem` take their inks as colours rather than as a palette, so
they take `colours: root.colours` as well, for the shape alone -- left off, they
draw at large. `innerRadius` on a Card, Group, Section or ListFrame is already
the shaped number.

`scripts/qml-shot.sh` photographs at any of the three: `CORNERS=square` for a
whole run, or `CORNERS=modest` as one shot's variable.

## What it needs

Quickshell, QtQuick, QtQuick.Layouts, `Qt5Compat.GraphicalEffects` for the
icon tint, and a Wayland compositor with layer shell for `AppWindow`. Nothing
from `omarchy-shell`: **no file here imports `qs.Commons` or `qs.Ui`**, which
is what lets an app built on the kit ship to a system that has Quickshell and
nothing of ours.

Three things used to come from the shell, and each has a portable answer that
keeps the phone's behaviour intact rather than approximating it:

- **`Style.font.body`** — `Metrics.shellBody(item)` compiles `import
  qs.Commons` as a string once at startup and returns the shell's own body
  size when that import resolves, 16 when it does not. Text size set in
  Settings still reaches every app on the phone.
- **`Ui.TextField`** — replaced by a `TextInput` in `TextField.qml`. Text
  reaches it without the shell: `moarchy-keyboard` binds `zwp_input_method_v2`
  and Qt speaks text-input-v3 for whatever holds focus. Focus does not raise the
  keyboard, so a press on the field asks `sm.puri.OSK0` through `Osk.qml`; with
  no keyboard on that bus name the call does nothing.
- **`Util.alpha`** — `Theme.alpha`, the same `Qt.rgba` call.

Icons resolve Adwaita's absolute paths first and fall back to
`Quickshell.iconPath()` only when a file is missing, so the phone never pays
for a theme walk and another distribution still gets glyphs.

# moarchy settings

Part of the moarchy skill. SKILL.md, beside this file, comes first.

## ui.toml

`~/.config/omarchy/ui.toml`. Every key is optional; a missing one is its
default. The full list, with what each value means, is the packaged copy:

    cat /usr/share/moarchy/ui.toml
    moarchy-ui keys                   # every key, its value now, and its default

| key | values | default | what it does |
| --- | --- | --- | --- |
| `shape.corners` | `large`, `modest`, `square` | `large` | every radius at once; `square` is Omarchy's own look |
| `shape.sheet`, `.tile`, `.card`, `.frame` | px | from `corners` | one radius; picking `corners` again clears these |
| `control-center.density` | `roomy`, `compact` | `roomy` | the control center's control sizes |
| `control-center.tile-height`, `.slider-height`, `.button-size` | px | from `density` | one size |
| `gestures.bottom` | `none`, `app-drawer`, `app-drawer-minimal`, `workspace-overview`, `control-center` | `app-drawer` | what a swipe up from the bottom raises |
| `gestures.right` | the same | `workspace-overview` | what a swipe in from the right edge raises |
| `gestures.hold` | the same, or `agent`, or a desktop id | `agent` | a press and hold on the bottom strip |
| `gestures.power` | the same as `hold` | `none` | two presses of the power button |
| `home.columns` | 2–12 | 6 | grid columns; cells are square |
| `home.opacity` | 0–1 | 0.88 | how much a tile covers the wallpaper |
| `home.border` | 0–8 px | 2 | a tile's border |
| `home.gaps-in` | 0–24 px | 6 | between tiles |
| `home.gaps-out` | 0–48 px | 6 | tiles to the screen's edge |
| `home.recent` | 0–12 | 8 | icons in the recent strip; 0 hides it |
| `home.prompt-bar` | `true`, `false` | `true` | the prompt bar on home |

```sh
moarchy-ui set home.opacity 0.7
moarchy-ui set shape.corners square
moarchy-ui get gestures.bottom
```

`moarchy-ui set` changes the one line it was asked about and keeps every comment.
An out-of-range value is refused rather than clamped. A file from before the
sections, with flat keys like `gesture_bottom = …`, still reads; the first
`moarchy-ui` write moves them into their sections.

## home.toml

`~/.config/omarchy/home.toml`: pages left to right, drawn in the order listed.
Page 1 is the first page of tiles; left of it go only faces, right of it faces
and pages of tiles mix. Two pages wait on home that are not in the file: an
empty one after the last (a tile put there makes it a page) and the face invite
left of the leftmost. A page of tiles that empties goes away. While it does not exist,
home is `/usr/share/moarchy/home.toml`, which documents the format.

```toml
[[page]]
face = "start"               # a whole-page face; faces always go left of page 1

[[page]]
tiles = [
  { widget = "fetch", x = 0, y = 0, w = 3, h = 4 },   # cell x/y, size in cells
  { widget = "today", x = 3, y = 0, w = 3, h = 4 },
  { widget = "clock" },                              # no position: first free spot
]
```

Shipped widgets for tiles: `today`, `fetch`, `media`, `calendar`, plus the
control center's `connectivity`, `brightness`, `volume` and `mobile-data`. Any
other id loads `~/.config/omarchy/widgets/<id>.qml`.

```sh
moarchy-home show                 # the pages as written, numbered as home numbers them
moarchy-home json                 # the same as JSON; edit it and hand it to `moarchy-home set`
moarchy-home add clock 1 2 2      # a 2x2 clock tile on page 1, first free spot
moarchy-home remove media
moarchy-home face start           # a face, left of the others
moarchy-home reset                # back to the shipped layout (keeps home.toml.bak)
moarchy-home share clock          # a link carrying ~/.config/omarchy/widgets/clock.qml
moarchy-home import '<link>'      # a shared widget, into ~/.config/omarchy/widgets/
```

Settings > Appearance > Home holds the `[home]` keys of ui.toml as steppers,
and its Pages screen reorders and removes pages by dragging. A person arranges
tiles on the phone itself: a long press on a tile selects it,
dragging it moves it (onto another tile, they swap), its edges resize it, and
the bar over it has `edit`, `share` and `remove`. Each of those is one
`moarchy-home set` of the whole layout, so the file always says what the screen
shows; read it again before editing it by hand.

## Widgets from the store

Omalauncher's store of OWL widgets installs on moarchy too. A tile names one
like any widget; its file is `~/.config/omarchy/widgets/<author>-<name>.owl`.

```sh
moarchy-owl catalog | jq '.widgets[] | {id, name, category, installed}'
moarchy-owl show simonschubert/calendar      # what it runs and needs
moarchy-owl install simonschubert/calendar   # onto the page home shows, or the next with room
moarchy-owl update simonschubert/calendar    # refuses if what it runs changed: add --yes
moarchy-owl remove simonschubert/calendar
```

Tell the person what a widget runs (`commands`) and which packages it installs
(`requires`) before installing it: that is the store's own rule. An animated
canvas widget costs about a CPU core while home shows it.

A link from `share` holds the whole file, deflated, after the `#`; nothing is
uploaded. `import` never writes over a widget that exists: give it
`--as <new-id>`. Read a shared widget before putting it on home, as you would
any code someone sent you.

A tile off the grid, or on top of an earlier one, moves to the first free spot.
One with no room left on its page is dropped, and `omarchy-shell home report`
names it. A file that does not parse leaves home as it was, `home report` gives
the line, and `moarchy-home` refuses to write over it.

## The coding agent

The prompt bar asks the agent named in `~/.config/omarchy/defaults/agent`,
which is upstream Omarchy's file.

```sh
moarchy-agent names               # the agents it knows: id and name
moarchy-agent set claude          # choose one (installs on first use)
moarchy-agent ask "a prompt"      # what Enter in the prompt bar does
```

## The theme

Colours are the theme's, not a setting in these files. A person changes it
from the home menu (a long press anywhere on home) or the theme picker; an
agent runs what both of those run:

```sh
omarchy-theme-set "Tokyo Night"   # the display name; ls /usr/share/omarchy/themes for slugs
```

It takes several seconds, and the whole shell recolours in place.

## Applying and checking

Every file above is watched, so a save is enough. To see what the shell made of
it:

```sh
omarchy-shell home report         # pages, tiles, states, errors, the frame's numbers
omarchy-shell home go 1         # show page 1 (0 and below are faces)
omarchy-shell home reload         # recompile your faces and widgets from disk
omarchy-shell home menu open      # the long-press menu (state | open | close)
```

`omarchy-shell` needs the session's environment. Over ssh run it as
`bash -lc 'omarchy-shell home report'`.

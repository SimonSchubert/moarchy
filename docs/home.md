# Home — specification

The home screen as Omalauncher draws it: pages of **widgets** on a grid,
**faces** left of page 1, the **prompt bar** that opens an app or asks a coding
agent, and the two sheets a swipe raises from it. Every UI setting lives in a
structured TOML file a person or an agent can edit. Present tense, normative.

Where this comes from: `~/Projects/omarchy-proot` (Omalauncher), its widget docs
`app/src/main/assets/widgets/docs/{faces,panels,home}.md`, `examples/65-ai-bar.owl`
and its frame in `ui/Theme.kt` (`Modifier.tile()`). This file takes the concept
and the look, not the code. Omalauncher is Kotlin and OWL; moarchy is quickshell
QML, and a tile here is a `widgets.md` widget.

Ids are `HM<n>`, cited by any check that proves one.

---

## A. What home is

**HM1** Home is drawn on the surface `moarchy.gestures` already maps on
`WlrLayer.Bottom` (namespace `moarchy-home`): above the wallpaper and under
every window. It shows exactly where `gestures.md`'s **home screen** is (a
workspace with nothing on it) and nowhere else, and it never asks which
workspace is focused. The gestures plugin keeps the surface and its drags
(`gestures.md` D). What is drawn on it is `moarchy.home/`, a kit directory with
no `manifest.json`, the same way `moarchy.common` is a kit. Keeping one surface
means the drag plumbing (`resolveTarget`, `releaseTarget`, the trackers) exists
once.
→ `hyprctl layers -j | jq '.. | objects | select(.namespace? == "moarchy-home") | .layer'`
is `1`; on an empty workspace `grim` shows tiles, and with an app open it shows
the app

**HM2** Home reserves nothing (`exclusiveZone: 0`), so a window is laid out the
same with home drawn as without it. Its content ends above the strip, and the
I1a/I1b fill still paints over it whenever it painted over the wallpaper.

**HM3** `omarchy-shell home report` prints home's model: the current page, the
pages with their kind (`face` or `tiles`), every tile with its widget id, cell
rectangle, `available` and any error, the frame's resolved numbers, and
`layout-error=` if the file could not be used. A collapsed tile and a missing one
are the same screenshot, so this is the check every other one here reads first.
→ `omarchy-shell home report` names the page and one line per tile

## B. Pages and faces

**HM4** Home is pages left to right, in the order `home.toml` lists them. Page 1
is the first page of tiles, and home opens on it. Left of it there are only
faces, by that definition; right of it faces and pages of tiles mix as listed,
as in Omalauncher, where only the left of page 1 is reserved. With no page of
tiles in the file, an empty one follows the last page (HM51).
→ a file listing tiles, a face, tiles reports `page 1 tiles`, `page 2 face`,
`page 3 tiles`

**HM5** A sideways drag on home turns the page, following the finger 1:1. On
release it settles on the nearer page, and a fling of `fling` (0.3 px/ms) or
more moves one page in its direction. This amends `gestures.md` D4. The strip's
sideways swipe still changes workspace (B), and the two edges are still back
and the overview (G, P), because those bands take touch ahead of home.
→ a 200px leftward drag on page 1 leaves `home report` on page 2; a sideways
swipe in the strip band still changes `hyprctl activeworkspace`

**HM5a** Nothing is built or torn down while a page moves -- under the finger
or settling after it. The page home lands on and its neighbours are built once
it has landed, without holding a frame where the engine allows, and a page
once built is kept.
→ after page turns across every page, `home report` says `built-moving=0`

**HM5b** While a page moves, OWL widgets draw at 1 frame a second, not 15, and
the page landed on starts its widgets only once it has landed. A turn that
comes back to the same page does not restart its widgets.
→ `home report` reads `moving=1 owl-fps=1` during a drag, `owl-fps=15` after

**HM5c** `home report` measures the page turns since the last `home stalls`:
the turns, the frames drawn per second while moving, the longest late tick of
a 16 ms timer, and how many ticks were 33 ms or more late. The timer runs only
while a page moves.
→ `omarchy-shell home stalls` prints and resets
`turns=N fps=F stall-max=Ms stalls33=K built-moving=B`

**HM6** Going home while already home returns to page 1. Going home from an app
lands on the page home was showing.
→ on page 2, `omarchy-shell gestures swipe home` leaves `home report` on page 1

**HM7** A face is one QML file whose root item declares `property var host`
and `property var shell`, which home sets the way the shell injects into a
plugin. It needs no base type, so a face in `~/.config/omarchy/faces/` does not
need to import anything of the package's. It takes the whole page between the
status bar and the strip, with no frame or background of its own, and draws on
the wallpaper. `face = "start"` loads
`~/.config/omarchy/faces/start.qml` if it exists, otherwise the packaged
`moarchy.home/faces/start.qml`. A name that resolves to neither is shown as one
line naming the file it looked for.
→ copying the packaged `start.qml` to `~/.config/omarchy/faces/` and editing
it shows the edit after `omarchy-shell home reload`

**HM8** One face ships, `start`: the time large, the date, the weather now, the
next calendar event and the battery. It is Omalauncher's `00-start` in this
phone's terms.

## C. Tiles

**HM9** A page of tiles is a grid of `[home] columns` columns (6 by default)
with square cells, so the row count follows from the page's height. A tile is a
widget at a cell rectangle (`x y w h`) and takes both its width and its height
from that rectangle. Home is the one host where W7's "the host gives width, the
widget gives height" becomes "the host gives both". `widgets.md` W7 says so in
place.
→ `home report` cell rects lie inside the grid and do not overlap

**HM10** A tile is framed the way Omalauncher frames one. The fill is the
theme's `background` at `[home] opacity` (0.88). The border is `[home] border`
px (2) in the theme's border colour. Tiles are `[home] gaps-in` px apart (6), and
the grid is `[home] gaps-out` px from the screen's edges (6). The prompt bar and
the recent strip wear the same frame. On home the host hands a widget
`container: "transparent"`, so a widget that draws its own card draws it
invisibly inside the frame and needs no change.
→ `scripts/style-check.sh` finds `border.width` in `moarchy.home/` only in `HomeFrame.qml`,
and in the files that draw over home rather than a tile: `HomeMenu.qml` (HM38),
`HomeArrange.qml` (HM42) and `HomeShare.qml` (HM46)

**HM10a** The frame's radius follows the user's `corners` preset, as
Omalauncher's follows its corners style. It is 16px times the preset's scale:
`square` 0 (Omarchy's look), `modest` 0.5 (8px) and `large` 1 (16px). That is
the same preset `style.md` D1 reads and the theme switcher writes, so home and
the sheets change together. D1 gains the frame as a row.
→ `moarchy-ui corners square` then `home report` gives `radius=0`; `large`
gives `radius=16`, with no restart

**HM11** Type is the theme's monospace face. A tile's label is lowercase in
`subdued`, its value is `foreground`, and an emphasis is `accent`, as in
Omalauncher's tiles. Colours come from the six roles (`style.md` C2), never
inline.
→ `style-check.sh`'s C2 and W4 checks pass over `moarchy.home/` and `widgets/`

**HM12** A widget that is not `available` (W6) keeps its cells, and the tiles
around it stay where they are. A grid that closed the gap would move every tile
under the user's thumb whenever music stopped. The frame says which widget rests
there (`now playing · nothing yet`, in `subdued`): left blank, it read on the
phone as a tile that had failed.
→ with nothing playing, `home report` shows `media available=0` at the same rect

**HM13** A widget that fails to load keeps its frame with a one-line error in
`subdued`, and the page and its other tiles keep working (W12 on a second host).
→ a widget file with a syntax error shows its frame, and `home report` shows
`error=` on that tile only

**HM14** The first home tiles are `today` (the date large, the weekday and month
beside it, the weather now and the next three days, as in Omalauncher's
screenshot), `fetch` (os, host, kernel, uptime, packages, shell, theme, memory,
disk and battery as label/value pairs), and the existing `media` and `calendar`.
`today` is a view of the Weather app's own cache, the way `calendar` is a view
of the Calendar app's file (W49). It never fetches by itself.

**HM14a** A tile can be the user's own: `widget = "<id>"` with no catalogued
widget of that id loads `~/.config/omarchy/widgets/<id>.qml`. That is how an
agent adds a tile: one file, plus one line in `home.toml`. It is not a directory
scan (W9). The layout names the file, so a stray file is never drawn.
→ a `clock.qml` written there and named in `home.toml` appears after
`home reload`; the same file not named in `home.toml` does not

**HM14b** Every control on a tile also drags home. Home hands widgets a `sheet`
(W13) whose `sheetPress`, `sheetMove` and `sheetRelease` feed home's router,
and the router decides once per touch: a page turn (sideways), the strip's sheet
(up) or the control center (down), with sideways winning ties as in B1. A touch
that never latched is a tap and reaches the control. `sheetWasDrag` keeps a
dragged control from also firing.

## D. The layout file

**HM15** Home's layout is `~/.config/omarchy/home.toml`: `[[page]]` blocks in
order, each holding either `face = "<name>"` or
`tiles = [ { widget = "<id>", x = 0, y = 0, w = 3, h = 4 }, ... ]`. This is
Omalauncher's `layout.toml`, reduced to what moarchy has, with no `app` or
`folder` tiles in this cut.
→ `moarchy-home show` prints the resolved pages

**HM16** Absent is not empty (W18). A missing file is the shipped layout, which
`/usr/share/moarchy/home.toml` documents line by line: the `start` face, then
`fetch` and `today` side by side over `media` and `calendar`. An unparseable file
leaves the previous layout on screen (the shipped one if there was none), is
never written over, and is named in `home report` as `layout-error=<line>: <why>`.
→ a `home.toml` with an unclosed `[` leaves the layout on screen and the file
byte-identical

**HM17** A tile off the grid, or overlapping one before it, takes the first free
spot at its size. A tile with no free spot left on its page is not drawn, and
`home report` names it `dropped=<id>`. An id that resolves to no widget and no
user file keeps its frame with `no widget "<id>"` in it. A silently missing tile
is the hardest thing for an agent to debug from outside.
→ `{ widget = "nope" }` shows its frame, and `home report` gives `missing=nope`

**HM18** A change to the file lands within a second with no restart.
→ changing a tile's `x` moves it, with `home report` agreeing and the shell's
pid unchanged

**HM19** `bin/moarchy-home` is the only program that writes `home.toml`:
`show`, `path`, `reset`, `add <widget> [page] [w h]`, `remove <widget>`. The
shell never writes it.

## E. The prompt bar

**HM20** The prompt bar sits at the bottom of every page of tiles, above the
strip, full width inside the grid margin and framed like a tile. It holds the
agent chip, then `open an app or ask <agent>…`, or `open an app…` while no
agent is chosen. There is no microphone, because the phone has no speech
recogniser. A face has no prompt bar; swiping up from it still opens the drawer.
`[home] prompt-bar = false` hides it.
→ `home report` says `prompt-bar=shown` on a page of tiles and `hidden` on a face

**HM21** Above the bar is the recent strip: one framed row of up to
`[home] recent` icons (8; 0 hides it). It shows the apps open now, most recently
focused first, and is not drawn while nothing is open -- but its room is kept,
as in Omalauncher, so the grid does not lose a row and move tiles whenever an
app opens. A tap focuses that app's window. It shows only what is open because
nothing on the phone counts launches: upstream's app library ranks by name and
match, not by use.
→ with foot and Settings open, `home report` lists `recent=` with both, the one
focused last first, and the same `rows=` as with nothing open

**HM22** On home the bar is a picture of a field. A tap on it raises the app
drawer with the drawer's field focused and the keyboard up, as Omalauncher's bar
opens its list when focused. Home never asks for keyboard focus. The drawer's
search field **is** the prompt bar. In this cut it stays where the search field
already is, at the top of the drawer, because its insets are `gestures.md` I4,
I5 and G14a. Moving it to the bottom is a follow-up with those criteria.
→ a tap on the bar leaves `app-drawer state` == `open` and the field focused

**HM23** In the drawer, typing narrows the grid as search always has. **Enter**
opens the first app when the text starts its name, the strong-match rule
Omalauncher's bar uses. Otherwise it asks the agent: `moarchy-agent ask
<text>` runs upstream's `omarchy-agent --prompt`, which owns every agent's flags,
in a terminal on a new workspace. The prompt is one argument end to end and
never passes through a shell string. With no agent chosen, `ask` opens the
agent picker, as the strip's hold does (C1).
→ `submit "foot"` launches foot; `submit "make the today tile show seconds"`
opens a window of app-id `org.omarchy.agent`; a prompt containing `"; rm -rf ~`
arrives intact

**HM24** The chip shows the agent in use (`settings.md` P17) by its command
name, in `accent`, and `agent` in `muted` while none is installed. A tap with
none installed opens Settings' coding agents page on its own (`settings.md`
P19). Otherwise it opens Omalauncher's agent menu above the bar
(`PromptBar.kt` `AgentsMenu`): a 2px `accent` frame on `background` at 16px
times the corner scale, lined up with the bar's start; one row per **installed**
agent, `●` and `accent` on the one in use, its name with its command under it
in `muted`; then a `muted` rule and `  manage agents…` in `muted`, which opens
that page on its own. Choosing one runs `moarchy-agent set <name>`. The choice
is upstream's `~/.config/omarchy/defaults/agent`: no second agent file, and
Settings, the strip's hold and the bar always agree. The menu and chip follow
an install or a removal within a second, by watching that file and mise's
`~/.config/mise/config.toml`.
→ with `claude` and `opencode` installed, the menu has exactly those two rows;
`moarchy-agent set opencode` and the chip reads `opencode` within a second

## F. The sheets a swipe raises

These are Omalauncher's **panels**. moarchy calls them **sheets**
(`naming-convention.md`), and this file does not add a second name.

**HM25** Swiping up on home raises the strip's sheet, following the finger:
`gestures.md` D1, unchanged.

**HM26** Swiping down on home raises the control center, following the finger
1:1 (D2a), entering from the top. This amends D4. Omalauncher's `controls.owl`
is the control center already: switches, volume, media, notifications.
→ a 300px downward drag on a page of tiles leaves `control-center state` == `open`

## G. Settings, for people and for agents

**HM27** Every setting that shapes the UI is in a TOML file under
`~/.config/omarchy/`, and each file has a packaged twin under
`/usr/share/moarchy/` that documents every key, its values and its default in
comments:

| file | holds | its one writer |
| --- | --- | --- |
| `ui.toml` | `[shape]` corners and radii, `[control-center]` sizes, `[gestures]` what each trigger opens, `[home]` the grid and its frame | `moarchy-ui` |
| `home.toml` | the pages, faces and tiles | `moarchy-home` |
| `widgets.toml` | which widgets a sheet shows, in order (`widgets.md` §D) | `moarchy-widgets` |
| `faces/<name>.qml`, `widgets/<id>.qml` | the user's own faces and tiles | nobody: they are hand- or agent-written |

Colours stay the theme's (`colors.toml`) and the agent stays upstream's
(`defaults/agent`).

**HM28** `ui.toml` is sectioned. Its keys are kebab-case inside `[shape]`,
`[control-center]`, `[gestures]` and `[home]`, and no key appears in two
sections. `corners` and `tile` keep their names, because `moarchy-keyboard`
reads them section-blind (its `parseUiToml`).
→ the packaged `ui.toml` parses with Python's `tomllib`, and
`scripts/style-check.sh` finds no key twice in it

**HM29** A file written before the sections, with flat `corners = …` and
`gesture_bottom = …` keys, reads exactly as it did. The first write through
`moarchy-ui` moves each flat key into its section and keeps every comment the
user wrote.
→ `scripts/ui-toml-test.sh` takes a flat file through `moarchy-ui gesture-right
none` and gets the sectioned file with the user's comment line intact

**HM30** One TOML reader serves the shell: `moarchy.common/Toml.js` reads
sections, arrays of tables, inline tables, strings, numbers and booleans, and
reports the line of the first error. `Ui.js`, `Widgets.js` and home read their
files through it. No surface keeps a parser of its own.
→ `node scripts/toml-test.js` passes, including a broken file it must reject with
the right line

**HM31** A writer edits the key it was asked about and leaves every other line,
comment and blank line where it was. `moarchy-ui set <section>.<key> <value>`
sets any key the packaged `ui.toml` documents and refuses one it does not,
naming the keys that exist.
→ `moarchy-ui set home.opacity 0.7` changes one line; `moarchy-ui set
home.opacty 0.7` exits 2 and lists `opacity`

**HM32** Agents are taught all of this by a skill, not by luck.
`/usr/share/moarchy/agents/skills/moarchy/` holds `SKILL.md` and its guides:
the settings files and their keys, writing a face, writing a tile, and the
commands that apply a change. First boot links it into `~/.agents/skills`,
`~/.claude/skills`, `~/.codex/skills` and `~/.pi/agent/skills`, beside
upstream's `omarchy` skill and the same way upstream links that one. A link the
user replaced with a directory of their own is left alone.
→ `readlink ~/.claude/skills/moarchy` names the packaged directory

## H. Debt this change retires

**HM33** `Ui.serialize` and `Ui.parseToml` are gone, in both copies of
`Ui.js`. Nothing called the first, because `moarchy-ui` is the writer, and the
second is now `Toml.js`. `Ui.merge` stays in the shell's copy for the theme
picker's optimistic chip, and carries every section now. The control-center keys
stop being spelled three ways (`controlCenter`, `control_center`,
`control_center_tile`) in the file anything writes. The flat spellings live only
in the two legacy readers (Ui.js `pick`, `moarchy-ui` `LEGACY`) (HM29).
→ `git grep -nE '(Ui|UiSpec)\.(serialize|parseToml)' default` matches nothing

**HM34** The PKGBUILD ships a kit's subdirectories by one rule (`widgets/`,
`faces/`) rather than one named copy per directory. `plugin-subdirs-do-not-ship`
is the failure that rule exists to end.
→ `pacman -Ql moarchy | grep -c 'moarchy.home/faces/start.qml'` is 1

## I. What must stay true

**HM35** Every criterion in `gestures.md`, `control-center.md` and `widgets.md`
still passes, except D4 and W7, which this file amends in place. `style.md` D1
gains the frame row.

**HM36** `naming-convention.md` gains **home**, **page**, **face**, **tile** and
**prompt bar**, and its picture shows them. This lands in the same commit as the
code.

## J. The home menu

Omalauncher's long press on empty home space (`HomeMenu.kt`): a card over a
scrim, with the way to Settings and a strip of themes drawn in their own
colours. A long press on a tile is §K's instead.

**HM37** A press on home held for 500ms without passing the slop opens the home
menu, anywhere that is not a tile: empty space, a face, the prompt bar, the
recent strip. On a tile it selects the tile (HM42). The number is
`gestures.md` C1's, because a phone has one hold. The release that ends the
hold is not a tap: nothing under the finger acts on it. A press that passes
the slop first is a swipe, exactly as before.
→ `moarchy-touch hold 360 1250 700` (empty space on page 1) leaves `home menu state` == `open`, and
`hyprctl clients` and the sheets' `state` are what they were before the hold

**HM38** The menu is Omalauncher's card (`HomeMenu.kt` `Menu`), centred on
home over a scrim of `background` at 90%: solid `background`, between 240 and
360px wide, a 2px `accent` frame at 20px times the corner scale (`frame`'s
16px stretched by 20/16, so `square` stays square), 8px inside. From the top:
the **create** row (HM53), with the **settings button** at its right end, a
44px round button on `containerHigh` with the gear in `accent`, which opens
Settings at its first page; `browse store` (owl.md OW7), a plain 15px row; the
**theme strip**; nothing else. A tap on the scrim closes it, as do the back
swipe and leaving home for an app.
→ a tap on the scrim, or `home menu close`, leaves `home menu state` == `closed`

**HM39** The theme strip is Omalauncher's `ThemeStrip`: over it `THEME` in
`accent` capitals, letter-spaced, and at the right the current theme's name in
`foreground` at 60%. Under them every installed theme as a 112px swatch drawn
in its own colours: its name in its `foreground` on its `background`, then
five 14x6 chips (`accent`, `red`, `yellow`, `green`, `magenta`), in a frame of
`muted` at 12px times the corner scale. The current theme's frame is 2px
`accent`, and the strip opens scrolled to it. The strip scrolls under the
card's padding to its frame. A tap applies the theme through
`omarchy-theme-set`, the way the theme picker does, and the menu stays open, so
the recolour is seen happen. While one applies its swatch says `applying…` and
other swatches ignore taps. The strip ends in `more themes ›`, a swatch of
`muted` chips on `containerHigh`, which opens the theme picker.
→ a tap on `Gruvbox`'s swatch leaves `current/theme.name` == `gruvbox` and the
strip's frame on it, without the menu closing

**HM40** One theme catalogue. The scan of every `colors.toml` and the call to
`omarchy-theme-set`, which `moarchy.themes` kept to itself, move to
`moarchy.common/ThemeCatalog.qml`, and the picker and the strip both use it.
→ `grep -l '"omarchy-theme-set"' default/omarchy/plugins/*/*.qml` (the command, not a
comment naming it) names ThemeCatalog.qml and no other file

**HM41** `omarchy-shell home menu state` answers `open` or `closed`, `home menu
open` and `home menu close` drive it, and `home report` ends with
`menu=open|closed`.

## K. Arranging tiles

Omalauncher's editing (`HomeGrid.kt`, `Home.kt`): a stock Android home screen's,
with Hyprland's swap. Every number below that is a time or a distance is
Omalauncher's.

**HM42** A long press on a tile (HM37's 500ms, no slop) selects it. If the same
finger then moves, it is carrying the tile (HM44) without letting go; if it lifts
where it was, the tile stays selected. Selected is **edit mode**: every cell of
the grid is outlined faintly, the tile wears a 3px `accent` frame with a handle
at the middle of each edge, and the **action bar** sits above it, lined up with
its left edge: below it where there is no room above, inside its top where there
is room on neither side.
→ `moarchy-touch hold` on the fetch tile, then lift: `home report` has
`edit=1:1 fetch`, and the Device screen did not open

**HM43** In edit mode every touch on home is the editor's, and nothing reaches a
tile, turns a page or pulls a sheet from home. The bottom strip and the edges
keep their gestures. A tap off the selected tile ends edit mode, as do the back
swipe and leaving home. The action bar's buttons take their own taps.
→ a tap on empty space leaves `edit=none`

**HM44** **Move.** A drag that starts inside the selected tile (or the lifted
one, HM42) carries it under the finger. An outline shows the cells it would land
on, snapped to the grid and kept clear of the others. Over another tile, that
tile is outlined instead, and the two trade places and sizes on release, as
windows swap in Hyprland. With nowhere to land it goes back. Held 600ms against
a side edge, the page turns; dropped on another page of tiles it moves there,
and onto a face's page it cannot go. A drag drops and ends edit mode; a long
press that never moved stays in it.
→ after dragging `media` onto `fetch`, `home report` has each at the other's
old rectangle, and `home.toml` says the same

**HM45** **Resize.** Pressing within 20px of the selected tile's frame (36px
inward at its sides, never more than a third of the tile in) drags that edge or
corner, snapped to the grid's lines. A tile is at least one cell each way, and
an edge that would grow into another tile or off the grid stops where it is.
Lifting keeps the tile selected.
→ dragging `today`'s bottom edge down two rows leaves it `3x6` in the report
and the file

**HM46** **The action bar:** `edit`, `share` and `remove`, in a frame of `accent`.
- `remove` takes the tile off its page; a user widget's file stays in
  `~/.config/omarchy/widgets/`, for `moarchy-home add` to bring back.
- `edit` asks the chosen agent, on a free workspace, as the prompt bar does
  (HM23). It names the widget's file and the moarchy skill. For a shipped
  widget it asks for a copy in `~/.config/omarchy/widgets/` first, put on this
  tile in its place, because the packaged file is not the user's to change.
- `share`, on a user's own widget only (a shipped one is on every moarchy
  phone), opens the share card: a QR code of the link, and `copy link`.
→ `remove` on `calendar` leaves no `calendar` in `home report` or the file

**HM47** **The link.** `https://simonschubert.github.io/omarchy-widgets/w#qml1.<id>.<data>`,
Omalauncher's shape (`Share.kt`) with its own prefix: `<id>` is the widget's id,
and `<data>` is the QML file's UTF-8 bytes, raw DEFLATE (no zlib header),
unpadded base64url. It sits after the `#`, so it reaches no server. A link longer than a QR code holds (2953 bytes)
still copies, and the card says the code could not be drawn. `moarchy-home
share <id>` prints the link; `moarchy-home import <link>` writes the widget to
`~/.config/omarchy/widgets/<id>.qml` (never over one that exists, unless
`--as <new-id>`) and prints the id.
→ `moarchy-home import "$(moarchy-home share clock)" --as clock2` gives a file
byte-identical to `clock.qml`

**HM48** Every arrangement is one write through `moarchy-home` (HM19):
`moarchy-home set <json>` replaces the pages. Afterwards the pages the edit
touched hold every tile's rectangle as it was seen, so the file and the screen
agree. The shell never writes `home.toml` itself.
→ `grep -c 'home.toml' moarchy.home/*.qml` finds it read, and written nowhere

**HM49** `omarchy-shell home edit <page>:<n>` selects the n-th tile of a page of
tiles (both 1-based, n as the file lists them), `home edit none` ends edit mode,
and `home report` has `edit=<page>:<n> <widget>` or `edit=none`.

**HM50** The geometry -- snapping to grid lines, which edges a press grabs, a
resize's clamp, where a carried tile would land and what it would swap with --
is pure functions in `Layout.js`, covered by `scripts/home-layout-test.js`
without a phone.

## L. Pages, and home's settings

Omalauncher's pages (`Home.kt`, `PagesScreen.kt`) and the home half of its style
screen (`StyleScreen.kt`): pages come and go as they fill and empty, two empty
ones always wait to be used, and Settings arranges them and sets how home looks.

**HM51** **Two pages wait, empty, and neither is in the file.**
- After the last page, an empty page of tiles: a tile carried there (HM44) or
  added for it (HM53) makes it a page in the file, and a new empty one follows.
  While empty it says `no widgets on this page · long-press for a new one`.
- Left of the leftmost page, the **face invite**: a card reading `a face of
  your own` with `create with <agent>` (HM53's face).
→ with the shipped file, `home report` lists `page -1 invite`, `page 0 face`,
`page 1 tiles`, `page 2 spare`; `moarchy-home show` lists neither waiting page

**HM52** A page exists while it holds something. An arrangement that empties a
page of tiles takes the page away, except the last page of tiles, which stays
as page 1 however empty it is. Pages moving under the one on screen leave it on
screen: home looking at page 1 is still on page 1 after Settings reorders them,
and otherwise on the page it was looking at, wherever that went.
→ moving page 2's only tile to page 1 leaves no page 2 in the file

**HM53** The home menu (HM38) opens on Omalauncher's first row: `create with
<agent>` and, right under it, `[ widget ]` `[ face ]` in `accent`, the first
bracket lined up with the label. Each asks the chosen agent, on a free
workspace, with the moarchy skill: `widget` for a new widget on the page the
menu was opened on, `face` for a new face left of the others. The face invite
asks for a face the same way.

**HM54** **Settings › Appearance › Home** holds what Omalauncher's style screen
holds for home, each a stepper (HM55) reading `moarchy-ui get` and writing
`moarchy-ui set`, so it lands on home within a second (HM18):
`columns` (2–12), `gaps in` (0–24 px), `gaps out` (0–48 px), `border` (0–8 px),
`opacity` (0–100 %, in fours), `recent apps` (0–12, 0 hides the strip); then a
switch, `prompt bar`; and **Pages** (HM56) first of all.
→ `+` on columns with 6 leaves `moarchy-ui get home.columns` == 7 and
`home report` at `columns=7`

**HM55** A **stepper** row: the label, then `−`, the value in its unit, `+`, each
button a 44px target. A tap writes the next value straight away and the row
reads it back (the write is the truth, as for a switch). At either end of its
range that button is dimmed and does nothing.

**HM56** **Settings › Appearance › Home › Pages** lists the pages in the file's
order, without the waiting ones: a face by its name, tagged `face`; a page of
tiles by its widgets (`fetch, today, media, calendar`), tagged `home` on page 1.
Each row has a handle, `≡`, at its leading edge: dragging it moves the row, the
neighbour it passes the middle of trades places with it, and letting go writes
the new order with `moarchy-home set`. A face row offers `edit` (the agent, a
shipped face copied to the user's own first); every row offers `remove`, which
asks first and names what goes; the only page of tiles has no `remove`.
→ dragging the `start` row below the tiles row leaves `home.toml` listing tiles
then the face, and home opening on that page of tiles

**HM57** `moarchy-home json` prints the pages as written, as JSON in `set`'s
shape, so Settings and an agent read the layout the way the writer will take it
back.

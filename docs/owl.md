# OWL widgets on home, and the store

Omalauncher's widgets are OWL files, from a reviewed store
([omarchy-widgets](https://github.com/SimonSchubert/omarchy-widgets)). That repo
also has a Quickshell runtime for them, `runtimes/quickshell`, and this file is
how moarchy runs it on home and installs from the store the way Omalauncher does
(`Market.kt`, `StoreScreen.kt`).

Widgets only, for now: the store's faces and apps are a later change, and a
`face` in `home.toml` is still a QML file (`home.md` HM7).

Words: an **OWL widget** is a `.owl` file; a **native widget** is a QML one
(`widgets.md`). Both are **tiles** on home (`home.md` §C).

## A. Running OWL on home

**OW1** The runtime is omarchy-widgets' `runtimes/quickshell` at the commit
`manifest.toml` pins under `[omarchy-widgets]`, unpatched. The moarchy package
installs it as the kit `/usr/share/moarchy/plugins/moarchy.owl/`. moarchy's side
of it is its host, `moarchy.home/HomeOwlHost.qml`, and nothing else.
→ `pacman -Ql moarchy | grep -c 'moarchy.owl/Owl.js'` is 1, and that file is
byte-identical to the pinned commit's

**OW2** A tile names an OWL widget as it names any widget, `widget = "<id>"`,
and the id resolves in this order: the catalogue's native widgets, then
`~/.config/omarchy/widgets/<id>.qml`, then `~/.config/omarchy/widgets/<id>.owl`.
→ with only `clock.owl` in that folder, `{ widget = "clock" }` draws it and
`home report` says `owl`

**OW3** An OWL tile wears home's frame (HM10) and draws inside it at the
widget's own padding, in the current theme's colours (`colors.toml`, read the
way the runtime's `shell.qml` reads it). Its scale is Omalauncher's: one cell
and gap of home's grid is the launcher's 69 dp.

**OW4** An OWL widget runs -- its sources, its triggers, its animation clock --
only while home is on screen and its page is the one showing. Behind an app,
or two pages away, nothing in it runs. It animates at 15 frames a second
(`OwlHost.frameRate`).
→ with a window over home, an OWL tile's process ticks stay where they were
for 30s

**OW5** Touch on an OWL tile is the widget's for taps and home's for
everything else: a drag that starts on it turns the page or pulls a sheet
(HM14b), a long press selects it (HM42), and the release after either is not a
tap on the widget.

**OW6** A widget that does not compile keeps its frame with the runtime's error
in it (HM13), and `home report` gives `state=error` and the first line.

## B. The store

**OW7** The store is Omalauncher's `store` panel (`StoreScreen.kt`), drawn in
the Settings window as the page **Settings › Appearance › Home › Widgets**, with
a header of its own in place of Settings': the title `store` in `accent` at
title size, then at the right a refresh button (`moarchy-owl catalog
--refresh`, `accent` while it runs) and, when the store is on its own, a red
`✕`. The home menu's `browse store` (HM38) opens it on its own.

**OW7a** **Back.** Opened on its own, the store is the whole of Settings' stack:
`✕`, the back swipe and Escape close the window, which leaves home on screen,
never a page of Settings. Reached from Settings, its title reads `‹ store` and
back goes to the page it came from. On a widget's page the title is `‹ <name>`,
and back, either way, goes to the grid first.
→ after `browse store`, `omarchy-shell settings stack` prints
`appearance.home.widgets` alone, and `settings back` answers `closed`; after
`settings openAt appearance.home` and a tap on `Widgets`, `settings back`
answers `appearance.home`

**OW8** The catalogue is the store's `index.json`, read by
`moarchy-owl catalog` from
`https://simonschubert.github.io/omarchy-widgets/index.json` and kept in
`~/.cache/moarchy/owl/index.json`, used for an hour. Offline, the cache is used
however old it is and the store says how old; with no cache it says it could
not reach the store.

**OW9** The store lists the widgets as a two-column grid of cards, each framed
in 1px of `muted` with no fill, at 12px times the corner scale: the preview,
104px high, drawn in the current theme (the entry's `themes[<slug>]`, else its
`preview`; the name on `containerHigh` until one loads), the name, a `new`
badge beside it while the catalogue says so, and one status line --
`✓ installed` in `green`, `update available` in `accent`, `needs a newer
runtime` in `red`, else `<category> · <w>x<h>` in `muted`. Above them, a search
field (name, description, author) reading `search <n> widgets`; under it the
chips, each `<name> <count>`, outlined, the chosen one in `accent` over 15%
`accent`: `all`, `new`, then each category the catalogue has, the biggest
first, then `installed`, which adds `· <n>↑` while updates wait; then the
caption `reviewed widgets from github.com/SimonSchubert/omarchy-widgets`.

**OW10** A card opens the widget's page: the preview large, the name at title
size with its `new` badge,
`category · author · v<version> · <license> · <w>x<h>` in `muted`, the
description, **what it installs** (`installs packages: none`, or each package
marked `✓` installed or `✗` not), **what it runs** (`runs no commands`, or
`runs these commands:` and each line of `commands` in a code block on
`containerHigh`), and then one bracket action in `accent`: `[ add to home ]`
(to the page OW11 picks), `[ update <a> → <b> ]`, or nothing but
`needs a newer runtime (owl <n>)` in `red` when its `owl` is above the
runtime's. An installed one says `✓ on your home screen` in `green` and has
`[ remove ]` in `red`.

**OW10a** An install that went through with nothing to say closes the store and
shows home, the new tile on its page, as Omalauncher's does. One that said
something -- packages that did not install (OW11 step 4), a failure -- stays on
the widget's page with what it said under the button.

**OW11** **Install** is `moarchy-owl install <id> [page]`:
1. the file is downloaded and its SHA-256 checked against the catalogue; a
   mismatch installs nothing;
2. it is written to `~/.config/omarchy/widgets/<author>-<name>.owl`;
3. what was approved -- id, version, `commands`, `requires`, the file's SHA-256
   -- is recorded in `~/.config/omarchy/widgets/.market.json`;
4. missing pacman packages are installed (`sudo pacman -S --needed`), and a
   failure says which and leaves the widget installed;
5. a tile at the entry's size goes on page `<page>` -- by default the page home
   is showing, or page 1 when that is a face -- if it has room for it, else on
   the next page that has, else on a new page after the last: Omalauncher's
   rule, and an install is never a tile dropped for want of room (HM17).
   `omarchy-shell home room <page> <w> <h>` answers which page that is.
→ after `moarchy-owl install simonschubert/calendar`, `home report` has an
`owl` tile `simonschubert-calendar`

**OW12** **Approval.** What a widget runs and needs is on its page before the
button that installs it. An update whose `commands` or `requires` differ from the
ones recorded says `its commands or packages changed since the version you
approved` above a button reading `update anyway`.

**OW13** **Edited.** A file whose SHA-256 is no longer the one recorded was
changed since it was installed -- by the user or their agent -- and its update
says `your changes to it go` before replacing it.

**OW14** **Remove** deletes the file and its record, and takes its tiles off
home.

**OW15** `moarchy-owl` is the one writer of `.market.json` and of the `.owl`
files it installs, as `moarchy-home` is of `home.toml`, and the moarchy skill
teaches it: `catalog`, `show <id>`, `install <id> [page]`, `update <id>`,
`remove <id>`, `installed`.

## C. What it needs

**OW16** WebP previews need Qt's WebP plugin: `moarchy-meta` depends on
`qt6-imageformats`.

**OW17** `scripts/test-owl.sh` runs `moarchy-owl` against a catalogue served from
a local folder, without the network: an install writes the file, the record and
the tile; a wrong SHA-256 installs nothing; an update that changes `commands` is
marked; an edited file is marked; remove leaves nothing behind.

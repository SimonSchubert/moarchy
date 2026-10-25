---
name: moarchy
description: >
  REQUIRED for customizing a moarchy phone (Omarchy on a Linux phone): its home
  screen, tiles/widgets, faces, the prompt bar, gestures, corners, the control
  center, and any file under ~/.config/omarchy/ that shapes the phone's UI
  (ui.toml, home.toml, widgets.toml, faces/, widgets/). Use it with the omarchy
  skill, which covers themes, Hyprland and the rest of Omarchy.
---

# moarchy

This phone runs moarchy: Omarchy's look and its quickshell shell, made for a
touch screen. Its home screen is pages of **tiles** (widgets) on a grid, with
**faces** (whole-page screens) to the left of page 1. At the bottom is the
**prompt bar**, which opens an app or asks you, the coding agent. Swiping up
opens the app drawer, and swiping down opens the control center.

Everything a person can change about that is in a TOML or QML file under
`~/.config/omarchy/`, and a change lands within a second with no restart. Read
the guide for the job before you start:

- [`settings.md`](settings.md): every settings file, every key, and the commands
  that change them
- [`home.md`](home.md): writing a tile or a face, and checking it on the phone

## The files

| file | what it holds | change it with |
| --- | --- | --- |
| `~/.config/omarchy/ui.toml` | `[shape]` corners, `[control-center]` sizes, `[gestures]` what each swipe and hold opens, `[home]` the grid and the tile frame | `moarchy-ui set <section>.<key> <value>`, or edit it |
| `~/.config/omarchy/home.toml` | home's pages: faces, and tiles at grid positions | `moarchy-home add/remove/face`, or edit it |
| `~/.config/omarchy/widgets.toml` | which widgets the control center shows, in order | `moarchy-widgets` |
| `~/.config/omarchy/widgets/<id>.qml` | a tile you wrote | write it, then name it in home.toml |
| `~/.config/omarchy/faces/<name>.qml` | a face you wrote | write it, then name it in home.toml |
| `~/.config/omarchy/defaults/agent` | which coding agent the prompt bar asks | `moarchy-agent set <name>` |

Colours are the Omarchy theme's (see the omarchy skill), never hex in these
files.

## Rules

- **Never edit `/usr/share/moarchy/`.** The package owns it and the next update
  overwrites it. Do read it: `/usr/share/moarchy/ui.toml` and
  `/usr/share/moarchy/home.toml` document every key, and
  `/usr/share/moarchy/plugins/moarchy.common/widgets/` holds the shipped widgets
  to learn from.
- **Prefer the commands for settings.** `moarchy-ui set` refuses a key that does
  not exist and names the ones that do, so a typo fails loudly rather than
  changing nothing. Hand edits are fine too; keep the sections.
- **Check your work on the phone.** `omarchy-shell home report` says what home
  actually drew: every tile, whether it loaded, and the line of any error in
  home.toml. A tile that went wrong keeps its frame and says why, so look before
  you say it works.
- **A QML file you write is code the shell runs.** It gets no network or shell
  access beyond what QML gives it. Keep commands in it constant and never build
  them from text.

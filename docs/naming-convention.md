# Naming convention

One name per part of the screen, and one per kind of thing on it. Orientation
in the sense [`README.md`](README.md) sets out: no criteria and no rationale —
every part names the document that governs it, and that document wins.

The point of writing the names down as a picture is that a second name for one
surface is how two documents start contradicting each other. The definitions
are [`README.md`](README.md#words-used-precisely)'s *Words used precisely*;
this is where they sit on the glass. [`README.md`](README.md#the-code) is the
third view of the same set: which file draws each one.

## The screen

```
                       swipe down = the control center
                                      |
                                      v
                    +-----------------------------------+
                    | 9:41                    wifi  82% |  status bar, reserved
                    +-----------------------------------+
                    |                                   |
                    |                                   |
  left-edge swipe > |                                   | < right-edge swipe
   = back           |             workspace             |   = the workspace overview
                    |                                   |
                    |                                   |
                    +-----------------------------------+
                    |               ______              |  the strip, 20px, reserved
                    +-----------------------------------+
                                      ^
                                      |
                          swipe up = the app drawer
```

| Part | Owned by | Governed by |
| --- | --- | --- |
| status bar | `moarchy.bar` | [`style.md`](style.md) |
| the strip, and the home pill on it | `moarchy.gestures` | [`gestures.md`](gestures.md) §A, §I |
| left-edge swipe — back | `moarchy.gestures` | [`gestures.md`](gestures.md) §G |
| right-edge swipe — the workspace overview | `moarchy.gestures` | [`gestures.md`](gestures.md) §P |
| down from the status bar — the control center | `moarchy.control-center` | [`control-center.md`](control-center.md), [`gestures.md`](gestures.md) Q7 |
| up from the strip — the app drawer | `moarchy.app-drawer` | [`gestures.md`](gestures.md) §A, §N |
| the workspace, and the window on it | the compositor | [`windows.md`](windows.md) |

One name per part, in three spellings, and they are the same name: prose for a
sentence, kebab for anything a machine parses, and the label a thumb reads.

| part | plugin id · IPC target · `ui.toml` word | Settings label |
| --- | --- | --- |
| the control center | `moarchy.control-center` · `control-center` | **Control Center** |
| the app drawer | `moarchy.app-drawer` · `app-drawer` | **App drawer** |
| the minimal app drawer | `moarchy.app-drawer-minimal` · `app-drawer-minimal` | **Minimal app drawer** |
| the workspace overview | `moarchy.workspace-overview` · `workspace-overview` | **Workspace overview** |
| the status bar | `moarchy.bar` · `bar` | **Status bar** |
| the strip | `moarchy.gestures` · `gestures` | no label of its own — *Press and hold the strip* |

The kebab spelling is not a second name. It is the one form an id, an IPC
target and a hand-edited `ui.toml` can all hold, and `Sheet.js` is the only
place it is written down (`refactor.md` I2). An IPC *verb* is a QML function
name and stays camelCase — `omarchy-shell control-center dragTrace` is one of
each.


Two of the four swipes are a setting rather than a fact: what the strip raises
and what the right-edge swipe raises are each named by `gesture_bottom` and
`gesture_right` in `~/.config/omarchy/ui.toml`, and either can be `none`, `app
drawer`, `minimal app drawer`, `workspace overview` or `control center`
([`gestures.md`](gestures.md) Q1). The app drawer and the workspace overview
are the pairing that ships, so that is what the picture shows. The control center keeps its grab band
whichever edge it is also set on (Q7).

## Home

What an empty workspace shows ([`home.md`](home.md)). Omalauncher's home screen,
in its own words where moarchy had none, and in moarchy's where it had one.

```
   faces  <-  swipe  ->  pages of tiles
   +-------------------+ +-------------------+
   | 9:41      wifi 82%| | 9:41      wifi 82%|  status bar
   |                   | | +------+ +------+ |
   |      12:30        | | | fetch| | today| |  tiles, on the grid
   |   saturday 25     | | |      | |      | |
   |   [ today ]       | | +------+ +------+ |
   |   [ calendar ]    | | +---------------+ |
   |                   | | |    media      | |
   |   a face          | | +---------------+ |
   |                   | | [ o  o  o       ] |  the recent strip
   |                   | | [claude⌄ open...] |  the prompt bar
   +-------------------+ +-------------------+
                               ^ page 1, where home opens
```

| Part | What it is | Governed by |
| --- | --- | --- |
| **home** | what is drawn on an empty workspace: pages, faces, the recent strip, the prompt bar. Drawn on `moarchy.gestures`' Bottom-layer surface by the kit in `moarchy.home/`; IPC target `home` | [`home.md`](home.md) §A |
| **page** | one screenful of home, turned by a sideways swipe. **Page 1** is the first page of tiles | [`home.md`](home.md) §B |
| **face** | a whole page drawn by one QML file, left of page 1 — Omalauncher's word | [`home.md`](home.md) HM7 |
| **tile** | a widget at a cell rectangle on a page, in a frame. A tile *is* a widget; the word says where it is | [`home.md`](home.md) §C, [`widgets.md`](widgets.md) |
| **prompt bar** | the field that opens an app or asks the coding agent: on home a picture of one, in the app drawer the live one. Never "bar", which is the status bar's IPC target | [`home.md`](home.md) §E |
| **recent strip** | the row of open apps above the prompt bar | [`home.md`](home.md) HM21 |
| **home menu** | what a long press anywhere on home opens: Settings, and the theme strip. Not "context menu", which is the kit's per-row menu | [`home.md`](home.md) §J |
| **OWL widget** | a widget written in OWL, Omalauncher's language: a `.owl` file, from the store or the user's own, drawn by `moarchy.owl`. A **native widget** is a QML one | [`owl.md`](owl.md) |
| **the store** | omarchy-widgets' reviewed catalogue, browsed in Settings › Appearance › Home › Widgets and installed by `moarchy-owl`. Not the App Store, which is `moarchy-store` and installs apps | [`owl.md`](owl.md) §B |
| **edit mode** | a tile selected by a long press: its frame and handles, the grid's guides, the action bar. Every touch on home is the editor's until it ends | [`home.md`](home.md) §K |
| **action bar** | `edit`, `share`, `remove`, over the selected tile. Not the app bar, which is a shell app's title row | [`home.md`](home.md) HM46 |
| **face invite** | the empty page waiting left of the leftmost: `a face of your own`, and the agent makes one | [`home.md`](home.md) HM51 |
| **spare page** | the empty page of tiles waiting after the last; a tile put there makes it a page | [`home.md`](home.md) HM51 |
| **stepper** | a Settings row with `−` value `+` | [`home.md`](home.md) HM55 |
| **theme strip** | every installed theme as a swatch in its own colours, in the home menu; one tap applies one | [`home.md`](home.md) HM39 |

Omalauncher's **panels** are this project's **sheets**: its drawer is the app
drawer, its `controls.owl` is the control center. There is no second word.

## What quickshell draws

Four kinds of thing, and which kind something is decides where it can appear,
what puts it away, and whether it can be dismissed at all.

```
  +----------------------------- quickshell --------------------------------+
  |                                                                         |
  |  SHEETS  dismissed, not left     APPS  a window on a workspace          |
  |          running                                                        |
  |    the control center              Settings   Wi-Fi   Bluetooth   SIM   |
  |    the app drawer                  Clock   Calendar   Phone   Messages  |
  |    the minimal app drawer          Files   Weather   Mail   + 11 more   |
  |    the workspace overview                                               |
  |    the theme picker                                                     |
  |                                                                         |
  |  WIDGETS  inside a surface someone else owns                            |
  |    the media card in the control center; the weather, the next          |
  |    meeting                                                              |
  |                                                                         |
  |  ALWAYS THERE  reserved or invisible, never dismissed                   |
  |    the status bar . the strip . the left edge . the right edge          |
  +-------------------------------------------------------------------------+
```

| Kind | What makes it one | Where the rule is |
| --- | --- | --- |
| **sheet** | Full-screen, and put away rather than left running. Opening one puts away every sheet on its own layer or above it, and none below | [`README.md`](README.md#how-the-screens-stack), `moarchy.common/Sheet.js` |
| **app** | A window on a workspace, owned by the compositor. Four of them are screens this shell draws itself — a **shell app** — and every criterion about apps still applies to them | [`windows.md`](windows.md), [`apps.md`](apps.md), [`gestures.md`](gestures.md) K |
| **widget** | Not a surface at all: content inside one that something else owns. It has no gesture, no layer and no way in of its own — and which of them a surface draws, in what order, is the user's | [`widgets.md`](widgets.md) |
| **always there** | Reserved off every window, or invisible and taking touch ahead of one. Nothing dismisses these. An **edge** is the band; a **left-edge** or **right-edge swipe** is the gesture it takes | [`gestures.md`](gestures.md) §I, [`style.md`](style.md) |

**widget** was a kind this document named and nothing ratified, with one
instance: the media card in the control center. [`widgets.md`](widgets.md)
ratifies it. There are six, they live in `moarchy.common/widgets/`, they carry
no manifest and no plugin id, and the arrangement — which of them a surface
draws and in what order — is a line in `~/.config/omarchy/widgets.toml`.

It is still not upstream's `bar-widget`, which is a manifest kind for a tile in
the desktop bar this phone replaces
([`control-center.md`](control-center.md)) — nothing here instantiates one.

## Where a widget goes

A widget is placed by the surface that hosts it, so its home is a row in
somebody else's layout:

```
   the control center  (a sheet)
   +-------------------------------+
   |  clock . date . gear . power  |  header
   |  [ now playing      < || > ]  |  media      <- a widget
   |  notification . notification  |  history
   +-------------------------------+
```

The widget decides nothing about its own position. That is the whole difference
between this kind and the other three — and the two things that *do* decide are
different from each other: the **user** says whether the row is there and where
it sits in the order ([`widgets.md`](widgets.md) §D), and the **widget** says
whether it has anything to draw at all, which is how the media card is absent
rather than empty while nothing is playing
([`control-center.md`](control-center.md) S16, `widgets.md` W6).

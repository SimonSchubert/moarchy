# Naming convention

One name per part of the screen, and one per kind of thing on it. Orientation in
the sense [`README.md`](README.md) sets out: no criteria and no rationale — every
part names the document that governs it, and that document wins.

The point of writing the names down as a picture is that a second name for one
surface is how two documents start contradicting each other. The definitions are
[`README.md`](README.md#words-used-precisely)'s *Words used precisely*; this is
where they sit on the glass. [`README.md`](README.md#the-code) is the third view
of the same set: which file draws each one.

## The screen

```
                           swipe down = the shade
                                      |
                                      v
                    +-----------------------------------+
                    | 9:41                    wifi  82% |  status bar, reserved
                    +-----------------------------------+
                    |                                   |
                    |                                   |
  left-edge swipe > |                                   | < right-edge swipe
   = back           |             workspace             |   = the overview
                    |                                   |
                    |                                   |
                    +-----------------------------------+
                    |               ______              |  the strip, 20px, reserved
                    +-----------------------------------+
                                      ^
                                      |
                            swipe up = the drawer
```

| Part | Owned by | Governed by |
| --- | --- | --- |
| status bar | `moarchy.bar` | [`style.md`](style.md) |
| the strip, and the home pill on it | `moarchy.gestures` | [`gestures.md`](gestures.md) §A, §I |
| left-edge swipe — back | `moarchy.gestures` | [`gestures.md`](gestures.md) §G |
| right-edge swipe — the overview | `moarchy.gestures` | [`gestures.md`](gestures.md) §P |
| down from the status bar — the shade | `moarchy.shade` | [`shade.md`](shade.md), [`gestures.md`](gestures.md) Q7 |
| up from the strip — the drawer | `moarchy.drawer` | [`gestures.md`](gestures.md) §A, §N |
| the workspace, and the window on it | the compositor | [`windows.md`](windows.md) |

A part's short name here is not always the words the phone shows. Both are
fixed, and neither is a mistake for the other — the short name is what an id, a
document and an IPC verb use, the label is what a thumb reads:

| part | this document | what Settings shows |
| --- | --- | --- |
| the shade | the shade | **Notification shade** |
| the drawer | the drawer | **App drawer** |
| the overview | the overview | **Overview** |
| status bar | the status bar | **Status bar** |
| the strip | the strip | no label of its own — *Press and hold the strip* |

Changing one does not change the other. `moarchy.shade` presents as
"Notification shade" the way `moarchy.editor` presents as "Text Editor".

Two of the four swipes are a setting rather than a fact: what the strip raises
and what the right-edge swipe raises are each named by `gesture_bottom` and
`gesture_right` in `~/.config/omarchy/ui.toml`, and either can be `none`,
`drawer`, `overview` or `shade` ([`gestures.md`](gestures.md) Q1). The drawer
and the overview are the pairing that ships, so that is what the picture shows.
The shade keeps its grab band whichever edge it is also set on (Q7).

## What quickshell draws

Four kinds of thing, and which kind something is decides where it can appear,
what puts it away, and whether it can be dismissed at all.

```
  +----------------------------- quickshell --------------------------------+
  |                                                                         |
  |  SHEETS  dismissed, not left     APPS  a window on a workspace          |
  |          running                                                        |
  |    the shade                       Settings   Wi-Fi   Bluetooth   SIM   |
  |    the drawer                      Clock   Calendar   Phone   Messages  |
  |    the overview                    Files   Weather   Mail   + 11 more   |
  |    the theme picker                                                     |
  |                                                                         |
  |  WIDGETS  inside a surface someone else owns                            |
  |    the media card in the shade; the weather, the next meeting           |
  |                                                                         |
  |  ALWAYS THERE  reserved or invisible, never dismissed                   |
  |    the status bar . the strip . the left edge . the right edge          |
  +-------------------------------------------------------------------------+
```

| Kind | What makes it one | Where the rule is |
| --- | --- | --- |
| **sheet** | Full-screen, and put away rather than left running. Opening one puts away every sheet on its own layer or above it, and none below | [`README.md`](README.md#how-the-screens-stack), `moarchy.common/Sheet.js` |
| **app** | A window on a workspace, owned by the compositor. Four of them are screens this shell draws itself — a **shell app** — and every criterion about apps still applies to them | [`windows.md`](windows.md), [`apps.md`](apps.md), [`gestures.md`](gestures.md) K |
| **widget** | Not a surface at all: content inside one that something else owns. It has no gesture, no layer and no way in of its own | — |
| **always there** | Reserved off every window, or invisible and taking touch ahead of one. Nothing dismisses these. An **edge** is the band; a **left-edge** or **right-edge swipe** is the gesture it takes | [`gestures.md`](gestures.md) §I, [`style.md`](style.md) |

**?** **widget** is a kind this document names and nothing ratifies yet. One
exists: the media card in the shade. It is not upstream's `bar-widget`, which is
a manifest kind for a tile in the desktop bar this phone replaces
([`shade.md`](shade.md)) — nothing here instantiates one.

## Where a widget goes

A widget is placed by the surface that hosts it, so its home is a row in
somebody else's layout:

```
   the shade  (a sheet)
   +-------------------------------+
   |  clock . date . gear . power  |  header
   |  [ now playing      < || > ]  |  media      <- a widget
   |  notification . notification  |  history
   +-------------------------------+
```

The host decides whether the row is there at all — the media card appears only
while something is playing ([`shade.md`](shade.md) S16) — and the widget decides
nothing about its own position. That is the whole difference between this kind
and the other three.

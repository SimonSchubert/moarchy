# Notification shade — specification

What the pull-down from the top edge shows and what each control does. Present
tense, normative. The archaeology lives in `docs/build-log.md`.

**How the shade opens, closes and is dismissed is not here** — it is a gesture,
and it belongs to `docs/gestures.md` (A8, G1–G3, H2, H5). Restating those
would give us two specs to disagree with each other. This file is the contents.

Lines marked **?** are my reading of the code, not your decision. Read those
first — the rest is a description of what is already there.

Ids are `S<n>`, cited by any check that proves one.

## Layout, top to bottom

| | |
| --- | --- |
| header | clock, date, gear, power |
| wide tiles | Wi-Fi, Bluetooth |
| small tiles | Silent, Airplane, Torch, Rotate |
| sliders | brightness, volume |
| media | title and transport, when something is playing |
| notifications | history, newest first, with a clear-all |

The sheet is 90% of the screen height below the gesture strip. Everything
scrolls only in the notification list; the rest is fixed.

## S1–S3. Header

**S1** The clock reads `H:mm` and the date `dddd d MMMM`, updating once a
minute. The sheet covers the status bar, so the time has to reappear here —
losing it is the one thing a phone user would notice immediately.

**S2** The gear opens the settings list and closes the shade on the way.
Everything the Omarchy menu reaches that is not an app lives there.

**S3** The power button opens Settings at its Power page and closes the shade on
the way. It used to summon the Omarchy menu at its `system` route; that menu is
a popup with no tap-outside dismiss in this port, since `install/port-4x.sh`
stubs out `HyprlandFocusGrab`, so it was a trapdoor. Lock, Suspend, Log out,
Restart and Power off are native rows now — see `docs/settings.md`.

## S4–S5. Wi-Fi and Bluetooth

**S4** The Wi-Fi tile is lit when Wi-Fi is enabled and a tap toggles it. Its
second line reads, in order of preference: `Off`, the connected network's name,
`Connected`, or `Not connected`.

**S5** The Bluetooth tile is lit when the adapter is enabled and a tap toggles
it. Its second line reads `No adapter`, `Off`, the connected device's name, or
`On`.

**? S6** Neither tile does anything but toggle. A long press does not open the
network or device picker.
— confirm: the picker is reachable from the gear, so this may be deliberate.
Android puts it on a long press.

## S7–S10. Small tiles

**S7** Silent toggles do-not-disturb.

**S8** Airplane runs `rfkill block all` / `unblock all` and re-reads the real
state 700ms later rather than trusting its own write.

**S9** With airplane on, the Wi-Fi and Bluetooth tiles show as off, because
`rfkill all` covers them. Tapping one turns that radio on **and clears airplane
mode** — the two are never left contradicting each other on screen.

Only that radio is unblocked, not all of them: airplane mode is read as "every
rfkill switch is blocked", so freeing one clears the state by itself, and
tapping Wi-Fi does not quietly switch Bluetooth back on. The radio is enabled
~700ms later, once the unblock has landed, because NetworkManager refuses to
enable an interface rfkill still has blocked.

**S10** Torch is **absent, not disabled**, when the device has no flash LED:
the row divides its width by what is actually shown, three tiles or four. When
present it writes the LED directly.

**S11** Rotate toggles `normal ↔ 90` — portrait and one landscape. Not a cycle
through all four transforms: this is a portrait phone, so 180 is upside-down
and 270 the other landscape, and cycling put both on the route to the one
orientation anybody wants.

## S12–S14. Sliders

**S12** Brightness commits **on release**, not while dragging, because each
write forks `brightnessctl`. Volume commits **live**, because it is in-process
and free.

**S13** Brightness never goes below 1%. The screen is the only way to see
anything, and a slider that reaches zero is a device you cannot recover without
a keyboard.

**S14** The volume slider is hidden entirely when there is no audio sink, not
shown disabled.

**? S15** Tapping anywhere on a slider jumps the value to that point rather
than requiring a drag from the handle.
— confirm: right for a phone, and it is why a vertical drag starting on a
slider has to hand the gesture over and *put the value back* (see
`gestures.md` H2).

## S16–S17. Media

**S16** The media card appears only when something is playing, showing the
title and the transport actions the player advertises.

**? S17** The card shows the title only — no artist, no album art.
— confirm: art would mean decoding an image per track on a Mali-400, which is
the cost that ruled out theme previews.

## S18–S20. Notifications

**S18** History is newest first, one card per notification, each dismissable on
its own.

**S19** A clear-all removes every notification, both the live popups and the
history.

**S20** The list is the only scrolling region on the sheet, and while it can
scroll it keeps vertical drags — the shade must never close out from under
someone reading it (`gestures.md` H5). When it fits, it gives that space back.

**? S21** With no notifications the list is simply empty — no "no
notifications" placeholder, and no change to the sheet's height.
— confirm: the sheet is a fixed 90%, so an empty list leaves a large blank
area below the sliders.

---

## Constraints

- **The shade covers the whole screen and reserves nothing.** Growing it with
  an exclusive zone would reflow every tiled window at 60Hz for the length of
  the drag.
- **It takes no keyboard focus**, so a tap on a tile and a flick back up leaves
  you exactly where you were.
- **The bar underneath has no tap targets** and cannot have any: the shade's
  grab strip is on Overlay and covers the bar's top band, so a button there
  would never receive a touch and the cause would not be anywhere near it.
- **Two edges are cut out of its input region** — the home pill along the
  bottom and the back edge down the left — so both keep working with the shade
  down.
- Every action that leaves the shell — airplane, torch, brightness, rotate —
  is fire-and-forget and re-reads the real state rather than trusting its own
  write.

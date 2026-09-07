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

The sheet is as tall as what is in it, up to 90% of the screen height below
the gesture strip. Everything scrolls only in the notification list; the rest
is fixed.

## S1–S3. Header

**S1** The clock reads `H:mm` and the date `dddd d MMMM`, updating once a
minute. The sheet covers the status bar, so the time has to reappear here —
losing it is the one thing a phone user would notice immediately.

**S2** The gear opens the settings list and closes the shade on the way.
Everything the Omarchy menu reaches that is not an app lives there.

**S3** The power button opens Settings at its Power page and closes the shade on
the way. It used to summon the Omarchy menu at its `system` route; that menu is
a popup with no tap-outside dismiss in this port, since the port patch
stubs out `HyprlandFocusGrab`, so it was a trapdoor. Lock, Suspend, Log out,
Restart and Power off are native rows now — see `docs/settings.md`.

## S4–S6. Wi-Fi and Bluetooth

**S4** The Wi-Fi tile is lit when Wi-Fi is enabled and a tap toggles it. Its
second line reads, in order of preference: `Off`, the connected network's name,
`Connected`, or `Not connected`.

**S5** The Bluetooth tile is lit when the adapter is enabled and a tap toggles
it. Its second line reads `No adapter`, `Off`, the connected device's name, or
`On`.

**S6** A **long press** on the Wi-Fi tile opens the network picker: the shade
closes and the `moarchy.wifi` screen comes up. The tap it interrupts does not
also fire, so the radio is left as it was. 500ms, Android's interval; a press
that turns into a drag of the sheet cancels it.

Joining a network is the one thing the tile could not do, and a radio switch
that cannot get you online is half a control. Android puts the picker on
exactly this gesture.

**S6a** A **tap** does the same thing — opens the picker rather than toggling
— when Wi-Fi is on, nothing is connected, and no network in range is one
NetworkManager has a saved connection for. In that state the toggle is a dead
end: there is nothing to reconnect to, so the only thing a tap could otherwise
do is switch the radio off, which is the opposite of what somebody tapping a
disconnected Wi-Fi tile wants.

The cost is that Wi-Fi cannot be switched **off** from this tile while it is
stranded. Airplane (S8) and Settings still do it, and an idle radio with
nothing saved in range is the case where turning it off matters least.

**S6b** The picker is `moarchy.wifi`, a screen, not a terminal.

It was `nmtui-connect`, which fits the 60x41 grid `moarchy-launch-tui` gives —
the network list and its buttons are all on screen. They still cannot be
pressed. You could see your network and not join it. Found on the device,
2026-09-06.

The reason is narrower than it first looked, and the narrower version matters
because it decides which *other* TUIs are safe to keep. It is not that a TUI's
buttons are drawn text: foot turns a tap into a left-button click
(`man 1 foot`, TOUCHSCREEN), so a terminal app that asks for mouse reporting
does get the tap. `nmtui` never asks — its binary contains none of the
`?1000/1002/1003/1006/1015h` sequences — so the click goes nowhere. Nor is the
keyboard the problem: it has esc, tab, ctrl, alt and all four arrows.
`wiremix` and `bluetui` both enable mouse reporting, and a tap on wiremix's tab
bar and volume slider was verified to work on the device (2026-09-07).

Upstream ships a complete network panel at `plugins/panels/network`, but its
manifest declares one kind, `bar-widget`, and the panel opens from that widget.
This phone replaces the bar with `moarchy.bar`, so the widget is never
instantiated and its panel can never be summoned. `moarchy.wifi` is the same
job as an overlay: scan, tap to join, a passphrase field the on-screen keyboard
can fill, and Disconnect/Forget on a saved network.

Nothing shells out to `nmcli` — `Quickshell.Networking` exposes `connect()`,
`connectWithPsk()`, `disconnect()` and `forget()` as methods, with signal,
security and known/connected as properties.

`impala` was never right for either: it is an iwd client and this phone runs
NetworkManager with `iwd.service` disabled — and iwd is D-Bus activatable, so
running impala would start it to fight NetworkManager for `wlan0` rather than
fail cleanly.

**S6c** A long press on the **Bluetooth** tile does the same for pairing: the
shade closes and the `moarchy.bluetooth` screen comes up. The two wide tiles
behave alike — hold for the thing the radio is for, and both of them now hold a
screen rather than a terminal.

There is no stranded tap here to match S6a. An adapter that is on with nothing
connected is the normal resting state of Bluetooth, not a dead end, so its tap
stays a plain toggle.

It was `bluetui`, and `bluetui` was not broken — unlike `nmtui` it enables mouse
reporting, so foot's tap-to-click reaches it, and its bindings are keys the
on-screen keyboard has. Three things it still could not be:

- **A row you can hit.** `moarchy-launch-tui` is a 60×41 grid on a 360×720
  logical screen, so a list row is one terminal line, roughly 17 logical px
  against the 44 `style.md` E1 asks for. Every tap is a near miss between two
  devices.
- **Part of the shell.** A terminal is a *window*: it takes a workspace, it
  gets a card in the carousel, and it is themed by foot's own palette rather
  than by `Color.popups.*`. Holding one tile gave you a screen and holding the
  other gave you an app.
- **Able to say what the tile already says.** Battery level, "Connecting…",
  which device is the audio sink — the shade knows all three and the terminal
  could not show any of them in the shell's own type.

**S6d** The picker is `moarchy.bluetooth`, an overlay plugin, the same shape as
`moarchy.wifi`: back chevron, radio switch, one list, one row open at a time.
Its criteria:

**S6d-1** The list is the adapter's devices — connected first, then remembered,
then whatever the scan has turned up — each group sorted by name. A device whose
name is only its own MAC address or a bare UUID is not listed at all; a phone
in a café otherwise shows forty of them and none of yours.

**S6d-2** Discovery runs **only while the screen is on screen**, and is stopped
on the way out. A scan left running costs radio time and battery for a list
nobody is reading. It is retried while the screen is up, because BlueZ refuses
`StartDiscovery` on an adapter that is still powering on, and because a scan
times out on its own after a couple of minutes.

**S6d-3** Tapping a row opens the drawer under it with the actions that apply to
that device, one row open at a time: **Connect** or **Pair**, **Disconnect**,
**Forget**. Nothing acts on a tap of the row itself — unlike Wi-Fi's open
network, there is no Bluetooth device for which the intent of a tap is
unambiguous.

**S6d-4** The list holds still while a row is open or an action is in flight.
Discovery reorders it every few seconds, and a list that reshuffles under a
finger aiming at **Forget** is a mis-tap waiting to happen. (Wi-Fi freezes for a
related but different reason — keeping a focused text field alive. There is no
text field here.)

**S6d-5** A device reports its battery level when BlueZ has one, as a percentage
next to its name. This is the one thing the shade cannot show and the reason to
open the screen when everything is already connected.

**S6d-6** Pairing, connecting and forgetting go through
`omarchy-bluetooth-device`, **not** through `BluetoothDevice.pair()`.

This is the one place this screen departs from `moarchy.wifi`, which touches no
`nmcli` at all, so it is worth being exact: quickshell registers no
`org.bluez.Agent1`. Its `pair()` is a bare `Device1.Pair()` call, and BlueZ
answers a pairing that needs an agent with `No agent available`, logged to the
journal where nobody will read it. `bluetoothctl` registers one, and
`omarchy-bluetooth-device` — which is on `PATH` from `omarchy-config`, and which
upstream's own Bluetooth panel calls for exactly this reason — wraps it with the
two steps a bare `Pair()` also skips: it unblocks rfkill first, because BlueZ
will not power an adapter up underneath a soft block, and it marks the device
trusted afterwards, without which it will not reconnect itself.

Everything the screen *reads* still comes from `Quickshell.Bluetooth`
properties. Nothing parses `bluetoothctl` output. **Disconnect** is the
exception on the writing side and stays a native `Device1.Disconnect()`: it
needs no agent, no power-up and no trust, which is the whole of what the
wrapper adds.

**S6d-7** An action that has not landed in 25 seconds says so on the row, and
says only what it knows: it did not come up in time. Same wording discipline as
Wi-Fi's join — guessing "wrong PIN" at a device that was simply switched off
sends somebody to re-pair for no reason.

**S6d-8** The header switch toggles the adapter, and **unblocks rfkill first**
when the adapter reads blocked, waiting ~700ms before writing `enabled` — the
same order and the same reason as S9. Without it the switch is dead for anyone
who has been in airplane mode, because BlueZ will not power up under a block and
drops the write silently.

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

**S18** History is newest first, one card per notification. A single
notification is dismissed by **swiping its card sideways** — there is no close
button on the card, and the swipe is the only per-card path. See
`gestures.md` H7 for the gesture and why it claims one axis.

**S19** A clear-all removes every notification, both the live popups and the
history. It is the only dismissal reachable by tap, which is what keeps
emptying the shade from depending on knowing about H7's swipe.

**S20** The list is the only scrolling region on the sheet, and while it can
scroll it keeps vertical drags — the shade must never close out from under
someone reading it (`gestures.md` H5). When it fits, it gives that space back,
and so does the sheet: it ends where the list does (S21).

**S21** The sheet is as tall as its content. With no notifications it ends
below the sliders; every card that arrives extends it. There is still no "no
notifications" placeholder — an empty list is simply empty, and the sheet now
stops there rather than holding two thirds of the screen blank underneath it.

**? S21a** The sheet grows *per open*, not live: a notification that arrives
while the shade is already down does not join the list, or extend the sheet,
until it is next opened.
— confirm: this is not new and not about the height. `historyRows` is filled
by `refresh()`, which runs on `open()` and nowhere else, so the list has always
behaved this way; the height simply follows whatever the list holds. Making it
live means watching the notification service rather than re-reading the history
directory on open, which is a change to S18, not to this.

**S22** It stops growing at 90% of the height below the gesture strip, and at
that cap the list scrolls rather than the sheet growing further (S20).

The cap is not slack. The band of scrim left underneath is the tap-to-dismiss
target and where a thumb starts the up-drag that closes the shade
(`gestures.md` H2), and the drag handle is the status bar, so a sheet allowed
to reach the full screen would leave an upward drag starting within 26px of
the top with nowhere to travel. A short sheet hands back more of that band,
never less.

**S23** The height never changes under a finger. It is latched when a drag
begins and released when it ends: the sheet's own height is the divisor for
both drag mappings (`gestures.md` D2a, 1:1 against the sheet it moves), so a
notification landing mid-gesture would otherwise grow the sheet downward while
making the same millimetre of thumb worth less of it.

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

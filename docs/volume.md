# Volume — specification

What the hardware volume keys do, and the panel they raise. Present tense,
normative. The archaeology lives in [build-log.md](build-log.md).

Ids are `V<n>`, cited by `bin/moarchy-selftest --volume` and by the code.

**The keys and the panel are two things that never call each other.**
`bin/moarchy-volume` moves the sink and writes a timestamp; `moarchy.volume`
watches both and draws what it sees. That is the whole wiring, and V3 is the
criterion that keeps it: a shell that is down, or too busy to answer, costs the
feedback and never the control — and any other way the volume moves (the
shade's slider, an Android app under Waydroid, `wpctl` over ssh) raises the
same panel with no second caller to teach.

The timestamp exists for one case and it is the case this surface was built
for (V1a): at 100% the up key changes nothing, so there is no change to watch.

**Brightness is not here.** It keeps upstream's `omarchy.osd` card, fed by
`omarchy-osd` from `omarchy-brightness-display`. This phone has no brightness
keys — that binding is for a USB keyboard — so the one hardware control that
needs a phone-shaped surface is the rocker.

## Layout

Right edge, vertically centred, thumb-side. Android's shape, and for Android's
reason: the hand holding the phone is already at that edge.

| | |
| --- | --- |
| track | 44 × 180, `radiusTile` capped at half its width. Fill grows from the bottom |
| mute | the shade's `shadeRound` circle under the track, answering in a 44 slot of its own (`style.md` E4) |
| card | the two of them on one `radiusCard` panel, `Style.space(6)` of padding, `Style.space(8)` between |
| margin | `Style.space(16)` clear of the screen's right edge — the gesture plugin's edge band (V10) |

Sizes are `Style.space()`, so they follow the theme's scale; the numbers above
are the drawn values at scale 1.0.

## V1–V3. The keys

**V1** A press of the volume rocker moves the output volume by 5% and raises
the panel. The rocker is a keyboard to sway — `XF86AudioRaiseVolume` and
`XF86AudioLowerVolume` through xkb — whichever input device a given phone
wires it to, so nothing about it is per-device.
→ `wpctl get-volume @DEFAULT_AUDIO_SINK@` differs by 0.05 across
`moarchy-volume up`, and `omarchy-shell volume state` reads `open` after it

**V1a** A press at either end of the range raises the panel too. At 100% a
`5%+` leaves the sink where it is and PipeWire publishes nothing — which is the
"the rocker is broken" reading this panel answers — so the key stamps
`~/.local/state/moarchy/volume-key` and the panel watches the path. The same at
0 on the way down.
→ from `wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0` with the panel down,
`moarchy-volume up` leaves `omarchy-shell volume state` == `open` and `level=100`

**V2** Volume **up** unmutes. Volume **down** leaves mute alone: a thumb on the
down key wants quieter, and a phone that unmuted itself on the way down would
be loud at exactly the moment its owner asked for the opposite.
→ from `wpctl set-mute @DEFAULT_AUDIO_SINK@ 1`, `moarchy-volume up` leaves
`wpctl get-volume @DEFAULT_AUDIO_SINK@` without `[MUTED]`, and `moarchy-volume
down` from the same state keeps it

**V3** `moarchy-volume` asks the shell for nothing and waits for nothing. It
sets the sink and writes a file; both triggers are things the panel reads, not
calls it answers, so a shell that is down or busy leaves an unread stamp rather
than a keypress that failed. A `qs ipc` per press would also be a process per
repeat, and sway repeats a held binding about 25 times a second.
→ `grep -c omarchy-shell /usr/lib/moarchy/bin/moarchy-volume` is 0

## V4–V7. The panel

**V4** The panel is a vertical track against the right edge, centred on the
screen's height, with the mute button below it.
→ `omarchy-shell volume geometry` reports a `card=` whose right edge is
`margin=` short of `screen=`'s width and whose vertical centre is within one
pixel of half its height

**V5** The fill is the level and grows from the bottom. At zero it is not drawn
— an empty track is what silence looks like — and once it is drawn it is never
shorter than the track's corner diameter, because a fill shorter than its own
radius cannot keep those corners and paints outside the outline it sits in.
→ after `wpctl set-volume @DEFAULT_AUDIO_SINK@ 0`, `omarchy-shell volume level`
reads `level=0 fill=0`; after `wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%` it
reads `level=1` with a `fill=` that is not 0

**V6** The glyph on the mute button follows the level — `mute`, `low`,
`medium`, `high` — and reads `mute` at zero as well as when muted.
→ `omarchy-shell volume level` reports `glyph=high` at 1.0, `glyph=low` at
0.15, and `glyph=mute` at 0

**V7** The panel goes away 3 seconds after the last key press or touch, and
every key press and every touch starts those 3 seconds again. Android's
interval, on a surface that exists to be looked at once.
→ `omarchy-shell volume state` reads `open` 2s after a `moarchy-volume up` and
`closed` 4s after it; a second `moarchy-volume up` at 2s leaves it `open` at 4s

## V8–V11. Touch

**V8** A drag along the track sets the volume as the finger moves, not on
release. The sink is in-process and free to follow a finger — the shade's
volume slider is `live` for the same reason, and its brightness slider is not.
→ `sudo moarchy-touch drag` down the track leaves `omarchy-shell volume drag`
reporting `commits=` above 2, and a `to=` at the finger's end

**V9** A tap on the mute button toggles mute. Muted, the fill keeps its height
and drops to the neutral tone, so what unmuting will return to is on screen
the whole time.
→ `sudo moarchy-touch tap` at the centre of `mute=` in `omarchy-shell volume
geometry` flips `muted=` in `omarchy-shell volume level` and leaves `level=`
unchanged

**V10** The panel answers touch on its card and nowhere else, and its card
clears the gesture plugin's right edge band — so both the app underneath and
the edge keep every touch outside 56 logical px of screen.
→ `margin=` in `omarchy-shell volume geometry` is not less than `w=` in
`omarchy-shell gestures geometry`; and with the panel up, a swipe in from the
right edge *at the card's own height* still opens what
`omarchy-shell gestures targets` says that edge raises. Aimed anywhere else the
check cannot fail: the panel's surface is 72 × 244, so everywhere but those
pixels is passing touch through by construction rather than by the mask

**V11** The panel reserves nothing. A window is the same size and in the same
place with it up as with it down.
→ the focused view's rect in `swaymsg -t get_tree` is identical before
`moarchy-volume up` and while `omarchy-shell volume state` reads `open`

## V12–V15. When it stays away

**V12** The panel does not appear while the shade is open. The shade's own
slider is already moving, and a second reading of the same number over the top
of it is not feedback.
→ with `omarchy-shell shade state` == `open`, `moarchy-volume up` leaves
`omarchy-shell volume state` == `closed`

**V13** The keys work with the screen blanked, and leave nothing on screen when
it comes back. A surface raised over a dark panel is never drawn, so its exit
cannot be an animation: the unmap is a timer.
→ `moarchy-screen blank; moarchy-volume down; sleep 4; moarchy-screen wake`
moves the volume and leaves `omarchy-shell volume state` == `closed`

**V14** With no audio sink there is no panel — the same rule the shade's volume
slider follows (`shade.md` S14). A track with nothing behind it is a control
that lies.
→ `omarchy-shell volume level` reads `sink=none`, and `state` stays `closed`
across a `moarchy-volume up`

**V15** The panel is not a sheet. It puts nothing away, nothing puts it away,
and the back gesture does not see it — it is a panel that comes and goes on its
own like the launch splash, not a surface you dismiss.
→ `moarchy.volume` appears nowhere in `moarchy.common/Sheet.js`, and
`Volume.qml` calls no `Sheet.cover`

## Coverage

`bin/moarchy-selftest --volume` runs V1–V13. Two are not covered and say so
rather than passing:

- **V14** needs a phone with no sink. Unloading the sound card to make one is a
  worse risk than the criterion is worth; the branch is one `sink=none` read
  away from being visible in `volume level`, which the suite prints.
- **V15** is greppable rather than runnable, and `scripts/style-check.sh`
  already fails on a sheet id written outside `Sheet.js`.

## Verified on glass

2026-09-19, on the Pixel 3a, against a user-directory copy of the plugin with
the rocker bound at runtime. `bin/moarchy-selftest --volume`: V1–V13 pass.

| | |
| --- | --- |
| geometry | `card=288,248 56x244 track=294,254 44x180 mute=294,442 44x44 margin=16 screen=360x740` — the layout table evaluated, on a 360×740 screen at `corners = "square"`, `shade = "compact"` |
| the key path | a real `KEY_VOLUMEUP` through `/dev/uinput` moves the sink 0.40 → 0.45 and leaves `volume state` == `open`: sway's binding, the command and the watch, end to end |
| the drag | 29 values written across one 700ms drag, finishing at 75% (V8) |
| blanked | `moarchy-screen blank`, a key press, and `volume state` == `closed` when the panel lights again (V13) |

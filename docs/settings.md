# Settings — specification

What the phone's Settings UI must do. Present tense, normative. Which upstream
menu entry lands where is recorded in `docs/menu-coverage.md`; the archaeology of
*why* lives in `docs/build-log.md`. This file is the contract.

Each AC is checkable from a terminal over ssh, with no finger on the screen.
`bin/moarchy-selftest --settings` cites these ids, so an AC with no test is
visible.

## Vocabulary

| Term | What it means |
| --- | --- |
| **Settings** | The `moarchy.settings` overlay. One plugin, many pages. |
| **page** | One screen in the stack, addressed by a dotted id (`appearance.bar`). |
| **stack** | The pages currently pushed, root first. Back pops one. |
| **row** | A line on a page. One of `nav`, `plugin`, `switch`, `choice`, `action`, `link`, `info`, `input`. |
| **guard** | A `when:` shell condition copied verbatim from `omarchy-menu.jsonc`. A row whose guard fails is not rendered. |
| **reader** | The command a `switch` or `choice` page reads its state from. |
| **bridged launch** | Running an upstream `omarchy-*` command unchanged, in a TUI terminal or the browser. |
| **the shade** | The pull-down (`moarchy.shade`), which owns the radios and sliders. |
| **running** | Summoned and not yet closed. Settings stays running across any number of hides, and has a carousel card for exactly that span (`gestures.md` K1). |
| **hidden** | Off screen but running. The strip's up-swipe hides; the page stack survives. |
| **closed** | Not running. The card is gone and the stack is back at the root. |

## The screen tree

Root is noun-shaped, the way a phone settings app is, not verb-shaped like
upstream's dmenu. Ten rows:

```
Settings
├─ Network & internet   Private DNS · Wi-Fi networks · Bluetooth devices · Wi-Fi QR
├─ Display              Night light · Stay awake
├─ Sound & notifications Output device · Input device · Crash capture
├─ Appearance           Theme · Wallpaper · Font · Status bar · Get more
├─ Apps & defaults      Default apps · Web apps · Terminal apps · Packages
├─ Shell & plugins      Plugins · Restart shell · Reset tmux config
├─ Security             Remote access · Passwordless sudo · Change password
├─ Tools                Screenshot · Screen record · Emoji · Reminders · Speed tests
├─ System               Date & time · Restart hardware · Update system · Power
└─ About phone          Omarchy · Kernel · Device · Keybindings · Help & docs · About Omarchy
```

There is no Branding row and no Screensaver row; both left for Unsupported on
2026-09-07, for the reasons under **Known-bad** at the foot of this file.

Four departures from upstream, each deliberate:

**`install` and `remove` merge into one Packages screen.** Upstream keeps mirror
trees only because every row is guarded on the complement of its twin
(`! omarchy-pkg-present X` against `omarchy-pkg-present X`), so at most one of any
pair is ever visible. Two trees to show one row each is a dmenu artifact.

**`trigger.toggle.*` dissolves.** Upstream groups those nine rows by *mechanism* —
they are together because they are all toggles. A phone groups by *subject*: the
status bar switch lives with the status bar, night light with Display, crash
capture with notifications. "Toggles" is a category nobody looks for.

**Power leaves the root.** The shade already has a power glyph. It now deep-links
to `system.power` here rather than summoning `omarchy.menu`, so there is one
implementation behind two entry points.

**`apps` leaves Settings entirely.** It is the app drawer, which already *is*
upstream's `apps` provider. A launcher inside Settings would repeat it.

Three rows exist that upstream has no id for. **Wi-Fi networks** and **Bluetooth
devices**: the shade toggles both radios, and each row opens the same screen its
tile opens on a long press — `moarchy.wifi` (`docs/shade.md` S6b) and
`moarchy.bluetooth` (S6c, S6d). One picker behind two entry points, twice.

The third is **Update system**, and it is not `update.omarchy` wearing a new
label. That id stays Unsupported for the reason `docs/menu-coverage.md` records —
`omarchy-update` wants pkgs.omarchy.org's aarch64 tree, which 404s, and Snapper on
btrfs — and none of that stops `pacman -Syu`, which `docs/structure.md` R8a
already says works here and updates the phone UI. So the row runs the plain
upgrade in the TUI terminal, carries no `covers:`, and adds no line to
`settings coverage`. A row that claimed the id would be promising the snapshots
and migrations upstream's script does and delivering an upgrade.

---

## A. Getting in and out

**A1** The shade's gear opens Settings at the root page.
→ `omarchy-shell settings state` == `open`; `omarchy-shell settings page` == `root`

**A2** Opening Settings puts away the shade, drawer, carousel and theme picker, so
exactly one full-screen surface is up.
→ each of `omarchy-shell {shade,drawer,recents,themes} state` == `closed`

**A3** The shade's power glyph opens Settings at the Power page, not the vendored
`omarchy.menu`.
→ `settings page` == `system.power`; `omarchy-shell shell listPlugins` does not
show `omarchy.menu` open

**A4** Settings opens directly at any page by id, and an unknown id is refused
rather than silently landing on the root.
→ `settings openAt appearance.bar` == `ok` and `settings page` == `appearance.bar`;
`settings openAt nope` == `unknown page: nope`

**A5** `open()` never blocks. The page paints with whatever state it has and fills
in afterwards; no `FileView` and no synchronous read runs inside it.
→ `settings state` answers `open` within 300 ms of `settings open`, on a session
where every reader has been made slow

**A6** Closing and reopening lands on the root, never on the page last left.

*Closing*, specifically — which since `gestures.md` K is not the only way to
leave the screen. Being hidden and resumed from the carousel card keeps the
page you were on (K5); it is closing that resets the stack, and the two ways to
close are the card flick and the back gesture at the root (K6). Written when
those were the same act, and the criterion is unchanged for the case it was
written about.
→ `settings close; settings open; settings page` == `root`

## B. The page stack and back

**B1** A `nav` row pushes exactly one page, and the header shows that page's title.
→ `settings stack` gains one line; `settings page` is the pushed id

**B2** The header chevron pops one page and stops at the root.
→ from depth 3, `settings back` returns `appearance`, then `root`, then `closed`

**B3** The left-edge back gesture pops one page, and closes Settings only when the
root is on top. It never closes the app underneath.
→ from depth 2: `settings page` moves up one and the open-window count is unchanged

**B4** An up-swipe from the strip treats Settings as the app it is: the carousel
rises over it with the Settings card leading (`gestures.md` K3), and a drag
carried on into the home band hides Settings and lands on a home screen (K4).
Hidden, not closed — the card is still there to come back to, and the
open-window count is still unchanged.
→ `recents list`'s first line is `moarchy.settings`; after the home band
`settings state` == `closed`, that line is still in `recents list`, and the
focused workspace's `representation` is empty

This replaces a criterion that was only ever half true. It read "an up-swipe
puts Settings away and does nothing else — A8 applied to this surface", and the
code applied A8 to Settings in exactly one case: with no window open anywhere
the strip had nothing to raise and fell through to clearing the topmost
surface. With an app running, the same swipe raised the carousel *over*
Settings and left it there, so the sheet was still up the moment the carousel
was dismissed. The fix is not to clear Settings in both cases — it is that the
two cases were disagreeing about whether Settings is an app, and K answers
that.

Hidden rather than closed is the half of this that is a decision rather than a
repair. An up-swipe on an app hides it and leaves it in the carousel; doing
anything else to Settings would make "treated as an app" stop at the card.

**B5** The back gesture dismisses whichever overlay is topmost, including vendored
ones. `HyprlandFocusGrab` is stubbed in this port, so no vendored popup dismisses
on tap-outside and back is the only way out of one.
→ with `omarchy.emojis` summoned, one back leaves it closed and closes no window

**B6** Pushing the page already on top is a no-op, so the stack cannot grow without
bound.
→ `settings goto appearance` twice leaves `settings stack` one line longer

**B7** Themes returns to the page it was opened from, not to the root.
→ after Themes' back: `settings state` == `open` and `settings page` == `appearance`

**B8** A page whose every row is hidden is unreachable: the `nav` row that would
open it is not rendered.
→ on a base install, `settings rowsOn apps.default` shows `browser` with `visible=0`

**B9** Opening *at* a page clears what the last page answered. Guard answers,
the reader's value and any provider-built rows are per-page state, and `open()`
rebuilds the stack without going through `push` -- so it reached `refresh()`
without the reset `afterPageChange()` does. A provider page then painted the rows
the *previous* provider page built, since `refresh()` re-runs a provider only
while `dynamicLoaded` is false. On screen that was "No reminders set" under a
"Font" header, and it survived a close and reopen.

A resume (K5) keeps what was typed, because that is the same screen coming back;
a rebuilt stack drops it, because those fields belong to pages nobody is standing
on any more (J12).
→ `settings openAt tools.reminders; settings close; settings openAt
appearance.font; settings rows` lists fonts, not `No reminders set`

## C. Switches

**C1** Every `switch` reads its state from a command at page-open, never from a
remembered value.
→ with the switch's page open, `settings value <rowId>` matches its reader run
directly. The id is the bare one (`show`, not `appearance.bar.show`): rows are
resolved against the open page, not by path

**C2** The four negative-polarity flags render inverted: a present flag file means
the feature is **off**.
→ `settings openAt appearance.bar; omarchy-toggle bar-off on; settings refresh;
settings value show` == `off`

**C3** Writing a switch re-reads it; the row shows the new value without the page
being reopened.
→ on `appearance.bar`: `settings set show on; settings value show` == `on`, and
`omarchy-toggle-enabled bar-off` exits non-zero

**C4** Turning the status bar off does not restart or kill the shell.
→ the `quickshell` pid is unchanged across `settings set show off`, and
`settings state` is still `open`

**C5** Stay awake actually stops the panel blanking, not just the row.
→ `omarchy-toggle-idle status | jq .enabled` == `true`, and the swayidle timeout
command is a no-op while the flag is set

**C6** Nothing in Settings writes `bar.transparent`, and the bar is opaque
whatever `shell.json` says. The flag can only be set through `omarchy-bar
transparent`, which ends by reloading the shell config -- and that reload leaves
upstream's `omarchy.bar` drawing in place of the phone bar until the shell is
restarted. An appearance switch that costs the status bar is worse than no
switch, so the row was removed rather than repaired.
→ `appearance.bar` lists no `transparent` row, and `moarchy.bar` declares no
`toggleTransparency`, so `omarchy-shell shell toggleBarTransparency` answers
`no-bar`

**C7** Crash capture reflects the unit, not only the flag.
→ on `sound`, after `settings set crashcapture off`, `omarchy-toggle-enabled
crash-capture-off` exits 0 and the watch service is not `active`

**C8** A switch may read natively while writing through a bridged launch.
→ on `security`, `settings value ssh` matches `systemctl is-enabled --quiet sshd`

## D. Choices

**D1** Exactly one row on a choice page is ticked, and it is the one the page's
reader names.
→ `settings rowsOn net.dns | grep -c 'checked=1'` == `1`, and that row's value ==
`$(omarchy-dns)`

**D2** A reader answering something no row declares ticks nothing, rather than
ticking the first row.
→ with `omarchy-dns` stubbed to print `Quad9`, the checked count is `0`

**D3** Read-value and write-value are separate fields.
→ the `epiphany` row on `apps.default.browser` reads
`readValue=org.gnome.Epiphany.desktop` (what `omarchy-default-browser` prints)
and writes an `xdg-settings` call. Upstream's own case is
`setup.default.editor.zed`, which reads `zeditor` and writes `zed`; that id is
Unsupported here, so the mechanism is asserted on the row that uses it

**D4** Setting a choice re-reads the page's reader and moves the tick.
→ `settings set net.dns Cloudflare; settings value net.dns` == `Cloudflare`

**D5** A choice page's parent `nav` row shows the current value as its detail line.
→ the `dns` row on page `net` has detail == `$(omarchy-dns)`

**D6** The font page is populated from the provider, not a hard-coded list.
→ `settings rowsOn appearance.font | wc -l` == `omarchy-font-list | wc -l`

**D7** A provider page's reader answers in the shape its rows carry. The rows are
whatever the provider printed -- paths, for a directory listing -- so a reader
that prettifies one ticks nothing at all. That is D2 behaving correctly and it is
still a page of eight wallpapers with no current one, which is why the reader is
the raw path and the *label* carries the prettifying instead.
→ on `appearance.background`, `settings value <rowId>` equals `readlink -f
~/.local/state/omarchy/current/background`, exactly one row is `checked=1`, and
its label is the name the `background` row on `appearance` shows as its detail

**D8** A choice row whose write ends in a terminal takes Settings off screen
first. Choosing is normally instant and writes a file, so a choice row leaves the
screen up and re-reads -- which is right for DNS and wrong for AI agent, where
the write is `moarchy-agent open <name>`: it writes the drawer tile (P), then hands
off to `omarchy-default-agent`, which installs through mise in a presentation
terminal and execs the agent. Both ends of that are a foot window, and a foot
window mapped under a full-screen layer surface is indistinguishable from a tap
that did nothing. `hides: true` on the row is what the action branch does by
default; it is not the page's property, because a page may hold both kinds.
→ every row on `apps.default.agent` carries `hides`, and no other choice row in
the model does

A reader may also answer something the provider's list genuinely omits, which is
not the same fault. `omarchy-font-list` enumerates `fc-list :spacing=100`, and
with no font configured `fc-match` falls back to a family fontconfig does not tag
that way -- so the font in use was real, current, and not on its own page. The
list carries the current value when it lacks it.
→ `settings rowsOn appearance.font` contains `$(omarchy-font-current)`

## E. Bridged launches

**E1** In dry-run, a bridged row records the command it would run and runs nothing.
→ on `tools`: `settings dryRun 1; settings activate emoji; settings lastLaunch` ==
`omarchy-menu-emoji`, and no new window appears

**E2** Every bridged row's command is byte-identical to the `action` string in
`omarchy-menu.jsonc` for the id it covers, with four declared exceptions.
→ a static diff of `Pages.js` against the upstream file. `install.package`,
`install.aur` and `remove.package` differ only in dropping upstream's
`xdg-terminal-exec --app-id=...` for the TUI terminal, which is the point of
bridging. `update.password.user` runs `sudo passwd "$USER"` where upstream runs
`passwd`: the image locks the account password, so the bare form has nothing to
authenticate against and fails on its first question. Checked statically rather than through `lastLaunch`,
because `lastLaunch` records the wrapped form that actually ran

**E3** Every command named by a Native or Bridged row resolves on the shell's PATH.
→ `command -v <first word>` succeeds under the PATH in
`/proc/$(pgrep -x quickshell)/environ`

**E4** The bridge shims exist and shadow upstream.
→ `command -v` for `omarchy-launch-floating-terminal-with-presentation`,
`omarchy-launch-config-editor` and `omarchy-launch-webapp` each starts with
`$MOARCHY_PATH/bin`

**E5** A bridged TUI opens tiled, identifiable, and typeable. Tiled *because*
typeable: a fullscreen view draws above the Top layer the keyboard is on, so the
rule that used to fullscreen these (`windows.md` W5) is what made
`install.aur` a prompt with no way to answer it.
→ `swaymsg -t get_tree` shows an `app_id == "moa-tui"` node filling the workspace
with `fullscreen_mode: 0`; focusing its prompt raises `sm.puri.OSK0` **and** a tap
on one of its keys arrives in the terminal. The bus property alone is not the
check — it read `Visible true` for the whole time the keyboard was drawn
underneath the terminal and taking no touches

**E6** Launching a bridged row puts Settings away first, so the terminal is not
covered by a layer surface. It is put away *hidden*, so Settings and the
terminal it launched are both cards and you can get back to the row you came
from (`gestures.md` K12).
→ `settings state` == `closed` when the child process starts, and
`recents list` holds both `moarchy.settings` and the terminal

**E7** A bridged row that summons a vendored picker reaches it.
→ on `shell.plugins`, after `settings activate enable`, `omarchy-shell shell listPlugins`
shows `omarchy.menu` open within 2 s

**E8** A bridged run leaves its output on screen until dismissed; it does not flash
and vanish.
→ the window survives 5 s after the wrapped command exits

**E9** A bridged command works on *this* image, not merely on its PATH. E3 checks
the first word resolves; these two resolved and still did nothing.
`omarchy-version` reads `pacman -Q omarchy`, and this image installs Omarchy as
`omarchy-config`, so it exited 1 and About's headline row was blank.
`omarchy-theme-bg-install` ends in `nautilus`, which is deliberately not in the
base set at 2-3 GB of RAM, so Install a wallpaper exited 127 into a detached
process and looked like a file manager opening somewhere out of sight. Both are
shimmed in `bin/`, upstream's own behaviour kept ahead of the fallback.
→ `omarchy-version` exits 0 and prints a version; `command -v
omarchy-theme-bg-install` starts with `$MOARCHY_PATH/bin`; the `version` row on
`about` has a non-empty detail

## F. Hidden when unsupported

**F1** No id classified Unsupported is reachable as a row anywhere.
→ `settings coverage` never lists an Unsupported id, because a row is the only
thing that can name one. The check is that every id the upstream file classifies
Unsupported is absent from `settings coverage`

**F2** A container row whose page has no visible child is itself hidden.
→ no `visible=1` row on any page targets a page with zero visible rows

**F3** Guards are evaluated per page, not for the whole model. Opening the root
runs no `pacman`.
→ with `pacman` wrapped in a counting stub, opening `root` leaves the count at 0;
opening `apps.packages.more` raises it by exactly 1

**F4** A page's guards go out as one `bash -lc` and come back as
`<rowId>:<w|c>:<0|1>` lines.
→ exactly one child `bash` per `settings goto`, whatever the row count

**F5** A reader repeated across rows on one page is captured once.
→ with `omarchy-default-agent` wrapped in a counting stub, `settings goto
apps.default.agent` raises the count by 1, not 9

**F6** A guard that fails, hangs or is missing hides its row rather than showing it
wrongly.
→ with `omarchy-cmd-present` off PATH, no row on `apps.default.terminal` is
visible, and nothing crashes

**F7** A page paints before its guards answer, and each row settles exactly once.
→ `settings rows <page>` sampled every 50 ms shows at most one transition per row

**F8** A container row whose page is guarded row by row carries the same guard.
F2 is not automatic -- a `nav` row's visibility is its own `when:`, and Settings
cannot ask the page it points at without running that page's guards from the
parent, which F3 forbids. So a page whose every row is guarded on a binary needs
the disjunction of those guards on the row that opens it, duplicated in the model
because a `when:` is a shell string and cannot see the page it names.

AI agent was the instance, and is deliberately no longer one. Its nine rows
guarded on nine agents none of which shipped, so the row was always visible and
always opened an empty screen; the fix then was to give the row the disjunction
of those nine guards. mise makes that fix wrong. The page installs what it
lists, so a guard on "is it installed" hides the only screen that could install
one -- the loop D8 describes. Both guards are gone and no page in the model is
guarded row by row any more, so the principle stands with nothing to point at.
The check is therefore the one that notices the guard coming back, not one that
watches it work.
→ no `when:` on any row of `apps.default.agent`, and none on the `agent` row of
`apps.default`, in the shipped `Pages.js` rather than the source tree

## G. Coverage parity

**G1** The coverage map names every id in `omarchy-menu.jsonc`, and no others.
→ `diff <(settings coverage | cut -f1 | sort) <(jq -r 'keys[]' <stripped jsonc> | sort)`
is empty

**G2** Every id appears exactly once.
→ `settings coverage | cut -f1 | sort | uniq -d` is empty; the line count is
`129`, one per id a row or page names, plus `apps` (the drawer) and the one
Shade id. It is not `320`: an id with no row cannot be emitted by a map built
out of rows

It said `137` until 2026-09-07, and had done since the eight branding ids left
for Unsupported: G7's totals were moved 66/70 to 58/70 and this number was not,
so the two halves of one fact disagreed by exactly those eight. Nothing caught
it because nothing asserted it -- G2's check tests for duplicates and never
counted the lines. O13 counts them now, which is what turned the drift up. The
same shape as the G7 note below, and the same lesson: a constant written in two
places drifts in one of them.

**G3** Every class is one of the three *renderable* words.
→ `settings coverage | cut -f2 | sort -u` == `Bridged Native Shade`.
`Unsupported` must never reach a row, so it has no case in `Settings.qml`'s
class map and cannot appear here; the Unsupported set lives in
`docs/menu-coverage.md` alone

**G4** Every Native and Bridged id resolves to a page and a row that exist, or
names the surface outside this stack that satisfies it.
→ `settings rowsOn <pageId>` contains `<rowId>` for each. The one exception is
`apps`, which is the app drawer: it names `moarchy.drawer` and no row

**G5** Every upstream id is accounted for, live or dropped.
→ `settings coverage` line count plus the `Unsupported` entry rows in
`docs/menu-coverage.md` == the 320 keys in `omarchy-menu.jsonc`, and every one
of those Unsupported rows carries a non-empty reason

**G6** The doc and the code agree.
→ `diff` of `settings coverage | cut -f1,2` against the table in
`docs/menu-coverage.md` is empty

**G7** The class totals are the ones committed to.
→ `settings coverage | cut -f2 | sort | uniq -c` == 58 Bridged, 70 Native,
1 Shade. `Unsupported` is not one of the answers -- see G3

It was 71/65 until the three `trigger.reminder.*` ids stopped being bridged
(section J), and 68/68 until `update.timezone`, the two `setup.plugin`
toggles and `about` followed them (sections L, M and N); the eight branding ids
leaving for Unsupported took it to 58/70. The Totals table in
`docs/menu-coverage.md` is the same numbers from the other side, and it stayed
at 71/65 through the reminders change -- a summary nothing asserts drifts, so
G7 is the copy to trust and the table is now moved with it. The selftest's copy of this number had said 74 since `1b01e5c`
dropped three rows without moving it, so G7 was red for reasons unrelated to
what it was asserting -- which is the failure mode a duplicated constant has.

## H. Not repeating the shade

**H1** No control the shade owns appears in Settings: Wi-Fi radio, Bluetooth radio,
airplane mode, brightness, volume, silent, torch, rotate, media transport.
→ no row on any page has a `switch` whose label matches
`^(wi-?fi|bluetooth|airplane|brightness|volume|silent|torch|rotate)`

The two rows that open `moarchy.wifi` and `moarchy.bluetooth` are network
*configuration*, not radio toggles, and are named "Wi-Fi networks" and
"Bluetooth devices".

**H2** The single Shade-class id is recorded and not rendered.
→ `settings coverage` shows `trigger.toggle.notifications` as `Shade` with an
empty row field

## I. Robustness

**I1** A Settings plugin that fails to load is loud, not a gear that does nothing.
→ `omarchy-shell shell listPlugins` contains `moarchy.settings`, and
`settings state` answers rather than `Target not found.`

**I2** Every icon literal is exactly one character.
→ the existing selftest icon check, extended over `Pages.js`, finds no
multi-character glyph. Every icon in `omarchy-menu.jsonc` is above U+FFFF, and
`\uXXXX` takes four hex digits, so a copied escape silently becomes two characters

**I3** No property is named `on<Uppercase>`.
→ `grep -nE '(readonly )?property[^:]*\bon[A-Z]' Settings.qml Pages.js` is empty.
QML reserves that prefix for signal handlers; the binding reads back `undefined`,
and `undefined` as a `color` renders pure black with nothing logged

**I4** Nothing routes a Settings row through `omarchy.menu` for a route that now
has a page.
→ `grep -n 'summon("omarchy.menu"' Settings.qml Shade.qml` returns only the
`launch: menu` bridge helper

**I5** `$MOARCHY_PATH/bin` comes first on the shell's PATH.
→ the PATH in `/proc/$(pgrep -x quickshell)/environ` lists it before
`$OMARCHY_PATH/bin`. If upstream wins, every bridge shim opens nothing

**I6** A detail line is one value. A `detailCmd` may name a command that prints a
whole record -- `omarchy-network-status` answers `<kind>\t<name>\t<signal>\t<freq>`
for a bar widget that lays those out itself -- and unsplit the row read "wifi
Paradise2 65 2462.0". Worse than ugly: the tabs shifted every column of the `rows`
TSV after it, so `enabled` came back as an SSID.
→ no row's detail contains a tab, on any page

## J. Reminders

Upstream's three reminder entries are a command line wearing a menu.
`trigger.reminder.set` runs `omarchy-reminder -i`, which summons
`omarchy.reminders`: a card with no field and no buttons that wants a number
typed, then Return, then a message, then Return. `show` and `clear` say what
they did in a notification and nothing else -- and an `action` row puts Settings
away before it runs (E6), so on this phone all three were a screen vanishing and
at most a toast flashing where it had been. Nothing was wrong with the timers
underneath; there was no way to reach them with a thumb.

All three are Native here, and this section is what they do instead.

**The timers stay upstream's.** `omarchy-reminder` still sets and clears them,
`bin/moarchy-reminders` reads them back and cancels one, and the unit naming is
upstream's. There is no second store: a reminder set from a terminal appears on
this screen, one set here fires through upstream's notification, and
`omarchy-reminder clear` empties the list whoever ran it.

**J1** Tools > Reminders *is* "show all". The page lists every live reminder, one
row each, with its message and the time it fires. Nothing is announced in a
notification.
→ `settings openAt tools.reminders; settings rows | awk -F'\t' '$1 ~ /^r-/' |
wc -l` == `omarchy-reminder show --json | jq .count`, and `find
~/.local/state/omarchy/notifications/history -newer <marker>` is empty across
the open

Three detectors for that second half could not have failed, and are recorded
here so they are not tried again. `omarchy-shell shade notifications` answered
zero lines on a phone holding ten notifications. A count of the store does not
move, because the store is capped. The newest filename does not reliably move
either -- the store prunes, and an entry newer than the ones it kept was seen
vanishing from it. `find -newer` survives both. The selftest also proves the
detector can see a notification -- a `clear`, which does announce itself --
before it trusts silence here.

**J2** With no reminders set the page says so, rather than leaving a blank above
Set a reminder. Clear all is not there either -- it has nothing to act on (J5) --
so an empty screen would be one row and a gap.
→ after `omarchy-reminder clear; settings refresh`, `settings rows` has an
`info` row and no `r-` row

**J3** A reminder set on the Set screen is on the list when that screen returns,
without Settings being reopened.
→ `settings goto tools.reminders.new; settings set minutes 7; settings activate
custom` leaves `settings page` == `tools.reminders` and `settings rows` one
`r-` row longer

**J4** Tapping a listed reminder asks before cancelling it, and dismissing the
question leaves the timer running.
→ `settings activate <r-id>` makes `settings confirmText` non-empty while
`systemctl --user list-timers` still lists the unit; `settings confirm` then
drops it from both

**J5** Clear all asks the same way, and is not offered when there is nothing to
clear.
→ with a reminder set, `settings guards` shows `clear 1`; after `settings
activate clear; settings confirm`, it shows `clear 0`

**J6** A reminder action leaves Settings on screen. Nothing on these two pages
hides the surface, opens a terminal or summons a vendored picker -- which is the
whole of what was wrong before.
→ `settings state` == `open` after each of `activate custom`, `activate clear;
confirm`, and a cancel; `settings lastLaunch` never begins `omarchy-launch-` and
never names `omarchy.reminders`

**J7** The Set screen takes any duration, not only the presets: a minutes field,
an optional message field, and one row that consumes both.
→ `settings goto tools.reminders.new; settings set minutes 25; settings set
message 'Check the oven'; settings dryRun 1; settings activate custom; settings
lastLaunch` == `moarchy-reminders set '25' 'Check the oven'`

**J8** The Set row is inert until the minutes field holds a number, and it looks
inert.
→ on a freshly entered `tools.reminders.new`, `settings rows` shows `custom`
with `enabled=0`, and `settings activate custom` answers `not ready` and leaves
`lastLaunch` untouched

**J9** A preset carries whatever is in the message field and asks nothing else.
→ `settings set message Tea; settings dryRun 1; settings activate m15; settings
lastLaunch` == `moarchy-reminders set 15 'Tea'`

**J10** A reminder with a message is listed by its message; one without is listed
by its duration.
→ `omarchy-reminder 9 Tea; omarchy-reminder 11; settings refresh; settings rows`
holds a row labelled `Tea` and one labelled `11-min reminder`

**J11** While a field has focus the surface gives the on-screen keyboard its room:
the negative bottom inset that lets a page draw under the gesture strip goes to
zero, and comes back when focus leaves. This is the first text input in Settings,
and that inset was unconditional because there had never been one.
→ `settings geometry` shows `margin=0` while `settings focused` names a field,
and `margin=-<strip>` when `settings focused` is empty

**J12** Fields do not outlive the screen. Coming back to Set a reminder starts
empty, so yesterday's message is never attached to today's timer.
→ after `settings back; settings goto tools.reminders.new`, `settings value
message` == ``

**J13** The list is read at open and after every write, never remembered.
→ a reminder set or cancelled from a terminal shows up on the next `settings
refresh`, with no reopen

## K. Audio devices

`wiremix` in a terminal was the only audio UI this phone had, and on this panel
it mapped its window and drew nothing but a truncated tab strip: no device list,
no sliders, nothing to touch. These two screens are what it was there for.

**Routing, not volume.** The shade owns volume, brightness and the radios (H1),
and a slider here would be exactly the repetition that section exists to stop.
What the shade has no room for is *which* device, and on a phone that is the
earpiece against the speaker against a headset against a paired Bluetooth sink.

**The devices stay PipeWire's.** `moarchy-audio` reads `pactl` and writes
`pactl`; there is no second store and no remembered selection. A device chosen
from a terminal shows here, and one chosen here is the default every application
sees.

**K1** Sound & notifications carries an output row and an input row, and no
volume control.
→ `settings rowsOn sound` holds `output` and `input`, and no row on any page has
a label matching `^(volume|mixer|audio devices &)`

**K2** Each page lists what PipeWire reports, labelled the way a person reads it
-- PipeWire's Description, "Built-in Audio Internal speaker", not
`alsa_output.platform-sound.HiFi__Speaker__sink` -- and ticks the one in use.
The label and the handle are different strings, which is why the rows are
`provider.json` and not one value per line.
→ on `sound.output`, the row count equals `pactl list short sinks | wc -l`,
exactly one row is `checked=1`, and `settings value <rowId>` on one of them ==
`pactl get-default-sink`

**K3** A monitor source is not an input device. Every sink has a matching
`.monitor` source, and it records what is playing rather than what is said, so
offering it is a voice memo of silence.
→ no row on `sound.input` has a value ending in `.monitor`, and the row count
equals `pactl list short sources | grep -vc '\.monitor'`

**K4** Choosing a device moves what is already playing onto it, not just the
default for the next thing to start. Otherwise picking the earpiece during a
call changes a setting and nothing you can hear.
→ after a `settings set` on `sound.output`, no entry in `pactl list short
sink-inputs` names another sink

**K5** A page with no device says so. "No output device" is a real state on a
phone whose sound card has not come up, and an empty screen reads as one that
failed to load.
→ with `pactl` answering nothing, `settings rows` on `sound.output` is a single
`info` row

**K6** Neither page opens a terminal, and neither puts Settings away. That was
the whole of what was wrong with the row they replace.
→ `settings state` == `open` after activating a device row, and `settings
lastLaunch` never begins `omarchy-launch-`

## L. Time zone

`omarchy-menu-timezone` piped all ~420 zones into the vendored select box: a
fixed card with the list clipped and a filter field, to find one entry out of
four hundred with no keyboard in front of you. Region then city is two taps down
lists you can read.

**The zone stays `timedatectl`'s.** `moarchy-timezone` writes through it and
reads through it, and ends with upstream's own `omarchy.clock refresh`.

**L1** Time zone is a screen reached by region, then city -- no filter field.
→ `settings rowsOn system.time.zone` holds one `nav` row per tzdata area, and
`system.time.zone.Europe` has as many rows as
`timedatectl list-timezones | grep -c '^Europe/'`

**L2** A city row is labelled by its city and carries the whole zone, because
that is what `timedatectl` takes and what the reader answers.
→ on `system.time.zone.Europe` a row labelled `Berlin` has value `Europe/Berlin`

**L3** The zone in use is ticked on the region it belongs to, and nowhere else.
→ with the zone set to `Europe/Berlin`, exactly one row on
`system.time.zone.Europe` is `checked=1` and none on `system.time.zone.Asia` is

**L4** UTC is a row and not a region: `timedatectl list-timezones` lists it flat,
with no `/` to walk into, and it is what a phone with no fixed home wants.
→ `settings rowsOn system.time.zone` holds a `choice` row whose value is `UTC`

**L5** Setting a zone writes it and leaves Settings standing.
→ after a `settings set` on a city row, `timedatectl show -p Timezone --value` is
that zone and `settings state` == `open`

## M. Plugins

Enable and disable were two separate launches of the vendored select box: tap
Enable, find the plugin, tap it; tap Disable, walk the same clipped card again to
undo it. Neither screen ever showed which plugins were already on.

**M1** Plugins is a list of switches, one per plugin the shell reports it can
turn off, and it shows which are on.
→ the `switch` row count on `shell.plugins` equals
`omarchy-shell shell listPlugins | jq '[.[] | select(.canDisable)] | length'`

**M2** A plugin the shell will not let go of is not offered as a switch. Both
bars are that: `moarchy.bar` is the one this phone draws, and `omarchy.bar`
replaces it with the thirteen-widget desktop bar. A switch that costs you the
status bar is worse than no switch -- C6 says the same about transparency.
→ no row on `shell.plugins` is `p-omarchy.bar` or `p-moarchy.bar`

**M3** The switches read their state from the listing that built them, not from
a command per row. Forty-odd rows with a `read` apiece is a fork apiece, and F5
exists because that cost is real on this SoC.
→ every switch row `moarchy-plugins rows` emits carries `state` and none carries
`read`

**M4** Flipping a switch changes the plugin, and the row settles on what the
shell then reports without the page being reopened. A provider page needs the
provider re-run for that, not the guard batch: `refresh` alone would read the
state the rows were built with.
→ `settings set p-<id> off` leaves that row `checked=0` and `listPlugins` agrees

**M5** The row that opens the page says how many are on.
→ the `plugins` row on `shell` has a detail matching `^[0-9]+ of [0-9]+ on$`

**M6** Add, clone and remove stay bridged and stay where they are. Adding takes a
repo URL typed in and cloning opens the copy in an editor; those are terminal
work, not a row that a switch could replace.
→ `settings rowsOn shell.plugins` still holds `add` and `clone`

## N. About

`omarchy-launch-about` is fastfetch in a terminal that sizes itself by measuring
its own output from inside that terminal and re-renders on every resize. On this
phone it re-execs through the default terminal with `--render`, and the default
terminal is qmlkonsole, which answers `Unknown option 'render'` under an ASCII
logo clipped to its first two letters. The fields were never the problem.

**N1** About Omarchy is a page of rows, and opens no terminal.
→ `settings activate aboutomarchy` leaves `settings state` == `open`, and
`settings lastLaunch` does not name `omarchy-launch-about`

**N2** Every row has a value. A field that cannot be read is not shown as a blank
label -- B1 was exactly that, an "Omarchy" row with nothing beside it.
→ no row on `about.omarchy` has an empty detail

**N3** It says which Omarchy and which moarchy, because on this phone they are
different versions of different packages and the pair is what a bug report needs.
→ `settings rowsOn about.omarchy` holds a row labelled `Omarchy` and one
labelled `moarchy`

## O. Search from the drawer

Everything above is reachable by thumb, and only by thumb: pull the shade, tap
the gear, walk the tree. That is the right shape for browsing and the wrong one
for the case where you already know the name of the thing. So the drawer's
search field searches this tree as well as the app catalogue, and a result is
the row itself rather than a screen two levels above it.

This runs the one-implementation rule the other way round from the departure
above, and both directions hold. Settings still has no launcher — `apps` left
for the drawer and stays there. What the drawer gains is not a copy of the tree:
the index is a walk of `Pages.js`, the tap goes through Settings' own
`activate()`, and there is no second list of actions anywhere.

**The index is declared rows only.** A page may build its rows at open from a
`provider`, and those are not in `Pages.js` to be walked — which is what keeps
the ~420 timezone cities, every installed font, every wallpaper, every live
reminder and every plugin out of a search for "e". It is a property of where the
index comes from, not a filter that could be forgotten.

**O1** With the field empty the drawer is what it was: no settings section, and
the two IPC verbs the store depends on still answer apps alone.
→ `drawer type ""; drawer results` is empty, and `drawer entries` lists only
`.desktop` ids

**O2** Typing shows at most five settings results, each carrying a glyph, a
label and the top-level section it lives in.
→ `drawer type screen; drawer results` has 1..5 lines and no empty field on any
of them

**O3** Every result names a page and a row that exist. The index is a walk of
the model, so a result that cannot be reached in Settings is a result that
should not have been offered.
→ for every key `<pageId>/<rowId>` in `drawer results`, `settings rowsOn
<pageId>` contains `<rowId>`

**O4** An `action` row runs, and Settings never appears. Not "appears briefly":
this is the surface `moarchy-capture-screenshot` would photograph.
→ after `drawer type screenshot; drawer activateResult tools/screenshot`,
`settings state` == `closed`, `settings running` == `stopped`, `settings
lastLaunch` == `moarchy-capture-screenshot`, and `drawer state` == `closed`

`running` is the load-bearing half. `state` says the surface is not up now;
`running` says it never was, because a Settings that had mapped would still be
running with a carousel card behind it (K1). The other half of this AC is the
effect rather than the cause -- that the PNG holds a wallpaper or an app and not
a half-drawn sheet -- and no IPC can answer it: it needs a real `grim` against a
running shell, which is why the selftest runs O4 under `dryRun` and takes no
capture at all.

**O5** A `nav` row lands on the page it points at, not on the page it lives on.
Set a reminder is a row on `tools.reminders` and a screen of its own, and the
screen is the thing being asked for.
→ `drawer activateResult tools.reminders/new`: `settings state` == `open` and
`settings page` == `tools.reminders.new`

**O6** A `switch` or a `choice` opens the screen it lives on and changes
nothing. A radio flipped from a search result is a setting changed by something
that never showed you its current value.
→ `drawer activateResult display/nightlight`: `settings page` == `display`, and
`moarchy-toggle-nightlight --status | jq -r .enabled` is what it was before

**O7** A row whose guard fails is not offered, and a query whose hits carry no
guard forks nothing. F3 and F5 exist because a fork on this SoC costs more than
the test inside it, and a search field runs on every keystroke.
→ with `omarchy-cmd-present` off PATH no guarded row appears in `drawer
results`; with `bash` wrapped in a counting stub, `drawer type screenshot`
leaves the count at 0 and `drawer type qr` raises it by exactly 1

**O8** A row carrying `confirm` shows Settings with the question armed rather
than acting on it. The quiet path is for rows that were going to run anyway, and
a row that asks was never one of those.
→ `drawer activateResult tools.reminders/clear`: `settings confirmText` is
non-empty and `systemctl --user list-timers` still lists the unit

**O9** A row that cannot act yet opens its page instead of failing silently.
J8's Set a reminder needs a duration typed, and the field it needs is on the
screen the drawer has just been asked to skip.
→ `drawer activateResult tools.reminders.new/custom` with nothing typed:
`settings state` == `open`, `settings page` == `tools.reminders.new`, and
`settings lastLaunch` is untouched

**O10** Provider-built rows are not indexed.
→ no key in `drawer results` names a timezone city, a font, a wallpaper or a
live reminder, for any query; `drawer type europe` answers the region `nav` row
and nothing under it

**O11** The second section does not cost the first its geometry. The bottom
inset that keeps the last content pixel clear of the home pill belongs to
whatever is last, and that is no longer the grid.
→ with results showing, `drawer geometry`'s `gap` is >= its `strip`

**O12** Search does not become a second shade. Section H keeps the radios,
brightness and volume out of Settings; a field that searched them back in would
undo it from the other end. The index inherits H1 rather than restating it --
what is not in the tree cannot be found in the tree -- so the check is that the
inheritance holds.

The row types matter, and H1's own regex applied flatly does not work here: it
catches four rows that are all correct. "Wi-Fi networks" and "Bluetooth devices"
are the two configuration screens H1 already exempts, "Wi-Fi QR code" is a
screen, and `system.hardware`'s Wi-Fi and Bluetooth restart an adapter. None of
them is a radio. What would break H1 is a row that *sets* one, and those are
`switch` and `choice`.
→ no `switch` or `choice` row in the index has a label matching
`^(wi-?fi|bluetooth|airplane|brightness|volume|silent|torch|rotate)`

**O13** Update system is a row on System, runs the plain upgrade through
upstream's own presentation terminal, and claims no upstream id.
→ `settings rowsOn system` holds `update`; with `dryRun 1`, `settings activate
update` leaves `settings lastLaunch` ==
`omarchy-launch-floating-terminal-with-presentation sudo pacman -Syu`; and
`settings coverage` is still 129 lines

## P. The coding agent tile

The AI agent page installs an agent (D8, F8). This section is the other half:
what the phone does with one once it is picked, which is put it in the app grid,
because a coding agent reached only by walking Settings > Apps & defaults >
Default apps > AI agent is four taps deep and invisible in the drawer.

**P1** The drawer carries exactly **one** agent tile, however many agents have
been opened. Every agent used to write a `.desktop` of its own, so the grid grew
by one each time a different one was tried and never shrank; nine of them is nine
icons in a 64-entry grid for a thing nobody runs nine of. There is one file and
it is rewritten.
→ after `moarchy-agent open claude; moarchy-agent open opencode`,
`ls ~/.local/share/applications/moarchy-agent*.desktop` is exactly
`moarchy-agent.desktop`

**P2** That tile names whichever agent was picked last, and its three moving
parts move together. A tile whose icon and label disagree with what it launches
is worse than no tile.
→ after `moarchy-agent open opencode` the entry holds `Name=OpenCode`,
`Exec=moarchy-agent open opencode`, `Icon=.../opencode.svg` and
`X-Moarchy-Agent=opencode`

**P3** With no agent picked the tile is a **setup tile**, not an agent. Omarchy
writes no default, so a fresh phone has nothing to name. It used to name Grok
anyway -- the one agent first boot happened to install -- which told a user who
wanted Claude that their phone came with the wrong agent, and gave them no hint
the other eight existed. There is no fallback agent now: an absent, unreadable
or unrecognised `defaults/agent` all produce the setup tile.
→ with `~/.config/omarchy/defaults/agent` absent, and again with junk in it,
`moarchy-agent entry` writes `Name=AI Agent` and `X-Moarchy-Agent=none`

**P4** The icon is a **file path**, never a theme name. No agent has an icon in
Adwaita, breeze or hicolor, which is what left this on `system-run` -- a stock
glyph the grid already draws for Terminal and Foot. The three candidates tried
before it were worse: `applications-development` exists, at
`breeze/categories/{22,32}/`, and a `categories/` icon is not one the drawer's
lookup finds, so the tile came up **empty**; `accessories-dictionary` and
`text-x-script` came up empty as well. `AppLibrary.iconSource()` returns a file
URL for anything starting with `/` and never consults the theme, which is the
same escape the three plugin entries take.
→ the tile's `Icon=` starts with `/`, and that path exists

**P5** The list of agents is **one list**. moarchy-agent's `agents()`, the choice
rows on `apps.default.agent`, and the icons in `/usr/share/moarchy/agents` are
three copies of it, and all three are checked against upstream's own
`omarchy:args=` line rather than against each other -- so an agent upstream adds
fails loudly here instead of quietly arriving with no icon.
→ `moarchy-agent list` sorted equals the names in `omarchy-default-agent`'s
`omarchy:args=[...]`, equals the choice-row ids on `apps.default.agent`, and
equals the `.svg` basenames in `/usr/share/moarchy/agents` once `setup.svg` --
the one file there that is not an agent (P10) -- is set aside. `setup.svg`
itself must be present, so setting it aside cannot hide its absence.

**P6** All nine names are on PATH from first boot, and nothing was downloaded to
put them there. `omarchy-mise-install` writes a five-line wrapper that runs
`mise use -g <package>` on **its** first invocation, so the cost of the eight
agents nobody picked is eight small files. What it buys is that the agent's own
name works in a terminal, that `omarchy-cmd-present <name>` is true, and that
upstream's keybinding launcher -- which gives up on `omarchy-cmd-missing` before
it ever reaches mise -- has something to find.
→ after `moarchy-agent seed`, every name in `moarchy-agent list` resolves through
`command -v`, and every file it resolves to names `mise`

**P7** A binary somebody put in `~/.local/bin` by hand is left alone.
`omarchy-mise-install` always clobbers, and seeding nine names into a directory
the user also writes to must not be how a real install disappears.
→ with a non-mise `~/.local/bin/claude` in place, `moarchy-agent seed` leaves it
byte-identical

**P8** An upgraded phone loses the old per-agent tiles. A device that was flashed
rather than reflashed still has `moarchy-agent-grok.desktop` from first boot, and
one more for every agent that was ever opened; P1 is not true on it until those
are gone.
→ with `moarchy-agent-grok.desktop` present, any `moarchy-agent entry` leaves no
`moarchy-agent-*.desktop` behind

**P9** The default can still be set behind this script's back, and the repair is
one command. `omarchy-default-agent <name>` typed into a terminal writes
`~/.config/omarchy/defaults/agent` without passing through `moarchy-agent`, so
the tile keeps naming the agent before it.
→ after `omarchy-default-agent codex`, `moarchy-agent entry` with no argument
leaves `X-Moarchy-Agent=codex`

**P10** The setup tile opens the picker rather than installing anything. It is
one tap to the screen that lists all nine and installs any of them, where before
that screen was four taps deep with nothing in the grid pointing at it. The IPC
is the one the plugin entries already use to raise a shell surface from a
`.desktop` (`Exec=omarchy-shell shell toggle moarchy.wifi`).
→ the setup tile's `Exec` is `omarchy-shell settings openAt apps.default.agent`;
running it answers `ok` and leaves `settings page` == `apps.default.agent` with
its nine choice rows drawn

**P11** A new user can find that screen by the name of the agent they want. The
setup tile carries all nine agent names as `Keywords`, so typing `claude` into
the drawer on a phone with no agent installed finds the screen that installs
Claude -- which is the search that returned nothing at all before.
→ the setup tile's `Keywords` contains every name in `moarchy-agent list`

## The IPC surface

These verbs exist so the ACs above are checkable without touching the screen.

Quickshell's typed IPC has no optional arguments -- a declared parameter is
required -- so the no-argument and one-argument forms are separate verbs rather
than one with a default.

```
omarchy-shell settings state                -> open | closed
omarchy-shell settings open                 -> ok                (at the root)
omarchy-shell settings openAt <pageId>      -> ok | unknown page: <id>
omarchy-shell settings close                -> ok
omarchy-shell settings page                 -> <pageId>
omarchy-shell settings stack                -> pageIds, root first
omarchy-shell settings goto <pageId>        -> ok | unknown page: <id>
omarchy-shell settings back                 -> <pageId> | closed
omarchy-shell settings rows                 -> TSV, the open page
omarchy-shell settings rowsOn <pageId>      -> TSV, another page
omarchy-shell settings value <rowId>        -> on | off | <choice value> | <input text> | ""
omarchy-shell settings set <rowId> <value>  -> ok | hidden | unknown row
omarchy-shell settings activate <rowId>     -> ok | hidden | not ready | unknown row
omarchy-shell settings confirmText          -> the armed question, or ""
omarchy-shell settings confirm              -> ok | nothing to confirm
omarchy-shell settings focused              -> the focused input's rowId, or ""
omarchy-shell settings guards               -> TSV rowId 0|1
omarchy-shell settings refresh              -> ok
omarchy-shell settings dryRun <0|1>         -> ok
omarchy-shell settings dryRunState         -> 0 | 1
omarchy-shell settings lastLaunch           -> the command line of the last launch
omarchy-shell settings coverage             -> TSV upstreamId class pageId rowId
omarchy-shell settings geometry             -> w= h= margin= strip= gap= screen=
omarchy-shell settings runRow <page> <row>  -> ok | unknown page: <id> | unknown row
```

Section O adds three verbs to the drawer's own handler and one here.

```
omarchy-shell drawer type <text>            -> ok      (sets the field, flushes the debounce)
omarchy-shell drawer results                -> TSV key type label section visible
omarchy-shell drawer matches                -> TSV key guarded|-
omarchy-shell drawer activateResult <key>   -> ok | unknown result | hidden
```

`results` is what the section is drawing; `matches` is what the index found
before the guards were asked. O7 is the difference between the two, and with one
verb it would not be checkable: a row missing from a one-verb answer could
equally mean its guard said no, its guard has not answered yet, or the query
never matched it.

`runRow` is the quiet path a drawer result takes: stand the stack up on `page`,
run that page's guard batch, then activate `row` -- and show the surface only if
the row asks a question, refuses, or is one of the kinds that has a screen to
show. It answers on dispatch, because the guards are a `bash -lc` away; what
happened is read afterwards from `state`, `page` and `lastLaunch`. `activate`
cannot stand in for it: `rowById` resolves against the page that is open, so the
row has to be standing before it can be named.

The `rows` TSV is `rowId, type, label, visible, checked, detail, enabled`.
Visibility and state are only real for the page that is open; `rowsOn` answers
`?` for another page's, because its guards have not been run and `0` would read
as "hidden" rather than "not asked".

`enabled` is the seventh column and is not `visible` restated: a row that is
drawn but cannot act yet -- Set a reminder with no duration typed -- is visible
and disabled, and answers `not ready` to `activate` (J8).

`refresh` re-reads the whole page, provider included. It used to re-run only
the guard batch, which on a provider page meant the Clear all row could correctly
appear while the list above it still said "No reminders set" -- the state that
made J13 fail on the device.

`dryRunState` reads back what `dryRun` set, and exists because the selftest's
most delicate block rests on it. Every check that activates a row without wanting
it to happen has dry run as its precondition, and when *that* call was the one
dropped the run did the opposite of what it said: the rows really fired, `back`
popped the page, and the next `activate` answered `unknown row` -- a red J9 that
had nothing to do with J9. A verb that can only be written cannot be asserted
before it is relied on.

`confirm` presses Continue on the sheet `confirmText` reports. Both exist so a
destructive row can be tested from ssh at all: `activate` on a row that carries
`confirm` arms the question and returns, and before these there was no verb that
could answer it.

`geometry` reports what the compositor granted this surface, and exists because
nothing else can: sway's IPC does not list layer surfaces. `h` is the configure
the window received; `margin` is only our own property read back. It answers
`docs/gestures.md` I2 and I4, not anything in this file.

`coverage` is emitted from `Pages.js`, not from this doc. That is what makes
parity a bash assertion rather than a promise.

## Known-bad, and deliberately so

- **`update.config.shell` stays hidden permanently.** `omarchy-refresh-shell`
  rewrites `~/.config/omarchy/shell.json` from Omarchy's defaults, dropping
  `bar.id: moarchy.bar` and every `moarchy.*` entry from `plugins[]`.
  It succeeds, then restarts into the thirteen-widget desktop bar with no drawer,
  shade or gestures.
- **There is no Branding page.** Its six rows edited two files of ASCII art, and
  nothing on this phone renders either. About Omarchy is a page of rows now
  (section N), and `omarchy-screensaver` opens with a check for `ttfx`, which has
  no aarch64 build in any repo this image uses -- which is why
  `system.screensaver` was already Unsupported. Nor is it a rendering job going
  begging: the art is 54 columns, and 54 columns across 360 logical pixels is
  about six pixels a character. A setting whose effect cannot appear anywhere is
  worse than a missing one, because it looks like it worked.
- **No vendored popup dismisses on tap-outside.**
  `pkgbuilds/omarchy-config/port-4x.patch` stubs `HyprlandFocusGrab`, which has
  no `Quickshell.I3` counterpart. AC B5 is the compensation, not a fix.

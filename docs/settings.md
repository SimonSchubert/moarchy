# Settings — specification

What the phone's Settings UI must do. Present tense, normative. Which upstream
menu entry lands where is recorded in `docs/menu-coverage.md`; the archaeology of
*why* lives in `docs/build-log.md`. This file is the contract.

Each AC is checkable from a terminal over ssh, with no finger on the screen.
`bin/mobileomarchy-selftest --settings` cites these ids, so an AC with no test is
visible.

## Vocabulary

| Term | What it means |
| --- | --- |
| **Settings** | The `mobileomarchy.settings` overlay. One plugin, many pages. |
| **page** | One screen in the stack, addressed by a dotted id (`appearance.bar`). |
| **stack** | The pages currently pushed, root first. Back pops one. |
| **row** | A line on a page. One of `nav`, `plugin`, `switch`, `choice`, `action`, `link`, `info`. |
| **guard** | A `when:` shell condition copied verbatim from `omarchy-menu.jsonc`. A row whose guard fails is not rendered. |
| **reader** | The command a `switch` or `choice` page reads its state from. |
| **bridged launch** | Running an upstream `omarchy-*` command unchanged, in a fullscreen TUI or the browser. |
| **the shade** | The pull-down (`mobileomarchy.shade`), which owns the radios and sliders. |

## The screen tree

Root is noun-shaped, the way a phone settings app is, not verb-shaped like
upstream's dmenu. Ten rows:

```
Settings
├─ Network & internet   Private DNS · Wi-Fi networks · Bluetooth devices · Wi-Fi QR · Speed test
├─ Display              Night light · Stay awake · Screen blanks after
├─ Sound & notifications Audio devices · Crash capture
├─ Appearance           Theme · Wallpaper · Font · Status bar · Branding · Get more
├─ Apps & defaults      Default apps · Web apps · Terminal apps · Packages
├─ Shell & plugins      Plugins · Restart shell · Reset tmux config
├─ Security             Remote access · Passwordless sudo · Change password
├─ Tools                Screenshot · Screen record · Emoji · Reminders · Screensaver · Speed tests
├─ System               Date & time · Restart hardware · Power
└─ About phone          Version · Keybindings · Help & docs · About Omarchy
```

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

Two rows exist that upstream has no id for: **Wi-Fi networks** (`impala`) and
**Bluetooth devices** (`bluetui`). The shade toggles both radios but can neither
join a network nor pair a device.

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
→ `settings open appearance.bar` == `ok` and `settings page` == `appearance.bar`;
`settings open nope` == `unknown page: nope`

**A5** `open()` never blocks. The page paints with whatever state it has and fills
in afterwards; no `FileView` and no synchronous read runs inside it.
→ `settings state` answers `open` within 300 ms of `settings open`, on a session
where every reader has been made slow

**A6** Closing and reopening lands on the root, never on the page last left.
→ `settings close; settings open; settings page` == `root`

## B. The page stack and back

**B1** A `nav` row pushes exactly one page, and the header shows that page's title.
→ `settings stack` gains one line; `settings page` is the pushed id

**B2** The header chevron pops one page and stops at the root.
→ from depth 3, `settings back` returns `appearance`, then `root`, then `closed`

**B3** The left-edge back gesture pops one page, and closes Settings only when the
root is on top. It never closes the app underneath.
→ from depth 2: `settings page` moves up one and the open-window count is unchanged

**B4** An up-swipe from the strip puts Settings away and does nothing else —
`gestures.md` A8 applied to this surface.
→ `settings state` == `closed`; open-window count unchanged

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
→ on a base install, `settings rows apps.default` shows `browser` with `visible=0`

## C. Switches

**C1** Every `switch` reads its state from a command at page-open, never from a
remembered value.
→ for each switch, `settings value <id>` matches its reader run directly

**C2** The four negative-polarity flags render inverted: a present flag file means
the feature is **off**.
→ `omarchy-toggle bar-off on; settings refresh; settings value bar.show` == `off`

**C3** Writing a switch re-reads it; the row shows the new value without the page
being reopened.
→ `settings set bar.show on; settings value bar.show` == `on`, and
`omarchy-toggle-enabled bar-off` exits non-zero

**C4** Turning the status bar off does not restart or kill the shell.
→ the `quickshell` pid is unchanged across `settings set bar.show off`, and
`settings state` is still `open`

**C5** Stay awake actually stops the panel blanking, not just the row.
→ `omarchy-toggle-idle status | jq .enabled` == `true`, and the swayidle timeout
command is a no-op while the flag is set

**C6** Transparency is observable in the bar, not only in `shell.json`.
→ after `settings set bar.transparent on`, the bar's `transparent` property reads
back `true`

**C7** Crash capture reflects the unit, not only the flag.
→ after `settings set sound.crashcapture off`, `omarchy-toggle-enabled
crash-capture-off` exits 0 and the watch service is not `active`

**C8** A switch may read natively while writing through a bridged launch.
→ `settings value security.ssh` matches `systemctl is-enabled --quiet sshd`

## D. Choices

**D1** Exactly one row on a choice page is ticked, and it is the one the page's
reader names.
→ `settings rows net.dns | grep -c 'checked=1'` == `1`, and that row's value ==
`$(omarchy-dns)`

**D2** A reader answering something no row declares ticks nothing, rather than
ticking the first row.
→ with `omarchy-dns` stubbed to print `Quad9`, the checked count is `0`

**D3** Read-value and write-value are separate fields.
→ `settings coverage` for `setup.default.editor.zed` names `readValue=zeditor`
and `value=zed`

**D4** Setting a choice re-reads the page's reader and moves the tick.
→ `settings set net.dns Cloudflare; settings value net.dns` == `Cloudflare`

**D5** A choice page's parent `nav` row shows the current value as its detail line.
→ the `dns` row on page `net` has detail == `$(omarchy-dns)`

**D6** The font page is populated from the provider, not a hard-coded list.
→ `settings rows appearance.font | wc -l` == `omarchy-font-list | wc -l`

## E. Bridged launches

**E1** In dry-run, a bridged row records the command it would run and runs nothing.
→ `settings dryRun 1; settings activate tools.screensaver; settings lastLaunch` ==
`omarchy-launch-screensaver force`, and no new window appears

**E2** Every bridged row's command is byte-identical to the `action` string in
`omarchy-menu.jsonc` for the id it covers.
→ `settings lastLaunch` matches `jq -r '.["<id>"].action'` of the upstream file

**E3** Every command named by a Native or Bridged row resolves on the shell's PATH.
→ `command -v <first word>` succeeds under the PATH in
`/proc/$(pgrep -x quickshell)/environ`

**E4** The bridge shims exist and shadow upstream.
→ `command -v` for `omarchy-launch-floating-terminal-with-presentation`,
`omarchy-launch-config-editor` and `omarchy-launch-webapp` each starts with
`$MOBILEOMARCHY_PATH/bin`

**E5** A bridged TUI opens fullscreen, identifiable, and typeable.
→ `swaymsg -t get_tree` shows an `app_id == "moa-tui"` node filling the workspace;
focusing its prompt raises `sm.puri.OSK0`

**E6** Launching a bridged row puts Settings away first, so the terminal is not
covered by a layer surface.
→ `settings state` == `closed` when the child process starts

**E7** A bridged row that summons a vendored picker reaches it.
→ after `settings activate shell.plugins.enable`, `omarchy-shell shell listPlugins`
shows `omarchy.menu` open within 2 s

**E8** A bridged run leaves its output on screen until dismissed; it does not flash
and vanish.
→ the window survives 5 s after the wrapped command exits

## F. Hidden when unsupported

**F1** No id classified Unsupported is reachable as a row anywhere.
→ the intersection of `settings coverage` Unsupported ids and every id in
`settings rows --all` is empty

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

## G. Coverage parity

**G1** The coverage map names every id in `omarchy-menu.jsonc`, and no others.
→ `diff <(settings coverage | cut -f1 | sort) <(jq -r 'keys[]' <stripped jsonc> | sort)`
is empty

**G2** Every id appears exactly once.
→ `settings coverage | cut -f1 | sort | uniq -d` is empty; the line count is `320`

**G3** Every class is one of the four words.
→ `settings coverage | cut -f2 | sort -u` == `Bridged Native Shade Unsupported`

**G4** Every Native and Bridged id resolves to a page and row that exist.
→ `settings rows <pageId>` contains `<rowId>` for each

**G5** Every Unsupported id carries a non-empty reason.
→ no Unsupported row has an empty reason field

**G6** The doc and the code agree.
→ `diff` of `settings coverage | cut -f1,2` against the table in
`docs/menu-coverage.md` is empty

**G7** The class totals are the ones committed to.
→ `settings coverage | cut -f2 | sort | uniq -c` == 78 Bridged, 63 Native,
1 Shade, 178 Unsupported

## H. Not repeating the shade

**H1** No control the shade owns appears in Settings: Wi-Fi radio, Bluetooth radio,
airplane mode, brightness, volume, silent, torch, rotate, media transport.
→ no row label matches `^(wi-?fi|bluetooth|airplane|brightness|volume|silent|torch|rotate)$`

The two rows that open `impala` and `bluetui` are network *configuration*, not
radio toggles, and are named "Wi-Fi networks" and "Bluetooth devices".

**H2** The single Shade-class id is recorded and not rendered.
→ `settings coverage` shows `trigger.toggle.notifications` as `Shade`;
`settings rows --all` does not contain it

## I. Robustness

**I1** A Settings plugin that fails to load is loud, not a gear that does nothing.
→ `omarchy-shell shell listPlugins` contains `mobileomarchy.settings`, and
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

**I5** `$MOBILEOMARCHY_PATH/bin` comes first on the shell's PATH.
→ the PATH in `/proc/$(pgrep -x quickshell)/environ` lists it before
`$OMARCHY_PATH/bin`. If upstream wins, every bridge shim opens nothing

## The IPC surface

These verbs exist so the ACs above are checkable without touching the screen.

```
omarchy-shell settings state                -> open | closed
omarchy-shell settings open [<pageId>]      -> ok | unknown page: <id>
omarchy-shell settings close                -> ok
omarchy-shell settings page                 -> <pageId>
omarchy-shell settings stack                -> pageIds, root first
omarchy-shell settings goto <pageId>        -> ok | unknown page: <id>
omarchy-shell settings back                 -> <pageId> | closed
omarchy-shell settings rows [<pageId>]      -> TSV rowId type label visible detail
omarchy-shell settings value <rowId>        -> on | off | <choice value> | ""
omarchy-shell settings set <rowId> <value>  -> ok | hidden | unknown row
omarchy-shell settings activate <rowId>     -> ok | hidden | unknown row
omarchy-shell settings guards [<pageId>]    -> TSV rowId 0|1
omarchy-shell settings refresh              -> ok
omarchy-shell settings dryRun <0|1>         -> ok
omarchy-shell settings lastLaunch           -> argv of the last bridged launch
omarchy-shell settings coverage             -> TSV upstreamId class pageId rowId reason
```

`coverage` is emitted from `Pages.js`, not from this doc. That is what makes
parity a bash assertion rather than a promise.

## Known-bad, and deliberately so

- **`update.config.shell` stays hidden permanently.** `omarchy-refresh-shell`
  rewrites `~/.config/omarchy/shell.json` from Omarchy's defaults, dropping
  `bar.id: mobileomarchy.bar` and every `mobileomarchy.*` entry from `plugins[]`.
  It succeeds, then restarts into the thirteen-widget desktop bar with no drawer,
  shade or gestures.
- **`setup.plugin.remove` can uninstall the phone UI.** Its upstream guard is true
  here — six `mobileomarchy.*` manifests match it. Kept, behind a confirm.
- **No vendored popup dismisses on tap-outside.** `install/port-4x.sh` stubs
  `HyprlandFocusGrab`, which has no `Quickshell.I3` counterpart. AC B5 is the
  compensation, not a fix.

# Can Omarchy 4.x run on the PinePhone?

**Answered: yes. It has been what moarchy ships since 2026-09-06.** This
document is kept as the correction to an earlier assessment in this repo that
was wrong, and as the record of what the port actually cost. The tense below is
the tense it was written in, on 2026-09-02, when the question was still open;
the outcome is in the README and the port itself is
`pkgbuilds/omarchy-config/port-4x.patch`.

## What the earlier assessment got wrong

The v3.8.4 pin was originally justified partly on the claim that *"4.x moved to
**herdr**, a bespoke shell shipped only as an x86_64 binary"*. That is incorrect
on two counts:

1. **herdr is not the shell.** Its package description reads *"Herdr terminal
   workspace manager for AI coding agents"* — a terminal multiplexer-ish tool,
   not a bar or launcher.
2. **herdr is not closed.** It is Apache-2.0 Rust with public source
   (`https://github.com/herdrdev/herdr`, and dhh's fork). It builds from source;
   it is merely absent from Omarchy's *binary* repo for aarch64.

The actual 4.x shell is **95 QML files shipped inside the Omarchy repo itself**
(`shell/**/*.qml`), rendered by **quickshell**. That is open source too.

## What was verified on the device (2026-09-02)

| Question | Finding |
| --- | --- |
| Is quickshell packaged for aarch64? | **Yes** — `quickshell 0.3.1-1` in Arch Linux ARM, with `qt6-declarative`, `qt6-wayland` |
| Does Qt/QML render on a Mali-400 (GLES 2.0)? | **Yes** — a layer-shell QML panel rendered correctly on the phone |
| Is there a Sway path, or is it Hyprland-only? | **`Quickshell/I3` module ships** — i3/Sway IPC, counterpart to `Quickshell.Hyprland` |
| How Hyprland-coupled is the QML? | **5 of 95 `.qml` files** import `Quickshell.Hyprland` |
| Is herdr buildable here? | Rust + Apache-2.0, `rust` is in ALARM for aarch64 |

The remaining 90 QML files import only compositor-agnostic modules:
`Quickshell`, `Quickshell.Io`, `Quickshell.Wayland`, and the service modules
(Pipewire, UPower, SystemTray, Pam, Notifications, Mpris).

## First run: it already loads

`scripts/experiment-4x.sh` ran Omarchy **v4.0.2's actual `shell/shell.qml`**
under quickshell on the phone, on 2026-09-02. (That script and
`scripts/port-4x-shell.sh` below were probes against a live v3.8.4 session and
were deleted once the port shipped; both are in git history.) It reached
`INFO: Configuration Loaded` and **stayed running**:

```
RUNNING -- RSS 197 MB
(waybar for comparison: 79 MB)
available RAM: 1246 MB
```

**Memory is not the blocker.** An earlier draft of this document predicted RAM
would sink the port, extrapolating from a 175 MB trivial panel. The real shell
costs 197 MB against 1246 MB available — roughly 16%, and only ~2.5x waybar.
That is affordable.

What actually failed is small and enumerable — every error was a missing
Hyprland dependency, not a rendering or resource problem:

```
WARN: Process failed to start ... Command: ("hyprctl","-j","getoption","decoration:rounding")
WARN: Process failed to start ... Command: ("hyprctl","-j","getoption","general:gaps_out")
WARN: Process failed to start ... Command: ("inotifywait", ...)
WARN qml: default shell.json load failed: 2 path=/config/omarchy/shell.json
```

So the concrete work is:

1. **Shim `hyprctl`** for the two options the shell reads (`decoration:rounding`,
   `general:gaps_out`) — a tiny script emitting the JSON sway equivalents. This
   repo already ships an `hyprctl`-shaped shim pattern in `bin/`.
2. **Repoint 5 QML files** from `Quickshell.Hyprland` to `Quickshell.I3`:
   `shell/plugins/services/idle/Service.qml`, `shell/plugins/bar/Bar.qml`,
   `shell/plugins/bar/widgets/Workspaces.qml`,
   `shell/plugins/bar/widgets/KeyboardLayout.qml`, `shell/Ui/PopupCard.qml`
   (5 of 95 `.qml` files).
3. **`pacman -S inotify-tools`** for the plugin file watcher.
4. **Set `OMARCHY_PATH`** so `$OMARCHY_PATH/config/omarchy/shell.json` resolves —
   the log shows it resolving to a bare `/config/omarchy/shell.json`.

## It runs: the 4.x bar renders under Sway

`scripts/port-4x-shell.sh` first reproduced this from a clean checkout; the
translation it prototyped is now `pkgbuilds/omarchy-config/port-4x.patch`,
applied at build time in that package's `prepare()`.
After the translation below, **Omarchy v4.0.2's bar renders on the PinePhone under Sway**,
populated with workspaces, clock, bluetooth, wifi, volume and battery. RSS
settles around 200-260 MB.

The translation is mechanical because `Quickshell.I3` mirrors the Hyprland
singleton for everything this shell touches:

| Omarchy 4.x uses | Sway equivalent | Notes |
| --- | --- | --- |
| `import Quickshell.Hyprland` | `import Quickshell.I3` | 5 files |
| `HyprlandEvent` | `I3Event` | |
| `target: Hyprland` | `target: I3` | bare singleton, no dot — easy to miss with a naive regex |
| `Hyprland.workspaces` / `.focusedWorkspace` / `.focusedMonitor` | same names on `I3` | |
| `onRawEvent` | exists on `I3` | |
| `HyprlandFocusGrab` | **no counterpart** | lives only in `Quickshell/Hyprland/_FocusGrab`; neutralised, so popups lose click-outside-to-dismiss |

Two further requirements, both easy to miss:

- **`SWAYSOCK` must be exported.** Without it `Quickshell.I3` logs
  *"$SWAYSOCK and I3SOCK are unset. Cannot connect to socket"* and the bar draws
  but never populates.
- **A `hyprctl` shim** answering `decoration:rounding` and `general:gaps_out`.
  The shell shells out to `hyprctl` for layout metrics; without it every call
  logs "binary could not be found".

### The one defect the first pass left, since fixed

```
Workspaces.qml[58]: TypeError: Cannot read property 'values' of undefined
```

`I3Workspace` has no `toplevels` model, so upstream's `occupied` binding read
`.values` off `undefined`. `port-4x.patch` answers it from sway's own
`representation` string instead, and adds a `wsNumber()` helper because sway's
visible number is `.number` (or `.num`) where Hyprland conflated number and id.

## What still cannot work

Hyprland itself, for the reason in the README: the Mali-400 is GLES 2.0 and
Hyprland hard-requires a GLES 3.0 context. So 4.x's `default/themed/hyprland.lua.tpl`,
`omarchy-hyprland-*` scripts, hyprlock, hypridle and hyprsunset all remain
unusable — the Sway substitution this repo does for the *compositor* is
unchanged by 4.x. What 4.x changes is that the *shell* layer is adopted rather
than replaced.

## How it went

The plan below was written on 2026-09-02 with step 1 done. All of it except
herdr landed by 2026-09-06, and the outcome replaced the 3.8.4 port rather than
running beside it.

1. ~~**Memory ceiling.**~~ Done: 197 MB of 1246 MB available. Not a blocker.
2. ~~**Sway substitution.**~~ Done, and it is
   `pkgbuilds/omarchy-config/port-4x.patch` — 9 files, applied in
   `omarchy-config`'s `prepare()` at build time rather than by a script on the
   phone (`docs/structure.md` P3, P4).
3. ~~**Theme bridge.**~~ Done: the same `colors.toml` drives `shell.toml.tpl`,
   and all 22 themes work with `default/themed/sway.conf.tpl` as the only file
   added.
4. **herdr build.** Not done and not needed. herdr is a terminal workspace
   manager, not part of the shell; `learn.herdr-keybindings` is Unsupported in
   `docs/menu-coverage.md` and nothing else refers to it.
5. ~~**Path migration.**~~ Done: the current theme is read from
   `~/.local/state/omarchy/current`.

**What it turned out to be.** Not a second branch. moarchy runs Omarchy v4.0.2
(`346e69e`) and the v3.8.4 port is gone from the tree — it exists only in git
history. Whether `omarchy-config` should stay a package at all, versus vendoring
the shell outright, is the live version of this question now; the patch size is
the test, and `docs/structure.md` §12 Q5 carries it.

# Can Omarchy 4.x run on the PinePhone?

**Short answer: probably yes, and it is a real project rather than a dead end.**
This document exists because an earlier assessment in this repo was wrong, and
the correction matters.

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

### Known remaining defect

```
Workspaces.qml[58]: TypeError: Cannot read property 'values' of undefined
```

`I3.workspaces` has a different shape to Hyprland's. Workspaces still render, so
this is a refinement rather than a blocker, and it is the obvious next task.

## What still cannot work

Hyprland itself, for the reason in the README: the Mali-400 is GLES 2.0 and
Hyprland hard-requires a GLES 3.0 context. So 4.x's `default/themed/hyprland.lua.tpl`,
`omarchy-hyprland-*` scripts, hyprlock, hypridle and hyprsunset all remain
unusable. A 4.x port would need the same Sway substitution this repo already
does for 3.8.4 — the difference is that the *shell* layer would be adopted
rather than replaced.

## Suggested order of experiments

Step 1 is **done** (see above) and it passed.

1. ~~**Memory ceiling.**~~ Done: 197 MB of 1246 MB available. Not a blocker.
2. **Sway substitution.** Repoint the 5 `Quickshell.Hyprland` imports at
   `Quickshell.I3` and see how much behaviour survives (workspaces, focus).
3. **Theme bridge.** 4.x themes through `shell.toml.tpl` rather than
   `waybar.css.tpl`; check whether the same `colors.toml` still drives it.
4. **herdr build.** Straightforward Rust cross-build in the existing
   `docker/Dockerfile.builder` container — do this last, it is optional polish.
5. **Path migration.** 4.x moved the current theme from
   `~/.config/omarchy/current` to `~/.local/state/omarchy/current`.

## If it works

The result would be a second branch of this project — Omarchy 4.x's shell on
Sway — rather than a replacement. Keep the v3.8.4 path working until the 4.x one
is demonstrably better on this hardware, because 3.8.4 is known-good today.

# Keep, in the shell

The GTK Keep app takes about four seconds to a window on a PinePhone,
because it starts Python and GTK. This plugin is an `Item` the shell already
holds: summoning it is `visible = true` on a `FloatingWindow` in the running
`omarchy-shell` process.

It is the same app. The notes file is `~/.local/share/moarchy-keep/notes.json`,
the file the GTK app already writes. A note typed here is a note over there.

It is a **window**, not a layer overlay. Keep has text fields, and a
`WlrLayer.Overlay` surface draws over the on-screen keyboard. Settings,
Wi-Fi and Bluetooth in the shell already made this move; this follows them.

It is not GTK. It is drawn to look like the GTK app: the same `colors.toml`,
the same 24%/30% mix into the background for the nine note colours, 12px
cards, a pill search, 44px swatches, and Adwaita Sans if the font is there.
`omarchy-theme-set` restages that file; a `FileView` on it recolours the
grid without restarting the shell.

## Install on the phone

From this repository:

```sh
plugins/moarchy.keep/install-on-device.sh
```

That copies the plugin into `~/.config/omarchy/plugins/moarchy.keep`,
asks the shell to validate and enable it, writes a `.desktop` entry so the
app drawer can summon it, and restarts the shell.

Then tap **Keep** in the app drawer. Time it against the GTK Keep: the GTK one
starts a process, this one does not.

```sh
omarchy-shell shell toggle moarchy.keep
omarchy plugin validate moarchy.keep
```

## Run it without the shell

`shell.qml` is the same app as its own Quickshell process, for a machine that
has Quickshell and none of omarchy:

```sh
plugins/moarchy.keep/run-local.sh     # vendors ui/, then quickshell -p
```

This did not work until the chrome moved to `qs_ui`. Keep was written
against `qs.Commons` and `qs.Ui`, so it could only ever run inside the shell --
which meant no check could start it, no screenshot could be taken of it, and a
laptop could not open it at all. Four files went with those imports:
`AppWindow.qml`, `Theme.js`, `Icon.qml` and `PressVeil.qml` were all local
copies of what the kit now provides, and the kit's versions had since grown a
fallback walk for missing icons and a light-theme palette this one never had.

What stayed is what is genuinely Keep's: `Notes.js`, the nine note colours and
the wash they are mixed at.

`Style.space` was the one coupling the kit had no answer for -- the shell's rem
for margins, which follows the text size. `Metrics.space(px, parent)` now probes
it exactly as `Metrics.shellBody` probes the font size, and falls back to the
numbers this file was written with when there is no shell to ask.

## What it does not do yet

Masonry is two columns of greedy packing, not the GTK widget. Undo after
delete is missing. The card menu is a bottom sheet rather than a popover.
Those are the next cuts if the summon time is the number we came for.

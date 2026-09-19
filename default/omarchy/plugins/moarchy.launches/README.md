# Launches, in the shell

The GTK app starts Python and GTK; this is an `Item` the shell already holds,
so summoning it is `visible = true` on a `FloatingWindow`.

It is the same app. The stars are
`~/.local/share/moarchy-launches/favourites.json` and the cache is
`upcoming.json` — the files the GTK app writes — so a launch starred here is
starred over there.

Chrome comes from [`qs_ui`](../../qs_ui), copied into this
plugin as `ui/` at install time: a third-party plugin cannot import
`moarchy.common`, and vendoring is what Python's `moarchy_ui` already does.

## What it does

Two tabs along the bottom, where a thumb is. **Upcoming** is the next twenty
by NET; **Starred** is the same rows in the order you tapped a star, because a
watchlist sorted by countdown reorders itself under a thumb halfway down it.

- status as a short mark in a coloured disc — colour is never the only signal
- a countdown that knows how well the time is known: `T-04:21:07` for a NET to
  the second, `Q3 2026` for a quarter, a date for TBD and TBC
- search by mission, vehicle, agency or pad, from the front of any word
- a tap opens window, orbit, probability, weather, hold and description out of
  the answer already in memory — no second request

## The network

One `GET` of Launch Library 2 `/launch/upcoming/?limit=20`, through `curl`,
with the same user agent and twelve-second timeout the Python app uses.
`MOARCHY_LAUNCHES_KEY` is sent as `Authorization: Token …` when it is set.

The clock ticks once a second only while the window is on screen, and the pad
is asked again at most four times an hour — every five minutes inside an hour
of a launch, every two inside ten. A refresh that fails keeps the launches on
screen, says `Not updating · 4 min ago` in the header, and backs off.

## Install on the phone

```sh
plugins/moarchy.launches/install-on-device.sh
```

Then tap **Launches** in the app drawer, or:

```sh
omarchy-shell shell toggle moarchy.launches
```

## Run it without the shell

`shell.qml` is the same app as its own Quickshell process, for a machine that
has Quickshell and none of omarchy:

```sh
plugins/moarchy.launches/run-local.sh     # vendors ui/, then quickshell -p
```

The plugin host is the only thing that goes missing, and everything that
needed it was already optional: `shell` stays null so the summon-and-return
calls are skipped, `colors.toml` is not staged so the built-in palette stands,
and closing the window ends the process instead of hiding a surface the shell
would otherwise keep alive. Same files, both ways — the phone is not running a
port of this, it is running this.

## What is not here yet

The GTK app's environment variables for the harness
(`MOARCHY_LAUNCHES_PAGE`, `_OPEN`, `_SEARCH`, `_NOW`, `_OFFLINE`) are still not
read; only `_KEY` is. What has changed is the reason. There *is* a screenshot
harness for plugins now — `scripts/qml-shot.sh`, which runs one under headless
sway and takes the picture with `grim` — so these are a job left undone rather
than a job with nothing to do it.

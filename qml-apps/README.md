# qml-apps

The Quickshell apps from [moarchy-apps](https://github.com/SimonSchubert/moarchy-apps),
snapshotted here so a package can ship them.

They cannot be fetched as a GitHub tarball yet: calculator, calendar, clock,
contacts, files and weather are still uncommitted in that tree, and a pin
would silently drop the five apps this package exists to put on a fresh
phone. `scripts/sync-qml-apps.sh` copies the working tree in front of you.

`ui.catalog` is a kit review window, not an app, and is not in this snapshot.

`pkgbuilds/moarchy-qml-apps` vendors `qs_ui/` into each plugin as `ui/` at
package time -- the same layout `install-on-device.sh` writes on a handset --
installs every `.desktop` file into `/usr/share/applications`, and a plugin's
`bin/` into `/usr/bin`. Two plugins have either. The editor's hidden entry is
what xdg-open runs for a text file, and `moarchy-editor` is what `$EDITOR`
runs, because a plugin is not a process that can be waited on. Mail's hidden
entry is what a `mailto:` link opens, and `moarchy-mail` is every conversation
it has with a mail server, because a plugin cannot open a TLS socket.

Edit the plugins in moarchy-apps and sync, not here. A change made to this
snapshot is undone by the next sync, which replaces everything but this file.

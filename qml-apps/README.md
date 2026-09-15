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
and installs the `.desktop` files into `/usr/share/applications`.

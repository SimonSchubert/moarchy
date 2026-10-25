# Writing a tile or a face

Part of the moarchy skill. SKILL.md, beside this file, comes first.

A **tile** is one QML file drawn in a frame on a page of home's grid. A **face**
is one QML file that is a whole page, drawn straight on the wallpaper. Both are
Qt 6 QML run by quickshell. Neither imports anything of the package's by
relative path. Everything they draw with comes from `host`, which home sets.

Learn from the shipped ones before writing:
`/usr/share/moarchy/plugins/moarchy.common/widgets/` (`Today.qml`, `Fetch.qml`,
`Calendar.qml`) and `/usr/share/moarchy/plugins/moarchy.home/faces/start.qml`.

## A tile

`~/.config/omarchy/widgets/<id>.qml`, then `{ widget = "<id>", ... }` in
`~/.config/omarchy/home.toml`. A file that home.toml does not name is not drawn.

```qml
import QtQuick
import qs.Commons            // Style: Style.space(n), Style.font.*

Item {
  id: widget

  // Set by home when it builds the tile. Declare all three.
  property var host: null
  property var shell: null
  property bool preview: false

  // false leaves the frame empty: say "nothing to show" without a blank card.
  readonly property bool available: true

  // Home sizes the tile to its cells; lay out to width and height.
  Column {
    anchors.fill: parent
    anchors.margins: Style.space(10)
    spacing: Style.space(4)

    Text {
      text: "uptime"                       // a label: lowercase, subdued
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.weight: widget.host.textWeight
      color: widget.host.subdued
    }
    Text {
      text: widget.uptime                  // a value: foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.weight: widget.host.textWeight
      color: widget.host.textOnSurface
    }
  }

  property string uptime: "…"
  Timer {
    interval: 60000; running: true; repeat: true; triggeredOnStart: true
    onTriggered: { /* read something, set widget.uptime */ }
  }
}
```

- **Colours only from `host`**: `textOnSurface` (values), `subdued` (labels),
  `accent` (emphasis), `textOnAccent`, `surface` (the tile fill), `containerHigh`
  (a faint fill inside a tile). No hex: the theme changes, and the tile must
  change with it.
- **Sizes** through `Style.space(n)` (it follows the theme's scale) and
  `Style.font.caption | bodySmall | body | title | display | iconLarge | family`.
- **Don't draw a frame.** Home draws the border and the background. A card
  inside is `host.container`, which is transparent on home.
- **Taps** go through home, so a swipe that starts on your tile still turns the
  page. Pass the area by its id; an arrow function's `this` is not the area:

  ```qml
  MouseArea {
    id: area
    anchors.fill: parent
    onPressed: m => widget.host.sheet.sheetPress(area, m)
    onPositionChanged: m => widget.host.sheet.sheetMove(area, m)
    onReleased: widget.host.sheet.sheetRelease()
    onCanceled: widget.host.sheet.sheetCancel()
    onClicked: if (!widget.host.sheetWasDrag) widget.host.openScreen("moarchy.weather")
  }
  ```

  `openScreen("<plugin id>")` opens an app the shell draws.
- **Reading the system**: `Process` from `Quickshell.Io` with a constant
  command array, `["bash", "-c", "uptime -p"]`, never text built from input.
  Files: `FileView { path: ...; watchChanges: true }`.
- **A tap target is at least 44 px** (`Style.space(44)`) on its short side.

## A face

`~/.config/omarchy/faces/<name>.qml`, then a `[[page]]` with
`face = "<name>"` in home.toml. A user face of the same name as a shipped one
replaces it.

```qml
import QtQuick
import qs.Commons

Item {
  id: face
  property var host: null
  property var shell: null

  // Text on the wallpaper needs a frame to be readable: the package's, from
  // the host, so it wears the user's opacity, border and corners.
  Loader {
    id: box
    x: Style.space(12); y: Style.space(40)
    width: parent.width - Style.space(24); height: Style.space(120)
    Component.onCompleted: if (face.host) box.setSource(face.host.frameUrl, { host: face.host })
  }

  Text {
    anchors.centerIn: box
    text: Qt.formatTime(new Date(), "HH:mm")
    font.family: Style.font.family
    font.pixelSize: Style.font.display * 2
    font.weight: face.host ? face.host.textWeight : Font.Normal
    color: face.host ? face.host.textOnSurface : "white"
  }
}
```

- A shipped widget inside a face: `Loader` with
  `setSource(face.host.widgetUrl("today"), { host: face.host, shell: face.shell })`.
- The face gets the page between the status bar and the bottom strip, with no
  background of its own. Lay it out by `width` and `height`. When
  `width > height` the phone is sideways, so put things side by side.
- A face has no prompt bar. Swiping up still opens the app drawer.

## Checking it

```sh
omarchy-shell home reload        # recompile your files from disk
omarchy-shell home report        # `state=ok`, or `error` / `missing=<id>`
omarchy-shell home go 0        # show the page left of page 1
journalctl --user -b | grep -i qml | tail    # QML errors, with file and line
```

A tile that fails keeps its frame with `<id> did not load` in it, and the
journal has the parse error with its line. A face that fails says so in the
middle of its page.

// One tile on home: the frame, and the widget inside it (docs/home.md §C).
//
// The widget comes from one of two places, decided by the catalogue and never
// by a directory scan (W9, HM14a):
//
//   catalogued for `home`   moarchy.common/widgets/<File>.qml, the package's
//   anything else           ~/.config/omarchy/widgets/<id>.qml, the user's
//
// and it is handed the same three properties WidgetColumn hands a widget --
// `host`, `shell`, `preview` -- so a widget written for the control center
// needs nothing new to be a tile. What differs is the size: here the host gives
// both dimensions (HM9), so the Loader is sized to the frame and the widget's
// implicitHeight is not read.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../moarchy.common/Widgets.js" as WidgetList

Item {
  id: tile

  property var host: null
  property string widgetId: ""
  // Bumped by `home reload`. A changed URL is how a Loader is made to compile
  // a file again: the engine caches components by URL, so an edited user
  // widget would otherwise keep drawing the version it first read.
  property int revision: 0
  // Bumped by this tile's own watch on its file. Kept apart from `revision`,
  // which is bound to home's: assigning to it here would break that binding,
  // and `home reload` would stop reaching this tile after its first edit.
  property int edits: 0

  // docs/owl.md OW4: home on screen and this tile's page the one showing.
  // Read by an OWL widget, which runs only then; a native one ignores it.
  property bool showing: true
  // Its cells, for an OWL widget's tileWidth and tileHeight.
  property int cols: 1
  property int rows: 1

  readonly property bool catalogued: WidgetList.entry("home", tile.widgetId) !== null
  readonly property string userPath:
    (Quickshell.env("HOME") || "") + "/.config/omarchy/widgets/" + tile.widgetId + ".qml"

  // HM17. A user widget that does not exist is said, not guessed at. A Loader
  // cannot tell a missing file from a broken one -- both are Loader.Error -- so
  // the file is looked for first, and only a file that exists is handed to it.
  property bool userFileExists: false
  FileView {
    id: probe
    path: tile.catalogued ? "" : tile.userPath
    printErrors: false
    watchChanges: true
    onLoaded: tile.userFileExists = true
    onLoadFailed: tile.userFileExists = false
    // An agent writing the file while home is up is the case this is for.
    onFileChanged: Qt.callLater(function () { probe.reload(); tile.edits++ })
  }

  // OW2. After the catalogue and a QML file of the user's: an OWL file, the
  // store's or the user's own, drawn by the store's runtime (../moarchy.owl).
  readonly property string owlPath:
    (Quickshell.env("HOME") || "") + "/.config/omarchy/widgets/" + tile.widgetId + ".owl"
  property bool owlFileExists: false
  FileView {
    id: owlProbe
    path: tile.catalogued ? "" : tile.owlPath
    printErrors: false
    watchChanges: true
    onLoaded: tile.owlFileExists = true
    onLoadFailed: tile.owlFileExists = false
    onFileChanged: Qt.callLater(function () { owlProbe.reload() })
  }
  readonly property bool isOwl: !tile.catalogued && !tile.userFileExists && tile.owlFileExists
  readonly property string kind: tile.catalogued ? "native" : tile.userFileExists ? "user" : tile.isOwl ? "owl" : ""

  // The query is on the user's file only. The package's widgets do not change
  // while the shell runs, so they keep a plain URL and the engine's cache.
  readonly property string source: {
    if (tile.widgetId === "") return ""
    if (tile.catalogued)
      return String(Qt.resolvedUrl("../moarchy.common/widgets/" + WidgetList.fileFor(tile.widgetId)))
    if (tile.userFileExists)
      return "file://" + tile.userPath + "?r=" + tile.revision + "." + tile.edits
    // OwlWidget watches its own file, so an edit or an update lands without
    // the cache-busting a QML file needs.
    return tile.isOwl ? String(Qt.resolvedUrl("OwlTile.qml")) : ""
  }

  // What `home report` says about this tile (HM3, HM12, HM13, HM17).
  readonly property string tileState: {
    if (!tile.catalogued && !tile.userFileExists && !tile.isOwl) return "missing"
    if (loader.status === Loader.Error) return "error"
    if (loader.status !== Loader.Ready || !loader.item) return "loading"
    // OW6. An OWL widget has compiled or said why not; until then it loads.
    if (tile.isOwl) return loader.item.error !== "" ? "error" : loader.item.ready ? "ok" : "loading"
    return loader.item.available === false ? "unavailable" : "ok"
  }

  function refresh(): void {
    if (loader.item && typeof loader.item.refresh === "function") loader.item.refresh()
  }

  HomeFrame {
    id: frame
    anchors.fill: parent
    host: tile.host
  }

  Loader {
    id: loader
    anchors.fill: parent
    anchors.margins: frame.inset
    // HM12. An unavailable widget keeps its cells: hidden, never collapsed.
    visible: tile.tileState === "ok"

    function load(): void {
      if (tile.source === "") { loader.source = ""; return }
      if (tile.isOwl) {
        loader.setSource(tile.source, { home: tile.host, owlHost: tile.host ? tile.host.owlHost : null,
                                        path: tile.owlPath })
        return
      }
      loader.setSource(tile.source, { host: tile.host,
                                      shell: tile.host ? tile.host.shell : null,
                                      preview: false })
    }
    Component.onCompleted: loader.load()
    Connections {
      target: tile
      function onSourceChanged() { loader.load() }
    }

    // W12's journal line, on a second host. The engine has already printed
    // the parse error with its line; this says which tile it was.
    onStatusChanged: if (loader.status === Loader.Error)
      console.warn("home: tile " + tile.widgetId + " did not load from " + tile.source)
  }
  // An OWL tile's live inputs: set once by setSource they would be stale the
  // first time a page turned or a window covered home.
  Binding { when: tile.isOwl && !!loader.item; target: loader.item; property: "active"; value: tile.showing }
  Binding { when: tile.isOwl && !!loader.item; target: loader.item; property: "cols"; value: tile.cols }
  Binding { when: tile.isOwl && !!loader.item; target: loader.item; property: "rows"; value: tile.rows }

  // OW6. The runtime's own message, first line: it names the line of the file.
  readonly property string error: tile.isOwl && loader.item ? String(loader.item.error || "").split("\n")[0] : ""

  // HM13, HM17. The frame stays and says why it is empty, so a tile that went
  // wrong is found by looking at home rather than by reading the journal.
  Text {
    anchors.fill: parent
    anchors.margins: Math.max(frame.inset, Style.space(8))
    visible: tile.tileState === "missing" || tile.tileState === "error"
    text: tile.tileState === "missing" ? "no widget \"" + tile.widgetId + "\""
          : tile.error !== "" ? tile.widgetId + ": " + tile.error
          : tile.widgetId + " did not load"
    wrapMode: Text.Wrap
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.weight: tile.host ? tile.host.textWeight : Font.Normal
    color: tile.host ? tile.host.subdued : "transparent"
  }

  // HM12. An unavailable widget keeps its cells, and its frame says which
  // widget is resting there: an empty frame read as a broken one on the phone.
  // Catalogued widgets only; a user widget has no name but its id to give.
  readonly property var catalogEntry: WidgetList.entry("home", tile.widgetId)
  Text {
    anchors.fill: parent
    anchors.margins: Math.max(frame.inset, Style.space(8))
    visible: tile.tileState === "unavailable"
    text: (tile.catalogEntry ? tile.catalogEntry.name : tile.widgetId).toLowerCase()
          + " \u00b7 nothing yet"
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.weight: tile.host ? tile.host.textWeight : Font.Normal
    color: tile.host ? tile.host.subdued : "transparent"
  }
}

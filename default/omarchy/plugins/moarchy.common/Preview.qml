// One arrangeable thing, drawn with mock data (docs/widgets.md W37, W38).
//
// What the Settings arrangement list puts in each card. A widget is the real
// file with `preview` set, because a picture of a widget would be a second
// thing to keep in step with it -- the whole value of showing it is that it is
// the thing being arranged. A toggle is one SmallTile, which is all a toggle
// ever is.
//
// It takes a host like anything else and hands it straight down, so the
// arrangement list gets the Settings palette and the control center gets its
// own, out of one component (docs/style.md C2).
import QtQuick
import "Widgets.js" as Catalogue

Item {
  id: preview

  property var host: null
  property string surface: ""
  property string itemId: ""

  readonly property bool isToggle: Catalogue.kindOf(preview.surface) === "toggle"

  // An id this surface has no entry for draws nothing at all. The arrangement
  // list carries one row that is not a widget -- the divider it groups by --
  // and without this, `fileFor()` would derive a file name from it and the
  // Loader would log an error per divider per rebuild.
  readonly property bool known:
    Catalogue.entry(preview.surface, preview.itemId) !== null

  implicitHeight: !preview.known ? 0
    : preview.isToggle ? tile.height
    : slot.height

  // A toggle. Never live -- `on` is a fixed lit/unlit rather than the real
  // do-not-disturb or the real rfkill, because a settings list that answered
  // the radio would flicker as the phone changed under it while somebody was
  // trying to read an order.
  Loader {
    id: tile
    active: preview.known && preview.isToggle
    width: Math.min(preview.width, preview.host ? preview.host.tileHeight * 1.6 : 96)
    height: preview.host ? preview.host.tileHeight : 0
    sourceComponent: SmallTile {
      host: preview.host
      glyph: Catalogue.glyphFor(preview.surface, preview.itemId)
      label: Catalogue.nameFor(preview.surface, preview.itemId)
      on: true
    }
  }

  // A widget, loaded the way the column loads it (W10) and handed `preview`.
  Loader {
    id: slot
    active: preview.known && !preview.isToggle
    width: preview.width
    height: slot.item ? slot.item.implicitHeight : 0
    Component.onCompleted: {
      if (!preview.known || preview.isToggle) return
      var file = Catalogue.fileFor(preview.itemId)
      if (file === "") return
      slot.setSource(Qt.resolvedUrl("widgets/" + file),
                     { host: preview.host,
                       shell: preview.host ? preview.host.shell : null,
                       preview: true })
    }
    onStatusChanged: if (slot.status === Loader.Error)
      console.warn("Preview: could not load " + preview.itemId
                   + " from " + slot.source)
  }
}

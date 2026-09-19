// One thing in a directory: a glyph, a name, a line about it, and a way in.
//
// Its own file because the browse list is a ListView rather than a Repeater,
// and a ListView only builds the rows it can see -- which is the difference
// between opening a camera roll and waiting for it. A delegate that is built
// and destroyed as a thumb moves wants to be small and to compute nothing,
// so every string on it is worked out by Listing.js and handed over.
//
// A ListRow, which is where the press and the two lines now come from, and
// where the rule under each row used to be. The list is one box with the rows
// inside it; a hairline between every two files was a spreadsheet drawn on a
// phone.
import QtQuick
import "ui" as Chrome
import "ui/Metrics.js" as Metrics

Chrome.ListRow {
  id: root

  property var entry: null
  property string note: ""
  property var glyphs: []
  property color foreground: root.colours ? root.colours.foreground : "#ffffff"
  property color accent: root.colours ? root.colours.accent : "#3584e4"

  signal activated
  signal menuWanted

  minHeight: 64
  // A broken link is drawn dim and says so underneath, rather than being
  // hidden: it is a thing on the disk, and hiding it is how a directory
  // becomes impossible to tidy up.
  titleColour: root.entry && root.entry.broken ? root.subtitleColour : root.foreground
  title: root.entry ? root.entry.name : ""
  subtitle: root.note
  spacing: 6
  pad: 6

  Accessible.role: Accessible.ListItem
  Accessible.name: root.entry ? root.entry.name : ""
  Accessible.onPressAction: root.activated()

  onClicked: root.activated()

  leading: Chrome.Icon {
    anchors.verticalCenter: parent.verticalCenter
    slot: 40
    size: 22
    // A folder is the row that leads somewhere, so it is the row that carries
    // the colour. Everything else is ink: twenty tinted mimetype glyphs would
    // be a fruit salad and would stop the folders standing out, which is the
    // one thing the colour is for.
    color: root.entry && root.entry.folder ? root.accent : root.subtitleColour
    names: root.glyphs
  }

  trailing: Chrome.IconButton {
    colours: root.colours
    anchors.verticalCenter: parent.verticalCenter
    names: ["view-more-symbolic", "open-menu-symbolic"]
    color: root.subtitleColour
    tooltip: "What can be done with this"
    onClicked: root.menuWanted()
  }
}

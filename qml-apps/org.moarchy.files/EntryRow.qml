// One thing in a directory: a glyph, a name, a line about it, and a way in.
//
// Its own file because the browse list is a ListView rather than a Repeater,
// and a ListView only builds the rows it can see -- which is the difference
// between opening a camera roll and waiting for it. A delegate that is built
// and destroyed as a thumb moves wants to be small and to compute nothing,
// so every string on it is worked out by Listing.js and handed over.
import QtQuick
import QtQuick.Layouts
import "ui" as Chrome
import "ui/Metrics.js" as Metrics

Item {
  id: root

  property var entry: null
  property string note: ""
  property var glyphs: []
  property color foreground: "#ffffff"
  property color dim: "#9a9996"
  property color line: "#333333"
  property color press: "#222222"
  property color accent: "#3584e4"
  property int bodySize: Metrics.BODY

  signal activated
  signal menuWanted

  height: 64

  Accessible.role: Accessible.ListItem
  Accessible.name: root.entry ? root.entry.name : ""
  Accessible.onPressAction: root.activated()

  Rectangle {
    anchors.fill: parent
    color: tap.pressed ? root.press : "transparent"
  }

  MouseArea {
    id: tap
    anchors.fill: parent
    onClicked: root.activated()
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: 8
    anchors.rightMargin: 2
    spacing: 6

    Chrome.Icon {
      Layout.preferredWidth: 40
      Layout.preferredHeight: 40
      Layout.alignment: Qt.AlignVCenter
      slot: 40
      size: 22
      // A folder is the row that leads somewhere, so it is the row that
      // carries the colour. Everything else is ink: twenty tinted mimetype
      // glyphs would be a fruit salad and would stop the folders standing out,
      // which is the one thing the colour is for.
      color: root.entry && root.entry.folder ? root.accent : root.dim
      names: root.glyphs
    }

    Column {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: 1

      Chrome.TypedText {
        width: parent.width
        role: "body"
        text: root.entry ? root.entry.name : ""
        // A broken link is drawn dim and says so underneath, rather than being
        // hidden: it is a thing on the disk, and hiding it is how a directory
        // becomes impossible to tidy up.
        color: root.entry && root.entry.broken ? root.dim : root.foreground
        bodySize: root.bodySize
        elide: Text.ElideMiddle
        maximumLineCount: 1
      }

      Chrome.TypedText {
        width: parent.width
        role: "caption"
        text: root.note
        color: root.dim
        bodySize: root.bodySize
        elide: Text.ElideRight
        maximumLineCount: 1
      }
    }

    Chrome.IconButton {
      Layout.alignment: Qt.AlignVCenter
      names: ["view-more-symbolic", "open-menu-symbolic"]
      color: root.dim
      tooltip: "What can be done with this"
      onClicked: root.menuWanted()
    }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: 54
    height: 1
    color: root.line
  }
}

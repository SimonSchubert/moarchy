// One event, as a row that can be tapped.
//
// Drawn the same on both screens that list events, because it is the same
// object: a bar in the event's own colour, its name, and one line underneath
// saying when and where. The day's list and the agenda differ in what is
// around the rows, not in the rows.
//
// The card is washed in the event's colour rather than outlined in it. An
// outline at 360px is two pixels of hue against the window and reads as a
// border; a wash is the whole row and can be seen without being looked at,
// which is what a colour is for.
import QtQuick
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "Events.js" as Events

Rectangle {
  id: root

  property var entry: null
  property var colours: null
  property int bodySize: Metrics.BODY
  property int radiusCard: Metrics.CARD_RADIUS

  signal clicked

  // A string rather than a `color`, because every use of it goes back through
  // Theme.mix, which takes hex. A color property would convert on the way in
  // and back on the way out, and the way out is `#aarrggbb` the moment an
  // alpha creeps in -- which Theme.rgb would read as a colour nobody chose.
  readonly property string hue: Events.hue(root.colours, root.entry ? root.entry.colour : "blue")
  readonly property string meta: root.entry ? Events.line(root.entry) : ""

  implicitHeight: Math.max(Metrics.TARGET + 8, text.height + 18)
  height: implicitHeight
  radius: root.radiusCard
  color: root.colours
    // A darker theme needs more of the hue to show the same amount of colour,
    // which is Habits' ramp in one number rather than eight.
    ? Theme.mix(root.hue, root.colours.background, root.colours.dark ? 0.20 : 0.13)
    : "#2a2a2e"

  Accessible.role: Accessible.Button
  Accessible.name: (root.entry ? root.entry.title : "") + ", " + root.meta
  Accessible.onPressAction: root.clicked()

  Rectangle {
    id: bar
    anchors.left: parent.left
    anchors.leftMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    width: 4
    height: parent.height - 18
    radius: 2
    color: root.hue
  }

  Column {
    id: text
    anchors.left: bar.right
    anchors.leftMargin: 12
    anchors.right: repeatGlyph.left
    anchors.rightMargin: 6
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1

    Chrome.TypedText {
      width: parent.width
      role: "body"
      text: root.entry ? root.entry.title : ""
      color: root.colours ? root.colours.foreground : "#ffffff"
      bodySize: root.bodySize
      elide: Text.ElideRight
      maximumLineCount: 1
    }

    Chrome.TypedText {
      width: parent.width
      visible: root.meta.length > 0
      role: "caption"
      text: root.meta
      // The event's own colour, one step towards the ink so that it stays
      // legible on its own wash. A caption in the theme's dim would be the
      // same grey on every card and would waste the one thing that tells
      // these rows apart at a glance.
      color: root.colours
             ? Theme.mix(root.hue, root.colours.foreground, root.colours.dark ? 0.55 : 0.7)
             : "#9a9996"
      bodySize: root.bodySize
      elide: Text.ElideRight
      maximumLineCount: 1
    }
  }

  // A repeating event says so here rather than in the line above, where it
  // would push out the place it is at.
  Chrome.Icon {
    id: repeatGlyph
    anchors.right: parent.right
    anchors.rightMargin: 2
    anchors.verticalCenter: parent.verticalCenter
    visible: !!root.entry && root.entry.repeat !== "none"
    slot: 28
    size: 14
    color: root.colours ? Theme.mix(root.hue, root.colours.foreground, 0.5) : "#9a9996"
    names: ["media-playlist-repeat-symbolic", "view-refresh-symbolic"]
  }

  Chrome.PressVeil {
    anchors.fill: parent
    radius: parent.radius
    ink: root.colours ? root.colours.foreground : "#ffffff"
    on: tap.pressed
  }

  MouseArea {
    id: tap
    anchors.fill: parent
    onClicked: root.clicked()
  }
}

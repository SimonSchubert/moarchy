// One row inside a Group or a ListFrame.
//
// Five apps had written this row: something on the left, a name over a smaller
// grey line, something on the right, and a press that lights the whole thing.
// They disagreed about the height, the gap, the ink of the second line and
// whether there was a rule under it. There is no rule under it.
//
// The slots are plain Rows rather than named properties because what goes on
// either end is the part that differs -- a folder glyph, a launch status, a
// price and a star, a three-dot button -- and a component that tried to name
// them all would be a component every app worked around.
import QtQuick
import QtQuick.Layouts
import "Theme.js" as Theme
import "Metrics.js" as Metrics

Item {
  id: root

  property var colours: null
  property int bodySize: Metrics.BODY
  property string title: ""
  property string subtitle: ""
  property color titleColour: root.colours ? root.colours.foreground : "#ffffff"
  property color subtitleColour: root.colours ? root.colours.dim : "#9a9996"
  property int titleWeight: Font.Normal
  property bool interactive: true
  property bool selected: false
  // A hue, when the row is an event or a warning rather than a neutral fact.
  property color tint: "transparent"
  property int radius: Metrics.radius(root.colours, Metrics.RADIUS_MD)
  property int pad: Metrics.GAP
  property int spacing: 10
  property int minHeight: 56

  property alias leading: leadingSlot.data
  property alias trailing: trailingSlot.data
  // For the row that wants its own middle: a two-line title with a badge in
  // it, a progress bar under the name. Replaces the title/subtitle column.
  property alias centre: centreExtra.data

  signal clicked
  signal held

  implicitWidth: 320
  implicitHeight: Math.max(root.minHeight, line.implicitHeight + root.pad * 2)

  Rectangle {
    anchors.fill: parent
    radius: root.radius
    visible: root.selected || root.tint.a > 0 || tap.pressed
    color: root.tint.a > 0
           ? Theme.tint(root.colours, root.tint, tap.pressed ? "pressed" : "card")
           : Theme.surface(root.colours, tap.pressed ? "pressed" : "raised")
    Behavior on color { ColorAnimation { duration: Metrics.PRESS_MS } }
  }

  RowLayout {
    id: line
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: root.pad
    anchors.rightMargin: root.pad
    spacing: root.spacing

    Row {
      id: leadingSlot
      Layout.alignment: Qt.AlignVCenter
      spacing: 8
    }

    Item {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      implicitHeight: Math.max(stack.implicitHeight, centreExtra.childrenRect.height)

      ColumnLayout {
        id: stack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: centreExtra.children.length === 0
        spacing: 1

        TypedText {
          Layout.fillWidth: true
          visible: root.title.length > 0
          role: "body"
          text: root.title
          color: root.titleColour
          font.weight: root.titleWeight
          bodySize: root.bodySize
          elide: Text.ElideRight
          maximumLineCount: 1
        }

        TypedText {
          Layout.fillWidth: true
          visible: root.subtitle.length > 0
          role: "caption"
          text: root.subtitle
          color: root.subtitleColour
          bodySize: root.bodySize
          elide: Text.ElideRight
          maximumLineCount: 1
        }
      }

      Item {
        id: centreExtra
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: childrenRect.height
        height: childrenRect.height
      }
    }

    Row {
      id: trailingSlot
      Layout.alignment: Qt.AlignVCenter
      spacing: 4
    }
  }

  MouseArea {
    id: tap
    anchors.fill: parent
    enabled: root.interactive
    onClicked: root.clicked()
    onPressAndHold: root.held()
  }
}

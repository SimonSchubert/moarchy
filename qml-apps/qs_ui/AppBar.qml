import QtQuick
import QtQuick.Layouts
import "Metrics.js" as Metrics

Item {
  id: root
  property string title: ""
  property string subtitle: ""
  property color foreground: "#ffffff"
  property color dim: "#9a9996"
  property int bodySize: 16
  property alias leading: leadingSlot.data
  property alias trailing: trailingSlot.data
  property alias center: centerExtra.data

  implicitHeight: Metrics.TARGET + 8
  implicitWidth: 360

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: 6
    anchors.rightMargin: 6
    spacing: 4

    Row {
      id: leadingSlot
      Layout.alignment: Qt.AlignVCenter
      spacing: 0
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      Column {
        visible: centerExtra.children.length === 0 && root.title.length > 0
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        TypedText {
          width: parent.width
          role: "subtitle"
          text: root.title
          color: root.foreground
          bodySize: root.bodySize
          elide: Text.ElideRight
          // One line, or the elide above never happens: TypedText wraps, and a
          // wrapped title with no line limit grows a second line instead --
          // which in a bar this height pushes the subtitle out of it. A file
          // called "Letter to the landlord.txt" was enough.
          maximumLineCount: 1
        }

        TypedText {
          width: parent.width
          visible: root.subtitle.length > 0
          role: "caption"
          text: root.subtitle
          color: root.dim
          bodySize: root.bodySize
          elide: Text.ElideRight
          maximumLineCount: 1
        }
      }

      Item {
        id: centerExtra
        anchors.fill: parent
      }
    }

    Row {
      id: trailingSlot
      Layout.alignment: Qt.AlignVCenter
      spacing: 0
    }
  }
}

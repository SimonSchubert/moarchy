// The header of a page drawn as an Omalauncher panel (Components.kt
// OverlayPanel, BackTitle): its title in accent at title size, `‹` before it
// when back goes somewhere, then the page's own actions and a red ✕ when the
// page is open on its own. The store (owl.md OW7) and the coding agents page
// (settings.md P14) wear it in place of Settings' SheetHeader.
import QtQuick
import qs.Commons
import qs.Ui as Ui

Item {
  id: header

  // Settings itself: its colour roles and weight.
  property var host: null
  property string title: ""
  // `‹` before the title, and the title takes a tap as back.
  property bool backward: false
  // The red ✕, for a page that is the whole of Settings' stack.
  property bool closable: false
  // Controls at the right, before the ✕: the store's refresh.
  default property alias actions: actionRow.data

  signal back()
  signal close()

  width: parent ? parent.width : 0
  height: Style.space(44)

  readonly property color accent: header.host ? header.host.accent : "transparent"

  Item {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.min(titleRow.implicitWidth + Style.space(8), header.width - right.width)
    Row {
      id: titleRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)
      Text {
        visible: header.backward
        anchors.verticalCenter: parent.verticalCenter
        // fa-angle-left, SheetHeader's chevron, as an escape: a rune like it
        // is the kind an editor eats.
        text: "\uf104"
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.weight: header.host ? header.host.textWeight : Font.Normal
        color: header.accent
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, header.width - right.width - Style.space(40))
        text: header.title
        elide: Text.ElideRight
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.weight: header.host ? header.host.textWeight : Font.Normal
        color: header.accent
      }
    }
    MouseArea {
      anchors.fill: parent
      enabled: header.backward
      // no press state (style.md H7): Omalauncher's title is its own back
      onClicked: header.back()
    }
  }

  Row {
    id: right
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    Row { id: actionRow }
    Item {
      visible: header.closable
      width: Style.space(44)
      height: Style.space(44)
      Ui.OpticalGlyph {
        anchors.fill: parent
        // nf-md-close, as an escape for the chevron's reason.
        text: "\udb80\udd56"
        fontFamily: Style.font.family
        fontSize: Style.font.heading
        color: header.host ? header.host.red : "transparent"
      }
      MouseArea {
        anchors.fill: parent
        // no press state (style.md H7): it closes the window
        onClicked: header.close()
      }
    }
  }
}

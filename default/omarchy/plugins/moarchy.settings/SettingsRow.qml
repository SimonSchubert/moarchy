// One row on a Settings page.
//
// Every row type is the same card -- glyph, label, optional second line -- and
// differs only in the ~24px at the trailing edge: a chevron, a switch, a tick,
// or nothing. Three separate components would have been three copies of the
// card, so this takes a `rowType` instead. It is the extraction of the row that
// Settings.qml, Themes.qml and the shade's WideTile had each written out
// separately.
//
// Colours come in as properties rather than being read from Color here, because
// the shade wants them from Color.popups and the full-screen surfaces want them
// from Color.menu, and a component that picks for itself cannot serve both.
import QtQuick
import qs.Commons

Rectangle {
  id: card

  property string rowType: "nav"
  property string glyph: ""
  property string label: ""
  property string detail: ""
  property bool checked: false

  // Dimming is for a row that exists but cannot act. It is deliberately NOT
  // wired to "is this tappable": an info row is not tappable and must still
  // look like ordinary text, or the About screen and the whole keybindings list
  // render as though they were disabled.
  property bool rowEnabled: true

  property color textColor: "white"
  property color subduedColor: "grey"
  property color accentColor: "white"

  signal activated()

  height: Style.space(58)
  radius: Style.space(18)
  opacity: card.rowEnabled ? 1 : 0.45

  Row {
    anchors.fill: parent
    anchors.leftMargin: Style.space(16)
    anchors.rightMargin: Style.space(14)
    spacing: Style.space(14)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: card.glyph !== ""
      width: visible ? implicitWidth : 0
      text: card.glyph
      font.family: Style.font.family
      font.pixelSize: Style.font.iconLarge
      color: card.textColor
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      // The trailing control and the two gaps. Measured rather than guessed:
      // a label that runs under the switch reads as a layout bug even when the
      // elide is doing its job.
      width: parent.width - (card.glyph !== "" ? Style.space(64) : Style.space(20))
             - trailing.width
      spacing: 0

      Text {
        width: parent.width
        text: card.label
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        color: card.textColor
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        visible: text !== ""
        text: card.detail
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: card.subduedColor
        elide: Text.ElideRight
      }
    }
  }

  // ------------------------------------------------------------- trailing
  Item {
    id: trailing
    anchors.right: parent.right
    anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    // Explicit per type rather than childrenRect, which counts invisible
    // children too -- so every row would reserve the width of the widest
    // trailing element, which is the switch, and every label would be short by
    // 44px for no reason.
    width: card.rowType === "switch" ? Style.space(44)
           : (card.rowType === "info" || card.rowType === "action") ? 0
           : Style.space(20)
    height: parent.height

    // nav, plugin
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: card.rowType === "nav" || card.rowType === "plugin"
      text: "󰅂"
      font.family: Style.font.family
      font.pixelSize: Style.font.iconSmall
      color: card.subduedColor
    }

    // link
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: card.rowType === "link"
      text: "󰏌"
      font.family: Style.font.family
      font.pixelSize: Style.font.iconSmall
      color: card.subduedColor
    }

    // choice
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: card.rowType === "choice"
      text: card.checked ? "󰄬" : ""
      font.family: Style.font.family
      font.pixelSize: Style.font.icon
      color: card.accentColor
    }

    // switch
    Rectangle {
      id: track
      anchors.verticalCenter: parent.verticalCenter
      visible: card.rowType === "switch"
      width: Style.space(44)
      height: Style.space(26)
      radius: height / 2
      color: card.checked ? card.accentColor : Util.alpha(card.textColor, 0.22)
      Behavior on color { ColorAnimation { duration: 120 } }

      Rectangle {
        width: Style.space(20)
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: card.checked ? parent.width - width - Style.space(3) : Style.space(3)
        // The knob is the card's own background, not white: on a light theme a
        // white knob on a pale track is invisible.
        color: card.color
        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: card.rowEnabled
    onClicked: card.activated()
  }
}

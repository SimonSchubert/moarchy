// Omalauncher's BracketAction (Components.kt): a terminal-style `[ label ]`
// in one colour, drawn at its text and answering 44 tall (style.md E1).
import QtQuick
import qs.Commons
import "../moarchy.common" as Shared

Item {
  id: bracket

  property string label: ""
  property color ink: "transparent"
  property int textWeight: Font.Normal

  signal activated()

  width: bracketText.implicitWidth + Style.space(16)
  height: Style.space(44)

  Shared.PressVeil {
    anchors.fill: parent
    ink: bracket.ink
    on: bracketArea.pressed
  }
  Text {
    id: bracketText
    anchors.centerIn: parent
    text: "[ " + bracket.label + " ]"
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.weight: bracket.textWeight
    color: bracket.ink
  }
  MouseArea {
    id: bracketArea
    anchors.fill: parent
    onClicked: bracket.activated()
  }
}

// The prompt bar's agent chip: the chosen agent's command and a chevron, in
// accent; tapping it opens the agent menu (docs/home.md HM24).
//
// Omalauncher's `agent ⌄` at the left of its bar. Drawn on home and in the app
// drawer's field from this one file, so the two cannot spell it differently.
// The colours are handed in, for W4's reason: the drawer's palette is `menu`
// and home's is the wallpaper's.
import QtQuick
import qs.Commons

Item {
  id: chip

  // The agent's command, "" for none chosen.
  property string agent: ""
  property color accent: "transparent"
  property color subdued: "transparent"
  property bool open: false
  property bool interactive: true
  property int textWeight: Font.Normal
  // The surface's own ink, for the press veil (style.md H4).
  property color ink: "transparent"
  property int radiusTile

  signal tapped()

  implicitWidth: label.implicitWidth + Style.space(8)
  // E1: the target is 44 on its short side even where the bar is drawn
  // thinner, and the drawing does not grow with it (E2).
  implicitHeight: Style.space(44)

  // style.md H1, H8.
  PressVeil {
    anchors.fill: parent
    radius: chip.radiusTile
    ink: chip.ink
    on: chipArea.pressed
  }

  Text {
    id: label
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    textFormat: Text.PlainText
    // md-chevron_down / md-chevron_up, read out of glyphnames.json.
    text: (chip.agent === "" ? "agent" : chip.agent) + (chip.open ? " 󰅃" : " 󰅀")
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.weight: chip.textWeight
    color: chip.agent === "" ? chip.subdued : chip.accent
  }

  MouseArea {
    id: chipArea
    anchors.fill: parent
    enabled: chip.interactive
    onClicked: chip.tapped()
  }
}

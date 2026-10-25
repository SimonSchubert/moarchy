// The agent menu above the prompt bar (docs/home.md HM24).
//
// Omalauncher's AgentsMenu on its bar (PromptBar.kt, a ChoicePopup): the
// installed agents, the one in use marked, and a way to the screen that
// installs them. It covers the surface it is drawn in
// so a tap anywhere outside the card puts it away, which is what `Menu.qml`
// upstream does with its scrim and what a phone expects of a menu.
//
// Choosing writes through AgentFile (`moarchy-agent set`) and closes; the
// chip changes when the file does, not when this guesses it did.
import QtQuick
import Quickshell
import qs.Commons

Item {
  id: menu

  property var agents: null       // an AgentFile
  property var shell: null
  property bool open: false
  // The chip that opened it, in this item's coordinates: its left edge, its
  // top and its bottom. The card opens above it -- home's bar is at the
  // bottom -- and below it where there is no room above, which is the drawer,
  // whose field is at the top.
  property real anchorX: 0
  property real anchorY: 0
  property real anchorBottom: 0

  // W4. Colours from the surface the menu is drawn on.
  property color surface: "transparent"
  property color textOnSurface: "transparent"
  property color subdued: "transparent"
  property color accent: "transparent"
  // The rule over `manage agents…`; the frame itself is Omalauncher's 2px
  // of accent wherever the menu is drawn.
  property color borderColor: "transparent"
  // style.md D1: home's frame radius, Omalauncher's 16px times the corner
  // scale, on whichever surface draws it.
  property int radiusFrame
  property int textWeight: Font.Normal

  signal closed()

  visible: menu.open
  // Over everything else in the surface while open, and nothing while shut:
  // an invisible Item takes no touch, so a closed menu costs nothing.
  z: 100

  readonly property int rowHeight: Style.space(50)

  // settings.md P19. The coding agents page on its own, so back is the bar
  // again. The chip opens it straight away while no agent is installed.
  function manage(): void {
    menu.closed()
    if (menu.shell && typeof menu.shell.summon === "function")
      menu.shell.summon("moarchy.settings", JSON.stringify({ page: "apps.default.agent", alone: true }))
  }

  MouseArea {
    id: scrim
    anchors.fill: parent
    // no press state (style.md H7): a scrim that dismisses
    onClicked: menu.closed()
  }

  Rectangle {
    id: card
    width: Math.min(Style.space(220), menu.width - Style.space(24))
    x: Math.max(Style.space(12), Math.min(menu.width - width - Style.space(12), menu.anchorX))
    // The whole card, if it fits: on home it opens above the bar, in the
    // drawer below the field. Where it does not fit -- nine agents under the
    // drawer's field with the keyboard up -- it keeps its place by the chip and
    // the list scrolls. Moved up to fit instead, it covered the chip and the
    // field it was opened from.
    readonly property real full: list.contentHeight + manageRow.height + Style.space(8)
    readonly property real gap: Style.space(6)
    readonly property real edge: Style.space(12)
    readonly property bool fitsAbove: menu.anchorY - full - gap >= edge
    readonly property real room: card.fitsAbove ? menu.anchorY - gap - edge
                                                : menu.height - menu.anchorBottom - gap - edge
    height: Math.min(card.full, Math.max(menu.rowHeight * 2, card.room))
    y: card.fitsAbove ? menu.anchorY - card.height - card.gap : menu.anchorBottom + card.gap
    color: menu.surface
    radius: menu.radiusFrame
    border.width: Style.space(2)
    border.color: menu.accent

    // A press on the card is not a press on the scrim behind it.
    MouseArea {
      anchors.fill: parent
      // no press state (style.md H7): a tap swallower behind a modal
    }

    Flickable {
      id: list
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: manageRow.top
      // Omalauncher's 4px inside the frame, and inset from its rounded
      // corners so a pressed first row is not drawn square over them.
      anchors.topMargin: Style.space(4) + card.radius / 4
      anchors.leftMargin: Style.space(4) + card.radius / 4
      anchors.rightMargin: Style.space(4) + card.radius / 4
      contentHeight: column.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      clip: true

    Column {
      id: column
      width: list.width

      Repeater {
        model: menu.agents ? menu.agents.installed : []
        delegate: Item {
          id: row
          required property var modelData
          readonly property bool chosen: menu.agents && menu.agents.current === row.modelData.id
          width: column.width
          height: menu.rowHeight

          // style.md H1, H8: over the fill, under the words.
          PressVeil {
            anchors.fill: parent
            ink: menu.textOnSurface
            on: rowArea.pressed
          }

          Text {
            id: mark
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(14)
            text: row.chosen ? "●" : ""
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.weight: menu.textWeight
            color: menu.accent
          }
          Column {
            anchors.left: mark.right
            anchors.leftMargin: Style.space(6)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            Text {
              width: parent.width
              text: row.modelData.name
              elide: Text.ElideRight
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.weight: menu.textWeight
              color: row.chosen ? menu.accent : menu.textOnSurface
            }
            Text {
              width: parent.width
              text: row.modelData.id
              elide: Text.ElideRight
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.weight: menu.textWeight
              color: menu.subdued
            }
          }
          MouseArea {
            id: rowArea
            anchors.fill: parent
            onClicked: {
              if (menu.agents) menu.agents.choose(row.modelData.id)
              menu.closed()
            }
          }
        }
      }
    }
    }

    // The one way from here to installing an agent, signing in to one or
    // removing one: the coding agents page. Under the list rather than in it,
    // so it is there however far the list scrolls.
    Column {
      id: manageRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Style.space(4) + card.radius / 4
      topPadding: Style.space(4)

      Rectangle {
        width: manageRow.width
        height: 1
        color: menu.borderColor
      }
      Item { width: 1; height: Style.space(4) }

      Item {
        width: manageRow.width
        height: Style.space(44)
        PressVeil {
          anchors.fill: parent
          ink: menu.textOnSurface
          on: manageArea.pressed
        }
        Text {
          anchors.fill: parent
          anchors.leftMargin: Style.space(10)
          verticalAlignment: Text.AlignVCenter
          // Omalauncher's two spaces: lined up with the names, past the mark.
          text: "  manage agents…"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: menu.textWeight
          color: menu.subdued
        }
        MouseArea {
          id: manageArea
          anchors.fill: parent
          onClicked: menu.manage()
        }
      }
    }
  }
}

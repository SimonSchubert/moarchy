// The home menu: what a long press on home opens (docs/home.md §J).
//
// Omalauncher's `HomeMenu.kt`, in this shell's kit: a card centred over a
// scrim, the way to Settings, and every theme drawn in its own colours so a
// theme is chosen by looking at it (the picker's reason, moarchy.themes).
// A tap on a theme applies it and leaves the menu up, so the recolour is seen
// happen -- the card, the scrim and home behind them all change together.
//
// Drawn by home, on home's surface. It needs no keyboard and no layer of its
// own: home is only ever on screen with no window over it, and the scrim
// covers all of home, so nothing under it takes a touch while it is up.
import QtQuick
import qs.Commons
import qs.Commons as Upstream
import "../moarchy.common" as Shared
import "../moarchy.common/Sheet.js" as Sheet

Item {
  id: menu

  // The home this is drawn on: its colour roles, radii and shell (HM38).
  property var host: null
  property bool open: false

  signal closed()

  visible: menu.open
  // Over the pages, the foot and the agent menu while open.
  z: 200

  // Scanned on creation; scanned again on each open, so a theme installed
  // since is in the strip.
  Shared.ThemeCatalog { id: catalog }
  onOpenChanged: if (menu.open) {
    catalog.scan()
    strip.showCurrent()
  }

  readonly property int rowHeight: Style.space(48)
  readonly property int swatchWidth: Style.space(112)
  readonly property int swatchHeight: Style.space(56)

  // HM38. Dims home, and a tap on it puts the menu away.
  Rectangle {
    anchors.fill: parent
    // The theme's own scrim, as upstream's menu draws it.
    color: Upstream.Color.menu.scrim
  }
  MouseArea {
    anchors.fill: parent
    // no press state (style.md H7): a scrim that dismisses
    onClicked: menu.closed()
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(Style.space(340), parent.width - Style.space(24))
    height: column.implicitHeight + Style.space(16)
    // Solid where a tile is translucent: a menu is read, not looked through.
    color: Util.alpha(Upstream.Color.background, 0.97)
    radius: menu.host ? menu.host.radiusCard : 0
    border.width: Style.space(2)
    border.color: menu.host ? menu.host.accent : "transparent"

    // A press on the card is not a press on the scrim behind it.
    MouseArea {
      anchors.fill: parent
      // no press state (style.md H7): a tap swallower behind a modal
    }

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(8)
      spacing: Style.space(4)

      // --------------------------------------------------- create (HM53)
      // Omalauncher's first row: what to make sits on the row itself, one tap
      // each, and the agent asks what it should be.
      Item {
        width: column.width
        height: Style.space(28)
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: "create with " + (menu.host ? menu.host.agentName : "")
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: menu.host ? menu.host.textWeight : Font.Normal
          color: menu.host ? menu.host.textOnSurface : "transparent"
        }
      }
      Row {
        x: Style.space(4)
        Repeater {
          model: [ { label: "widget", face: false }, { label: "face", face: true } ]
          delegate: Item {
            id: kind
            required property var modelData
            width: kindText.implicitWidth + Style.space(16)
            height: menu.rowHeight
            Shared.PressVeil {
              anchors.fill: parent
              ink: menu.host ? menu.host.accent : "transparent"
              on: kindArea.pressed
            }
            Text {
              id: kindText
              anchors.centerIn: parent
              text: "[ " + kind.modelData.label + " ]"
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.weight: menu.host ? menu.host.textWeight : Font.Normal
              color: menu.host ? menu.host.accent : "transparent"
            }
            MouseArea {
              id: kindArea
              anchors.fill: parent
              onClicked: {
                menu.closed()
                if (!menu.host) return
                if (kind.modelData.face) menu.host.createFace()
                else menu.host.createWidget(menu.host.page)
              }
            }
          }
        }
      }

      // ------------------------------------------------------------ settings
      Item {
        width: column.width
        height: menu.rowHeight

        Shared.PressVeil {
          anchors.fill: parent
          ink: menu.host ? menu.host.textOnSurface : "transparent"
          on: settingsArea.pressed
        }
        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(12)
          Text {
            // The control center's gear: one glyph for Settings in this shell.
            text: ""
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.weight: menu.host ? menu.host.textWeight : Font.Normal
            color: menu.host ? menu.host.accent : "transparent"
          }
          Text {
            text: "settings"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.weight: menu.host ? menu.host.textWeight : Font.Normal
            color: menu.host ? menu.host.textOnSurface : "transparent"
          }
        }
        MouseArea {
          id: settingsArea
          anchors.fill: parent
          onClicked: {
            menu.closed()
            if (menu.host) Sheet.summon(menu.host.shell, "moarchy.settings")
          }
        }
      }

      // ------------------------------------------------------- the store
      // owl.md OW7. Omalauncher's `browse store`, for widgets.
      Item {
        width: column.width
        height: menu.rowHeight
        Shared.PressVeil {
          anchors.fill: parent
          ink: menu.host ? menu.host.textOnSurface : "transparent"
          on: storeArea.pressed
        }
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: "browse widgets"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: menu.host ? menu.host.textWeight : Font.Normal
          color: menu.host ? menu.host.textOnSurface : "transparent"
        }
        MouseArea {
          id: storeArea
          anchors.fill: parent
          onClicked: {
            menu.closed()
            if (menu.host) Sheet.summon(menu.host.shell, "moarchy.settings",
                                        JSON.stringify({ page: "appearance.home.widgets" }))
          }
        }
      }

      // --------------------------------------------------------- theme strip
      Item {
        width: column.width
        height: Style.space(28)
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: "theme"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: menu.host ? menu.host.textWeight : Font.Normal
          color: menu.host ? menu.host.subdued : "transparent"
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: catalog.pendingSlug !== "" ? "applying…" : strip.currentName
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: menu.host ? menu.host.textWeight : Font.Normal
          color: menu.host ? menu.host.subdued : "transparent"
        }
      }

      ListView {
        id: strip
        width: column.width
        height: menu.swatchHeight
        orientation: ListView.Horizontal
        spacing: Style.space(8)
        clip: true
        leftMargin: Style.space(8)
        rightMargin: Style.space(8)
        boundsBehavior: Flickable.StopAtBounds
        // The catalogue, then one more cell: `more themes ›`.
        model: catalog.themes.length + 1

        readonly property string currentName: {
          for (var i = 0; i < catalog.themes.length; i++)
            if (catalog.themes[i].slug === catalog.currentSlug)
              return String(catalog.themes[i].name).toLowerCase()
          return ""
        }

        // HM39. Opens on the current theme rather than on the first one.
        function showCurrent(): void {
          for (var i = 0; i < catalog.themes.length; i++) {
            if (catalog.themes[i].slug === catalog.currentSlug) {
              strip.positionViewAtIndex(i, ListView.Center)
              return
            }
          }
        }
        // The scan answers after the menu has opened, the first time, and again
        // after each apply. Later rather than now: it sets the list before the
        // current slug, so now would centre on the theme just replaced.
        Connections {
          target: catalog
          function onThemesChanged() { if (menu.open) Qt.callLater(strip.showCurrent) }
          function onCurrentSlugChanged() { if (menu.open) Qt.callLater(strip.showCurrent) }
        }

        delegate: Item {
          id: cell
          required property int index
          readonly property bool more: cell.index >= catalog.themes.length
          readonly property var row: cell.more ? null : catalog.themes[cell.index]
          readonly property bool isCurrent: !cell.more && cell.row.slug === catalog.currentSlug
          readonly property bool isPending: !cell.more && cell.row.slug === catalog.pendingSlug
          width: menu.swatchWidth
          height: menu.swatchHeight
          opacity: catalog.pendingSlug !== "" && !cell.isPending ? 0.45 : 1

          // A theme in its own colours; `more themes ›` in the menu's.
          Rectangle {
            id: swatch
            anchors.fill: parent
            radius: menu.host ? menu.host.radiusOn(height) : 0
            color: cell.more ? "transparent" : cell.row.background
            border.width: cell.isCurrent ? Style.space(2) : Style.space(1)
            border.color: menu.host ? (cell.isCurrent ? menu.host.accent : menu.host.frameBorderColor)
                                    : "transparent"

            Shared.PressVeil {
              anchors.fill: parent
              radius: parent.radius
              ink: cell.more ? (menu.host ? menu.host.textOnSurface : "transparent") : cell.row.foreground
              on: cellArea.pressed
            }
          }
          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)
            Text {
              width: parent.width
              text: cell.more ? "more themes ›"
                              : (cell.isPending ? "applying…" : String(cell.row.name).toLowerCase())
              elide: Text.ElideRight
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.weight: menu.host ? menu.host.textWeight : Font.Normal
              color: cell.more ? (menu.host ? menu.host.accent : "transparent") : cell.row.foreground
            }
            Row {
              spacing: Style.space(3)
              Repeater {
                model: cell.more ? 6 : cell.row.chips
                delegate: Rectangle {
                  required property var modelData
                  width: Style.space(12)
                  height: Style.space(6)
                  color: cell.more ? (menu.host ? menu.host.frameBorderColor : "transparent")
                                   : modelData
                }
              }
            }
          }
          MouseArea {
            id: cellArea
            anchors.fill: parent
            enabled: cell.more || catalog.pendingSlug === ""
            onClicked: {
              if (cell.more) {
                menu.closed()
                if (menu.host) Sheet.summon(menu.host.shell, "moarchy.themes")
              } else {
                catalog.apply(cell.row)
              }
            }
          }
        }
      }
    }
  }
}

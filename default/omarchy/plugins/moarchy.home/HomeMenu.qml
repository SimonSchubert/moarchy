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
import qs.Ui as Ui
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

  // Omalauncher's sizes (HomeMenu.kt, Setup.kt ThemeStrip), a step for a
  // step: its menu entries are Item, its brackets Body, the strip's words Small.
  readonly property int textItem: Style.font.subtitle
  readonly property int textBody: Style.font.body
  readonly property int textSmall: Style.font.bodySmall
  readonly property int textWeight: menu.host ? menu.host.textWeight : Font.Normal
  readonly property color ink: menu.host ? menu.host.textOnSurface : "transparent"
  readonly property color accent: menu.host ? menu.host.accent : "transparent"
  readonly property color border: menu.host ? menu.host.frameBorderColor : "transparent"
  readonly property color raised: menu.host ? menu.host.containerHigh : "transparent"
  // Its radii are the frame's 16px stretched, times the corner scale the
  // preset already put into `frame`, so `square` stays square.
  function radiusFrameAt(px, size): int {
    return Math.min(Math.round((menu.host ? menu.host.radiusFrame : 0) * px / 16), Math.floor(size / 2))
  }
  readonly property int swatchWidth: Style.space(112)
  FontMetrics {
    id: swatchFont
    font.family: Style.font.family
    font.pixelSize: menu.textSmall
  }
  // The strip scrolls under the card's padding and its own, to the frame.
  readonly property int gutter: Style.space(20)

  // HM38. Dims home, and a tap on it puts the menu away.
  Rectangle {
    anchors.fill: parent
    // Omalauncher's overlay: the theme's background at 90%.
    color: Util.alpha(Upstream.Color.background, 0.9)
  }
  MouseArea {
    anchors.fill: parent
    // no press state (style.md H7): a scrim that dismisses
    onClicked: menu.closed()
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.max(Style.space(240), Math.min(Style.space(360), parent.width - Style.space(32)))
    height: column.implicitHeight + Style.space(16)
    // Solid where a tile is translucent: a menu is read, not looked through.
    color: Upstream.Color.background
    radius: menu.radiusFrameAt(20, width)
    border.width: Style.space(2)
    border.color: menu.accent

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

      // ------------------------------------------ create (HM53), settings
      // Omalauncher's first row: what to make sits on the row itself, one tap
      // each, and the agent asks what it should be. Settings at its right
      // end, as in the drawer.
      Item {
        width: column.width
        height: Math.max(createColumn.implicitHeight, gear.height)

        Column {
          id: createColumn
          anchors.left: parent.left
          anchors.right: gear.left
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(4)
          topPadding: Style.space(10)
          Text {
            text: "create with " + (menu.host ? menu.host.agentName : "")
            font.family: Style.font.family
            font.pixelSize: menu.textItem
            font.weight: menu.textWeight
            color: menu.ink
          }
          Row {
            // Pulled left by the buttons' own padding, so the first bracket
            // lines up with the label.
            x: -Style.space(8)
            Repeater {
              model: [ { label: "widget", face: false }, { label: "face", face: true } ]
              delegate: Item {
                id: kind
                required property var modelData
                width: kindText.implicitWidth + Style.space(16)
                height: Style.space(44)
                Shared.PressVeil {
                  anchors.fill: parent
                  ink: menu.accent
                  on: kindArea.pressed
                }
                Text {
                  id: kindText
                  anchors.centerIn: parent
                  text: "[ " + kind.modelData.label + " ]"
                  font.family: Style.font.family
                  font.pixelSize: menu.textBody
                  font.weight: menu.textWeight
                  color: menu.accent
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
        }

        // Omalauncher's SettingsButton: a 44px round button, the gear in accent.
        Rectangle {
          id: gear
          anchors.right: parent.right
          anchors.top: parent.top
          width: Style.space(44)
          height: width
          radius: menu.radiusFrameAt(22, width)
          color: menu.raised
          Shared.PressVeil {
            anchors.fill: parent
            radius: parent.radius
            ink: menu.accent
            on: settingsArea.pressed
          }
          Ui.OpticalGlyph {
            anchors.fill: parent
            // The control center's gear, U+E615: one glyph for Settings in this
            // shell. An escape, because the rune itself is the kind an editor eats.
            text: "\ue615"
            fontFamily: Style.font.family
            fontSize: Style.font.iconLarge
            color: menu.accent
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
      }

      // ------------------------------------------------------- the store
      // owl.md OW7, OW7a. Omalauncher's `browse store`, opened on its own so
      // back from it is home again.
      Item {
        width: column.width
        height: Style.space(40)
        Shared.PressVeil {
          anchors.fill: parent
          ink: menu.ink
          on: storeArea.pressed
        }
        Text {
          id: storeText
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: "browse store"
          font.family: Style.font.family
          font.pixelSize: menu.textItem
          font.weight: menu.textWeight
          color: menu.ink
        }
        MouseArea {
          id: storeArea
          anchors.fill: parent
          // style.md E1: the row is drawn 40, and answers 44.
          anchors.topMargin: -Style.space(2)
          anchors.bottomMargin: -Style.space(2)
          onClicked: {
            menu.closed()
            if (menu.host) Sheet.summon(menu.host.shell, "moarchy.settings",
                                        JSON.stringify({ page: "appearance.home.widgets", alone: true }))
          }
        }
      }

      // --------------------------------------------------------- theme strip
      // HM39. Omalauncher's ThemeStrip: a THEME label, the current name, and
      // the swatches under them.
      Item {
        width: column.width
        height: themeLabel.implicitHeight + Style.space(10 + 12)
        Text {
          id: themeLabel
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.top: parent.top
          anchors.topMargin: Style.space(10)
          text: "THEME"
          font.family: Style.font.family
          font.pixelSize: menu.textSmall
          font.weight: menu.textWeight
          font.letterSpacing: Style.space(1.5)
          color: menu.accent
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.baseline: themeLabel.baseline
          text: catalog.pendingSlug !== "" ? "applying…" : strip.currentName
          font.family: Style.font.family
          font.pixelSize: menu.textSmall
          font.weight: menu.textWeight
          // Omalauncher's Subtle: some themes' dim colours match their
          // surfaces, so the foreground fades instead.
          color: Util.alpha(menu.ink, 0.6)
        }
      }

      ListView {
        id: strip
        // Out through the card's padding to the inside of its frame.
        x: -(Style.space(8) - card.border.width)
        width: column.width + 2 * (Style.space(8) - card.border.width)
        height: Style.space(10) + Math.ceil(swatchFont.height) + Style.space(10 + 6 + 10)
        orientation: ListView.Horizontal
        spacing: Style.space(8)
        clip: true
        // The first swatch lines up with THEME, 20px in from the frame.
        leftMargin: menu.gutter - card.border.width
        rightMargin: leftMargin
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
          height: strip.height
          opacity: catalog.pendingSlug !== "" && !cell.isPending ? 0.45 : 1

          // A theme in its own colours; `more themes ›` in the menu's.
          Rectangle {
            id: swatch
            anchors.fill: parent
            radius: menu.radiusFrameAt(12, height)
            color: cell.more ? menu.raised : cell.row.background
            border.width: cell.isCurrent ? Style.space(2) : Style.space(1)
            border.color: cell.isCurrent ? menu.accent : menu.border

            Shared.PressVeil {
              anchors.fill: parent
              radius: parent.radius
              ink: cell.more ? menu.ink : cell.row.foreground
              on: cellArea.pressed
            }
          }
          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(10)
            spacing: Style.space(10)
            Text {
              width: parent.width
              height: Math.ceil(swatchFont.height)
              text: cell.more ? "more themes ›"
                              : (cell.isPending ? "applying…" : String(cell.row.name).toLowerCase())
              elide: Text.ElideRight
              font.family: Style.font.family
              font.pixelSize: menu.textSmall
              font.weight: menu.textWeight
              color: cell.more ? menu.accent : cell.row.foreground
            }
            Row {
              spacing: Style.space(3)
              Repeater {
                model: cell.more ? 5 : (cell.row.swatch || cell.row.chips.slice(0, 5))
                delegate: Rectangle {
                  required property var modelData
                  width: Style.space(14)
                  height: Style.space(6)
                  color: cell.more ? menu.border : modelData
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
      // The strip's own padding under it, as in Omalauncher's menu.
      Item { width: 1; height: Style.space(10) }
    }
  }
}

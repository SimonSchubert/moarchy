// The now-playing card (docs/control-center.md S16, S17).
//
// Title, artist and three transport buttons. It appears only when something is
// playing, which is W6's `available` and not a `visible` -- the difference is
// whether the row leaves a gap behind it.
import QtQuick
import qs.Commons
import qs.Ui as Ui
import ".." as Shared

Item {
  id: widget

  property var host: null
  property var shell: null

  // W37. Drawn in the Settings arrangement list rather than on the surface.
  // The values are canned and every action is a no-op: the list is a list of
  // real widgets, so without this, arranging them would toggle the radio,
  // move the brightness and open screens from inside a settings page.
  property bool preview: false

  readonly property var media: widget.shell && typeof widget.shell.serviceFor === "function"
    ? widget.shell.serviceFor("omarchy.media") : null

  // S16. Only when something is playing.
  readonly property bool available: widget.preview || (widget.media && widget.media.hasMedia)

  implicitHeight: Style.space(56)

  Rectangle {
    anchors.fill: parent
    radius: widget.host.radiusCard
    color: widget.host.container

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(14)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(10)

      Column {
        // Whatever the transport block and the one gap before it leave.
        width: parent.width - widget.host.tapSlot * 3 - Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        Text {
          width: parent.width
          text: widget.preview ? "Chelsea Hotel No. 2"
                : (widget.media ? widget.media.title : "")
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.weight: widget.host.textWeight
          color: widget.host.textOnSurface
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: widget.preview ? "Leonard Cohen"
                : (widget.media ? widget.media.artist : "")
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: widget.host.textWeight
          color: widget.host.subdued
          elide: Text.ElideRight
        }
      }

      // Three tapSlot squares butted together with the glyph centred in each,
      // rather than three glyphs on a shared 10px spacing with the hit areas
      // grown outward (docs/style.md E4).
      //
      // Grown outward they could not get there. On 34px centres -- a 24px
      // glyph plus the Row's 10px gap -- the middle button can claim 5 on each
      // side before it starts eating its neighbours (E3), which tops out at 34
      // and leaves play the smallest target on the sheet. Carrying the gap
      // *inside* the slot is what buys the floor, and it costs the title 40px
      // of width: the one place where 44 was not free. Nested in its own Row so
      // the outer 10px spacing applies once, between the title and the block,
      // and not between buttons.
      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Repeater {
          // Names read out of the font's cmap, not off a chart -- and
          // written down here because this row is where guessing them
          // went wrong. It shipped as md-skip_previous, **md-sim** and
          // **md-shredder**: U+F04A7 is a SIM card and U+F049C is a
          // paper shredder in JetBrainsMono Nerd Font, which is what
          // actually draws these (omarchy.ttf has none of the Material
          // range). Nobody saw it because the card is only on screen
          // while something is playing. docs/control-center.md S29
          // records the same failure on the mobile-data tile.
          model: [
            { glyph: "󰒮", action: "previous" },   // md-skip_previous
            { glyph: "󰐎", action: "playPause" },  // md-play_pause
            { glyph: "󰒭", action: "next" }        // md-skip_next
          ]
          delegate: Item {
            required property var modelData
            width: widget.host.tapSlot
            height: widget.host.tapSlot

            // These have never had chrome, so the veil is the chrome
            // (docs/style.md H8) -- and it is drawn at tapSlot minus the Row
            // gap E4 moved *inside* the target, not at the full tapSlot, which
            // would butt three circles edge to edge and undo what E4 bought.
            Shared.PressVeil {
              anchors.centerIn: parent
              width: widget.host.tapSlot - Style.space(10)
              height: width
              radius: widget.host.radiusOn(width)
              ink: widget.host.textOnSurface
              on: mediaArea.pressed && !widget.host.sheetDragging
            }

            Ui.OpticalGlyph {
              anchors.centerIn: parent
              width: widget.host.glyphSlot
              height: widget.host.glyphSlot
              text: modelData.glyph
              fontFamily: Style.font.family
              fontSize: Style.font.iconLarge
              color: widget.host.textOnSurface
            }

            Shared.SheetDragArea {
              id: mediaArea
              sheet: widget.host.sheet
              anchors.fill: parent
              onClicked: if (!widget.preview && !widget.host.sheetWasDrag
                             && widget.media && typeof widget.media.runAction === "function")
                widget.media.runAction(modelData.action)
            }
          }
        }
      }
    }
  }
}

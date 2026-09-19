// A track you can put a thumb on rather than a hairline with a knob. The
// glyph rides inside it, so the control is its own label and the row costs
// one height instead of two.
//
// Out of ControlCenter.qml because two widgets draw one -- brightness and
// volume -- and a widget is a file (docs/widgets.md W1).
import QtQuick
import qs.Commons
import qs.Ui as Ui

Item {
  id: slider

  property var host: null
  property real value: 0        // 0..1
  property string glyph: ""
  // Whether to report every step of the drag or only the end of it. Volume is
  // in-process and free to follow the finger; brightness forks brightnessctl
  // per write, so it waits for the release.
  property bool live: false
  signal committed(real value)

  implicitHeight: slider.host.sliderHeight
  height: implicitHeight
  readonly property int vGrow: Math.min(Style.space(4),
    Math.max(0, Math.round((Style.space(44) - height) / 2)))
  readonly property real clamped: Math.max(0, Math.min(1, slider.value))
  property real dragValue: slider.clamped
  property bool dragging: false
  readonly property real shown: slider.dragging ? slider.dragValue : slider.clamped

  Rectangle {
    anchors.fill: parent
    // D1: the same tile radius as the quick-settings tiles, capped at a
    // half-side so Large stays a pill and Square goes to 0.
    radius: slider.host.radiusOn(height)
    color: slider.host.container

    Rectangle {
      height: parent.height
      // Never narrower than the corner diameter: below that a rounded fill
      // collapses into a lens and reads as a rendering fault rather than a
      // low value. Square (radius 0) may be a sliver.
      width: Math.max(parent.radius * 2, parent.width * slider.shown)
      radius: parent.radius
      color: slider.host.accent
      Behavior on width {
        enabled: !slider.dragging
        NumberAnimation { duration: 120 }
      }
    }

    // Over the track and the fill together, so it says "engaged" without
    // saying anything about the value. This looks like the one control that
    // does not need a press state -- the fill follows the thumb -- but that
    // fails at exactly one point: tap a slider at its current value and
    // nothing whatever happens. Guarded on the handover rather than on
    // sheetDragging, because this one hands the gesture over itself (H6).
    PressVeil {
      anchors.fill: parent
      radius: parent.radius
      ink: slider.host.textOnSurface
      on: sliderArea.pressed && !sliderArea.handedOver
    }

    // Positioned by where the glyph's centre should land, not by where its
    // box starts: the brightness sun is 3px wider than the speaker, so two
    // sliders given the same left margin had their glyphs on different
    // vertical lines.
    Ui.OpticalGlyph {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(20) - Math.round(slider.host.glyphSlot / 2)
      anchors.verticalCenter: parent.verticalCenter
      width: slider.host.glyphSlot
      height: slider.host.glyphSlot
      text: slider.glyph
      fontFamily: Style.font.family
      fontSize: Style.font.icon
      color: slider.host.textOnAccent
    }
  }

  // The one control on the sheet that cannot simply add the sheet drag
  // alongside its own, because it commits on *press*: this is a tap-to-set
  // slider, so the value has already moved by the time it is known whether
  // the finger is going sideways or up. So it hands over instead -- and puts
  // the value back, which for a live slider means undoing a commit it has
  // already sent.
  //
  // A raw MouseArea and not SheetDragArea, for that reason: the four handlers
  // that component owns are exactly the four this one has to do differently.
  // `sheet` null is a host that is not dragged (W13), and then there is
  // nothing to hand over to and the slider simply keeps the gesture.
  MouseArea {
    id: sliderArea
    anchors.fill: parent
    // Compact sliders draw under 44; grow the target into the Column gap,
    // never more than 4, so two adjacent sliders cannot eat each other (E3).
    anchors.topMargin: -slider.vGrow
    anchors.bottomMargin: -slider.vGrow
    readonly property var sheet: slider.host ? slider.host.sheet : null
    property real preValue: 0
    property real pressX: 0
    property bool handedOver: false
    function valueAt(x) { return Math.max(0, Math.min(1, x / Math.max(1, width))) }

    onPressed: mouse => {
      preValue = slider.value
      pressX = mouse.x
      handedOver = false
      if (sheet) sheet.sheetPress(this, mouse)
      slider.dragging = true
      slider.dragValue = valueAt(mouse.x)
      if (slider.live) slider.committed(slider.dragValue)
    }

    onPositionChanged: mouse => {
      if (handedOver) { if (sheet) sheet.sheetMove(this, mouse); return }
      if (!slider.dragging) return
      // Vertical and clearly not a slider adjustment: give the gesture to
      // the sheet and restore what the press already changed.
      if (sheet) {
        var dyScene = mapToItem(null, mouse.x, mouse.y).y - sheet.sheetPressY
        if (dyScene < -slider.host.dragSlop && Math.abs(dyScene) > Math.abs(mouse.x - pressX)) {
          slider.dragging = false
          handedOver = true
          if (slider.live) slider.committed(preValue)
          slider.dragValue = preValue
          sheet.sheetMove(this, mouse)
          return
        }
      }
      slider.dragValue = valueAt(mouse.x)
      if (slider.live) slider.committed(slider.dragValue)
    }

    // The sheet's touch is ended on every path, not only the handed-over
    // one. A slider drag never latches the sheet, so this used to be
    // harmless; since F2 it strands a live watchdog that fires four seconds
    // later and puts `progress` back under whatever is on screen.
    onReleased: mouse => {
      var handed = handedOver
      handedOver = false
      if (sheet) sheet.sheetRelease()
      if (handed) return
      if (!slider.dragging) return
      slider.dragging = false
      slider.committed(valueAt(mouse.x))
    }

    onCanceled: {
      if (sheet) sheet.sheetCancel()
      handedOver = false
      slider.dragging = false
    }
  }
}

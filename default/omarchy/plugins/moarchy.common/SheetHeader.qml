// The row at the top of a sheet: back, title, and whatever that sheet puts on
// the right (docs/refactor.md I3, and E5 with it).
//
// Usage:
//     // once per plugin, beside `component PressVeil:`
//     component SheetHeader: Shared.SheetHeader {
//       ink: root.textOnSurface
//       fill: root.container
//       titleWeight: root.textWeight
//       onBack: root.dismiss()
//     }
//
//     // at the top of the sheet's Column
//     SheetHeader {
//       title: "Wi-Fi"
//       Rectangle { id: radioSwitch; anchors.right: parent.right; ... }
//     }
//
// Four screens drew this: Wi-Fi, Bluetooth, the theme picker and Settings. The
// four back buttons were identical to the pixel -- 38 drawn, 44 answering, the
// glyph optically centred, the veil over the circle -- and three of them carried
// a comment saying they were the same as Settings'. A constraint stated three
// times is not enforced once (E4's argument, and this is the same shape).
//
// ---------------------------------------------------------------------------
// The measurements, which are the reason this is not four declarations
// ---------------------------------------------------------------------------
// **38 drawn, 44 answering** (`style.md` E1, E2). The header is 44 tall and the
// circle is centred in it, so the 3px is already there vertically; horizontally
// it eats into the surface margin on one side and the 12px before the title on
// the other, and neither of those takes a tap.
//
// **`OpticalGlyph`, not `anchors.centerIn`** -- centred on its ink rather than
// on its advance, for the reason the row chevron is: `centerIn` centres the box
// the font reserves, and a Nerd Font glyph is rarely centred inside that box.
// Measured, the gear in the control center's matching button sat 4 device pixels right
// of centre.
//
// ---------------------------------------------------------------------------
// What it does not own
// ---------------------------------------------------------------------------
// **Where back goes.** Three of the four dismiss; Settings walks its page stack
// first and dismisses only at the root. That is the screen's own business, so
// this emits `back()` and knows nothing about page stacks.
//
// **Its colours.** `ink` and `fill` are the surface's own roles, passed once per
// plugin the way `PressVeil`'s are (E2, H2) -- a shared type cannot know which
// surface it is on, and guessing paints the wrong colour on whichever screen
// forgets.
import QtQuick
import qs.Commons
import qs.Ui as Ui
import "Ui.js" as UiSpec

Item {
  id: header

  property string title: ""

  // The surface's text colour: the glyph, the title and the press veil's ink.
  property color ink

  // The resting fill of the back circle -- the surface's `container` role.
  property color fill

  property int titleWeight: Font.DemiBold

  // D1 tile radius from the surface. Passed in rather than watched here:
  // this component's default property is the trailing slot, so a UiFile
  // child would land in that slot and cover the back button.
  // -1 means "fully round" (Large); 0 is Square.
  property int radiusTile: -1

  // Controls this sheet puts at the right-hand end. They are children of an
  // item with the header's own geometry, so a child anchoring to `parent.right`
  // and `parent.verticalCenter` lands where it did when it was a sibling of the
  // back button.
  default property alias trailing: trailingSlot.data

  signal back()

  width: parent ? parent.width : 0
  height: Style.space(44)

  Rectangle {
    id: backButton
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(38)
    height: width
    // D1: same tile radius as the control center's icon buttons, capped at a half-side
    // so Large stays a circle and Square goes to 0.
    radius: UiSpec.radiusOn(header.radiusTile < 0 ? width : header.radiusTile, width)
    color: header.fill

    PressVeil { anchors.fill: parent; radius: parent.radius; ink: header.ink; on: backArea.pressed }

    // fa-angle-left. Pair of SettingsRow's fa-angle-right.
    Ui.OpticalGlyph {
      anchors.fill: parent
      text: ""
      fontFamily: Style.font.family
      fontSize: Style.font.icon
      color: header.ink
    }

    MouseArea {
      id: backArea
      anchors.fill: parent
      anchors.margins: -Style.space(3)
      onClicked: header.back()
    }
  }

  // Anchored right and eliding, which is what Settings' title did and what the
  // other three did not need: their titles are one word. Left-aligned, so a
  // title short enough to clear the trailing controls draws exactly where it
  // drew before.
  Text {
    anchors.left: backButton.right
    anchors.leftMargin: Style.space(12)
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: header.title
    font.family: Style.font.family
    font.pixelSize: Style.font.heading
    font.weight: header.titleWeight
    color: header.ink
    elide: Text.ElideRight
  }

  Item {
    id: trailingSlot
    anchors.fill: parent
  }
}

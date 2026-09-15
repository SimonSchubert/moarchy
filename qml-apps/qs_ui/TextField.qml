// Bound because the caret is a delegate. TextInput instantiates it, it reads
// `root` from inside cursorDelegate, and says so: it captures across the
// component boundary rather than resolving it by accident.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "Metrics.js" as Metrics

// A pill field with optional icons on either side.
//
// The inner control was the shell's Ui.TextField. It is a plain TextInput now,
// because the keyboard is not the shell's to give: moarchy-keyboard binds
// zwp_input_method_v2 and Qt speaks text-input-v3 for whatever holds focus, so
// a field raises the OSK through the compositor rather than through an API
// that only exists on our image.
//
// Icons sit outside the input: putting them in a suffix that can take focus
// would drop the keyboard the way a Gtk.Button on an Entry does.
Rectangle {
  id: root
  property alias text: field.text
  property alias placeholderText: placeholder.text
  property alias font: field.font
  property color foreground: "#ffffff"
  property color accent: "#3584e4"
  property color iconColor: "#9a9996"
  property color placeholderColor: root.iconColor
  property int bodySize: Metrics.BODY
  property var leadingNames: []
  property var trailingNames: []
  property bool trailingClickable: false

  signal trailingClicked
  signal accepted

  // The keyboard, on demand.
  //
  // `field` is private to this file, and forcing focus onto the pill itself
  // does nothing -- the TextInput inside it is what the compositor gives a
  // keyboard to. Without a way in, every form on the phone opens with its
  // first field waiting to be tapped before it can be typed into, which is a
  // tap spent reaching a keyboard that was always going to be needed.
  function focusInput(): void { field.forceActiveFocus() }

  implicitHeight: Metrics.PILL
  implicitWidth: 240
  radius: height / 2
  color: Qt.rgba(1, 1, 1, 0.06)

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: root.leadingNames.length ? 6 : 12
    anchors.rightMargin: root.trailingNames.length ? 4 : 12
    spacing: 4

    Icon {
      visible: root.leadingNames.length > 0
      Layout.preferredWidth: 22
      Layout.preferredHeight: 22
      slot: 22
      size: 14
      color: root.iconColor
      names: root.leadingNames
    }

    TextInput {
      id: field
      Layout.fillWidth: true
      Layout.fillHeight: true
      verticalAlignment: TextInput.AlignVCenter
      clip: true
      selectByMouse: true
      font.family: Metrics.FONT
      font.pixelSize: Metrics.typeSize(root.bodySize, "body")
      color: root.foreground
      selectionColor: root.accent
      selectedTextColor: root.foreground
      onAccepted: root.accepted()

      // TextInput draws the caret in `color`; a search field wants it in the
      // accent, the way every other field on the phone has it. Blinking and
      // visibility stay TextInput's: it drives them on the delegate itself.
      cursorDelegate: Rectangle {
        width: 2
        color: root.accent
      }

      Text {
        id: placeholder
        anchors.verticalCenter: parent.verticalCenter
        visible: !field.text.length
        color: root.placeholderColor
        font: field.font
        elide: Text.ElideRight
        width: parent.width
      }
    }

    Icon {
      visible: root.trailingNames.length > 0 && !root.trailingClickable
      Layout.preferredWidth: 32
      Layout.preferredHeight: 32
      slot: 32
      size: 16
      color: root.iconColor
      names: root.trailingNames
    }

    IconButton {
      visible: root.trailingNames.length > 0 && root.trailingClickable
      Layout.preferredWidth: 32
      Layout.preferredHeight: 32
      slot: 32
      size: 16
      color: root.foreground
      names: root.trailingNames
      onClicked: root.trailingClicked()
    }
  }
}

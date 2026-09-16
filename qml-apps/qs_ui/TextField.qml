// Bound because the caret is a delegate. TextInput instantiates it, it reads
// `root` from inside cursorDelegate, and says so: it captures across the
// component boundary rather than resolving it by accident.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "Theme.js" as Theme
import "Metrics.js" as Metrics

// A pill field with optional icons on either side.
//
// The inner control was the shell's Ui.TextField. It is a plain TextInput now,
// because the keyboard is not the shell's to give: moarchy-keyboard binds
// zwp_input_method_v2 and Qt speaks text-input-v3 for whatever holds focus.
// That is how text reaches the field, not how the keyboard comes up: focus
// arriving on its own raises nothing (moarchy's gestures.md G14), so a press on
// this field asks sm.puri.OSK0, the same way the restore handle does.
//
// Icons sit outside the input: putting them in a suffix that can take focus
// would drop the keyboard the way a Gtk.Button on an Entry does.
Rectangle {
  id: root
  property var colours: null
  // Where the field sits on the elevation ramp. "raised" is right inside a
  // Card; a field that is the only thing on the background takes "card".
  property string level: "raised"
  property alias text: field.text
  property alias placeholderText: placeholder.text
  property alias font: field.font
  // A password is typed into one of these too, and an address wants a
  // keyboard that does not capitalise it. Mail's sign-in form was the first
  // to need either.
  property alias echoMode: field.echoMode
  property alias inputMethodHints: field.inputMethodHints
  // Whether the caret is in this field -- for a form that shows suggestions
  // under whichever field is being typed in.
  readonly property alias inputFocus: field.activeFocus
  // Where the caret is. A field filled in for you -- a reply's To -- scrolls
  // to its end, and 0 is how it shows its start instead.
  property alias cursorPosition: field.cursorPosition
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

  // Place the caret.
  //
  // `field` is private to this file, and forcing focus onto the pill itself
  // does nothing -- the TextInput inside it is what takes the text. It does not
  // raise the keyboard: a form that focuses its first field for you is not a
  // person asking (G14). A press that starts on `field` is.
  function focusInput(): void { field.forceActiveFocus() }

  Osk { id: osk }
  // Armed a moment after the field exists, so a finger already down when it
  // slides into place -- an app opening under a swipe -- does not count.
  property bool raiseArmed: false
  Timer {
    interval: 200
    running: true
    onTriggered: root.raiseArmed = true
  }

  implicitHeight: Metrics.PILL
  implicitWidth: 240
  radius: Metrics.round(root.colours, height)
  // The theme's own ink into the theme's own background, not white at an
  // alpha: on a light desktop the latter is an invisible field.
  color: Theme.surface(root.colours, root.level)

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
      // A press that starts on this field, passed on so the TextInput still
      // places the caret. onPressed rather than a TapHandler: onTapped fires on
      // the release of a finger that began elsewhere, which is how the keyboard
      // came up by itself.
      MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        onPressed: mouse => {
          if (root.raiseArmed) osk.show()
          mouse.accepted = false
        }
      }

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

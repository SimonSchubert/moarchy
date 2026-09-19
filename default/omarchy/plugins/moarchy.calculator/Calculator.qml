// A calculator for a phone: the four operations, and arithmetic in tens.
//
// Two bands. **The keypad is the bottom half**, because it is the only part
// anybody touches and a phone is held from the bottom. **The sum is everything
// above it**, sitting on the keys rather than at the far end of the window, so
// the thing changing is next to the thing changing it.
//
// The running answer under the expression is why `=` goes unpressed in most
// sessions. It appears as soon as the sum has an operator in it and is
// recomputed on every keystroke, which is affordable because `Calc.complete()`
// makes a half-typed expression into a whole one and evaluating one is a few
// hundred string operations on something never longer than a line.
//
// The one thing written down is the sum being typed, and it is not written per
// keystroke -- that is a write per digit onto a phone's flash -- but when the
// window stops being mapped, which on this phone is the event immediately
// before the app is reclaimed. Coming back to a blank screen after taking a
// call is the thing that makes a phone calculator annoying.
//
// Nothing here is a port. The GTK half of this repository has no calculator,
// and this was written for the shell first: it is an Item the plugin host keeps
// loaded, so summoning it is a window becoming visible rather than a process
// starting.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Calc.js" as Calc
import "Store.js" as Store

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "moarchy.calculator"
  readonly property bool opened: sumWindow.visible
  readonly property var appWindow: sumWindow

  property string returnTo: ""
  readonly property var colours: themeFile.colours
  property int bodySize: Metrics.BODY
  Component.onCompleted: root.bodySize = Metrics.shellBody(root)

  // The sum being typed. One string, and `Calc.js` holds every function that is
  // allowed to change it -- which is what makes it impossible to type something
  // that will not evaluate.
  property string entry: ""

  // The display is showing an answer rather than something being typed. The
  // next digit then starts a new sum and the next operator carries on from this
  // one, which is how every calculator ever made behaves and what nobody has
  // ever had to be told.
  property bool answered: false

  // A sentence where the running answer goes, when the sum cannot have one.
  property string problem: ""

  property bool loaded: false

  // The file has been read. It is read exactly once, and the flag is the whole
  // reason this property exists -- see `store` below.
  property bool restored: false

  // The shell keeps the bottom of every screen for itself, and both things it
  // keeps it for are layer surfaces that draw over an app and take the taps
  // that land on them: the gesture bar across the middle, and
  // moarchy-keyboard's toggle at the right.
  //
  // Measured on a PinePhone at 360x740: the toggle is 49x28 and its top edge is
  // 58px up from the bottom. Drawn under it, the `=` key is covered across its
  // middle -- the pill sits exactly where the glyph is -- and the gesture bar
  // takes the same bite out of `.` and the backspace. Vitals draws under both
  // and loses half its Network tab to them; a keypad cannot afford the same
  // trade, because the keys it would lose are the ones people press.
  //
  // Only under the shell. `shell` is null when this runs as its own Quickshell
  // process from shell.qml, where there is no furniture and a reserved strip
  // would be a bug rather than a fix.
  readonly property int shellFurniture: root.shell ? 60 : 0

  readonly property string dataDir: Plugin.dataDir(
    "calculator", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_CALCULATOR_DIR"))

  // --- colour ---------------------------------------------------------------

  readonly property color background: root.colours.background
  readonly property color ink: root.colours.foreground
  readonly property color dim: root.colours.dim
  readonly property color accent: root.colours.accent
  readonly property string danger: (root.colours.hues && root.colours.hues.red) || "#e01b24"

  // How bright a colour is, on the crude weighting that has been good enough
  // for choosing black-or-white text since the nineteen-fifties.
  function shade(colour) {
    var c = Theme.rgb(String(colour))
    return (c[0] * 299 + c[1] * 587 + c[2] * 114) / 255000.0
  }

  // What can be read on the equals key. Not always the background: on a light
  // theme that is white, and white on a theme whose accent is a pale yellow is
  // an equals key nobody can find.
  readonly property string onAccent: {
    var level = root.controlCenter(root.colours.accent)
    return Math.abs(level - root.controlCenter(root.colours.background))
         > Math.abs(level - root.controlCenter(root.colours.foreground))
      ? root.colours.background : root.colours.foreground
  }

  // A key's colour says what kind of key it is, and there are only four kinds:
  // a digit is the theme's foreground on a step up from the window, an operator
  // is the accent on a wash of the accent, equals is the accent solid, and
  // clear is the theme's red. Nothing carries meaning by colour alone -- every
  // key says what it does in a glyph as well.
  //
  // The step is mixed from the theme's *foreground* rather than from its
  // surface, which is Minesweeper's rule and for its reason: on a light theme a
  // surface colour is nearly the window colour, so keys mixed from it come out
  // invisible.
  function keyFill(kind, pressed) {
    var bg = root.colours.background
    if (kind === "operator")
      return Theme.mix(root.colours.accent, bg, pressed ? 0.26 : 0.15)
    if (kind === "equals")
      return pressed ? Theme.mix(root.colours.foreground, root.colours.accent, 0.22)
                     : root.colours.accent
    if (kind === "clear")
      return Theme.mix(root.danger, bg, pressed ? 0.26 : 0.13)
    return Theme.mix(root.colours.foreground, bg, pressed ? 0.17 : 0.09)
  }

  function keyInk(kind) {
    if (kind === "operator") return root.colours.accent
    if (kind === "equals") return root.onAccent
    if (kind === "clear") return root.danger
    // Quieter than a digit, but not the dim a caption is drawn in: these three
    // are controls rather than labels, and on a light theme the theme's own dim
    // against a key that is itself pale is a key somebody has to look for.
    if (kind === "aux") return Theme.mix(root.colours.foreground, root.colours.dim, 0.45)
    return root.colours.foreground
  }

  function keySize(key) {
    if (key.kind === "operator" || key.kind === "equals") return Math.round(root.bodySize * 1.6)
    // The backspace is a drawn glyph rather than a word, and at the size the
    // two words beside it take it reads as a smudge.
    if (key.t === "<") return Math.round(root.bodySize * 1.4)
    if (key.kind === "aux" || key.kind === "clear") return Math.round(root.bodySize * 1.15)
    return Math.round(root.bodySize * 1.45)
  }

  // --- what is on the screen ------------------------------------------------

  readonly property string shownSum: root.entry.length ? Calc.pretty(root.entry) : "0"

  // The running answer, or nothing at all. Nothing at all while the sum is a
  // single number: `12` under `12` is a line of the display spent saying that
  // twelve is twelve, and a preview that is always there stops being read.
  readonly property string shownAnswer: {
    if (root.problem.length) return root.problem
    var ready = Calc.complete(root.entry)
    if (!ready.length || Calc.isPlain(ready)) return ""
    var value = Calc.running(root.entry)
    return value === null ? "" : Calc.formatNumber(value)
  }

  // --- the keys -------------------------------------------------------------

  function press(token) {
    if (token === "=") { root.equals(); return }
    if (token === "AC") { root.clearSum(); return }

    var text = root.entry
    // Backspacing an answer would delete a digit of a number the display is
    // showing a rounded version of, which is an edit nobody could see. It
    // clears instead, as a fresh digit does.
    if (root.answered && (token === "<" || token === "()"
                          || token === "." || Calc.isDigit(token))) text = ""
    root.answered = false
    root.problem = ""

    if (Calc.isDigit(token)) text = Calc.digit(text, token)
    else if (token === ".") text = Calc.point(text)
    else if (Calc.isOperator(token)) text = Calc.operator(text, token)
    else if (token === "()") text = Calc.bracket(text)
    else if (token === "%") text = Calc.percent(text)
    else if (token === "<") text = Calc.back(text)
    root.entry = text
  }

  // `=` replaces the sum with its answer, and the answer is kept to the digit
  // rather than to the twelve the display shows -- so carrying on from it
  // carries on from what the arithmetic had, not from what was legible.
  function equals() {
    var ready = Calc.complete(root.entry)
    if (!ready.length) return
    var answer = Calc.evaluate(ready)
    if (!answer.ok) { root.problem = answer.why; return }
    root.entry = Calc.toEntry(answer.value)
    root.answered = true
    root.problem = ""
    root.save()
  }

  function clearSum() {
    root.problem = ""
    root.answered = false
    root.entry = ""
  }

  // A run of keys, pressed one at a time rather than assigned. The screenshot
  // harness's way in, and the IPC handler's: a state the keypad cannot reach is
  // a state worth not being able to photograph or script.
  function keysFrom(text) {
    var source = String(text || "")
    for (var i = 0; i < source.length; i++) {
      var ch = source.charAt(i)
      if (ch === "(" || ch === ")") root.press("()")
      else root.press(ch)
    }
  }

  // --- the plugin host's end of it ------------------------------------------

  function say(text) { toast.show(text) }

  function open(payloadJson) {
    Plugin.hideOverlays(root.shell)
    root.returnTo = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload.returnTo) root.returnTo = String(payload.returnTo)
    } catch (e) {}
    sumWindow.show()
    Qt.callLater(root.ensureLoaded)
  }

  function close() {}

  function dismiss() {
    sumWindow.hide()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    var back = root.returnTo
    root.returnTo = ""
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, "{}")
  }

  function ensureLoaded() {
    if (root.loaded) return
    ensureDir.running = true
    store.reload()
    root.loaded = true
  }

  function save() {
    store.setText(Store.serialize({ entry: root.entry, answered: root.answered }))
  }

  Process { id: ensureDir; running: false; command: ["mkdir", "-p", root.dataDir] }

  Chrome.JsonFile {
    id: store
    path: root.dataDir + "/calculator.json"

    // Read once, at startup, and never again.
    //
    // Not an optimisation. `setText` writes the file, the watch on it fires,
    // and the reload hands back whatever was saved -- so without this guard,
    // pressing `=` and carrying on typing puts the *answer* back on the display
    // a moment later and takes away the sum being typed with it. Every other
    // plugin here gets away without the guard because re-reading its own write
    // restores the state it was already in; this one has a field that moves on
    // between the write and the read, which is what makes it visible.
    onParsed: function (data) {
      if (root.restored) return
      root.restored = true
      var state = Store.parse(data)
      root.entry = state.entry
      root.answered = state.answered
    }
    onQuarantined: function (to) { root.say("The saved sum was unreadable and was kept aside.") }
  }

  Chrome.ThemeFile { id: themeFile }

  IpcHandler {
    target: "calculator"
    function state(): string { return root.opened ? "open" : "closed" }
    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      return "ok"
    }
    function close(): string { root.dismiss(); return "ok" }
    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }
    // One key at a time, named as the keypad names it, so a script drives the
    // app through exactly the path a thumb does.
    function key(token: string): string { root.press(String(token)); return root.entry }
    function keys(tokens: string): string { root.keysFrom(tokens); return root.entry }
    function sum(): string { return root.entry }
    function answer(): string { return root.shownAnswer }
  }

  // --- the window -----------------------------------------------------------

  Chrome.AppWindow {
    id: sumWindow
    shell: root.shell
    appName: "Calculator"
    pluginId: root.pluginId
    color: root.background

    onMapped: Qt.callLater(root.ensureLoaded)
    // The one write there is: whatever was being typed when the window went
    // away. See the header.
    onUnmapped: if (root.loaded) root.save()

    Rectangle {
      anchors.fill: parent
      color: root.background
      focus: true

      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.press("="); event.accepted = true; return
        }
        if (event.key === Qt.Key_Backspace) { root.press("<"); event.accepted = true; return }
        if (event.key === Qt.Key_Delete) { root.press("AC"); event.accepted = true; return }
        var ch = String(event.text || "")
        if (!ch.length) return
        if (Calc.isDigit(ch) || Calc.isOperator(ch) || ch === "%" || ch === "=") {
          root.press(ch); event.accepted = true; return
        }
        if (ch === "." || ch === ",") { root.press("."); event.accepted = true; return }
        if (ch === "(" || ch === ")") { root.press("()"); event.accepted = true }
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Chrome.AppBar {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 12
          title: "Calculator"
          foreground: root.ink
          dim: root.dim
          bodySize: root.bodySize
        }

        // --- the sum ----------------------------------------------------------

        // Everything between the title and the keys, with the sum sitting at the
        // bottom of it. Against the keypad rather than centred in the space:
        // what is being typed belongs next to what is typing it, and a number
        // that moved as it grew would be a number nobody could read while it
        // was changing.
        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.minimumHeight: display.height + Metrics.GAP * 2

          // The sum is in a box, like everything else on this phone. It is
          // also the one box that is anchored to the *bottom* of the room it
          // is given: what is being typed belongs next to what is typing it,
          // and a number that moved as it grew would be a number nobody could
          // read while it was changing.
          Rectangle {
            id: display
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Metrics.GAP
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Metrics.GUTTER
            anchors.rightMargin: Metrics.GUTTER
            height: sum.implicitHeight + answer.implicitHeight + Metrics.PAD * 2 + 2
            radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
            color: Theme.surface(root.colours, "card")

            Chrome.TypedText {
              id: sum
              anchors.bottom: answer.top
              anchors.bottomMargin: 2
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Metrics.PAD
              anchors.rightMargin: Metrics.PAD
              role: "title"
              font.pixelSize: Math.round(root.bodySize * 2.4)
              font.weight: Font.Normal
              text: root.shownSum
              color: root.ink
              bodySize: root.bodySize
              horizontalAlignment: Text.AlignRight
              // Elided at the *left*, which is the end a long sum is not being
              // typed at. What stays on screen is the part still being written.
              elide: Text.ElideLeft
              maximumLineCount: 1
            }

            Chrome.TypedText {
              id: answer
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Metrics.PAD
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Metrics.PAD
              anchors.rightMargin: Metrics.PAD
              role: "subtitle"
              font.pixelSize: Math.round(root.bodySize * 1.35)
              text: root.shownAnswer
              color: root.problem.length ? root.danger : root.accent
              bodySize: root.bodySize
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideLeft
              maximumLineCount: 1
            }
          }

          Chrome.Toast {
            id: toast
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 12
            colours: root.colours
            bodySize: root.bodySize
          }
        }

        // --- the keys ---------------------------------------------------------

        GridLayout {
          Layout.fillWidth: true
          Layout.leftMargin: Metrics.GUTTER
          Layout.rightMargin: Metrics.GUTTER
          Layout.topMargin: 4
          Layout.bottomMargin: Metrics.GUTTER + root.shellFurniture
          columns: Calc.COLUMNS
          columnSpacing: Metrics.GAP
          rowSpacing: Metrics.GAP

          Repeater {
            model: Calc.KEYS

            delegate: Rectangle {
              id: key
              required property var modelData

              Layout.fillWidth: true
              // 62 against the 44 a thumb is usually given. A keypad is the one
              // surface on a phone where a slip costs a wrong number rather
              // than a wrong screen, and five rows of 62 still leave a third of
              // the window for the sum above them.
              Layout.preferredHeight: 62
              radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
              color: root.keyFill(key.modelData.kind, keyTap.pressed)
              Behavior on color { ColorAnimation { duration: Metrics.PRESS_MS } }

              Chrome.TypedText {
                anchors.centerIn: parent
                role: "body"
                font.pixelSize: root.keySize(key.modelData)
                font.weight: key.modelData.kind === "digit" ? Font.Medium : Font.DemiBold
                text: key.modelData.label
                color: root.keyInk(key.modelData.kind)
                bodySize: root.bodySize
              }

              MouseArea {
                id: keyTap
                anchors.fill: parent
                onClicked: root.press(key.modelData.t)
              }

              Accessible.role: Accessible.Button
              Accessible.name: key.modelData.say
              Accessible.onPressAction: root.press(key.modelData.t)
            }
          }
        }
      }
    }
  }
}

// Settings: a stack of phone screens over Omarchy's menu.
//
// ---------------------------------------------------------------------------
// What this replaced
// ---------------------------------------------------------------------------
// Eight rows, of which seven summoned `omarchy.menu` at a route and handed the
// user Omarchy's desktop list. That list is a popup this port cannot dismiss by
// tapping outside -- install/port-4x.sh stubs out HyprlandFocusGrab, which has
// no Quickshell.I3 counterpart -- so every one of those rows was a trapdoor.
//
// The screens live in Pages.js as data; this file is the machinery that renders
// them. docs/menu-coverage.md records which of upstream's 320 entries land
// where, and docs/settings.md is the contract with the acceptance criteria.
//
// ---------------------------------------------------------------------------
// Three things here are load-bearing and look optional
// ---------------------------------------------------------------------------
// 1. open() does no reading. It sets the page and returns; the guard batch runs
//    from Qt.callLater. open() is called inside the IPC handler for
//    `omarchy-shell shell summon`, and anything that spins a nested event loop
//    there leaves it unfinished -- which maps a layer surface that never paints:
//    a black rectangle over the whole screen, logged nowhere. Same trap
//    port-4x.sh documents on the launcher's FileView.
//
// 2. Row visibility is a property looked up per row, not a filter over the
//    model. A ListView whose model array is replaced tears down and recreates
//    its delegates, and a delegate recreated under a finger eats the tap.
//
// 3. No property here is named on<Uppercase>. QML reserves that prefix for
//    signal handlers, so such a property reads back undefined, and undefined
//    assigned to a color renders pure black with nothing logged.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "Pages.js" as Pages
import "Guards.js" as Guards

Item {
  id: root

  // Injected by the host in onLoaded, by name, after construction. NOT
  // `readonly` and NOT `required`: readonly makes the assignment throw,
  // required makes the component fail to instantiate, and either way the
  // plugin silently does not load.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
                               || (Quickshell.env("HOME") + "/.local/share/omarchy")
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "mobileomarchy.settings"

  property bool opened: false
  property string returnTo: ""

  // The page stack, root first. currentPage is its top.
  property var stack: ["root"]
  readonly property string currentPage: root.stack.length
                                        ? root.stack[root.stack.length - 1] : "root"

  // Answers from the last guard batch, keyed by row id.
  property var whenMap: ({})
  property var valueMap: ({})
  property string pageValue: ""

  // Rows a provider or text page built for itself. Empty for ordinary pages.
  property var dynamicRows: []

  // Set by `settings dryRun 1`. Records what would have run instead of running
  // it, which is what lets the selftest exercise every bridged row on a phone
  // it is not allowed to reboot.
  property bool dryRun: false
  property string lastLaunch: ""

  property string confirmText: ""
  property var confirmRow: null

  readonly property int radiusCard: Style.space(18)

  // NOT `onSurface` / `onAccent` -- see the header.
  readonly property color surface: Color.menu.background
  readonly property color textOnSurface: Color.menu.text
  readonly property color container: Util.alpha(Color.menu.text, 0.08)
  readonly property color subdued: Util.alpha(Color.menu.text, 0.6)
  readonly property color accent: Color.accent

  readonly property var pageDef: Pages.page(root.currentPage)
  readonly property string pageTitle: root.pageDef ? root.pageDef.title : "Settings"

  // Stable identity for an ordinary page: the same array object comes back from
  // Pages.js every time, so the ListView keeps its delegates.
  readonly property var currentRows: {
    var p = root.pageDef
    if (!p) return []
    return (p.provider || p.text) ? root.dynamicRows : p.rows
  }

  function rowsTsv(pageId) {
    if (!Pages.exists(pageId)) return "unknown page: " + pageId
    var live = (pageId === root.currentPage)
    var rows = live ? root.currentRows : Pages.page(pageId).rows
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i]
      out.push([r.id, r.type, r.label,
                live ? (root.rowVisible(r) ? "1" : "0") : "?",
                live ? (root.rowChecked(r) ? "1" : "0") : "?",
                live ? root.rowDetail(r) : ""].join("\t"))
    }
    return out.join("\n")
  }

  function rowById(id) {
    var rows = root.currentRows
    for (var i = 0; i < rows.length; i++) if (rows[i].id === id) return rows[i]
    return null
  }

  // A row with no `when` is visible. One with a `when` is visible only on an
  // explicit pass -- so a guard that fails, hangs or is missing hides its row
  // rather than showing it wrongly.
  function rowVisible(row) {
    if (!row) return false
    if (!row.when) return true
    return root.whenMap[row.id] === true
  }

  function rowChecked(row) {
    if (!row) return false
    if (row.type === "switch") {
      var v = String(root.valueMap[row.id] || "").toLowerCase()
      var on = (v === "true" || v === "1" || v === "on" || v === "enabled")
      return row.invert ? !on : on
    }
    if (row.type === "choice")
      return root.pageValue !== "" &&
             root.pageValue === String(row.readValue || row.value)
    return false
  }

  // `detail` is prose written in the model; `detailCmd` is a shell expression
  // the guard batch answers. Two fields rather than one guessed apart at
  // runtime -- "Keep the screen on" and "basename \"$(omarchy-theme-bg-current)\""
  // are not distinguishable by inspection, and guessing got it wrong both ways.
  function rowDetail(row) {
    if (!row) return ""
    if (row.detailCmd || row.type === "info")
      return String(root.valueMap[row.id] || "")
    return String(row.detail || "")
  }

  // ------------------------------------------------------------ lifecycle
  function open(payloadJson) {
    if (root.shell && typeof root.shell.isPluginOpen === "function") {
      var others = ["mobileomarchy.shade", "mobileomarchy.drawer",
                    "mobileomarchy.recents", "mobileomarchy.themes"]
      for (var i = 0; i < others.length; i++)
        if (root.shell.isPluginOpen(others[i])) root.shell.hide(others[i])
    }

    root.returnTo = ""
    var start = "root"
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload.returnTo) root.returnTo = String(payload.returnTo)
      if (payload.page && Pages.exists(String(payload.page)))
        start = String(payload.page)
    } catch (e) {
      // A malformed payload is not worth refusing to open over.
    }

    root.stack = [start]
    root.confirmText = ""
    root.opened = true
    // Deferred, always. See note 1 in the header.
    Qt.callLater(root.refresh)
  }

  function close() { root.opened = false }

  function dismiss() {
    var back = root.returnTo
    root.returnTo = ""
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.close()
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, "{}")
  }

  // ---------------------------------------------------------- navigation
  function push(pageId) {
    if (!Pages.exists(pageId)) return false
    if (pageId === root.currentPage) return true   // pushing the top is a no-op
    var next = root.stack.slice()
    next.push(pageId)
    root.stack = next
    root.afterPageChange()
    return true
  }

  function pop() {
    if (root.stack.length <= 1) return false
    var next = root.stack.slice()
    next.pop()
    root.stack = next
    root.afterPageChange()
    return true
  }

  // What the left-edge back gesture calls. True means "consumed"; false means
  // there is nothing left to go back to, so the gesture layer closes us.
  function goBack() {
    if (root.confirmText !== "") { root.confirmText = ""; root.confirmRow = null; return true }
    return root.pop()
  }

  function afterPageChange() {
    root.whenMap = ({})
    root.valueMap = ({})
    root.pageValue = ""
    root.dynamicRows = []
    root.refresh()
  }

  // ------------------------------------------------------ reading a page
  //
  // One bash for the whole page. A provider or text page needs its rows before
  // there is anything to ask about, so that runs first and calls back here.
  function refresh() {
    var p = root.pageDef
    if (!p) return
    if ((p.provider || p.text) && root.dynamicRows.length === 0) {
      dynamicProc.command = ["bash", "-lc", p.provider ? p.provider.list : p.text]
      dynamicProc.running = true
      return
    }
    var script = Guards.build(root.currentRows, p.reader || "")
    if (!script) return
    guardProc.command = ["bash", "-lc", script]
    if (!guardProc.running) guardProc.running = true
  }

  Process {
    id: dynamicProc
    stdout: StdioCollector {
      onStreamFinished: {
        var p = root.pageDef
        if (!p) return
        var lines = String(text || "").split("\n")
        var built = []
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i]
          if (!line || !line.trim()) continue
          if (p.text) {
            // Columnar output from omarchy-menu-keybindings --print: keys,
            // action, section, padded apart. Two or more spaces is the split.
            var parts = line.split(/\s{2,}/)
            built.push({ id: "k" + i, type: "info",
                         label: (parts[0] || "").trim(),
                         detail: (parts[1] || "").trim() })
          } else {
            var value = line.trim()
            var label = p.provider.label === "basename"
                        ? value.replace(/^.*\//, "") : value
            built.push({ id: "p" + i, type: "choice", label: label, value: value,
                         write: p.write + " " + JSON.stringify(value) })
          }
        }
        root.dynamicRows = built
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: guardProc
    stdout: StdioCollector {
      onStreamFinished: {
        var parsed = Guards.parse(String(text || ""))
        root.whenMap = parsed.when
        root.valueMap = parsed.value
        root.pageValue = parsed.value["__page"] !== undefined
                         ? String(parsed.value["__page"]) : ""
      }
    }
  }

  // ------------------------------------------------------------ activating
  function commandFor(row) {
    if (!row) return ""
    if (row.type === "link")
      return "omarchy-launch-webapp " + JSON.stringify(String(row.url))
    if (row.type === "choice") return String(row.write || "")
    if (row.launch === "tui")
      return "omarchy-launch-floating-terminal-with-presentation " + String(row.run)
    return String(row.run || "")
  }

  function runCommand(cmd) {
    if (!cmd) return
    root.lastLaunch = cmd
    if (root.dryRun) return
    Quickshell.execDetached(["bash", "-lc", cmd])
  }

  function setSwitch(row, on) {
    if (!row) return
    var cmd = on ? row.on : row.off
    if (!cmd) return
    root.lastLaunch = String(cmd)
    if (root.dryRun) return
    switchProc.command = ["bash", "-lc", String(cmd)]
    // Process.running rather than execDetached: the write is only half of it,
    // and onExited is what tells us to read the state back.
    if (!switchProc.running) switchProc.running = true
  }

  Process {
    id: switchProc
    onExited: Qt.callLater(root.refresh)
  }

  function activate(row) {
    if (!row) return
    if (row.confirm && root.confirmText === "") {
      root.confirmText = String(row.confirm)
      root.confirmRow = row
      return
    }
    root.confirmText = ""
    root.confirmRow = null

    if (row.type === "nav") { root.push(row.page); return }

    if (row.type === "plugin") {
      var target = String(row.plugin)
      var here = root.currentPage
      root.dismiss()
      if (root.shell && typeof root.shell.summon === "function")
        root.shell.summon(target, JSON.stringify({ returnTo: root.pluginId,
                                                   page: here }))
      return
    }

    if (row.type === "switch") { root.setSwitch(row, !root.rowChecked(row)); return }

    if (row.type === "choice") {
      root.runCommand(root.commandFor(row))
      // Re-read rather than assume: the reader is the truth, and a write that
      // did not take must not leave the tick moved.
      if (!root.dryRun) Qt.callLater(root.refresh)
      return
    }

    if (row.type === "info") return

    // action, link. Settings goes away first so the terminal or the vendored
    // picker is not underneath a layer surface -- and so a screenshot is not
    // a screenshot of this screen.
    var cmd = root.commandFor(row)
    if (!root.dryRun) root.dismiss()
    root.runCommand(cmd)
  }

  // ------------------------------------------------------------------ IPC
  IpcHandler {
    target: "settings"

    function state(): string { return root.opened ? "open" : "closed" }

    // Quickshell's typed IPC has no optional arguments -- a declared parameter
    // is required -- so the no-argument and one-argument forms are separate
    // functions rather than one with a default.
    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      return "ok"
    }

    function openAt(page: string): string {
      if (!Pages.exists(page)) return "unknown page: " + page
      if (root.shell)
        root.shell.summon(root.pluginId, JSON.stringify({ page: page }))
      return "ok"
    }

    function close(): string { root.dismiss(); return "ok" }

    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }

    function page(): string { return root.currentPage }

    function stack(): string { return root.stack.join("\n") }

    function goto(page: string): string {
      if (!Pages.exists(page)) return "unknown page: " + page
      root.push(page)
      return "ok"
    }

    function back(): string {
      if (root.goBack()) return root.currentPage
      root.dismiss()
      return "closed"
    }

    // TSV so a value with a space in it survives: rowId, type, label, visible,
    // checked, detail. Visibility and state are only real for the page that is
    // actually open -- another page's guards have not been run, and answering
    // "0" for those would read as "hidden" rather than "not asked".
    function rows(): string { return root.rowsTsv(root.currentPage) }

    function rowsOn(page: string): string { return root.rowsTsv(page) }

    function value(rowId: string): string {
      var row = root.rowById(rowId)
      if (!row) return "unknown row"
      if (row.type === "switch") return root.rowChecked(row) ? "on" : "off"
      if (row.type === "choice") return root.pageValue
      return String(root.valueMap[rowId] || "")
    }

    function set(rowId: string, value: string): string {
      var row = root.rowById(rowId)
      if (!row) return "unknown row"
      if (!root.rowVisible(row)) return "hidden"
      if (row.type === "switch") {
        root.setSwitch(row, value === "on" || value === "true" || value === "1")
        return "ok"
      }
      if (row.type === "choice") {
        root.runCommand(root.commandFor(row))
        if (!root.dryRun) Qt.callLater(root.refresh)
        return "ok"
      }
      return "not settable"
    }

    function activate(rowId: string): string {
      var row = root.rowById(rowId)
      if (!row) return "unknown row"
      if (!root.rowVisible(row)) return "hidden"
      root.activate(row)
      return "ok"
    }

    function guards(): string {
      var out = []
      var rows = root.currentRows
      for (var i = 0; i < rows.length; i++)
        out.push(rows[i].id + "\t" + (root.rowVisible(rows[i]) ? "1" : "0"))
      return out.join("\n")
    }

    function refresh(): string { root.refresh(); return "ok" }

    function dryRun(on: string): string {
      root.dryRun = (on === "1" || on === "true" || on === "on")
      return "ok"
    }

    function lastLaunch(): string { return root.lastLaunch }

    // Emitted from Pages.js, not from the doc -- which is what makes coverage
    // parity a bash assertion rather than a promise.
    function coverage(): string {
      var rows = Pages.coverage()
      var out = []
      var names = { N: "Native", B: "Bridged", S: "Shade" }
      for (var i = 0; i < rows.length; i++)
        out.push([rows[i][0], names[rows[i][1]] || rows[i][1],
                  rows[i][2], rows[i][3]].join("\t"))
      return out.join("\n")
    }
  }

  // --------------------------------------------------------------- surface
  PanelWindow {
    id: settingsWindow

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "mobileomarchy-settings"
    WlrLayershell.layer: WlrLayer.Top

    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive
                                             : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: root.surface
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 140 } }

      focus: true
      Keys.onEscapePressed: { if (!root.goBack()) root.dismiss() }

      Column {
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        anchors.topMargin: Style.space(8)
        anchors.bottomMargin: Style.space(8)
        spacing: Style.space(10)

        Item {
          width: parent.width
          height: Style.space(44)

          Rectangle {
            id: backButton
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(38)
            height: width
            radius: width / 2
            color: root.container

            Text {
              anchors.centerIn: parent
              text: "󰅁"
              font.family: Style.font.family
              font.pixelSize: Style.font.icon
              color: root.textOnSurface
            }
            MouseArea {
              anchors.fill: parent
              onClicked: { if (!root.goBack()) root.dismiss() }
            }
          }

          Text {
            anchors.left: backButton.right
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.pageTitle
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            color: root.textOnSurface
            elide: Text.ElideRight
          }
        }

        ListView {
          id: rowList
          width: parent.width
          height: Math.max(0, parent.height - y)
          clip: true
          spacing: Style.space(6)
          model: root.currentRows
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          cacheBuffer: Style.space(58) * 4

          delegate: SettingsRow {
            required property var modelData
            width: rowList.width
            visible: root.rowVisible(modelData)
            height: visible ? Style.space(58) : 0
            color: root.container
            rowType: modelData.type
            glyph: modelData.glyph || ""
            label: modelData.label || ""
            detail: root.rowDetail(modelData)
            checked: root.rowChecked(modelData)
            rowEnabled: modelData.type !== "info"
            textColor: root.textOnSurface
            subduedColor: root.subdued
            accentColor: root.accent
            onActivated: root.activate(modelData)
          }
        }
      }

      // ------------------------------------------------------- confirm
      Rectangle {
        anchors.fill: parent
        visible: root.confirmText !== ""
        color: Util.alpha(root.surface, 0.92)

        MouseArea { anchors.fill: parent }   // swallow taps behind the card

        Rectangle {
          anchors.centerIn: parent
          width: parent.width - Style.space(48)
          height: confirmCol.implicitHeight + Style.space(32)
          radius: root.radiusCard
          color: root.container

          Column {
            id: confirmCol
            anchors.centerIn: parent
            width: parent.width - Style.space(32)
            spacing: Style.space(16)

            Text {
              width: parent.width
              text: root.confirmText
              wrapMode: Text.WordWrap
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              color: root.textOnSurface
            }

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(12)

              Rectangle {
                width: Style.space(110); height: Style.space(44)
                radius: height / 2
                color: Util.alpha(root.textOnSurface, 0.10)
                Text {
                  anchors.centerIn: parent; text: "Cancel"
                  font.family: Style.font.family; font.pixelSize: Style.font.body
                  color: root.textOnSurface
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: { root.confirmText = ""; root.confirmRow = null }
                }
              }

              Rectangle {
                width: Style.space(110); height: Style.space(44)
                radius: height / 2
                color: root.accent
                Text {
                  anchors.centerIn: parent; text: "Continue"
                  font.family: Style.font.family; font.pixelSize: Style.font.body
                  color: root.surface
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    var row = root.confirmRow
                    root.confirmText = ""
                    root.confirmRow = null
                    if (row) root.activate(row)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

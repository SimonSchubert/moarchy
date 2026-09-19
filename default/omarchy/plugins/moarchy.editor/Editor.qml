// Text Editor, in the shell: one file at a time, and the files you opened.
//
// Two screens. **The list** is the files this has opened, newest first, and a
// plus for a new one. **The file** is the text in a box, with undo and save in
// the bar above it, because the phone's keyboard has no Ctrl key to reach
// either with.
//
// It is also the phone's $EDITOR, which is the part that is not obvious from
// the screen. `moarchy-editor --wait FILE` summons this with a marker path in
// the payload, and stays running until the marker exists; this touches it when
// that file is closed, replaced, or the window goes away. That is what lets
// `git commit` read the message back after the window, and not before.
//
// Nothing here reads a file until it has been asked what the file is: the
// shell is the phone's UI, FileView reads a file whole into the shell's own
// process, and a mistaken tap on a 400 MB log is refused by one `stat` rather
// than found out by the phone.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Doc.js" as Doc
import "Store.js" as Store

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "moarchy.editor"
  readonly property bool opened: editorWindow.visible
  readonly property var appWindow: editorWindow

  property string returnTo: ""
  readonly property var colours: themeFile.colours
  property int bodySize: Metrics.BODY

  Component.onCompleted: root.bodySize = Metrics.shellBody(root)

  // MOARCHY_EDITOR_HOME is the harness's: it lets a screenshot of a fixture
  // read ~/Documents rather than a temporary directory's full path.
  readonly property string home: Quickshell.env("MOARCHY_EDITOR_HOME")
                                 || Quickshell.env("HOME") || ""
  readonly property string dataDir: Plugin.dataDir(
    "editor", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_EDITOR_DIR"))

  readonly property color background: root.colours.background
  readonly property color ink: root.colours.foreground
  readonly property color dim: root.colours.dim
  readonly property color accent: root.colours.accent
  readonly property color danger: (root.colours.hues && root.colours.hues.red) || "#e01b24"
  readonly property color warning: (root.colours.hues && root.colours.hues.yellow) || "#e5a50a"

  // --- what is kept ---------------------------------------------------------

  // Nothing is written back until the file has been read, so a save that
  // races the first read cannot replace the list with an empty one.
  property bool stateReady: false
  property var recent: []
  property bool wrap: true
  // Seconds, set as the window opens, so "2 h ago" is not a binding on a clock.
  property real now: Date.now() / 1000

  // "list" | "file"
  property string page: "list"

  // --- the open file --------------------------------------------------------

  // "" for a file with no name yet.
  property string docPath: ""
  property string docEndings: "lf"
  // Doc.problem()'s kind, when this file cannot be written back exactly.
  property string docProblem: ""
  property bool docWritable: true
  // Not on disk yet: a new file, or a path somebody named that is not there.
  property bool docNew: false
  property bool docLoading: false
  property bool dirty: false
  property int revision: 0
  property bool settingText: false

  property bool saving: false
  property string savingPath: ""
  property int savingRevision: 0
  property var afterSave: null

  // moarchy-editor --wait's marker for this file, and whether closing the file
  // should close the window with it -- which is what a caller that summoned the
  // editor for one file wants back.
  property string waitMarker: ""
  property bool leaveOnClose: false

  // --- what is on top of it -------------------------------------------------

  // "" | "unsaved" | "saveas"
  property string dialog: ""
  // What the unsaved question is standing in the way of.
  property var pending: null
  property var afterSaveAs: null
  // The path a Save As has already warned it would replace.
  property string replaceArmed: ""
  property bool menuOpen: false

  readonly property bool readOnly: root.docProblem.length > 0
                                   || (root.docPath.length > 0 && !root.docWritable && !root.docNew)

  readonly property string docTitle: root.docPath.length ? Doc.basename(root.docPath) : "Untitled"

  readonly property string docState: {
    if (root.docLoading) return "Opening…"
    if (root.saving) return "Saving…"
    if (root.readOnly) return "Read only"
    if (root.dirty) return "Not saved"
    if (root.waitMarker.length) return "Go back when you are done"
    if (root.docNew) return root.docPath.length ? "New file" : "Not saved yet"
    return Doc.tilde(Doc.dirname(root.docPath), root.home)
  }

  function say(text) { toast.show(text) }

  // --- the host -------------------------------------------------------------

  function open(payloadJson) {
    Plugin.hideOverlays(root.shell)
    var ask = Doc.parsePayload(payloadJson)
    root.returnTo = ask.returnTo
    root.now = Date.now() / 1000
    editorWindow.show()
    if (ask.path.length) {
      root.request({ kind: "open", path: ask.path, wait: ask.wait })
      return
    }
    // Nothing to wait on is still an answer the caller is waiting for.
    root.touchMarker(ask.wait)
    if (ask.refused) root.say("That path is not one this can open. It needs to start with /.")
  }

  function close() {
    root.menuOpen = false
    root.cancelDialog()
  }

  function dismiss() {
    root.close()
    editorWindow.hide()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    var back = root.returnTo
    root.returnTo = ""
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, "{}")
  }

  function back() {
    if (root.menuOpen) { root.menuOpen = false; return }
    if (root.dialog.length) { root.cancelDialog(); return }
    if (root.page === "file") { root.request({ kind: "close" }); return }
    root.dismiss()
  }

  // `omarchy-shell shell call moarchy.editor waiting <marker>` -- how
  // moarchy-editor finds out that a shell which restarted has forgotten it,
  // rather than waiting for a marker nobody is going to touch.
  function waiting(marker) {
    var m = String(marker || "")
    if (!m.length) return "no"
    if (m === root.waitMarker) return "yes"
    if (root.pending && root.pending.wait === m) return "yes"
    if (root.afterSaveAs && root.afterSaveAs.wait === m) return "yes"
    return "no"
  }

  function saveState() {
    if (!root.stateReady) return
    stateFile.setText(Store.serialize({ recent: root.recent, wrap: root.wrap }))
  }

  // --- what the markers are for ---------------------------------------------

  function touchMarker(marker) {
    if (Doc.markerOk(marker)) Quickshell.execDetached(["touch", "--", String(marker)])
  }

  function attachWait(marker) {
    var m = Doc.markerOk(marker) ? String(marker) : ""
    if (root.waitMarker.length && root.waitMarker !== m) root.touchMarker(root.waitMarker)
    root.waitMarker = m
    if (m.length) root.leaveOnClose = true
  }

  function releaseWait() {
    root.touchMarker(root.waitMarker)
    root.waitMarker = ""
  }

  // --- one place that can drop the open file --------------------------------

  // Opening another file, starting a new one and closing this one all come
  // through here, so edits that are not saved are asked about once and in one
  // way, whatever asked for the file to go.
  function request(action) {
    root.menuOpen = false
    if (action.kind === "open" && root.page === "file" && action.path === root.docPath) {
      // The same file again keeps what is typed in it. Only who is waiting
      // for it changes.
      root.attachWait(action.wait)
      return
    }
    if (root.page === "file" && root.dirty) {
      if (root.pending) root.touchMarker(root.pending.wait)
      root.pending = action
      root.dialog = "unsaved"
      return
    }
    root.perform(action)
  }

  function perform(action) {
    root.pending = null
    root.dialog = ""
    if (!action) return
    if (action.kind === "close") { root.closeFile(false); return }
    root.closeFile(true)
    if (action.kind === "new") root.startNew()
    else if (action.kind === "open") root.startOpen(action.path, action.wait || "", !!action.recent)
  }

  function cancelDialog() {
    if (root.pending) root.touchMarker(root.pending.wait)
    if (root.afterSaveAs) root.touchMarker(root.afterSaveAs.wait)
    root.pending = null
    root.afterSaveAs = null
    root.replaceArmed = ""
    root.dialog = ""
  }

  function closeFile(replacing) {
    var leave = root.leaveOnClose && !replacing && root.page === "file"
    root.releaseWait()
    root.leaveOnClose = false
    root.page = "list"
    root.docPath = ""
    root.docProblem = ""
    root.docEndings = "lf"
    root.docWritable = true
    root.docNew = false
    root.docLoading = false
    root.readPath = ""
    root.setText("")
    root.now = Date.now() / 1000
    if (leave) root.dismiss()
  }

  function startNew() {
    root.page = "file"
    root.docNew = true
    root.setText("")
    Qt.callLater(root.focusText)
  }

  function startOpen(path, wait, fromList) {
    root.page = "file"
    root.docPath = path
    root.docLoading = true
    root.openedFromList = fromList
    root.attachWait(wait)
    root.setText("")
    root.probe("open", path)
  }

  // Loading or not, and whatever it says: the undo history is the file's, so a
  // new file starts with none.
  function setText(text) {
    root.settingText = true
    edit.text = text
    root.settingText = false
    edit.cursorPosition = 0
    flick.contentY = 0
    flick.contentX = 0
    root.dirty = false
    root.revision = 0
  }

  function focusText() {
    if (root.page === "file" && !root.readOnly) edit.forceActiveFocus()
  }

  // --- asking before reading --------------------------------------------------

  property bool openedFromList: false
  property string readPath: ""
  property var queuedProbe: null

  function probe(job, path) {
    if (prober.running) { root.queuedProbe = { job: job, path: path }; return }
    prober.job = job
    prober.target = path
    prober.command = Doc.probeCommand(path)
    prober.running = true
  }

  function probed(job, path, code, out) {
    var p = code === 0 ? Doc.parseProbe(out) : null
    if (job === "open") root.probedOpen(path, p)
    else if (job === "saveas") root.probedSaveAs(path, p)
  }

  function probedOpen(path, p) {
    if (root.page !== "file" || root.docPath !== path || !root.docLoading) return
    if (p && p.kind === "missing" && root.openedFromList) {
      root.recent = Store.forget(root.recent, path)
      root.saveState()
      root.failOpen("That file is not there any more.")
      return
    }
    var trouble = Doc.probeTrouble(p)
    if (trouble.length) { root.failOpen(trouble); return }

    root.recent = Store.touch(root.recent, path, Date.now() / 1000)
    root.saveState()

    if (p.kind === "missing") {
      root.docNew = true
      root.docWritable = true
      root.docLoading = false
      root.afterLoad()
      Qt.callLater(root.focusText)
      return
    }
    root.docWritable = p.writable
    root.readPath = path
  }

  function failOpen(message) {
    root.say(message)
    root.closeFile(true)
  }

  function loadedText(path, text) {
    if (root.page !== "file" || root.docPath !== path || !root.docLoading) return
    var held = Doc.forEditing(text)
    root.docEndings = held.endings
    root.docProblem = held.problem
    root.setText(held.text)
    root.docLoading = false
    // The reader lets go of its copy. The file is in the TextEdit now, and a
    // second copy of it in the shell's memory is nobody's.
    Qt.callLater(function () { root.readPath = "" })
    root.afterLoad()
  }

  function loadFailed(path, code) {
    if (root.page !== "file" || root.docPath !== path || !root.docLoading) return
    root.readPath = ""
    root.failOpen(Doc.loadTrouble(code))
  }

  // --- writing ----------------------------------------------------------------

  function save(then) {
    root.menuOpen = false
    if (root.page !== "file" || root.docLoading || root.saving) { root.drop(then); return }
    if (root.docProblem.length) {
      root.say(Doc.problemText(root.docProblem))
      root.drop(then)
      return
    }
    if (!root.docPath.length) { root.askSaveAs(then); return }
    if (root.readOnly) {
      root.say("You do not have permission to change this file. Save a copy somewhere else.")
      root.askSaveAs(then)
      return
    }
    root.write(root.docPath, then)
  }

  function write(path, then) {
    root.saving = true
    root.savingPath = path
    root.savingRevision = root.revision
    root.afterSave = then || null
    writer.path = path
    writer.setText(Doc.forDisk(edit.text, root.docEndings))
  }

  function wrote() {
    if (!root.saving) return
    root.saving = false
    var path = root.savingPath
    root.docPath = path
    root.docNew = false
    root.docWritable = true
    root.dirty = root.revision !== root.savingRevision
    root.recent = Store.touch(root.recent, path, Date.now() / 1000)
    root.saveState()
    var then = root.afterSave
    root.afterSave = null
    root.say("Saved")
    if (then) root.perform(then)
  }

  function writeFailed(code) {
    if (!root.saving) return
    root.saving = false
    root.drop(root.afterSave)
    root.afterSave = null
    root.say(Doc.saveTrouble(code))
  }

  // An action that is not going to happen after all. Whoever was waiting on it
  // is told, rather than left to find out from a poll twenty seconds later.
  function drop(action) {
    if (action) root.touchMarker(action.wait)
  }

  function askSaveAs(then) {
    root.menuOpen = false
    if (root.docProblem.length) {
      root.say(Doc.problemText(root.docProblem))
      root.drop(then)
      return
    }
    root.afterSaveAs = then || null
    // Documents for a new file, because that is where Files opens a person's
    // own things; the folder is made on save if it is not there, which
    // FileView does by itself.
    var start = root.docPath.length && !root.readOnly
                ? root.docPath
                : root.home + "/Documents/" + (root.docPath.length ? Doc.basename(root.docPath) : "Untitled.txt")
    nameField.text = Doc.tilde(start, root.home)
    root.replaceArmed = ""
    root.dialog = "saveas"
    Qt.callLater(nameField.focusInput)
  }

  function confirmSaveAs() {
    var trouble = Doc.saveAsProblem(nameField.text, root.home)
    if (trouble.length) { root.say(trouble); return }
    root.probe("saveas", Doc.expand(nameField.text, root.home))
  }

  function probedSaveAs(path, p) {
    if (root.dialog !== "saveas") return
    // Typed on since the question was asked: that answer is about another path.
    if (Doc.expand(nameField.text, root.home) !== path) return
    var trouble = ""
    if (!p || p.kind === "") trouble = "That path cannot be saved to."
    else if (p.kind === "dir") trouble = "That is a folder. Add a file name."
    else if (p.kind === "unreadable" || p.kind === "other") trouble = "Something that is not yours to replace is already there."
    else if (p.kind === "missing" && !p.writable) trouble = "That folder is not yours to write in."
    else if (p.kind === "file" && !p.writable) trouble = "You do not have permission to change that file."
    if (trouble.length) { root.say(trouble); return }

    if (p.kind === "file" && path !== root.docPath && root.replaceArmed !== path) {
      root.replaceArmed = path
      root.say("There is already a " + Doc.basename(path) + " there. Save again to replace it.")
      return
    }
    var then = root.afterSaveAs
    root.afterSaveAs = null
    root.replaceArmed = ""
    root.dialog = ""
    root.write(path, then)
  }

  function copyAll() {
    root.menuOpen = false
    if (!edit.length) { root.say("There is nothing in this file to copy."); return }
    var at = edit.cursorPosition
    edit.selectAll()
    edit.copy()
    edit.deselect()
    edit.cursorPosition = at
    root.say("Copied")
  }

  function pasteHere() {
    root.menuOpen = false
    if (!edit.canPaste) { root.say("There is nothing to paste."); return }
    edit.paste()
    Qt.callLater(root.focusText)
  }

  function setWrap(on) {
    root.wrap = on
    root.menuOpen = false
    root.saveState()
  }

  // --- the harness ------------------------------------------------------------

  // The variables plugins/moarchy.editor/shots.sh sets. Each is a screen a
  // thumb can already reach; naming them is what lets a screenshot run reach
  // it without one.
  property bool harnessed: false
  property bool loadHarnessed: false

  function applyHarness() {
    if (root.harnessed) return
    root.harnessed = true
    var want = Quickshell.env("MOARCHY_EDITOR_OPEN") || ""
    if (want === "new") {
      root.request({ kind: "new" })
      root.afterLoad()
      return
    }
    if (want === "recent" && root.recent.length) want = root.recent[0].path
    else if (/^recent:\d+$/.test(want)) {
      var i = parseInt(want.slice(7), 10)
      want = i < root.recent.length ? root.recent[i].path : ""
    }
    if (want.charAt(0) === "/") root.request({ kind: "open", path: want, recent: true })
  }

  function afterLoad() {
    if (root.loadHarnessed) return
    root.loadHarnessed = true
    var typed = Quickshell.env("MOARCHY_EDITOR_TYPE") || ""
    if (typed.length) edit.insert(edit.length, typed)
    if ((Quickshell.env("MOARCHY_EDITOR_MENU") || "").length) root.menuOpen = true
    var dialog = Quickshell.env("MOARCHY_EDITOR_DIALOG") || ""
    if (dialog === "unsaved") root.request({ kind: "close" })
    else if (dialog === "saveas") root.askSaveAs(null)
  }

  // --- the parts that are not on screen ---------------------------------------

  Process {
    id: prober
    property string job: ""
    property string target: ""
    running: false
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    // `exited` carries a QProcess::ExitStatus, which is not in the type
    // information Quickshell ships, so the linter cannot resolve a parameter
    // this handler does not read.
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) {
      root.probed(prober.job, prober.target, code, probeOut.text)
      var next = root.queuedProbe
      root.queuedProbe = null
      if (next) Qt.callLater(function () { root.probe(next.job, next.path) })
    }
    // qmllint enable signal-handler-parameters
  }

  FileView {
    id: reader
    path: root.readPath
    printErrors: false
    onLoaded: root.loadedText(reader.path, reader.text())
    onLoadFailed: function (error) { root.loadFailed(reader.path, error) }
  }

  // A second FileView, so that saving never reads: `preload: false` is what
  // stops pointing it at a path from loading that path first. It writes
  // atomically, through a symlink to its target, keeps the file's mode, and
  // creates missing folders -- each measured against the phone's Quickshell
  // before this relied on it.
  FileView {
    id: writer
    preload: false
    printErrors: false
    onSaved: root.wrote()
    onSaveFailed: function (error) { root.writeFailed(error) }
  }

  Chrome.JsonFile {
    id: stateFile
    path: root.dataDir + "/state.json"
    watchChanges: false
    // Read once, as the shell starts: it is one small file, and a second read
    // on every open would race the write an open makes.
    onParsed: function (data) {
      var s = Store.parse(data)
      root.recent = s.recent
      root.wrap = s.wrap
      root.stateReady = true
      Qt.callLater(root.applyHarness)
    }
    onQuarantined: function (to) {
      root.say("The list of files was unreadable and was kept aside.")
    }
  }

  Chrome.ThemeFile { id: themeFile }
  // Show only. Down is the back swipe's, and nothing here asks for it.
  Chrome.Osk { id: osk }

  IpcHandler {
    target: "editor"

    function state(): string { return root.opened ? "open" : "closed" }
    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      else root.open("{}")
      return "ok"
    }
    function close(): string { root.dismiss(); return "ok" }
    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }
    // A path, the way a script would hand one over. Waiting is moarchy-editor's.
    function openFile(path: string): string {
      var p = Doc.pathFrom(path)
      if (!p.length) return "not an absolute path: " + path
      var payload = JSON.stringify({ path: p })
      if (root.shell) root.shell.summon(root.pluginId, payload)
      else root.open(payload)
      return "ok"
    }
    function file(): string { return root.page === "file" ? (root.docPath || "untitled") : "" }
  }

  // --- the window --------------------------------------------------------------

  Chrome.AppWindow {
    id: editorWindow
    shell: root.shell
    appName: "Text Editor"
    pageTitle: root.page === "file" ? root.docTitle : ""
    pluginId: root.pluginId
    color: root.background

    onMapped: root.now = Date.now() / 1000

    onUnmapped: {
      // A window that has gone is a file somebody has stopped looking at, and
      // whatever is waiting on it gets the file as it is on disk. What is typed
      // and not saved stays here, and is here the next time the window is.
      root.releaseWait()
      root.leaveOnClose = false
      root.menuOpen = false
      root.cancelDialog()
      // The keyboard is left where it is. moarchy's gestures.md G14: nothing
      // puts it down but the back swipe, and switching apps leaves it alone.
    }

    Rectangle {
      anchors.fill: parent
      color: root.background
      focus: true

      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true }
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 12

          Chrome.AppBar {
            anchors.fill: parent
            visible: root.page === "list"
            title: "Text Editor"
            subtitle: root.recent.length
                      ? root.recent.length + (root.recent.length === 1 ? " file" : " files")
                      : ""
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize
          }

          Chrome.AppBar {
            anchors.fill: parent
            visible: root.page === "file"
            title: root.docTitle
            subtitle: root.docState
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize

            leading: Chrome.BackButton {
              colours: root.colours
              color: root.ink
              onClicked: root.back()
            }

            trailing: [
              Chrome.IconButton {
                colours: root.colours
                visible: !root.readOnly
                names: ["edit-undo-symbolic"]
                color: root.ink
                // Faded as a whole rather than in a paler ink: the glyph is
                // tinted by a shader, and a translucent tint came out the full
                // ink on a light theme.
                opacity: edit.canUndo ? 1 : 0.35
                tooltip: "Undo"
                onClicked: if (edit.canUndo) edit.undo()
              },
              Chrome.IconButton {
                colours: root.colours
                visible: !root.readOnly
                names: ["document-save-symbolic"]
                // The accent while there is something to save, so the key says
                // whether pressing it would do anything.
                color: root.dirty || root.docNew ? root.accent : root.ink
                tooltip: "Save"
                onClicked: root.save(null)
              },
              Chrome.IconButton {
                colours: root.colours
                names: ["view-more-symbolic", "open-menu-symbolic"]
                color: root.ink
                tooltip: "More"
                onClicked: root.menuOpen = !root.menuOpen
              }
            ]
          }
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          // ========== the list ==========

          Flickable {
            id: listFlick
            anchors.fill: parent
            visible: root.page === "list"
            contentWidth: width
            contentHeight: listColumn.implicitHeight + Metrics.GAP + 88
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: listColumn
              x: Metrics.GUTTER
              y: Metrics.GAP / 2
              width: listFlick.width - Metrics.GUTTER * 2
              spacing: Metrics.GAP

              Chrome.EmptyState {
                Layout.fillWidth: true
                Layout.topMargin: 40
                visible: root.recent.length === 0
                colours: root.colours
                bodySize: root.bodySize
                names: ["text-x-generic-symbolic", "document-new-symbolic"]
                title: "No files yet"
                detail: "Tap + for a new file, or tap a text file in Files."
              }

              Chrome.Section {
                id: recentSection
                Layout.fillWidth: true
                visible: root.recent.length > 0
                colours: root.colours
                bodySize: root.bodySize
                title: "Recent"
                pad: Metrics.GROUP_PAD
                radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
                cardSpacing: 0

                Repeater {
                  model: root.recent

                  delegate: Chrome.ListRow {
                    id: row
                    required property var modelData
                    Layout.fillWidth: true
                    radius: recentSection.innerRadius
                    minHeight: Metrics.TARGET + 10
                    colours: root.colours
                    bodySize: root.bodySize
                    title: Doc.basename(row.modelData.path)
                    subtitle: {
                      var where = Doc.tilde(Doc.dirname(row.modelData.path), root.home)
                      var when = Doc.ago(row.modelData.opened, root.now)
                      return when.length ? where + " · " + when : where
                    }
                    onClicked: root.request({ kind: "open", path: row.modelData.path, recent: true })

                    leading: Chrome.Icon {
                      slot: 28
                      size: Metrics.ICON_INK
                      color: root.dim
                      names: ["text-x-generic-symbolic"]
                    }

                    // Off the list, not off the disk. Deleting a file is Files'
                    // job, and a cross beside a file that deleted it would be a
                    // trap.
                    trailing: Chrome.IconButton {
                      colours: root.colours
                      slot: 36
                      size: 16
                      names: ["window-close-symbolic"]
                      color: root.dim
                      tooltip: "Remove from this list"
                      onClicked: {
                        root.recent = Store.forget(root.recent, row.modelData.path)
                        root.saveState()
                      }
                    }
                  }
                }
              }
            }
          }

          // ========== the file ==========

          ColumnLayout {
            anchors.fill: parent
            visible: root.page === "file"
            spacing: Metrics.GAP

            // Why this file will not be written, said once and in a box, above
            // the text rather than in a toast that has gone by the time
            // somebody wonders why Save is not there.
            Chrome.Card {
              Layout.fillWidth: true
              Layout.leftMargin: Metrics.GUTTER
              Layout.rightMargin: Metrics.GUTTER
              visible: root.docProblem.length > 0
              colours: root.colours
              tint: root.warning

              RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Chrome.Icon {
                  Layout.alignment: Qt.AlignTop
                  slot: 22
                  size: Metrics.ICON_INK
                  color: root.warning
                  names: ["dialog-warning-symbolic"]
                }

                Chrome.TypedText {
                  Layout.fillWidth: true
                  role: "caption"
                  text: Doc.problemText(root.docProblem)
                  color: root.ink
                  bodySize: root.bodySize
                  wrapMode: Text.WordWrap
                }
              }
            }

            Rectangle {
              id: paper
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.leftMargin: Metrics.GUTTER
              Layout.rightMargin: Metrics.GUTTER
              Layout.bottomMargin: Metrics.GUTTER
              radius: Metrics.radius(root.colours, Metrics.CARD_RADIUS)
              color: Theme.surface(root.colours, "card")

              Flickable {
                id: flick
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: root.wrap ? width : Math.max(width, edit.width + Metrics.PAD * 2)
                contentHeight: Math.max(height, edit.height + Metrics.PAD * 2)

                // Keeps the caret on screen as it moves -- and as the screen
                // moves, because the keyboard coming up takes half of it.
                function ensureVisible(r) {
                  var top = r.y + edit.y - Metrics.PAD
                  var bottom = r.y + r.height + edit.y + Metrics.PAD
                  if (flick.contentY > top) flick.contentY = Math.max(0, top)
                  else if (flick.contentY + flick.height < bottom)
                    flick.contentY = bottom - flick.height
                  if (root.wrap) return
                  var left = r.x + edit.x - Metrics.PAD
                  var right = r.x + r.width + edit.x + Metrics.PAD
                  if (flick.contentX > left) flick.contentX = Math.max(0, left)
                  else if (flick.contentX + flick.width < right)
                    flick.contentX = right - flick.width
                }

                onHeightChanged: if (edit.activeFocus) Qt.callLater(function () {
                  flick.ensureVisible(edit.cursorRectangle)
                })

                TextEdit {
                  id: edit
                  objectName: "text"
                  x: Metrics.PAD
                  y: Metrics.PAD
                  width: root.wrap
                         ? flick.width - Metrics.PAD * 2
                         : Math.max(implicitWidth, flick.width - Metrics.PAD * 2)
                  // At least the box, so a tap anywhere under the last line
                  // puts the caret at the end rather than landing on nothing.
                  height: Math.max(implicitHeight, flick.height - Metrics.PAD * 2)
                  textFormat: TextEdit.PlainText
                  wrapMode: root.wrap ? TextEdit.Wrap : TextEdit.NoWrap
                  // Monospace, because what this is opened on most is a config
                  // file or a commit message, and both are laid out in columns.
                  font.family: "monospace"
                  font.pixelSize: Metrics.typeSize(root.bodySize, "caption")
                  color: root.ink
                  selectionColor: Theme.alpha(root.accent, 0.4)
                  selectedTextColor: root.ink
                  // Dragging scrolls. A drag that selected instead would leave
                  // a 360px screen with no way to move through a long file.
                  selectByMouse: false
                  readOnly: root.readOnly || root.docLoading
                  tabStopDistance: 4 * fontMetrics.advanceWidth(" ")

                  cursorDelegate: Rectangle {
                    width: 2
                    color: root.accent
                    visible: edit.activeFocus && !edit.readOnly
                  }

                  onTextChanged: {
                    if (root.settingText) return
                    root.revision += 1
                    root.dirty = true
                  }
                  onCursorRectangleChanged: if (edit.activeFocus) flick.ensureVisible(edit.cursorRectangle)

                  Keys.onPressed: function (event) {
                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) {
                      root.save(null)
                      event.accepted = true
                    }
                  }

                  // A tap on the text asks for the keyboard. Focus does not:
                  // moarchy-keyboard takes nothing from text-input since
                  // 59acf64 (gestures.md G14), so a field that only takes focus
                  // is typed into with no keyboard. The press goes on to the
                  // TextEdit, which places the caret, and a drag still scrolls.
                  MouseArea {
                    anchors.fill: parent
                    enabled: !edit.readOnly
                    onPressed: function (mouse) {
                      osk.show()
                      mouse.accepted = false
                    }
                  }

                  Chrome.TypedText {
                    visible: edit.length === 0 && !root.docLoading
                    role: "body"
                    text: root.readOnly ? "This file is empty." : "Nothing here yet."
                    color: root.dim
                    bodySize: root.bodySize
                    font.family: "monospace"
                    font.pixelSize: edit.font.pixelSize
                  }
                }

                FontMetrics {
                  id: fontMetrics
                  font: edit.font
                }
              }
            }
          }
        }
      }

      Chrome.Fab {
        colours: root.colours
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 16
        anchors.bottomMargin: 16
        visible: root.page === "list"
        accent: root.accent
        foreground: Theme.inkOn(root.colours, root.accent)
        names: ["document-new-symbolic", "list-add-symbolic"]
        tooltip: "A new file"
        onClicked: root.request({ kind: "new" })
      }

      Chrome.ContextMenu {
        open: root.menuOpen
        colours: root.colours
        background: root.background
        foreground: root.ink
        danger: root.danger
        bodySize: root.bodySize
        onDismissed: root.menuOpen = false

        Chrome.MenuItem {
          colours: root.colours
          visible: !root.readOnly
          names: ["edit-redo-symbolic"]
          text: "Redo"
          foreground: root.ink
          opacity: edit.canRedo ? 1 : 0.4
          bodySize: root.bodySize
          onClicked: { root.menuOpen = false; if (edit.canRedo) edit.redo() }
        }

        // Dragging scrolls, so a selection cannot be made by hand. These are
        // the two a phone needs anyway: a whole file out to a message, and a
        // snippet somebody sent in.
        Chrome.MenuItem {
          colours: root.colours
          names: ["edit-copy-symbolic"]
          text: "Copy all"
          foreground: root.ink
          bodySize: root.bodySize
          onClicked: root.copyAll()
        }

        Chrome.MenuItem {
          colours: root.colours
          visible: !root.readOnly
          names: ["edit-paste-symbolic"]
          text: "Paste"
          foreground: root.ink
          opacity: edit.canPaste ? 1 : 0.4
          bodySize: root.bodySize
          onClicked: root.pasteHere()
        }

        Chrome.MenuItem {
          colours: root.colours
          visible: !root.docProblem.length
          names: ["document-save-as-symbolic"]
          text: "Save as…"
          foreground: root.ink
          bodySize: root.bodySize
          onClicked: root.askSaveAs(null)
        }

        Chrome.MenuItem {
          colours: root.colours
          // A tick as well as a colour: a menu whose only answer to "is this
          // on" is a hue has not answered.
          names: root.wrap ? ["object-select-symbolic"] : ["format-justify-left-symbolic"]
          text: "Wrap long lines"
          foreground: root.wrap ? root.accent : root.ink
          bodySize: root.bodySize
          onClicked: root.setWrap(!root.wrap)
        }

        Chrome.MenuItem {
          colours: root.colours
          names: ["window-close-symbolic"]
          text: "Close file"
          foreground: root.ink
          bodySize: root.bodySize
          onClicked: root.request({ kind: "close" })
        }
      }

      // --- the two questions ---------------------------------------------------

      Item {
        anchors.fill: parent
        visible: root.dialog.length > 0
        z: 120

        Rectangle {
          anchors.fill: parent
          color: Theme.alpha(root.colours.background, 0.55)

          MouseArea {
            anchors.fill: parent
            onClicked: root.cancelDialog()
          }
        }

        Rectangle {
          anchors.centerIn: parent
          width: parent.width - 48
          height: sheetCol.height + 28
          radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
          color: Theme.surface(root.colours, "raised")

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {}
          }

          Column {
            id: sheetCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 12

            Chrome.TypedText {
              width: parent.width
              role: "subtitle"
              text: root.dialog === "saveas" ? "Save as" : "Save " + root.docTitle + "?"
              color: root.ink
              bodySize: root.bodySize
              elide: Text.ElideMiddle
              wrapMode: Text.NoWrap
            }

            Chrome.TypedText {
              width: parent.width
              visible: root.dialog === "unsaved"
              role: "body"
              text: "What you typed since it was last saved is only in this window."
              color: root.dim
              bodySize: root.bodySize
              wrapMode: Text.WordWrap
            }

            Chrome.TextField {
              id: nameField
              visible: root.dialog === "saveas"
              width: parent.width
              colours: root.colours
              level: "pressed"
              bodySize: root.bodySize
              placeholderText: "~/Documents/Notes.txt"
              foreground: root.ink
              accent: root.accent
              iconColor: root.dim
              trailingNames: ["edit-clear-symbolic"]
              trailingClickable: true
              onTrailingClicked: nameField.text = ""
              onAccepted: root.confirmSaveAs()
              onTextChanged: root.replaceArmed = ""
            }

            Row {
              anchors.right: parent.right
              spacing: 8

              Chrome.Button {
                colours: root.colours
                kind: "plain"
                destructive: root.dialog === "unsaved"
                text: root.dialog === "unsaved" ? "Discard" : "Cancel"
                bodySize: root.bodySize
                onClicked: {
                  if (root.dialog === "unsaved") root.perform(root.pending)
                  else root.cancelDialog()
                }
              }

              Chrome.Button {
                colours: root.colours
                kind: "filled"
                text: "Save"
                bodySize: root.bodySize
                onClicked: {
                  if (root.dialog === "saveas") { root.confirmSaveAs(); return }
                  var then = root.pending
                  root.pending = null
                  root.dialog = ""
                  root.save(then)
                }
              }
            }
          }
        }
      }

      Chrome.Toast {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.page === "list" ? 88 : 12 + Metrics.GUTTER
        colours: root.colours
        bodySize: root.bodySize
        z: 130
      }
    }
  }
}

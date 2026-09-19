// Files, in the shell: one directory at a time, with a thumb.
//
// There is no GTK half of this one and there is not going to be. It was
// written for the shell first, which is what an app opened for eleven seconds
// to find one photograph should be -- summoning it is `visible = true` on a
// window that is already up, and the directory somebody was last in is already
// on the screen.
//
// Everything that touches the disk is a short shell script with the paths
// passed in as arguments: Listing.js reads a directory, Ops.js changes one,
// Places.js finds the places worth a tap. None of the decisions are in those
// scripts. Which trash a file goes to, whether a folder may be pasted inside
// itself, and what a usable name is are functions with tests, because those
// are the three ways a file manager loses somebody's afternoon.
//
// Nothing here runs until the window is on the screen. `keepLoaded` means the
// shell builds this Item during its own startup, so a list that lays itself
// out while hidden is not a slow app, it is a phone that did not finish
// booting -- which is why the browse list's model is empty until the window is
// mapped, and why no directory is read before `open()`.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Path.js" as Path
import "Listing.js" as Listing
import "Ops.js" as Ops
import "Places.js" as Places
import "Store.js" as Store

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "moarchy.files"
  readonly property bool opened: filesWindow.visible
  readonly property var appWindow: filesWindow

  property string returnTo: ""
  // `colours` and not `palette`: QQuickItem already has a `palette`, and
  // shadowing it makes a binding resolve to whichever the compiler picked.
  readonly property var colours: themeFile.colours
  property int bodySize: Metrics.BODY

  // The real home is where the trash is and where user-dirs.dirs lives.
  // MOARCHY_FILES_HOME is the harness's: a made-up tree for the screenshots,
  // so the pictures are of a fixture rather than of whatever the machine
  // taking them happens to have in it.
  readonly property string realHome: Quickshell.env("HOME") || "/"
  readonly property string home: Quickshell.env("MOARCHY_FILES_HOME") || root.realHome
  readonly property string xdgData: Quickshell.env("XDG_DATA_HOME") || ""
  readonly property string trashDir: Path.join(
    root.xdgData.length ? Path.clean(root.xdgData)
                        : Path.join(Path.clean(root.realHome), ".local/share"), "Trash")

  readonly property string dataDir: Plugin.dataDir(
    "files", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_FILES_DIR"))

  // --- where we are -----------------------------------------------------

  property string path: ""
  property var entries: []
  property bool listing: false
  property bool relist: false
  property string trouble: ""
  property bool loaded: false

  // "Yesterday" and "Tue" are answers about the clock, so a screenshot taken
  // on a Thursday and one taken on a Friday disagree about a fixture that has
  // not changed. MOARCHY_FILES_NOW pins the clock the list is read against,
  // and demo.py dates the fixture from the same number.
  readonly property double pinnedNow:
    1000 * parseFloat(Quickshell.env("MOARCHY_FILES_NOW") || "0")
  property double now: Date.now()

  property int tab: 0
  property string query: ""
  property bool searching: false

  property string sort: "name"
  property bool hidden: false

  // What is waiting to be pasted: { kind: "copy" | "move", path: "..." }.
  // One thing rather than a selection, because a phone has no shift-click and
  // because a clipboard holding six files is a thing to display, manage and
  // get wrong. Copy, walk somewhere, paste.
  property var holding: null

  // The row menu, the overflow menu and the one panel that asks a question.
  property var menuFor: null
  property bool overflow: false
  // The screenshot harness's, and nothing else reads them: a menu and a
  // half-finished paste are states somebody has to be *in*, and a picture of
  // an app with every menu closed says nothing about what its menus hold.
  // Applied after the first listing, because both name a row that has to exist.
  property string wantMenu: ""
  property string wantHolding: ""
  property string dialog: ""
  property var subject: null

  readonly property color background: colours.background
  readonly property color textOnSurface: colours.foreground
  readonly property color dim: colours.dim
  readonly property color accent: colours.accent
  readonly property color pressed: Theme.mix(colours.foreground, colours.background, 0.08)
  readonly property color raised: Theme.mix(colours.foreground, colours.background, 0.06)

  readonly property var shown: Listing.arrange(root.entries, root.sort, root.hidden, root.query)
  readonly property var crumbs: Path.crumbs(root.path, root.home)
  readonly property var placeRows: Places.rows(root.home, root.userDirs, root.probe, root.trashDir)
  property var userDirs: ({})
  property var probe: null

  readonly property bool inTrash: root.path.length > 0
                                  && Path.isUnder(root.path, Path.join(root.trashDir, "files"))

  function hueColor(name) {
    var hues = root.colours.hues || {}
    return hues[name] || root.accent
  }

  function say(text) { toast.show(text) }

  function title() {
    if (root.tab === 1) return "Places"
    if (!root.path.length) return "Files"
    if (root.path === root.home) return "Home"
    if (Path.isRoot(root.path)) return "Filesystem"
    return Path.base(root.path)
  }

  function subtitle() {
    if (root.tab === 1) return "Where things are"
    if (root.trouble.length) return root.trouble
    if (root.listing && !root.entries.length) return "Reading…"
    if (root.query.length)
      return root.shown.length + (root.shown.length === 1 ? " match" : " matches")
    var line = Listing.summary(root.entries)
    if (root.hidden) line += " · hidden shown"
    return line
  }

  // --- the shell's plugin contract --------------------------------------

  function open(payloadJson) {
    Plugin.hideOverlays(root.shell)
    root.returnTo = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload.returnTo) root.returnTo = String(payload.returnTo)
      if (payload.path) root.path = Path.clean(payload.path)
    } catch (e) {}
    filesWindow.show()
    Qt.callLater(root.ensureLoaded)
  }

  function close() {
    root.menuFor = null
    root.overflow = false
    root.dialog = ""
  }

  function dismiss() {
    root.close()
    root.saveView()
    filesWindow.hide()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
    var back = root.returnTo
    root.returnTo = ""
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, "{}")
  }

  // The first directory is read here and nowhere earlier. MOARCHY_FILES_PATH
  // beats the remembered folder, which beats home -- the harness, then the
  // person, then the only answer that is always right.
  function ensureLoaded() {
    if (root.loaded) return
    root.loaded = true
    ensureDir.running = true
    var forced = Quickshell.env("MOARCHY_FILES_PATH") || ""
    if (forced.length) root.go(forced)
    else if (root.path.length) root.list()
    else root.go(root.home)
  }

  // --- walking ----------------------------------------------------------

  function go(target) {
    var next = Path.clean(target)
    root.query = ""
    root.searching = false
    root.trouble = ""
    root.tab = 0
    if (next !== root.path) {
      root.path = next
      root.entries = []
      browse.positionViewAtBeginning()
    }
    root.list()
  }

  function up() {
    if (Path.isRoot(root.path)) return
    root.go(Path.parent(root.path))
  }

  function list() {
    if (!root.loaded) return
    // A tap that arrives while a directory is still being read is not dropped:
    // it is remembered and run once the current read is back. Dropping it is
    // how a second tap on a folder appears to do nothing on a slow card.
    if (lister.running) { root.relist = true; return }
    root.listing = true
    root.now = root.pinnedNow > 0 ? root.pinnedNow : Date.now()
    lister.command = Listing.command(root.path)
    lister.running = true
  }

  function listed(code, blob) {
    root.listing = false
    if (root.relist) { root.relist = false; Qt.callLater(root.list); return }

    if (code === Listing.OK) {
      root.trouble = ""
      root.entries = Listing.parse(blob)
      root.staged()
      return
    }

    root.entries = []
    root.trouble = Listing.trouble(code)
    // A folder that is gone is the ordinary case after a phone has been away
    // for a week with a card pulled out of it, and the only useful answer is
    // to be somewhere. A folder that is merely not ours to read is left on
    // screen with its reason on it, because the way out of it is the crumb
    // strip that is still showing where it was.
    if (code !== Listing.UNREADABLE && root.path !== root.home) {
      root.say(root.trouble)
      root.go(root.home)
    }
  }

  // The harness's states, once the directory they refer to is on screen.
  function staged() {
    if (root.wantMenu.length) {
      var menu = root.wantMenu
      root.wantMenu = ""
      if (menu === "view") root.overflow = true
      else root.menuFor = root.find(menu)
    }
    if (root.wantHolding.length) {
      var held = root.find(root.wantHolding)
      root.wantHolding = ""
      if (held) root.holding = { kind: "copy", name: held.name,
                                 path: Path.join(root.path, held.name) }
    }
  }

  function find(name) {
    for (var i = 0; i < root.entries.length; i++)
      if (root.entries[i].name === name) return root.entries[i]
    return null
  }

  function enter(entry) {
    var target = Path.join(root.path, entry.name)
    if (entry.broken) {
      root.say("That link points at something that is not there.")
      return
    }
    if (entry.folder) { root.go(target); return }
    if (opener.running) return
    root.say("Opening " + entry.name + "…")
    opener.command = Ops.openCommand(target)
    opener.running = true
  }

  // --- changing something ------------------------------------------------

  function run(job, what, command) {
    worker.job = job
    worker.subject = what
    worker.command = command
    worker.running = true
  }

  function busyText() {
    if (!worker.running) return ""
    if (worker.job === "place")
      return worker.subject && worker.subject.kind === "move" ? "Moving…" : "Copying…"
    if (worker.job === "trash-tops" || worker.job === "trash-move") return "Deleting…"
    if (worker.job === "purge") return "Deleting…"
    return "Working…"
  }

  function hold(kind, entry) {
    root.holding = { kind: kind, path: Path.join(root.path, entry.name), name: entry.name }
    root.say(kind === "move" ? "Ready to move. Open a folder and tap Paste."
                             : "Ready to copy. Open a folder and tap Paste.")
  }

  function paste() {
    if (!root.holding || worker.running) return
    var problem = Ops.pasteProblem(root.holding.kind, root.holding.path, root.path)
    if (problem.length) { root.say(problem); return }
    root.run("place", { kind: root.holding.kind, name: root.holding.name },
             Ops.place(root.holding.kind, root.holding.path, root.path))
  }

  // Delete, which on this app means the trash -- except inside the trash,
  // where it means gone and is the one thing here that asks first.
  function remove(entry) {
    if (worker.running) return
    var target = Path.join(root.path, entry.name)
    var trashed = Ops.trashedName(target, root.trashDir)
    if (trashed.length) {
      root.subject = { path: target, name: entry.name, trashed: trashed }
      root.dialog = "purge"
      return
    }
    var problem = Ops.trashProblem(target, root.home)
    if (problem.length) { root.say(problem); return }
    root.run("trash-tops", { path: target, name: entry.name },
             Ops.tops(target, root.realHome))
  }

  function finished(code, text) {
    var job = worker.job
    var what = worker.subject
    worker.job = ""

    if (job === "trash-tops") {
      var plan = Ops.trashPlan(what.path, root.realHome, root.xdgData, Ops.parseTops(text))
      if (code !== 0 || plan.problem) {
        root.say(plan.problem || "Could not work out which volume that is on.")
        return
      }
      // Qt.callLater rather than starting it from inside this handler: the
      // process that just exited is the process being asked to run again.
      Qt.callLater(function () {
        root.run("trash-move", what, Ops.trashCommand(plan.dir, what.path, plan.line))
      })
      return
    }

    if (job === "trash-move") {
      if (code !== 0) root.say(Ops.trashTrouble(code))
      else root.say("Moved " + what.name + " to the trash.")
      root.list()
      return
    }

    if (job === "purge") {
      if (code !== 0) root.say("That could not be deleted.")
      else root.say("Deleted " + what.name + ".")
      root.list()
      return
    }

    if (job === "place") {
      if (code !== 0) { root.say(Ops.why(code, "That")); return }
      root.say((what.kind === "move" ? "Moved " : "Copied ") + what.name + " here.")
      root.holding = null
      root.list()
      return
    }

    if (job === "mkdir") {
      if (code !== 0) { root.say(Ops.why(code, "The folder")); return }
      root.list()
      return
    }

    if (job === "rename") {
      if (code !== 0) { root.say(Ops.why(code, "The rename")); return }
      root.list()
      return
    }
  }

  function askNewFolder() {
    root.overflow = false
    root.subject = null
    root.dialog = "folder"
    nameField.text = ""
    Qt.callLater(nameField.focusInput)
  }

  function askRename(entry) {
    root.subject = { path: Path.join(root.path, entry.name), name: entry.name }
    root.dialog = "rename"
    nameField.text = entry.name
    Qt.callLater(nameField.focusInput)
  }

  function confirm() {
    var kind = root.dialog
    var what = root.subject
    if (kind === "purge") {
      root.dialog = ""
      root.run("purge", what, Ops.purge(what.path, root.trashDir, what.trashed))
      return
    }

    var name = nameField.text
    var problem = Ops.nameProblem(name)
    if (problem.length) { root.say(problem); return }
    root.dialog = ""

    if (kind === "folder") {
      root.run("mkdir", { name: name }, Ops.makeDir(root.path, name))
      return
    }
    if (kind === "rename") {
      if (name === what.name) return
      root.run("rename", { name: name }, Ops.rename(root.path, what.name, name))
    }
  }

  // --- the places page ---------------------------------------------------

  function probePlaces() {
    if (prober.running) return
    var paths = Places.candidates(root.home)
    var wanted = Places.wanted(root.home, root.userDirs)
    for (var i = 0; i < wanted.length; i++)
      if (paths.indexOf(wanted[i].path) < 0) paths.push(wanted[i].path)
    prober.command = Places.command(paths)
    prober.running = true
  }

  // --- what is remembered -------------------------------------------------

  function saveView() {
    if (!root.loaded) return
    viewFile.setText(Store.serialize(root.sort, root.hidden, root.path))
  }

  function setSort(which) {
    root.overflow = false
    if (root.sort === which) return
    root.sort = which
    root.saveView()
  }

  function setHidden(on) {
    if (root.hidden === on) return
    root.hidden = on
    root.saveView()
  }

  // The page a screenshot run asked for, held rather than applied: the first
  // listing goes through go(), and go() puts the window back on the Files tab
  // -- which is right when a person taps a folder and wrong when the harness
  // asked for Places before anything had been listed at all.
  property bool wantPlaces: false

  Component.onCompleted: {
    root.bodySize = Metrics.shellBody(root)
    root.wantPlaces = (Quickshell.env("MOARCHY_FILES_PAGE") || "") === "places"
    root.wantMenu = Quickshell.env("MOARCHY_FILES_MENU") || ""
    root.wantHolding = Quickshell.env("MOARCHY_FILES_HOLDING") || ""
  }

  // --- plumbing -----------------------------------------------------------

  Process { id: ensureDir; running: false; command: ["mkdir", "-p", root.dataDir] }

  Process {
    id: lister
    running: false
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    // `exited` carries a QProcess::ExitStatus, which is not in the type
    // information Quickshell ships, so the linter cannot resolve a parameter
    // this handler does not read.
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.listed(code, listOut.text) }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: worker
    property string job: ""
    property var subject: null
    running: false
    stdout: StdioCollector { id: workOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.finished(code, workOut.text) }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: prober
    running: false
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) {
      if (code === 0) root.probe = Places.parseProbe(probeOut.text)
    }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: opener
    running: false
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) {
      if (code !== 0) root.say(Ops.openTrouble(code))
    }
    // qmllint enable signal-handler-parameters
  }

  // Not a fork: the file is read once and then followed, so a phone that gets
  // its language changed offers "Bilder" the next time it is opened without
  // this app being told.
  FileView {
    id: userDirsFile
    path: Path.join(root.home, ".config/user-dirs.dirs")
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.userDirs = Places.parseUserDirs(text(), root.home)
      if (root.tab === 1) root.probePlaces()
    }
    onFileChanged: Qt.callLater(function () { userDirsFile.reload() })
  }

  Chrome.JsonFile {
    id: viewFile
    path: root.dataDir + "/view.json"
    onParsed: function (data) {
      var state = Store.parse(data)
      root.sort = state.sort
      root.hidden = state.hidden
      // The folder is taken only before the app has opened. After that, a
      // change to this file is somebody's editor or a sync, and being carried
      // to another directory mid-scroll is not a feature.
      if (!root.loaded && state.path.length) root.path = state.path
    }
    onQuarantined: function (movedTo) {
      root.say("view.json would not parse; it is at " + Path.base(movedTo) + ".")
    }
  }

  Chrome.ThemeFile { id: themeFile }

  IpcHandler {
    target: "files"
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
    function cd(where: string): string {
      root.go(where)
      return root.path
    }
    function here(): string { return root.path }
    // What the screenshot harness waits for: a directory that has been read
    // and nothing still in flight.
    function settled(): bool {
      return root.loaded && !lister.running && !worker.running
    }
  }

  // --- the window ---------------------------------------------------------

  Chrome.AppWindow {
    id: filesWindow
    shell: root.shell
    appName: "Files"
    pageTitle: root.tab === 1 ? "Places" : Path.pretty(root.path, root.home)
    pluginId: root.pluginId
    color: root.background

    onMapped: {
      root.now = root.pinnedNow > 0 ? root.pinnedNow : Date.now()
      Qt.callLater(root.ensureLoaded)
      if (root.wantPlaces) Qt.callLater(function () {
        root.wantPlaces = false
        root.tab = 1
        root.probePlaces()
      })
      if (root.tab === 1) root.probePlaces()
    }
    // The folder is written down when the window leaves the screen, which on
    // this phone is the event immediately before the app is reclaimed. Not on
    // every step: that would be a write onto flash per tap, for a file whose
    // whole purpose is the next cold start.
    onUnmapped: root.saveView()

    Rectangle {
      anchors.fill: parent
      color: root.background
      focus: true
      Keys.onEscapePressed: {
        if (root.dialog.length) { root.dialog = ""; return }
        if (root.menuFor) { root.menuFor = null; return }
        if (root.overflow) { root.overflow = false; return }
        if (root.searching) { root.searching = false; root.query = ""; return }
        if (root.tab === 1) { root.tab = 0; return }
        if (root.path !== root.home && !Path.isRoot(root.path)) { root.up(); return }
        root.dismiss()
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Chrome.AppBar {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 12
          title: root.title()
          subtitle: root.subtitle()
          foreground: root.textOnSurface
          dim: root.trouble.length ? root.hueColor("red") : root.dim
          bodySize: root.bodySize

          leading: Chrome.IconButton {
            colours: root.colours
            visible: root.tab === 0 && !Path.isRoot(root.path)
            color: root.textOnSurface
            names: ["go-up-symbolic", "go-previous-symbolic", "pan-start-symbolic"]
            tooltip: "Up one folder"
            onClicked: root.up()
          }

          trailing: Row {
            Chrome.IconButton {
              colours: root.colours
              visible: root.tab === 0
              color: root.textOnSurface
              names: ["system-search-symbolic", "edit-find-symbolic"]
              tooltip: "Search this folder"
              onClicked: {
                root.searching = !root.searching
                if (!root.searching) root.query = ""
                else Qt.callLater(searchField.focusInput)
              }
            }
            Chrome.IconButton {
              colours: root.colours
              color: root.textOnSurface
              names: ["view-more-symbolic", "open-menu-symbolic"]
              tooltip: "More"
              onClicked: {
                if (root.tab === 1) { root.probePlaces(); return }
                root.overflow = !root.overflow
              }
            }
          }
        }

        // --- the search field ----------------------------------------------

        Chrome.AppBar {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 8
          visible: root.searching && root.tab === 0
          foreground: root.textOnSurface
          bodySize: root.bodySize

          center: Chrome.TextField {
            id: searchField
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            colours: root.colours
            level: "card"
            bodySize: root.bodySize
            leadingNames: ["system-search-symbolic"]
            trailingNames: ["edit-clear-symbolic"]
            trailingClickable: true
            // Named for what it does, which is not what a desktop search does:
            // this filters the folder that is open. Nothing here walks a tree.
            placeholderText: "Name, in this folder"
            foreground: root.textOnSurface
            accent: root.accent
            iconColor: root.dim
            text: root.query
            onTextChanged: root.query = text
            onTrailingClicked: root.query = ""
          }
        }

        // --- where we are, as one tap per level -----------------------------

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 38
          visible: root.tab === 0 && !root.searching

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: Metrics.GUTTER
            anchors.rightMargin: Metrics.GUTTER
            anchors.bottomMargin: 4
            radius: Metrics.round(root.colours, height)
            color: Theme.surface(root.colours, "card")

            Flickable {
              id: crumbFlick
              anchors.fill: parent
              clip: true
              contentWidth: crumbRow.width
              contentHeight: height
              flickableDirection: Flickable.HorizontalFlick
              boundsBehavior: Flickable.StopAtBounds
              // The strip is 360px wide and the interesting end is the right
              // one, so it sits there whenever the path changes length.
              onContentWidthChanged: crumbFlick.contentX =
                Math.max(0, crumbFlick.contentWidth - crumbFlick.width)

              Row {
                id: crumbRow
                height: crumbFlick.height
                leftPadding: 10
                rightPadding: 10

                Repeater {
                  model: root.crumbs

                  delegate: Row {
                    id: crumb
                    required property var modelData
                    required property int index
                    height: crumbRow.height

                    Chrome.TypedText {
                      anchors.verticalCenter: parent.verticalCenter
                      visible: crumb.index > 0
                      role: "caption"
                      text: " › "
                      color: root.dim
                      bodySize: root.bodySize
                    }

                    Item {
                      height: crumbRow.height
                      width: label.implicitWidth + 12

                      Chrome.TypedText {
                        id: label
                        anchors.centerIn: parent
                        role: "caption"
                        text: crumb.modelData.label
                        // The last crumb is where we are, so it is the one
                        // that is not a link anywhere.
                        color: crumb.index === root.crumbs.length - 1
                               ? root.textOnSurface : root.dim
                        bodySize: root.bodySize
                      }

                      MouseArea {
                        anchors.fill: parent
                        onClicked: root.go(crumb.modelData.path)
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // --- what is waiting to be pasted ------------------------------------

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 60
          visible: !!root.holding && root.tab === 0

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: Metrics.GUTTER
            anchors.rightMargin: Metrics.GUTTER
            anchors.bottomMargin: Metrics.GAP
            radius: Metrics.radius(root.colours, Metrics.CARD_RADIUS)
            color: Theme.surface(root.colours, "card")

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Metrics.PAD
              anchors.rightMargin: 6
              spacing: 8

              Chrome.Icon {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                slot: 22
                size: 16
                color: root.dim
                names: root.holding && root.holding.kind === "move"
                       ? ["edit-cut-symbolic"] : ["edit-copy-symbolic"]
              }

              Chrome.TypedText {
                Layout.fillWidth: true
                role: "caption"
                text: root.holding ? root.holding.name : ""
                color: root.textOnSurface
                bodySize: root.bodySize
                elide: Text.ElideMiddle
                maximumLineCount: 1
              }

              Chrome.Button {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 38
                colours: root.colours
                kind: "filled"
                text: root.busyText().length ? root.busyText() : "Paste here"
                bodySize: root.bodySize
                pad: 14
                onClicked: root.paste()
              }

              Chrome.IconButton {
                colours: root.colours
                Layout.alignment: Qt.AlignVCenter
                slot: 36
                names: ["window-close-symbolic"]
                color: root.dim
                tooltip: "Forget it"
                onClicked: root.holding = null
              }
            }
          }
        }

        // --- the list --------------------------------------------------------

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          Chrome.ListFrame {
            id: browseFrame
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: Metrics.GUTTER
            anchors.rightMargin: Metrics.GUTTER
            // Hugs a folder with three things in it and fills the screen for a
            // camera roll. A frame that always reached the bottom made every
            // small folder look like a list that had failed to load.
            height: Math.min(parent.height - Metrics.GAP,
                             browse.contentHeight + browseFrame.pad * 2)
            visible: root.tab === 0 && root.shown.length > 0
            colours: root.colours

            ListView {
              id: browse
              anchors.fill: parent
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              // Empty until the window is up. A ListView that lays itself out
              // while the shell is still starting is the fault that takes a
              // phone down rather than an app, and there is no cheaper guard
              // than not giving it anything to lay out.
              model: filesWindow.visible ? root.shown : []

              delegate: EntryRow {
                id: entryRow
                required property var modelData
                width: browse.width
                radius: browseFrame.innerRadius
                colours: root.colours
                entry: entryRow.modelData
                note: Listing.note(entryRow.modelData, root.now)
                glyphs: Listing.glyphs(entryRow.modelData)
                foreground: root.textOnSurface
                accent: root.accent
                bodySize: root.bodySize
                onActivated: root.enter(entryRow.modelData)
                onMenuWanted: root.menuFor = entryRow.modelData
              }
            }
          }

          // --- nothing to show ---------------------------------------------

          Chrome.EmptyState {
            anchors.centerIn: parent
            width: parent.width - Metrics.GUTTER * 2
            visible: root.tab === 0 && !root.listing && root.shown.length === 0
            colours: root.colours
            bodySize: root.bodySize
            names: {
              if (root.trouble.length) return ["action-unavailable-symbolic"]
              if (root.query.length) return ["system-search-symbolic"]
              return ["folder-symbolic"]
            }
            title: {
              if (root.trouble.length) return "Nothing to show"
              if (root.query.length) return "No match"
              if (root.entries.length) return "Nothing but hidden files"
              return "This folder is empty"
            }
            detail: {
              if (root.trouble.length) return root.trouble
              if (root.query.length)
                return "Nothing in this folder is called " + root.query + "."
              if (root.entries.length)
                return "There are " + root.entries.length + " hidden files here. "
                     + "Show them from the menu."
              return "Paste something in, or make a folder from the menu."
            }
          }

          // --- places -------------------------------------------------------

          Flickable {
            id: placesFlick
            anchors.fill: parent
            visible: root.tab === 1
            clip: true
            contentWidth: width
            contentHeight: placesCol.implicitHeight + Metrics.GUTTER * 2
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: placesCol
              x: Metrics.GUTTER
              y: 4
              width: placesFlick.width - Metrics.GUTTER * 2
              spacing: 0

              Chrome.Group {
                id: placesGroup
                Layout.fillWidth: true
                colours: root.colours

                Repeater {
                  model: root.placeRows

                  delegate: Chrome.ListRow {
                    id: place
                    required property var modelData
                    Layout.fillWidth: true
                    radius: placesGroup.innerRadius
                    minHeight: place.modelData.volume ? 76 : 60
                    colours: root.colours
                    bodySize: root.bodySize
                    onClicked: root.go(place.modelData.path)

                    leading: Chrome.Icon {
                      anchors.verticalCenter: parent.verticalCenter
                      slot: 28
                      size: 20
                      color: root.accent
                      names: [place.modelData.glyph, "folder-symbolic"]
                    }

                    centre: Column {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      spacing: 3

                      Chrome.TypedText {
                        width: parent.width
                        role: "body"
                        text: place.modelData.label
                        color: root.textOnSurface
                        bodySize: root.bodySize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                      }

                      Chrome.TypedText {
                        width: parent.width
                        visible: !place.modelData.volume
                        role: "caption"
                        text: place.modelData.note
                        color: root.dim
                        bodySize: root.bodySize
                        elide: Text.ElideMiddle
                        maximumLineCount: 1
                      }

                      // How full a volume is, which is the only question
                      // anybody has ever asked about one.
                      Chrome.TypedText {
                        width: parent.width
                        visible: !!place.modelData.volume
                        role: "caption"
                        text: Listing.human(place.modelData.free) + " free of "
                              + Listing.human(place.modelData.total)
                        color: root.dim
                        bodySize: root.bodySize
                      }

                      Rectangle {
                        visible: !!place.modelData.volume
                        width: parent.width
                        height: 5
                        radius: Metrics.round(root.colours, height)
                        color: Theme.surface(root.colours, "raised")

                        Rectangle {
                          id: usedBar
                          readonly property real used: place.modelData.total > 0
                            ? 1 - place.modelData.free / place.modelData.total : 0
                          width: Math.max(parent.height, parent.width * usedBar.used)
                          height: parent.height
                          radius: parent.radius
                          color: usedBar.used >= 0.9 ? root.hueColor("red")
                                 : (usedBar.used >= 0.75 ? root.hueColor("yellow")
                                                         : root.accent)
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // --- a sentence, not a spinner ------------------------------------

          Chrome.Toast {
            id: toast
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            colours: root.colours
            bodySize: root.bodySize
          }
        }

        Chrome.BottomNav {
          id: bottomNav
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.BOTTOM_NAV
          color: root.background
          dim: root.dim
          accent: root.accent
          bodySize: root.bodySize
          currentIndex: root.tab
          onActivated: function (i) {
            root.tab = i
            if (i === 1) root.probePlaces()
          }

          Chrome.BottomNavItem {
            text: "Files"
            names: ["folder-symbolic", "view-list-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }
          Chrome.BottomNavItem {
            text: "Places"
            names: ["user-home-symbolic", "go-home-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }
        }
      }

      // --- what can be done with one row ----------------------------------

      Chrome.ContextMenu {
        open: !!root.menuFor
        placement: "center"
        colours: root.colours
        background: root.background
        foreground: root.textOnSurface
        danger: root.hueColor("red")
        bodySize: root.bodySize
        menuWidth: 248
        onDismissed: root.menuFor = null

        Chrome.TypedText {
          width: parent ? parent.width : 0
          role: "overline"
          text: root.menuFor ? root.menuFor.name : ""
          color: root.dim
          bodySize: root.bodySize
          elide: Text.ElideMiddle
          maximumLineCount: 1
          bottomPadding: 4
        }

        Chrome.MenuItem {
          colours: root.colours
          names: root.menuFor && root.menuFor.folder
                 ? ["folder-symbolic"] : ["document-open-symbolic"]
          text: root.menuFor && root.menuFor.folder ? "Open folder" : "Open"
          foreground: root.textOnSurface
          bodySize: root.bodySize
          onClicked: { var e = root.menuFor; root.menuFor = null; root.enter(e) }
        }

        Chrome.MenuItem {
          colours: root.colours
          names: ["edit-copy-symbolic"]
          text: "Copy"
          foreground: root.textOnSurface
          bodySize: root.bodySize
          onClicked: { var e = root.menuFor; root.menuFor = null; root.hold("copy", e) }
        }

        Chrome.MenuItem {
          colours: root.colours
          names: ["edit-cut-symbolic"]
          text: "Move"
          foreground: root.textOnSurface
          bodySize: root.bodySize
          onClicked: { var e = root.menuFor; root.menuFor = null; root.hold("move", e) }
        }

        Chrome.MenuItem {
          colours: root.colours
          names: ["document-edit-symbolic"]
          text: "Rename"
          foreground: root.textOnSurface
          bodySize: root.bodySize
          onClicked: { var e = root.menuFor; root.menuFor = null; root.askRename(e) }
        }

        Chrome.MenuItem {
          colours: root.colours
          names: root.inTrash ? ["edit-delete-symbolic"] : ["user-trash-symbolic"]
          // The word changes because the act does. Everywhere else this moves
          // a file to the trash and the trash is the undo; in the trash there
          // is nothing under it, so it says so and then asks.
          text: root.inTrash ? "Delete for ever" : "Move to trash"
          destructive: true
          danger: root.hueColor("red")
          bodySize: root.bodySize
          onClicked: { var e = root.menuFor; root.menuFor = null; root.remove(e) }
        }
      }

      // --- the folder's own menu --------------------------------------------

      Chrome.ContextMenu {
        open: root.overflow
        placement: "topEnd"
        colours: root.colours
        background: root.background
        foreground: root.textOnSurface
        bodySize: root.bodySize
        onDismissed: root.overflow = false

        Chrome.MenuItem {
          colours: root.colours
          names: ["folder-new-symbolic"]
          text: "New folder"
          foreground: root.textOnSurface
          bodySize: root.bodySize
          onClicked: root.askNewFolder()
        }

        // A gap groups these three, and the one under them, without a rule
        // across a 248px menu.
        Item {
          width: parent ? parent.width : 0
          height: Metrics.GAP
        }

        Repeater {
          model: [{ key: "name", label: "Name" },
                  { key: "size", label: "Size" },
                  { key: "modified", label: "Modified" }]

          delegate: Chrome.MenuItem {
            colours: root.colours
            id: sortItem
            required property var modelData
            readonly property bool current: root.sort === sortItem.modelData.key
            // A tick as well as a colour: one man in twelve cannot tell this
            // app's accent from its ink, and a menu whose only answer to
            // "which one am I on" is a hue has not answered.
            names: sortItem.current
                   ? ["object-select-symbolic"] : ["view-sort-ascending-symbolic"]
            text: sortItem.modelData.label
            foreground: sortItem.current ? root.accent : root.textOnSurface
            bodySize: root.bodySize
            onClicked: root.setSort(sortItem.modelData.key)
          }
        }

        // A gap groups these three, and the one under them, without a rule
        // across a 248px menu.
        Item {
          width: parent ? parent.width : 0
          height: Metrics.GAP
        }

        Chrome.Check {
          colours: root.colours
          text: "Show hidden files"
          checked: root.hidden
          foreground: root.textOnSurface
          tickColor: root.colours.dark ? root.textOnSurface : root.background
          accent: root.accent
          dim: root.dim
          bodySize: root.bodySize
          onToggled: function (on) { root.setHidden(on) }
        }
      }

      // --- the one panel that asks a question --------------------------------

      Item {
        id: sheet
        anchors.fill: parent
        visible: root.dialog.length > 0
        z: 120

        Rectangle {
          anchors.fill: parent
          color: Theme.alpha(root.colours.background, 0.55)

          MouseArea {
            anchors.fill: parent
            onClicked: root.dialog = ""
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
              text: {
                if (root.dialog === "folder") return "New folder"
                if (root.dialog === "rename") return "Rename"
                return "Delete for ever?"
              }
              color: root.textOnSurface
              bodySize: root.bodySize
            }

            Chrome.TypedText {
              width: parent.width
              visible: root.dialog === "purge"
              role: "body"
              text: root.subject
                    ? "“" + root.subject.name + "” is in the trash. There is "
                      + "nothing under the trash: this cannot be undone."
                    : ""
              color: root.dim
              bodySize: root.bodySize
              wrapMode: Text.WordWrap
            }

            Chrome.TextField {
              id: nameField
              visible: root.dialog === "folder" || root.dialog === "rename"
              width: parent.width
              colours: root.colours
              level: "pressed"
              bodySize: root.bodySize
              placeholderText: "Name"
              foreground: root.textOnSurface
              accent: root.accent
              iconColor: root.dim
              trailingNames: ["edit-clear-symbolic"]
              trailingClickable: true
              onTrailingClicked: nameField.text = ""
              onAccepted: root.confirm()
            }

            Row {
              anchors.right: parent.right
              spacing: 8

              Chrome.Button {
                colours: root.colours
                kind: "plain"
                text: "Cancel"
                bodySize: root.bodySize
                onClicked: root.dialog = ""
              }

              Chrome.Button {
                colours: root.colours
                kind: "filled"
                destructive: root.dialog === "purge"
                text: root.dialog === "purge" ? "Delete" : "Save"
                bodySize: root.bodySize
                onClicked: root.confirm()
              }
            }
          }
        }
      }
    }
  }
}

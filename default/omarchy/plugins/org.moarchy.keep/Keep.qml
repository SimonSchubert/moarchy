// Keep, in the shell: a notes grid that is already loaded.
//
// The GTK app takes ~4s to a window on this phone because it starts Python
// and GTK. This file is an Item the shell already holds, so summoning it is
// `visible = true` on a FloatingWindow. The notes file is the GTK app's
// (`~/.local/share/moarchy-keep/notes.json`), so a note typed in either
// place is the same note. Colours come from the same colors.toml, mixed the
// same way, so a coral card here is a coral card there.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Store.js" as Store
import "Notes.js" as Notes

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
                               || (Quickshell.env("HOME") + "/.local/share/omarchy")
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "org.moarchy.keep"
  readonly property bool opened: keepWindow.visible
  readonly property var appWindow: keepWindow

  property string returnTo: ""
  property var notes: []
  property string view: "grid"
  property string query: ""
  property var editing: null
  property bool menuOpen: false
  property var menuNote: null
  property bool moreOpen: false
  property bool colourOpen: false
  property bool doneOpen: true
  property bool loaded: false
  // `colours` and not `palette`: QQuickItem already has a `palette`, and
  // shadowing it makes a binding resolve to whichever the compiler picked --
  // The property-override warning names it, and it is the one warning here
  // that could silently draw the wrong thing. (A comment must not open with
  // the linter's own name: it reads the rest of the line as a directive.)
  readonly property var colours: themeFile.colours

  // The shell's text size where there is a shell to ask, 16 otherwise. This
  // and Metrics.space are what `Style.font.body` and `Style.space` were before
  // this file came off qs.Commons: the same answers on the phone, and answers
  // at all everywhere else.
  property int bodySize: Metrics.BODY
  Component.onCompleted: {
    root.bodySize = Metrics.shellBody(root)
    root.applyHarness()
  }

  // Same numbers the GTK app paints: the palette is parsed out of colors.toml
  // here rather than taken from the shell, so a coral card matches GTK Keep
  // rather than a Settings row.
  readonly property color background: colours.background
  readonly property color textOnSurface: colours.foreground
  readonly property color dim: colours.dim
  readonly property color accent: colours.accent
  readonly property color subdued: colours.dim
  readonly property color danger: (colours.hues && colours.hues.red) ? colours.hues.red : "#e01b24"
  readonly property color textOnAccent: "#ffffff"
  readonly property int doneCount: {
    if (!root.editing || !root.editing.items) return 0
    var n = 0
    for (var i = 0; i < root.editing.items.length; i++)
      if (root.editing.items[i].done) n++
    return n
  }
  readonly property int radiusCard: 12
  readonly property string noteFont: "Adwaita Sans"

  readonly property string notesDir: Plugin.dataDir(
    "keep", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_KEEP_DIR"))
  readonly property string notesPath: root.notesDir + "/notes.json"

  readonly property var shown: Store.sections(root.notes, root.query)
  readonly property var pinnedCol: Store.splitColumns(root.shown.pinned)
  readonly property var othersCol: Store.splitColumns(root.shown.others)

  function open(payloadJson) {
    Plugin.hideOverlays(root.shell)
    root.returnTo = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload.returnTo) root.returnTo = String(payload.returnTo)
    } catch (e) {}
    keepWindow.show()
    Qt.callLater(root.ensureLoaded)
  }

  function close() {
    root.leaveEditor()
    root.menuOpen = false
    root.moreOpen = false
    root.colourOpen = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
    var back = root.returnTo
    root.returnTo = ""
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, "{}")
  }

  function ensureLoaded() {
    if (root.loaded) return
    ensureDir.running = true
    disk.reload()
  }

  function applyText(text) {
    var parsed = Store.parse(text)
    root.notes = parsed.notes
    root.view = parsed.view
    root.loaded = true
    if (!root.harnessed) { root.harnessed = true; Qt.callLater(root.applyLoadedHarness) }
  }

  // --- the harness ------------------------------------------------------

  // The variables plugins/org.moarchy.keep/shots.sh sets. Everything here is
  // a screen this app can already reach by tapping; naming them is what lets
  // a screenshot run reach the same ones without a robot with a thumb.
  property bool harnessed: false
  property string wantView: ""

  function applyHarness() {
    root.query = Quickshell.env("MOARCHY_KEEP_SEARCH") || ""
    root.wantView = Quickshell.env("MOARCHY_KEEP_VIEW") || ""
  }

  function applyLoadedHarness() {
    if (root.wantView === "list" || root.wantView === "grid") root.view = root.wantView
    var open = Quickshell.env("MOARCHY_KEEP_OPEN") || ""
    var menu = Quickshell.env("MOARCHY_KEEP_MENU") || ""
    var want = open || menu
    if (!want.length) return
    for (var i = 0; i < root.notes.length; i++) {
      if (String(root.notes[i].title).toLowerCase().indexOf(want.toLowerCase()) < 0) continue
      if (menu.length) { root.menuNote = root.notes[i]; root.menuOpen = true }
      else root.openNote(root.notes[i])
      return
    }
  }

  function scheduleSave() {
    saveTimer.restart()
  }

  function saveNow() {
    saveTimer.stop()
    if (!root.loaded) return
    disk.setText(Store.serialize({ notes: root.notes, view: root.view }))
  }

  function replaceNotes(next) {
    root.notes = next
    root.scheduleSave()
  }

  function newNote(kind) {
    var note = Store.create(kind)
    var next = [note]
    for (var i = 0; i < root.notes.length; i++) next.push(root.notes[i])
    root.replaceNotes(next)
    root.openNote(note)
  }

  function openNote(note) {
    root.menuOpen = false
    root.moreOpen = false
    root.colourOpen = false
    root.editing = Store.cloneNote(note)
    root.doneOpen = true
  }

  function leaveEditor() {
    if (!root.editing) return
    var note = root.editing
    root.editing = null
    if (Store.isEmpty(note)) {
      var kept = []
      for (var i = 0; i < root.notes.length; i++)
        if (root.notes[i].id !== note.id) kept.push(root.notes[i])
      root.replaceNotes(kept)
      return
    }
    root.upsert(note)
  }

  function upsert(note) {
    note.edited = Date.now() / 1000
    var next = []
    var found = false
    for (var i = 0; i < root.notes.length; i++) {
      if (root.notes[i].id === note.id) {
        next.push(Store.cloneNote(note))
        found = true
      } else next.push(root.notes[i])
    }
    if (!found) next.unshift(Store.cloneNote(note))
    root.replaceNotes(next)
  }

  function persistEditing() {
    if (!root.editing) return
    root.editing.edited = Date.now() / 1000
    root.upsert(root.editing)
  }

  function rewriteItems(fn) {
    if (!root.editing) return
    var items = []
    for (var i = 0; i < root.editing.items.length; i++)
      items.push({ text: root.editing.items[i].text, done: !!root.editing.items[i].done })
    fn(items)
    root.editing.items = items
    root.persistEditing()
  }

  function toggleItemDone(idx) {
    root.rewriteItems(function (items) {
      if (items[idx]) items[idx].done = !items[idx].done
    })
  }

  function removeItem(idx) {
    root.rewriteItems(function (items) { items.splice(idx, 1) })
  }

  function patchEditing(fn) {
    // Mutate in place. Cloning here rebuilds every TextField on each
    // keystroke and the keyboard loses the cursor.
    if (!root.editing) return
    fn(root.editing)
    root.persistEditing()
  }

  function deleteNote(id) {
    var next = []
    for (var i = 0; i < root.notes.length; i++)
      if (root.notes[i].id !== id) next.push(root.notes[i])
    root.replaceNotes(next)
    if (root.editing && root.editing.id === id) root.editing = null
    root.menuOpen = false
  }

  function setColour(id, colour) {
    if (root.editing && root.editing.id === id)
      root.patchEditing(function (n) { n.colour = colour })
    else {
      var next = []
      for (var i = 0; i < root.notes.length; i++) {
        var n = Store.cloneNote(root.notes[i])
        if (n.id === id) { n.colour = colour; n.edited = Date.now() / 1000 }
        next.push(n)
      }
      root.replaceNotes(next)
    }
    root.menuOpen = false
  }

  function togglePin(id) {
    if (root.editing && root.editing.id === id)
      root.patchEditing(function (n) { n.pinned = !n.pinned })
    else {
      var next = []
      for (var i = 0; i < root.notes.length; i++) {
        var n = Store.cloneNote(root.notes[i])
        if (n.id === id) { n.pinned = !n.pinned; n.edited = Date.now() / 1000 }
        next.push(n)
      }
      root.replaceNotes(next)
    }
    root.menuOpen = false
  }

  function noteFill(key) {
    return Notes.fill(root.colours, key)
  }

  // The open note's colour, which is the colour of its boxes and never of the
  // window. The editor used to wear the note's colour as its whole page, and
  // the shell does not draw an app under the status bar -- so a coral note was
  // a coral screen with a black strip across the top of it. The page is the
  // theme's background, like every other screen here, and the colour is where
  // it is in the grid: on the note.
  readonly property color noteColour: root.noteFill(root.editing ? root.editing.colour : "default")

  IpcHandler {
    target: "keep"
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
  }

  Timer {
    id: saveTimer
    interval: 500
    onTriggered: root.saveNow()
  }

  Process {
    id: ensureDir
    running: false
    command: ["mkdir", "-p", root.notesDir]
  }

  FileView {
    id: disk
    path: root.notesPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyText(text())
    onFileChanged: Qt.callLater(function () { disk.reload() })
  }

  Chrome.ThemeFile { id: themeFile }

  Chrome.AppWindow {
    id: keepWindow
    shell: root.shell
    appName: "Notes"
    pageTitle: root.editing ? (root.editing.title || "Note") : ""
    pluginId: root.pluginId
    color: root.background

    onUnmapped: {
      root.leaveEditor()
      root.menuOpen = false
      // The keyboard is left where it is. moarchy's gestures.md G14: nothing
      // puts it down but the back swipe, and switching apps leaves it alone.
    }

    Rectangle {
      anchors.fill: parent
      color: root.background
      focus: true
      Keys.onEscapePressed: {
        if (root.menuOpen) { root.menuOpen = false; return }
        if (root.moreOpen) { root.moreOpen = false; return }
        if (root.colourOpen) { root.colourOpen = false; return }
        if (root.editing) { root.leaveEditor(); return }
        root.dismiss()
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- header -------------------------------------------------------
        RowLayout {
          Layout.fillWidth: true
          // The same gutter the grid under it uses. They were 6 and 12, which
          // put the search pill four pixels out of line with every card.
          Layout.leftMargin: Metrics.GUTTER
          Layout.rightMargin: Metrics.GUTTER
          Layout.topMargin: Metrics.GAP
          Layout.bottomMargin: Metrics.GAP
          spacing: 4

          Chrome.Icon {
            visible: !!root.editing
            color: root.textOnSurface
            names: ["go-previous-symbolic", "pan-start-symbolic"]
            MouseArea {
              anchors.fill: parent
              onClicked: root.leaveEditor()
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Metrics.PILL
            visible: !root.editing
            radius: Metrics.round(root.colours, height)
            color: Theme.surface(root.colours, "card")
            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 4
              spacing: 4
              Chrome.Icon {
                slot: 22
                size: 14
                color: root.dim
                names: ["system-search-symbolic"]
              }
              Chrome.TextField {
                id: searchField
                Layout.fillWidth: true
                // Bare: the pill belongs to the row around it, not to the
                // field. The kit's TextField draws its own, so it is asked
                // for a transparent one rather than handed a null Item --
                // which is what Ui.TextField wanted and this is not.
                color: "transparent"
                placeholderText: "Search your notes"
                foreground: root.textOnSurface
                accent: root.accent
                text: root.query
                onTextChanged: root.query = text
              }
              Chrome.Icon {
                slot: 32
                size: 16
                color: root.textOnSurface
                names: root.view === "list"
                       ? ["view-grid-symbolic", "view-app-grid-symbolic"]
                       : ["view-list-symbolic"]
                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    root.view = root.view === "list" ? "grid" : "list"
                    root.scheduleSave()
                  }
                }
              }
            }
          }

          Item { Layout.fillWidth: true; visible: !!root.editing }

          Chrome.Icon {
            visible: !!root.editing
            color: root.textOnSurface
            names: ["view-more-symbolic", "open-menu-symbolic"]
            MouseArea {
              anchors.fill: parent
              onClicked: { root.moreOpen = !root.moreOpen; root.colourOpen = false }
            }
          }
          Chrome.Icon {
            visible: !!root.editing
            color: root.textOnSurface
            names: ["color-select-symbolic"]
            MouseArea {
              anchors.fill: parent
              onClicked: { root.colourOpen = !root.colourOpen; root.moreOpen = false }
            }
          }
          Chrome.Icon {
            visible: !!root.editing
            color: root.textOnSurface
            names: ["view-pin-symbolic", "starred-symbolic"]
            MouseArea {
              anchors.fill: parent
              onClicked: if (root.editing) root.togglePin(root.editing.id)
            }
          }

        }

        // --- grid ---------------------------------------------------------
        Flickable {
          id: gridFlick
          Layout.fillWidth: true
          Layout.fillHeight: true
          visible: !root.editing
          clip: true
          contentWidth: width
          contentHeight: gridColumn.height
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: gridColumn
            width: gridFlick.width
            leftPadding: Metrics.space(12, root)
            rightPadding: Metrics.space(12, root)
            bottomPadding: 80
            spacing: Metrics.space(10, root)

            Chrome.TypedText {
              visible: root.shown.pinned.length && root.shown.others.length && !root.query
              role: "overline"
              text: "Pinned"
              color: root.dim
              bodySize: root.bodySize
              leftPadding: 2
            }
            NoteColumns {
              width: parent.width - parent.leftPadding - parent.rightPadding
              notes: root.shown.pinned
              listView: root.view === "list"
            }
            Chrome.TypedText {
              visible: root.shown.pinned.length && root.shown.others.length && !root.query
              Layout.topMargin: 4
              role: "overline"
              text: "Others"
              color: root.dim
              bodySize: root.bodySize
              leftPadding: 2
            }
            NoteColumns {
              width: parent.width - parent.leftPadding - parent.rightPadding
              notes: root.shown.others
              listView: root.view === "list"
            }
            Item {
              visible: !root.shown.pinned.length && !root.shown.others.length
              width: parent.width - parent.leftPadding - parent.rightPadding
              height: blank.implicitHeight + Metrics.space(40, root)

              Chrome.EmptyState {
                id: blank
                anchors.bottom: parent.bottom
                width: parent.width
                colours: root.colours
                bodySize: root.bodySize
                names: root.query
                       ? ["system-search-symbolic"]
                       : ["document-edit-symbolic", "list-add-symbolic"]
                title: root.query ? "Nothing matches" : "Take a note"
                detail: root.query
                        ? "No note here has those words in its title, its body or its list."
                        : "Tap + for a note, or hold it for a list with tick boxes."
              }
            }
          }
        }

        // --- editor -------------------------------------------------------
        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          visible: !!root.editing
          spacing: 0

          Flickable {
            id: editorFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: editorCol.implicitHeight + Metrics.GUTTER * 2
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: editorCol
              x: Metrics.GUTTER
              y: Metrics.GAP
              width: editorFlick.width - Metrics.GUTTER * 2
              spacing: Metrics.GAP

              // The title stays loose. It is the heading of the page it is on,
              // which is the one thing on this phone that is allowed to be.
              Chrome.TextField {
                Layout.fillWidth: true
                // A bare field still insets its text by 12, which is the
                // padding a Card gives its own contents -- so the title lands
                // on the same left edge as the body under it.
                Layout.leftMargin: Metrics.PAD - 12
                // Bare: the pill belongs to the row around it, not to the
                // field. The kit's TextField draws its own, so it is asked
                // for a transparent one rather than handed a null Item --
                // which is what Ui.TextField wanted and this is not.
                color: "transparent"
                placeholderText: "Title"
                foreground: root.textOnSurface
                accent: root.accent
                placeholderColor: root.dim
                font.pixelSize: Math.round(root.bodySize * 1.4)
                font.weight: Font.DemiBold
                text: root.editing ? root.editing.title : ""
                onTextChanged: {
                  if (!root.editing || text === root.editing.title) return
                  root.editing.title = text
                  root.persistEditing()
                }
              }

              // The body is in a box, and the box is the note's colour -- the
              // same fill its card has in the grid, so opening a note is the
              // card getting bigger rather than the screen changing colour.
              Rectangle {
                Layout.fillWidth: true
                visible: root.editing && root.editing.kind !== "list"
                radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
                color: root.noteColour
                implicitHeight: Math.max(120, bodyEdit.implicitHeight + Metrics.PAD * 2)

                TextEdit {
                  id: bodyEdit
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Metrics.PAD
                  text: root.editing && root.editing.kind !== "list"
                        ? (root.editing.body || "") : ""
                  color: root.textOnSurface
                  font.family: root.noteFont
                  font.pixelSize: Math.round(root.bodySize * 1.05)
                  font.weight: Font.Normal
                  wrapMode: TextEdit.Wrap
                  // The body is not a Chrome.TextField, so it asks for the
                  // keyboard itself: a press that starts here, passed on so the
                  // caret still lands where the finger did (G14).
                  Chrome.Osk { id: bodyOsk }
                  MouseArea {
                    anchors.fill: parent
                    propagateComposedEvents: true
                    onPressed: mouse => {
                      bodyOsk.show()
                      mouse.accepted = false
                    }
                  }
                  onTextChanged: {
                    if (!root.editing || root.editing.kind === "list") return
                    if (text === root.editing.body) return
                    root.editing.body = text
                    root.persistEditing()
                  }
                }
              }

              Chrome.Card {
                id: listCard
                Layout.fillWidth: true
                visible: root.editing && root.editing.kind === "list"
                colours: root.colours
                color: root.noteColour
                radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
                pad: Metrics.GROUP_PAD
                spacing: 0

                Repeater {
                  model: root.editing && root.editing.kind === "list" ? root.editing.items : []
                  delegate: RowLayout {
                    id: item
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredHeight: Metrics.TARGET
                    spacing: 4
                    visible: root.editing && (!item.modelData.done || root.doneOpen)

                    Chrome.Check {
                      colours: root.colours
                      Layout.alignment: Qt.AlignVCenter
                      checked: !!item.modelData.done
                      foreground: root.textOnSurface
                      tickColor: Theme.inkOn(root.colours, root.accent)
                      accent: root.accent
                      dim: root.dim
                      bodySize: root.bodySize
                      onToggled: root.toggleItemDone(item.index)
                    }

                    Chrome.TextField {
                      Layout.fillWidth: true
                      // Bare: the pill belongs to the row around it, not to
                      // the field.
                      color: "transparent"
                      foreground: root.textOnSurface
                      accent: root.accent
                      placeholderColor: root.dim
                      bodySize: root.bodySize
                      text: item.modelData.text
                      onTextChanged: {
                        var idx = item.index
                        if (!root.editing || !root.editing.items[idx]) return
                        if (root.editing.items[idx].text === text) return
                        root.editing.items[idx].text = text
                        root.persistEditing()
                      }
                    }

                    Chrome.IconButton {
                      colours: root.colours
                      Layout.alignment: Qt.AlignVCenter
                      slot: 36
                      size: 16
                      color: root.dim
                      names: ["window-close-symbolic"]
                      tooltip: "Remove this item"
                      onClicked: root.removeItem(item.index)
                    }
                  }
                }

                Item {
                  Layout.fillWidth: true
                  Layout.preferredHeight: Metrics.TARGET

                  Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    spacing: 10
                    Chrome.Icon { slot: 24; size: 16; color: root.dim; names: ["list-add-symbolic"] }
                    Chrome.TypedText {
                      anchors.verticalCenter: parent.verticalCenter
                      role: "body"
                      text: "List item"
                      color: root.dim
                      bodySize: root.bodySize
                    }
                  }

                  Chrome.PressVeil {
                    anchors.fill: parent
                    radius: listCard.innerRadius
                    ink: root.textOnSurface
                    on: addTap.pressed
                  }

                  MouseArea {
                    id: addTap
                    anchors.fill: parent
                    onClicked: root.patchEditing(function (n) {
                      n.items = (n.items || []).concat([{ text: "", done: false }])
                    })
                  }
                }

                Item {
                  Layout.fillWidth: true
                  Layout.preferredHeight: Metrics.TARGET
                  visible: root.editing && root.editing.kind === "list" && root.doneCount > 0

                  Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    spacing: 10
                    Chrome.Icon {
                      slot: 24; size: 16
                      color: root.dim
                      names: root.doneOpen ? ["pan-down-symbolic"] : ["pan-end-symbolic"]
                    }
                    Chrome.TypedText {
                      anchors.verticalCenter: parent.verticalCenter
                      role: "body"
                      text: root.doneCount + " ticked item" + (root.doneCount === 1 ? "" : "s")
                      color: root.dim
                      bodySize: root.bodySize
                    }
                  }

                  Chrome.PressVeil {
                    anchors.fill: parent
                    radius: listCard.innerRadius
                    ink: root.textOnSurface
                    on: doneTap.pressed
                  }

                  MouseArea {
                    id: doneTap
                    anchors.fill: parent
                    onClicked: root.doneOpen = !root.doneOpen
                  }
                }
              }
            }
          }

          // When it was last written, in a box of its own. It is the last
          // loose caption this app had, and a page whose every other word is
          // inside something made it look like a line left over.
          Rectangle {
            Layout.leftMargin: Metrics.GUTTER
            Layout.bottomMargin: Metrics.GAP
            Layout.topMargin: 4
            implicitWidth: edited.implicitWidth + 24
            implicitHeight: 28
            radius: Metrics.round(root.colours, height)
            visible: edited.text.length > 0
            color: Theme.surface(root.colours, "card")

            Chrome.TypedText {
              id: edited
              anchors.centerIn: parent
              role: "caption"
              text: root.editing ? Store.editedLabel(root.editing.edited) : ""
              color: root.dim
              bodySize: root.bodySize
            }
          }
        }

      }

      // The kit's, not a sixth hand-drawn circle: every other app on this
      // phone reaches its new-thing button at the same size, in the same
      // corner, with the same press.
      Chrome.Fab {
        colours: root.colours
        visible: !root.editing
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 16
        anchors.bottomMargin: 16
        accent: root.accent
        foreground: Theme.inkOn(root.colours, root.accent)
        names: ["list-add-symbolic"]
        tooltip: "A new note"
        onClicked: root.newNote("text")
        onHeld: root.newNote("list")
      }

      // --- card menu (GTK popover, not a sheet) ---------------------------
      MouseArea {
        anchors.fill: parent
        visible: root.menuOpen || root.moreOpen || root.colourOpen
        onClicked: { root.menuOpen = false; root.moreOpen = false; root.colourOpen = false }

        // A scrim, not an outline. The three panels below used to be the page
        // colour with a hairline round them, which on a coral note was a
        // rectangle you had to look for.
        Rectangle {
          anchors.fill: parent
          color: Theme.alpha(root.colours.background, 0.55)
        }

        Rectangle {
          visible: root.menuOpen
          width: 220
          height: cardMenuCol.height + 20
          anchors.centerIn: parent
          radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
          color: Theme.surface(root.colours, "raised")

          Column {
            id: cardMenuCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 8

            Item {
              width: parent.width
              height: 36
              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Chrome.Icon { slot: 28; size: 16; color: root.textOnSurface; names: ["view-pin-symbolic"] }
                Chrome.TypedText {
                  role: "body"
                  text: root.menuNote && root.menuNote.pinned ? "Unpin" : "Pin"
                  color: root.textOnSurface
                  bodySize: root.bodySize
                }
              }
              MouseArea {
                anchors.fill: parent
                onClicked: if (root.menuNote) root.togglePin(root.menuNote.id)
              }
            }

            Grid {
              columns: 3
              columnSpacing: 8
              rowSpacing: 8
              Repeater {
                model: Store.COLOURS
                delegate: Rectangle {
                  id: swatch
                  required property var modelData
                  readonly property bool on: !!root.menuNote
                                             && root.menuNote.colour === swatch.modelData
                  width: 44; height: 44
                  radius: Metrics.round(root.colours, width)
                  color: root.noteFill(swatch.modelData)

                  // Which one is chosen is a tick on it, not a ring round it:
                  // a 2px outline on a 44px disc of a colour the theme chose
                  // is a difference nobody sees at arm's length.
                  Chrome.Icon {
                    anchors.centerIn: parent
                    slot: 22
                    size: swatch.on ? 16 : 14
                    color: swatch.on ? root.textOnSurface : root.dim
                    names: swatch.on
                           ? ["object-select-symbolic"]
                           : (swatch.modelData === "default"
                              ? ["action-unavailable-symbolic"] : [])
                  }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: if (root.menuNote) root.setColour(root.menuNote.id, swatch.modelData)
                  }
                }
              }
            }

            Item {
              width: parent.width
              height: 36
              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Chrome.Icon { slot: 28; size: 16; color: root.textOnSurface; names: ["user-trash-symbolic"] }
                Chrome.TypedText {
                  role: "body"
                  text: "Delete"
                  color: root.textOnSurface
                  bodySize: root.bodySize
                }
              }
              MouseArea {
                anchors.fill: parent
                onClicked: if (root.menuNote) root.deleteNote(root.menuNote.id)
              }
            }
          }
        }

        Rectangle {
          visible: root.moreOpen
          width: 220
          height: moreCol.height + 16
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: 8
          anchors.topMargin: 48
          radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
          color: Theme.surface(root.colours, "raised")
          Column {
            id: moreCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 4
            Item {
              width: parent.width
              height: 40
              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Chrome.Icon { slot: 28; size: 16; color: root.textOnSurface; names: ["checkbox-checked-symbolic"] }
                Chrome.TypedText {
                  role: "body"
                  text: root.editing && root.editing.kind === "list" ? "Hide tick boxes" : "Tick boxes"
                  color: root.textOnSurface
                  bodySize: root.bodySize
                }
              }
              MouseArea {
                anchors.fill: parent
                onClicked: {
                  root.patchEditing(function (n) {
                    if (n.kind === "list") Store.toText(n); else Store.toList(n)
                  })
                  root.moreOpen = false
                }
              }
            }
            Item {
              width: parent.width
              height: 40
              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Chrome.Icon { slot: 28; size: 16; color: root.textOnSurface; names: ["user-trash-symbolic"] }
                Chrome.TypedText {
                  role: "body"
                  text: "Delete note"
                  color: root.textOnSurface
                  bodySize: root.bodySize
                }
              }
              MouseArea {
                anchors.fill: parent
                onClicked: { if (root.editing) root.deleteNote(root.editing.id); root.moreOpen = false }
              }
            }
          }
        }

        Rectangle {
          visible: root.colourOpen
          width: 168
          height: colourCol.height + 20
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: 8
          anchors.topMargin: 48
          radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
          color: Theme.surface(root.colours, "raised")
          Grid {
            id: colourCol
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 10
            columns: 3
            columnSpacing: 8
            rowSpacing: 8
            Repeater {
              model: Store.COLOURS
              delegate: Rectangle {
                id: pick
                required property var modelData
                readonly property bool on: !!root.editing
                                           && root.editing.colour === pick.modelData
                width: 44; height: 44
                radius: Metrics.round(root.colours, width)
                color: root.noteFill(pick.modelData)

                Chrome.Icon {
                  anchors.centerIn: parent
                  slot: 22
                  size: pick.on ? 16 : 14
                  color: pick.on ? root.textOnSurface : root.dim
                  names: pick.on
                         ? ["object-select-symbolic"]
                         : (pick.modelData === "default"
                            ? ["action-unavailable-symbolic"] : [])
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    if (root.editing) root.setColour(root.editing.id, pick.modelData)
                    root.colourOpen = false
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component NoteColumns: Item {
    id: cols
    property var notes: []
    property bool listView: false
    readonly property var split: Store.splitColumns(cols.notes)
    height: cols.listView
            ? listCol.height
            : Math.max(leftCol.height, rightCol.height)

    Column {
      id: listCol
      visible: cols.listView
      width: parent.width
      spacing: Metrics.space(10, root)
      Repeater {
        model: cols.notes
        delegate: NoteCard { width: listCol.width; note: modelData }
      }
    }

    Row {
      visible: !cols.listView
      width: parent.width
      spacing: Metrics.space(10, root)
      Column {
        id: leftCol
        width: (parent.width - parent.spacing) / 2
        spacing: Metrics.space(10, root)
        Repeater {
          model: cols.split.left
          delegate: NoteCard { width: leftCol.width; note: modelData }
        }
      }
      Column {
        id: rightCol
        width: (parent.width - parent.spacing) / 2
        spacing: Metrics.space(10, root)
        Repeater {
          model: cols.split.right
          delegate: NoteCard { width: rightCol.width; note: modelData }
        }
      }
    }
  }

  component NoteCard: Rectangle {
    id: card
    property var note
    radius: Metrics.radius(root.colours, Metrics.CARD_RADIUS)
    color: root.noteFill(note ? note.colour : "default")
    height: cardCol.height + Metrics.PAD * 2

    Column {
      id: cardCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Metrics.PAD
      spacing: 6

      Chrome.TypedText {
        visible: !!(card.note && card.note.title)
        width: parent.width
        role: "body"
        font.pixelSize: Math.round(root.bodySize * 1.05)
        font.weight: Font.DemiBold
        text: card.note ? card.note.title : ""
        color: root.textOnSurface
        bodySize: root.bodySize
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
      }
      Chrome.TypedText {
        visible: card.note && card.note.kind !== "list"
        width: parent.width
        role: "body"
        font.pixelSize: Math.round(root.bodySize * 0.95)
        text: card.note ? (card.note.body || "") : ""
        color: root.textOnSurface
        bodySize: root.bodySize
        wrapMode: Text.Wrap
        maximumLineCount: 6
        elide: Text.ElideRight
      }
      Repeater {
        model: card.note && card.note.kind === "list" ? Store.previewItems(card.note).items : []
        delegate: Row {
          id: preview
          required property var modelData
          width: cardCol.width
          spacing: 8
          Item {
            width: 14; height: 16
            anchors.verticalCenter: parent.verticalCenter
            // A filled square rather than an outlined one. At 12px a 1.5px
            // border is most of the box, and it is the first thing to vanish
            // on a phone screen outdoors.
            Rectangle {
              visible: !preview.modelData.done
              width: 12; height: 12
              anchors.centerIn: parent
              radius: Metrics.radius(root.colours, 3)
              color: Theme.alpha(root.textOnSurface, 0.22)
            }
            Chrome.Icon {
              visible: preview.modelData.done
              anchors.centerIn: parent
              slot: 14; size: 12
              color: root.dim
              names: ["object-select-symbolic"]
            }
          }
          Chrome.TypedText {
            width: cardCol.width - 22
            role: "body"
            font.pixelSize: Math.round(root.bodySize * 0.95)
            font.strikeout: !!preview.modelData.done
            text: preview.modelData.text
            color: preview.modelData.done ? root.dim : root.textOnSurface
            bodySize: root.bodySize
            elide: Text.ElideRight
          }
        }
      }
    }

    Chrome.PressVeil {
      anchors.fill: parent
      radius: parent.radius
      ink: root.textOnSurface
      on: cardTap.pressed
    }

    MouseArea {
      id: cardTap
      anchors.fill: parent
      onClicked: root.openNote(card.note)
      onPressAndHold: { root.menuNote = card.note; root.menuOpen = true }
    }
  }
}

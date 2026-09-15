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
  Component.onCompleted: root.bodySize = Metrics.shellBody(root)

  // Same numbers the GTK app paints: the palette is parsed out of colors.toml
  // here rather than taken from the shell, so a coral card matches GTK Keep
  // rather than a Settings row.
  readonly property color surface: colours.surface
  readonly property color background: colours.background
  readonly property color textOnSurface: colours.foreground
  readonly property color dim: colours.dim
  readonly property color line: colours.line
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
  readonly property int radiusCard: uiFile.radiusCard
  readonly property string noteFont: "Adwaita Sans"

  readonly property color pageColor: root.editing
                                     ? Notes.fill(root.colours, root.editing.colour)
                                     : root.background

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
  Chrome.UiFile { id: uiFile }

  Chrome.AppWindow {
    id: keepWindow
    shell: root.shell
    appName: "Notes"
    pageTitle: root.editing ? (root.editing.title || "Note") : ""
    pluginId: root.pluginId
    color: root.pageColor

    onUnmapped: {
      root.leaveEditor()
      root.menuOpen = false
    }

    Rectangle {
      anchors.fill: parent
      color: root.pageColor
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
          Layout.leftMargin: 6
          Layout.rightMargin: 6
          Layout.topMargin: 4
          Layout.bottomMargin: 4
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
            Layout.preferredHeight: 40
            visible: !root.editing
            radius: 20
            color: root.surface
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

            Text {
              visible: root.shown.pinned.length && root.shown.others.length && !root.query
              text: "PINNED"
              font.family: root.noteFont
              font.pixelSize: Math.round(root.bodySize * 0.75)
              font.weight: Font.DemiBold
              font.letterSpacing: 1.2
              color: root.dim
              leftPadding: 6
            }
            NoteColumns {
              width: parent.width - parent.leftPadding - parent.rightPadding
              notes: root.shown.pinned
              listView: root.view === "list"
            }
            Text {
              visible: root.shown.pinned.length && root.shown.others.length && !root.query
              text: "OTHERS"
              font.family: root.noteFont
              font.pixelSize: Math.round(root.bodySize * 0.75)
              font.weight: Font.DemiBold
              font.letterSpacing: 1.2
              color: root.dim
              leftPadding: 6
            }
            NoteColumns {
              width: parent.width - parent.leftPadding - parent.rightPadding
              notes: root.shown.others
              listView: root.view === "list"
            }
            Text {
              visible: !root.shown.pinned.length && !root.shown.others.length
              width: parent.width - parent.leftPadding - parent.rightPadding
              text: root.query ? "Nothing here matches that." : "Take a note."
              font.family: root.noteFont
              font.pixelSize: root.bodySize
              color: root.subdued
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
              topPadding: Metrics.space(40, root)
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
            contentHeight: editorCol.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: editorCol
              width: editorFlick.width
              leftPadding: 16
              rightPadding: 16
              topPadding: 8
              spacing: 10

              Chrome.TextField {
                width: parent.width - parent.leftPadding - parent.rightPadding
                // Bare: the pill belongs to the row around it, not to the
                // field. The kit's TextField draws its own, so it is asked
                // for a transparent one rather than handed a null Item --
                // which is what Ui.TextField wanted and this is not.
                color: "transparent"
                placeholderText: "Title"
                foreground: root.textOnSurface
                accent: root.accent
                font.pixelSize: Math.round(root.bodySize * 1.4)
                font.weight: Font.DemiBold
                text: root.editing ? root.editing.title : ""
                onTextChanged: {
                  if (!root.editing || text === root.editing.title) return
                  root.editing.title = text
                  root.persistEditing()
                }
              }

              TextEdit {
                id: bodyEdit
                width: parent.width - parent.leftPadding - parent.rightPadding
                visible: root.editing && root.editing.kind !== "list"
                text: root.editing && root.editing.kind !== "list" ? (root.editing.body || "") : ""
                color: root.textOnSurface
                font.family: root.noteFont
                font.pixelSize: Math.round(root.bodySize * 1.05)
                font.weight: Font.Normal
                wrapMode: TextEdit.Wrap
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

              Repeater {
                model: root.editing && root.editing.kind === "list" ? root.editing.items : []
                delegate: RowLayout {
                  width: editorCol.width - editorCol.leftPadding - editorCol.rightPadding
                  height: 44
                  spacing: 6
                  visible: root.editing && (!modelData.done || root.doneOpen)

                  Item {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 44
                    Rectangle {
                      width: 22; height: 22
                      anchors.centerIn: parent
                      radius: 4
                      color: modelData.done ? root.accent : "transparent"
                      border.color: modelData.done ? root.accent : root.dim
                      border.width: 1.5
                      Chrome.Icon {
                        visible: modelData.done
                        anchors.centerIn: parent
                        slot: 16; size: 12
                        color: root.textOnAccent
                        names: ["object-select-symbolic"]
                      }
                    }
                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.toggleItemDone(index)
                    }
                  }

                  Chrome.TextField {
                    Layout.fillWidth: true
                    // Bare: the pill belongs to the row around it, not to the
                // field. The kit's TextField draws its own, so it is asked
                // for a transparent one rather than handed a null Item --
                // which is what Ui.TextField wanted and this is not.
                color: "transparent"
                    foreground: root.textOnSurface
                    accent: root.accent
                    text: modelData.text
                    onTextChanged: {
                      var idx = index
                      if (!root.editing || !root.editing.items[idx]) return
                      if (root.editing.items[idx].text === text) return
                      root.editing.items[idx].text = text
                      root.persistEditing()
                    }
                  }

                  Chrome.Icon {
                    slot: 36; size: 16
                    color: root.dim
                    names: ["window-close-symbolic"]
                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.removeItem(index)
                    }
                  }
                }
              }

              Item {
                visible: root.editing && root.editing.kind === "list"
                width: parent.width - parent.leftPadding - parent.rightPadding
                height: 44
                Row {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 10
                  Chrome.Icon { slot: 28; size: 16; color: root.dim; names: ["list-add-symbolic"] }
                  Text {
                    text: "List item"
                    font.family: root.noteFont
                    font.pixelSize: root.bodySize
                    color: root.dim
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: root.patchEditing(function (n) {
                    n.items = (n.items || []).concat([{ text: "", done: false }])
                  })
                }
              }

              Item {
                visible: root.editing && root.editing.kind === "list" && root.doneCount > 0
                width: parent.width - parent.leftPadding - parent.rightPadding
                height: 44
                Row {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 10
                  Chrome.Icon {
                    slot: 28; size: 16
                    color: root.dim
                    names: root.doneOpen ? ["pan-down-symbolic"] : ["pan-end-symbolic"]
                  }
                  Text {
                    text: root.doneCount + " ticked item" + (root.doneCount === 1 ? "" : "s")
                    font.family: root.noteFont
                    font.pixelSize: root.bodySize
                    color: root.dim
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: root.doneOpen = !root.doneOpen
                }
              }
            }
          }

          Text {
            Layout.fillWidth: true
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            text: root.editing ? Store.editedLabel(root.editing.edited) : ""
            font.family: root.noteFont
            font.pixelSize: Math.round(root.bodySize * 0.85)
            color: root.dim
          }
        }

      }

      Chrome.Fab {
        visible: !root.editing
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 16
        anchors.bottomMargin: 16
        accent: root.accent
        foreground: root.textOnAccent
        names: ["list-add-symbolic"]
        onClicked: root.newNote("text")
        onPressAndHold: root.newNote("list")
      }

      // --- card menu (GTK popover, not a sheet) ---------------------------
      MouseArea {
        anchors.fill: parent
        visible: root.menuOpen || root.moreOpen || root.colourOpen
        onClicked: { root.menuOpen = false; root.moreOpen = false; root.colourOpen = false }

        Rectangle {
          visible: root.menuOpen
          width: 220
          height: cardMenuCol.height + 20
          anchors.centerIn: parent
          radius: 12
          color: root.background
          border.color: root.line
          border.width: 1

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
                Text {
                  text: root.menuNote && root.menuNote.pinned ? "Unpin" : "Pin"
                  font.family: root.noteFont
                  font.pixelSize: root.bodySize
                  color: root.textOnSurface
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
                  width: 44; height: 44
                  radius: 22
                  color: root.noteFill(modelData)
                  border.color: root.menuNote && root.menuNote.colour === modelData ? root.accent : root.line
                  border.width: root.menuNote && root.menuNote.colour === modelData ? 2 : 1
                  Chrome.Icon {
                    visible: modelData === "default"
                    anchors.centerIn: parent
                    slot: 22; size: 14
                    color: root.dim
                    names: ["action-unavailable-symbolic"]
                  }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: if (root.menuNote) root.setColour(root.menuNote.id, modelData)
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
                Text {
                  text: "Delete"
                  font.family: root.noteFont
                  font.pixelSize: root.bodySize
                  color: root.textOnSurface
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
          radius: 12
          color: root.background
          border.color: root.line
          border.width: 1
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
                Text {
                  text: root.editing && root.editing.kind === "list" ? "Hide tick boxes" : "Tick boxes"
                  font.family: root.noteFont
                  font.pixelSize: root.bodySize
                  color: root.textOnSurface
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
                Text {
                  text: "Delete note"
                  font.family: root.noteFont
                  font.pixelSize: root.bodySize
                  color: root.textOnSurface
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
          radius: 12
          color: root.background
          border.color: root.line
          border.width: 1
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
                width: 44; height: 44
                radius: 22
                color: root.noteFill(modelData)
                border.color: root.editing && root.editing.colour === modelData ? root.accent : root.line
                border.width: root.editing && root.editing.colour === modelData ? 2 : 1
                Chrome.Icon {
                  visible: modelData === "default"
                  anchors.centerIn: parent
                  slot: 22; size: 14
                  color: root.dim
                  names: ["action-unavailable-symbolic"]
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    if (root.editing) root.setColour(root.editing.id, modelData)
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
    radius: 12
    color: root.noteFill(note ? note.colour : "default")
    height: cardCol.height + 24
    border.color: note && note.colour === "default" ? root.line : "transparent"
    border.width: 1

    Column {
      id: cardCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 12
      spacing: 6

      Text {
        visible: !!(note && note.title)
        width: parent.width
        text: note ? note.title : ""
        font.family: root.noteFont
        font.pixelSize: Math.round(root.bodySize * 1.05)
        font.weight: Font.DemiBold
        color: root.textOnSurface
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
      }
      Text {
        visible: note && note.kind !== "list"
        width: parent.width
        text: note ? (note.body || "") : ""
        font.family: root.noteFont
        font.pixelSize: Math.round(root.bodySize * 0.95)
        font.weight: Font.Normal
        color: root.textOnSurface
        wrapMode: Text.Wrap
        maximumLineCount: 6
        elide: Text.ElideRight
      }
      Repeater {
        model: note && note.kind === "list" ? Store.previewItems(note).items : []
        delegate: Row {
          width: cardCol.width
          spacing: 8
          Item {
            width: 14; height: 16
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
              visible: !modelData.done
              width: 12; height: 12
              anchors.centerIn: parent
              radius: 3
              color: "transparent"
              border.color: root.dim
              border.width: 1.5
            }
            Chrome.Icon {
              visible: modelData.done
              anchors.centerIn: parent
              slot: 14; size: 12
              color: root.dim
              names: ["object-select-symbolic"]
            }
          }
          Text {
            width: cardCol.width - 22
            text: modelData.text
            font.family: root.noteFont
            font.pixelSize: Math.round(root.bodySize * 0.95)
            font.weight: Font.Normal
            font.strikeout: !!modelData.done
            color: modelData.done ? root.dim : root.textOnSurface
            elide: Text.ElideRight
          }
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.openNote(note)
      onPressAndHold: { root.menuNote = note; root.menuOpen = true }
    }
  }
}

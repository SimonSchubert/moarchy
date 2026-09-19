// Contacts, in the shell: a name, a number, an email, and a note.
//
// Two screens and no more. **The list** is every contact, searchable, grouped
// by the letter of the name. **The editor** is one screen per person, reached
// by the plus or by tapping a row. Nothing syncs, nothing is on the network,
// and the file is the whole of the storage layer.
//
// Written for the shell first: a plugin is an Item the host already holds, so
// summoning it is `visible = true` on a window that exists rather than four
// seconds of starting a process. An address book is opened for eleven seconds
// to find a number, and that is what this is for.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Contacts.js" as Contacts
import "Store.js" as Store

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "moarchy.contacts"
  readonly property bool opened: bookWindow.visible
  readonly property var appWindow: bookWindow

  property string returnTo: ""
  readonly property var colours: themeFile.colours
  property int bodySize: Metrics.BODY

  Component.onCompleted: {
    root.bodySize = Metrics.shellBody(root)
    root.applyHarness()
  }

  property var contacts: []
  property var strays: []
  property bool loaded: false
  property int revision: 0

  property string query: ""
  // "list" | "editor"
  property string page: "list"
  property var draft: null
  property bool draftIsNew: false
  property bool armed: false

  readonly property int shellFurniture: root.shell ? 60 : 0

  readonly property string dataDir: Plugin.dataDir(
    "contacts", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_CONTACTS_DIR"))

  readonly property var shown: {
    var r = root.revision
    return Contacts.filtered(root.contacts, root.query)
  }

  readonly property var groups: {
    var r = root.revision
    var q = root.query
    return Contacts.sections(root.shown)
  }

  readonly property color background: root.colours.background
  readonly property color ink: root.colours.foreground
  readonly property color dim: root.colours.dim
  readonly property color accent: root.colours.accent
  readonly property string danger: (root.colours.hues && root.colours.hues.red) || "#e01b24"

  function shade(colour) {
    var c = Theme.rgb(String(colour))
    return (c[0] * 299 + c[1] * 587 + c[2] * 114) / 255000.0
  }

  readonly property string accentInk: {
    var level = root.controlCenter(root.colours.accent)
    return Math.abs(level - root.controlCenter(root.colours.background))
         > Math.abs(level - root.controlCenter(root.colours.foreground))
      ? root.colours.background : root.colours.foreground
  }

  function surface(amount) {
    return Theme.mix(root.colours.foreground, root.colours.background, amount)
  }

  function say(text) { toast.show(text) }

  function startNew() {
    root.openEditor(Contacts.blank(Date.now()), true)
    Qt.callLater(function () { nameField.focusInput() })
  }

  function startEdit(c) {
    root.openEditor(Contacts.copy(c), false)
  }

  function openEditor(c, isNew) {
    root.draft = c
    root.draftIsNew = !!isNew
    root.armed = false
    nameField.text = c.name
    phoneField.text = c.phone
    emailField.text = c.email
    noteField.text = c.note
    root.page = "editor"
  }

  function closeEditor() {
    root.draft = null
    root.armed = false
    root.page = "list"
  }

  function change(field, value) {
    if (!root.draft) return
    var d = Contacts.copy(root.draft)
    d[field] = value
    root.draft = d
  }

  function commitDraft() {
    if (!root.draft) return
    var d = Contacts.copy(root.draft)
    d.name = String(nameField.text || "").trim()
    d.phone = String(phoneField.text || "").trim()
    d.email = String(emailField.text || "").trim()
    d.note = String(noteField.text || "").trim()
    if (Contacts.isEmpty(d)) {
      root.say("A contact needs something on it.")
      return
    }
    root.contacts = Contacts.withContact(root.contacts, d)
    root.revision += 1
    root.closeEditor()
    root.save()
  }

  function deleteDraft() {
    if (!root.draft || root.draftIsNew) return
    if (!root.armed) {
      root.armed = true
      disarm.restart()
      root.say("Tap again to delete.")
      return
    }
    disarm.stop()
    root.armed = false
    root.contacts = Contacts.without(root.contacts, root.draft.id)
    root.revision += 1
    root.closeEditor()
    root.save()
    root.say("Deleted.")
  }

  Timer {
    id: disarm
    interval: 3000
    onTriggered: root.armed = false
  }

  function open(payloadJson) {
    Plugin.hideOverlays(root.shell)
    root.returnTo = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload.returnTo) root.returnTo = String(payload.returnTo)
    } catch (e) {}
    bookWindow.show()
    Qt.callLater(root.ensureLoaded)
  }

  function close() {
    if (root.page === "editor") root.closeEditor()
  }

  function dismiss() {
    root.close()
    bookWindow.hide()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    var back = root.returnTo
    root.returnTo = ""
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, "{}")
  }

  function back() {
    if (root.page === "editor") { root.closeEditor(); return }
    root.dismiss()
  }

  function ensureLoaded() {
    if (root.loaded) return
    ensureDir.running = true
    store.reload()
    root.loaded = true
  }

  function save() {
    store.setText(Store.serialize(root.contacts, root.strays))
  }

  function applyHarness() {
    var page = Quickshell.env("MOARCHY_CONTACTS_PAGE") || ""
    if (page === "editor") Qt.callLater(root.startNew)
  }

  property bool harnessed: false

  function applyLoadedHarness() {
    if ((Quickshell.env("MOARCHY_CONTACTS_NEW") || "") !== "") root.startNew()
    else if ((Quickshell.env("MOARCHY_CONTACTS_EDIT") || "") !== "") {
      var want = Quickshell.env("MOARCHY_CONTACTS_EDIT")
      for (var i = 0; i < root.contacts.length; i++)
        if (root.contacts[i].name === want || root.contacts[i].id === want) {
          root.startEdit(root.contacts[i])
          return
        }
    }
  }

  Process { id: ensureDir; running: false; command: ["mkdir", "-p", root.dataDir] }

  Chrome.JsonFile {
    id: store
    path: root.dataDir + "/contacts.json"

    onParsed: function (data) {
      var state = Store.parse(data)
      root.contacts = state.contacts
      root.strays = state.strays
      root.revision += 1
      if (!root.harnessed) { root.harnessed = true; Qt.callLater(root.applyLoadedHarness) }
    }
    onQuarantined: function (to) {
      root.say("The contacts file was unreadable and was kept aside.")
    }
  }

  Chrome.ThemeFile { id: themeFile }

  IpcHandler {
    target: "contacts"

    function state(): string { return root.opened ? "open" : "closed" }
    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      else bookWindow.show()
      return "ok"
    }
    function close(): string { root.dismiss(); return "ok" }
    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }

    function add(json: string): string {
      var raw
      try { raw = JSON.parse(String(json || "")) } catch (e) { return "not JSON: " + e }
      var c = Contacts.normalise(raw, Date.now())
      if (c === null) return "a contact needs a name, phone, email or note"
      root.contacts = Contacts.withContact(root.contacts, c)
      root.revision += 1
      root.save()
      return c.id
    }

    function remove(id: string): string {
      if (!Contacts.find(root.contacts, id)) return "no such contact: " + id
      root.contacts = Contacts.without(root.contacts, String(id))
      root.revision += 1
      root.save()
      return "ok"
    }
  }

  Chrome.AppWindow {
    id: bookWindow
    shell: root.shell
    appName: "Contacts"
    pluginId: root.pluginId
    color: root.background
    pageTitle: root.page === "editor"
              ? (root.draftIsNew ? "New contact" : "Contact")
              : "Contacts"

    onMapped: Qt.callLater(root.ensureLoaded)

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
            title: "Contacts"
            subtitle: root.contacts.length
                      ? (root.query.length
                         ? root.shown.length + " of " + root.contacts.length
                         : root.contacts.length + (root.contacts.length === 1 ? " person" : " people"))
                      : ""
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize
          }

          Chrome.AppBar {
            anchors.fill: parent
            visible: root.page === "editor"
            title: root.draftIsNew ? "New contact" : "Contact"
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize

            leading: Chrome.BackButton {
              colours: root.colours
              color: root.ink
              onClicked: root.closeEditor()
            }

            trailing: [
              Chrome.IconButton {
                colours: root.colours
                visible: !root.draftIsNew
                names: ["user-trash-symbolic", "edit-delete-symbolic"]
                color: root.armed ? root.danger : root.ink
                tooltip: "Delete this contact"
                onClicked: root.deleteDraft()
              },
              Chrome.IconButton {
                colours: root.colours
                names: ["object-select-symbolic"]
                color: root.accent
                tooltip: "Save"
                onClicked: root.commitDraft()
              }
            ]
          }
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          // ========== the list ==========

          ColumnLayout {
            anchors.fill: parent
            visible: root.page === "list"
            spacing: 0

            Chrome.TextField {
              id: searchField
              Layout.fillWidth: true
              Layout.leftMargin: Metrics.GUTTER
              Layout.rightMargin: Metrics.GUTTER
              Layout.topMargin: 4
              Layout.bottomMargin: Metrics.GAP
              placeholderText: "Search"
              leadingNames: ["edit-find-symbolic", "system-search-symbolic"]
              colours: root.colours
              level: "card"
              foreground: root.ink
              accent: root.accent
              iconColor: root.dim
              bodySize: root.bodySize
              text: root.query
              onTextChanged: root.query = text
            }

            Flickable {
              id: listFlick
              Layout.fillWidth: true
              Layout.fillHeight: true
              contentWidth: width
              contentHeight: listColumn.implicitHeight + 88 + root.shellFurniture
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              ColumnLayout {
                id: listColumn
                x: Metrics.GUTTER
                width: listFlick.width - Metrics.GUTTER * 2
                spacing: Metrics.GAP

                Chrome.EmptyState {
                  Layout.fillWidth: true
                  Layout.topMargin: 40
                  visible: root.loaded && root.shown.length === 0
                  colours: root.colours
                  bodySize: root.bodySize
                  names: root.query.length
                         ? ["system-search-symbolic"]
                         : ["contact-new-symbolic", "list-add-symbolic"]
                  title: root.query.length ? "Nothing matches" : "No contacts yet"
                  detail: root.query.length
                          ? "Try a different name or number."
                          : "Tap + for someone to call."
                }

                // One box per letter, the people in it flush inside. The
                // letter is the only loose text on this screen, which is what
                // a heading is for -- and an index that is itself a row of
                // boxes is an index that reads as part of the list.
                Repeater {
                  model: root.groups

                  delegate: Chrome.Section {
                    id: section
                    required property var modelData
                    Layout.fillWidth: true
                    colours: root.colours
                    bodySize: root.bodySize
                    title: section.modelData.letter
                    pad: Metrics.GROUP_PAD
                    radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
                    cardSpacing: 0

                    Repeater {
                      model: section.modelData.contacts

                      delegate: Chrome.ListRow {
                        id: row
                        required property var modelData
                        Layout.fillWidth: true
                        radius: section.innerRadius
                        minHeight: Metrics.TARGET + 10
                        colours: root.colours
                        bodySize: root.bodySize
                        title: row.modelData.name
                               || row.modelData.phone
                               || row.modelData.email
                               || "Untitled"
                        subtitle: row.modelData.name.length > 0
                                  ? Contacts.line(row.modelData) : ""
                        onClicked: root.startEdit(row.modelData)
                      }
                    }
                  }
                }
              }
            }
          }

          // ========== the editor ==========

          Flickable {
            id: editorFlick
            anchors.fill: parent
            visible: root.page === "editor"
            contentWidth: width
            contentHeight: editorColumn.implicitHeight + 40 + root.shellFurniture
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: editorColumn
              x: Metrics.GUTTER
              y: Metrics.GAP
              width: editorFlick.width - Metrics.GUTTER * 2
              spacing: Metrics.GAP

              // One box, four fields. They were four loose captions over four
              // pills on the window's own background, which is a form drawn as
              // a list of unrelated things -- and a contact is one thing.
              Chrome.Section {
                Layout.fillWidth: true
                colours: root.colours
                bodySize: root.bodySize
                title: "Contact"
                cardSpacing: 10

                Chrome.TypedText {
                  Layout.fillWidth: true
                  role: "caption"
                  text: "Name"
                  color: root.dim
                  bodySize: root.bodySize
                }

                Chrome.TextField {
                  id: nameField
                  Layout.fillWidth: true
                  placeholderText: "Name"
                  colours: root.colours
                  foreground: root.ink
                  accent: root.accent
                  iconColor: root.dim
                  bodySize: root.bodySize
                  onTextChanged: root.change("name", text)
                }

                Chrome.TypedText {
                  Layout.fillWidth: true
                  Layout.topMargin: 2
                  role: "caption"
                  text: "Phone"
                  color: root.dim
                  bodySize: root.bodySize
                }

                Chrome.TextField {
                  id: phoneField
                  Layout.fillWidth: true
                  placeholderText: "Phone"
                  colours: root.colours
                  foreground: root.ink
                  accent: root.accent
                  iconColor: root.dim
                  bodySize: root.bodySize
                  onTextChanged: root.change("phone", text)
                }

                Chrome.TypedText {
                  Layout.fillWidth: true
                  Layout.topMargin: 2
                  role: "caption"
                  text: "Email"
                  color: root.dim
                  bodySize: root.bodySize
                }

                Chrome.TextField {
                  id: emailField
                  Layout.fillWidth: true
                  placeholderText: "Email"
                  colours: root.colours
                  foreground: root.ink
                  accent: root.accent
                  iconColor: root.dim
                  bodySize: root.bodySize
                  onTextChanged: root.change("email", text)
                }

                Chrome.TypedText {
                  Layout.fillWidth: true
                  Layout.topMargin: 2
                  role: "caption"
                  text: "Note"
                  color: root.dim
                  bodySize: root.bodySize
                }

                Chrome.TextField {
                  id: noteField
                  Layout.fillWidth: true
                  placeholderText: "Note"
                  colours: root.colours
                  foreground: root.ink
                  accent: root.accent
                  iconColor: root.dim
                  bodySize: root.bodySize
                  onTextChanged: root.change("note", text)
                }
              }
            }
          }
        }

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: root.shellFurniture
        }
      }

      Chrome.Fab {
        colours: root.colours
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 16
        anchors.bottomMargin: 16 + root.shellFurniture
        visible: root.page === "list"
        accent: root.accent
        foreground: root.accentInk
        names: ["contact-new-symbolic", "list-add-symbolic"]
        tooltip: "A new contact"
        onClicked: root.startNew()
      }

      Chrome.Toast {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12 + root.shellFurniture
        colours: root.colours
        bodySize: root.bodySize
      }
    }
  }
}

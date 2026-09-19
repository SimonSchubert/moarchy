// Messages, in the shell: texts, by the person they are with.
//
// Three screens. **Conversations** is one row per person, newest first, with
// the ones not yet read in bold. **A conversation** is the texts themselves,
// the newest at the bottom and a field to write the next one. **New message**
// picks somebody from Contacts or takes a number.
//
// This replaces Chatty, and like Phone it replaces Chatty's daemon too: the
// shell keeps the plugin loaded, and a sleeping `gdbus monitor` hears
// ModemManager say a text arrived. What happens to that text is Threads.js --
// it is written to messages.json first and deleted from the modem after, so a
// text is never only in the one place that forgets it.
//
// SMS only. No MMS, so no pictures and no group texts; see the README.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Modem.js" as Modem
import "Numbers.js" as Numbers
import "Store.js" as Store
import "Threads.js" as Threads

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "moarchy.messages"
  readonly property bool opened: messagesWindow.visible
  readonly property var appWindow: messagesWindow

  property string returnTo: ""
  readonly property var colours: themeFile.colours
  property int bodySize: Metrics.BODY
  readonly property int shellFurniture: root.shell ? 60 : 0

  readonly property bool offline: (Quickshell.env("MOARCHY_MESSAGES_OFFLINE") || "") !== ""

  readonly property string dataDir: Plugin.dataDir(
    "messages", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_MESSAGES_DIR"))
  readonly property string contactsFile: Plugin.dataDir(
    "contacts", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_CONTACTS_DIR")) + "/contacts.json"

  readonly property color background: root.colours.background
  readonly property color ink: root.colours.foreground
  readonly property color dim: root.colours.dim
  readonly property color accent: root.colours.accent
  readonly property color red: (root.colours.hues && root.colours.hues.red) || "#e01b24"

  // --- state ------------------------------------------------------------------

  // "threads" | "thread" | "new"
  property string page: "threads"
  property string number: ""
  property string to: ""

  property bool warm: false
  property bool loaded: false
  property var messages: []
  property var strays: []
  property var people: []
  property var names: ({})

  property bool again: false
  property bool sweepWhenLoaded: false
  property int backoff: 2000
  // SMS paths waiting for the file to be written before they are deleted.
  property var toDelete: []
  property var outbox: []

  property var menuThread: null
  property bool armed: false
  property real now: Date.now()

  readonly property int unread: Threads.unread(root.messages)
  // The lists are only built while somebody can see them.
  readonly property var threads: messagesWindow.visible ? Threads.threads(root.messages) : []
  readonly property var conversation: messagesWindow.visible && root.page === "thread"
                                      ? Threads.conversation(root.messages, root.number) : []
  readonly property var candidates: Numbers.matching(root.people, root.to)
  readonly property string typedNumber: Numbers.dialable(root.to)

  // --- the plugin contract --------------------------------------------------

  Component.onCompleted: {
    root.bodySize = Metrics.shellBody(root)
    root.applyHarness()
  }

  function open(payloadJson: string): void {
    Plugin.hideOverlays(root.shell)
    root.returnTo = ""
    var to = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload.returnTo) root.returnTo = String(payload.returnTo)
      if (payload.to) to = String(payload.to)
    } catch (e) {}
    root.warmUp()
    if (to) root.openThread(to)
    messagesWindow.show()
  }

  function close(): void {
    root.menuThread = null
    root.armed = false
    messagesWindow.hide()
  }

  function dismiss(): void {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    var back = root.returnTo
    root.returnTo = ""
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, "{}")
  }

  function back(): void {
    if (root.menuThread) { root.menuThread = null; return }
    if (root.page !== "threads") { root.page = "threads"; root.number = ""; return }
    root.dismiss()
  }

  function say(text: string): void { toast.show(text) }

  function warmUp(): void {
    if (root.warm) return
    root.warm = true
    ensureDir.running = true
  }

  // --- screens --------------------------------------------------------------

  function openThread(number: string): void {
    root.number = String(number)
    root.page = "thread"
    root.readThread()
    Qt.callLater(function () { composer.focusInput() })
  }

  function readThread(): void {
    if (root.page !== "thread" || !messagesWindow.visible || !root.loaded) return
    var next = Threads.markRead(root.messages, root.number)
    if (next !== root.messages) {
      root.messages = next
      root.save()
    }
  }

  function startNew(): void {
    root.to = ""
    toField.text = ""
    root.page = "new"
    Qt.callLater(function () { toField.focusInput() })
  }

  function call(number: string): void {
    if (root.shell && typeof root.shell.summon === "function")
      root.shell.summon("moarchy.phone", JSON.stringify({ dial: number }))
    else root.say("Phone is not running here.")
  }

  // --- the file ---------------------------------------------------------------

  function save(): void {
    if (!root.loaded) return
    store.setText(Store.serialize(root.messages, root.strays))
  }

  function deleteKept(): void {
    if (root.toDelete.length === 0) return
    var paths = root.toDelete
    root.toDelete = []
    if (!root.offline) Quickshell.execDetached(Modem.deleteSmsCommand(paths))
  }

  // --- listening --------------------------------------------------------------

  function heard(line: string): void {
    root.backoff = 2000
    if (Modem.classify(line, "messages") !== Modem.IGNORE) debounce.restart()
  }

  function refresh(): void {
    if (root.offline) return
    debounce.restart()
  }

  function collect(): void {
    if (reader.running) { root.again = true; return }
    reader.running = true
  }

  function collected(code: int, text: string): void {
    if (code !== 0) return
    if (!root.loaded) {
      root.sweepWhenLoaded = true
      root.warmUp()
      return
    }
    var at = Date.now()
    var result = Threads.sweep(Modem.parseLines(text, Modem.parseSms), root.messages, at)
    if (result.add.length === 0 && result.remove.length === 0) return
    root.messages = Threads.withMessages(root.messages, result.add)
    root.toDelete = root.toDelete.concat(result.remove)
    root.readThread()
    // Written even when nothing was added, because the delete waits for the
    // write -- and a text kept on an earlier pass whose delete never landed
    // has to get one.
    root.save()
    if (result.add.length) root.arrived(result.add)
  }

  function arrived(list): void {
    root.now = Date.now()
    var last = list[list.length - 1]
    var watching = messagesWindow.visible && root.page === "thread" && Numbers.same(root.number, last.number)
    if (watching) return
    if (!root.offline) {
      ping.command = Modem.feedbackCommand("message-new-sms", false, false)
      ping.running = true
      Quickshell.execDetached(Modem.notifyCommand(Numbers.label(root.names, last.number), last.text))
    }
  }

  // --- sending ----------------------------------------------------------------

  function send(): void {
    var text = composer.text
    if (!String(text).trim().length) return
    var n = Numbers.dialable(root.number)
    if (!n) { root.say("Texts can only go to a phone number."); return }
    var m = Threads.outgoing(n, text, Date.now())
    root.messages = Threads.withMessages(root.messages, [m])
    composer.text = ""
    root.save()
    root.queue(m.id)
  }

  function retry(id: string): void {
    root.messages = Threads.withStatus(root.messages, id, "sending", Date.now())
    root.save()
    root.queue(id)
  }

  function queue(id: string): void {
    root.outbox = root.outbox.concat([id])
    root.pump()
  }

  function pump(): void {
    if (sender.running || root.outbox.length === 0) return
    var id = root.outbox[0]
    var m = Threads.find(root.messages, id)
    if (!m) { root.outbox = root.outbox.slice(1); root.pump(); return }
    if (root.offline) { root.sent(id, 1, "There is no modem here."); return }
    sender.messageId = id
    sender.command = Modem.sendCommand(m.number, m.text)
    sender.running = true
  }

  function sent(id: string, code: int, stderr: string): void {
    root.outbox = root.outbox.slice(1)
    root.messages = Threads.withStatus(root.messages, id, code === 0 ? "sent" : "failed", 0)
    root.save()
    if (code !== 0) root.say(Modem.trouble(stderr, "Not sent."))
    root.pump()
  }

  // --- the harness ----------------------------------------------------------

  property bool harnessed: false

  function applyHarness(): void {
    if ((Quickshell.env("MOARCHY_MESSAGES_PAGE") || "") === "new") root.page = "new"
  }

  function applyLoadedHarness(): void {
    var thread = Quickshell.env("MOARCHY_MESSAGES_THREAD") || ""
    if (thread) {
      root.number = thread
      root.page = "thread"
    }
    var typed = Quickshell.env("MOARCHY_MESSAGES_TYPED") || ""
    if (typed && root.page === "new") { root.to = typed; toField.text = typed }
    else if (typed) composer.text = typed
  }

  // --- processes and files ---------------------------------------------------

  Process { id: ensureDir; running: false; command: ["mkdir", "-p", root.dataDir] }

  Timer {
    interval: 5000
    running: true
    onTriggered: {
      root.warmUp()
      if (root.offline) return
      monitor.running = true
      root.refresh()
    }
  }

  Process {
    id: monitor
    running: false
    command: Modem.monitorCommand()
    stdout: SplitParser {
      onRead: function (data) { root.heard(data) }
    }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { retry.restart() }
    // qmllint enable signal-handler-parameters
  }

  Timer {
    id: retry
    interval: root.backoff
    onTriggered: {
      root.backoff = Math.min(60000, root.backoff * 2)
      monitor.running = true
      root.refresh()
    }
  }

  Timer {
    id: debounce
    interval: 150
    onTriggered: root.collect()
  }

  Process {
    id: reader
    running: false
    command: Modem.collectCommand("messages")
    stdout: StdioCollector { id: readerOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) {
      root.collected(code, readerOut.text)
      if (root.again) { root.again = false; root.collect() }
    }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: sender
    property string messageId: ""
    running: false
    stderr: StdioCollector { id: senderErr; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.sent(sender.messageId, code, senderErr.text) }
    // qmllint enable signal-handler-parameters
  }

  // fbcli ends its feedback on the first byte it can read from stdin, so the
  // pipe is held open and nothing is written to it.
  Process {
    id: ping
    running: false
    stdinEnabled: true
  }

  // The dates under the bubbles and in the list move on while the window is up.
  Timer {
    interval: 60000
    repeat: true
    running: messagesWindow.visible
    onTriggered: root.now = Date.now()
  }

  // The app is this file's only writer, so it does not watch it -- a reload
  // racing its own write would put back a text it had just moved past. The
  // modem is only told to delete what was kept once the write has landed.
  Chrome.JsonFile {
    id: store
    path: root.warm ? root.dataDir + "/messages.json" : ""
    watchChanges: false

    onParsed: function (data) {
      if (!store.path) return
      var state = Store.parse(data)
      root.messages = state.messages
      root.strays = state.strays
      root.loaded = true
      if (!root.harnessed) { root.harnessed = true; Qt.callLater(root.applyLoadedHarness) }
      if (root.sweepWhenLoaded) { root.sweepWhenLoaded = false; root.refresh() }
      Qt.callLater(root.readThread)
    }
    onSaved: root.deleteKept()
  }

  Chrome.JsonFile {
    id: contactsStore
    path: root.warm ? root.contactsFile : ""

    onParsed: function (data) {
      if (!contactsStore.path) return
      root.people = Numbers.people(data)
      root.names = Numbers.index(root.people)
    }
  }

  Chrome.ThemeFile { id: themeFile }

  IpcHandler {
    target: "messages"

    function state(): string { return root.opened ? "open" : "closed" }
    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      else { root.warmUp(); messagesWindow.show() }
      return "ok"
    }
    function close(): string { root.dismiss(); return "ok" }
    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }
    function compose(number: string): string {
      if (root.shell) root.shell.summon(root.pluginId, JSON.stringify({ to: number }))
      else { root.warmUp(); root.openThread(number); messagesWindow.show() }
      return "ok"
    }
    // For testing on the device, where ssh cannot reach the modem itself.
    function send(number: string, text: string): string {
      var n = Numbers.dialable(number)
      if (!n) return "not a number: " + number
      if (!root.loaded) return "not loaded yet"
      var m = Threads.outgoing(n, text, Date.now())
      root.messages = Threads.withMessages(root.messages, [m])
      root.save()
      root.queue(m.id)
      return m.id
    }
    function unread(): int { return root.unread }
    function settled(): bool { return root.loaded }
  }

  // --- the window -----------------------------------------------------------

  Chrome.AppWindow {
    id: messagesWindow
    shell: root.shell
    appName: "Messages"
    pluginId: root.pluginId
    color: root.background
    pageTitle: root.page === "thread" ? Numbers.label(root.names, root.number)
             : root.page === "new" ? "New message" : ""

    onMapped: {
      root.warmUp()
      root.now = Date.now()
      Qt.callLater(root.readThread)
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
            visible: root.page === "threads"
            title: "Messages"
            subtitle: root.unread > 0 ? root.unread + " unread" : ""
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize
          }

          Chrome.AppBar {
            anchors.fill: parent
            visible: root.page === "thread"
            title: Numbers.label(root.names, root.number)
            subtitle: Numbers.nameFor(root.names, root.number) ? root.number : ""
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize

            leading: Chrome.BackButton {
              colours: root.colours
              color: root.ink
              onClicked: root.back()
            }

            trailing: Chrome.IconButton {
              colours: root.colours
              visible: Numbers.dialable(root.number) !== ""
              names: ["/usr/share/icons/Adwaita/symbolic/actions/call-start-symbolic.svg", "call-start-symbolic"]
              color: root.ink
              tooltip: "Call"
              onClicked: root.call(root.number)
            }
          }

          Chrome.AppBar {
            anchors.fill: parent
            visible: root.page === "new"
            title: "New message"
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize

            leading: Chrome.BackButton {
              colours: root.colours
              color: root.ink
              onClicked: root.back()
            }
          }
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          // ========== conversations ==========

          Item {
            anchors.fill: parent
            visible: root.page === "threads"

            Chrome.EmptyState {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Metrics.GUTTER
              anchors.topMargin: 40
              visible: root.loaded && root.messages.length === 0
              colours: root.colours
              bodySize: root.bodySize
              names: ["/usr/share/icons/Adwaita/symbolic/actions/chat-message-new-symbolic.svg", "chat-message-new-symbolic"]
              title: "No messages yet"
              detail: "Texts you send and get are kept here. Tap + to write one."
            }

            Chrome.ListFrame {
              id: threadsFrame
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Metrics.GUTTER
              // Stops short of the + in the corner, so it never sits on a row.
              height: Math.min(parent.height - Metrics.GUTTER - Metrics.FAB - 16 - Metrics.GAP,
                               threadList.contentHeight + threadsFrame.pad * 2)
              visible: root.threads.length > 0
              colours: root.colours

              ListView {
                id: threadList
                anchors.fill: parent
                boundsBehavior: Flickable.StopAtBounds
                model: root.threads

                delegate: Chrome.ListRow {
                  id: threadRow
                  required property var modelData
                  readonly property var thread: threadRow.modelData
                  readonly property string label: Numbers.label(root.names, threadRow.thread.number)

                  width: ListView.view.width
                  minHeight: 64
                  radius: threadsFrame.innerRadius
                  colours: root.colours
                  bodySize: root.bodySize
                  title: threadRow.label
                  titleWeight: threadRow.thread.unread > 0 ? Font.DemiBold : Font.Normal
                  subtitle: Threads.preview(threadRow.thread.last)
                  subtitleColour: threadRow.thread.unread > 0 ? root.ink : root.dim
                  onClicked: root.openThread(threadRow.thread.number)
                  onHeld: root.menuThread = threadRow.thread

                  leading: Rectangle {
                    width: 40
                    height: 40
                    radius: Metrics.round(root.colours, 40)
                    color: Theme.surface(root.colours, "raised")

                    Chrome.TypedText {
                      anchors.centerIn: parent
                      visible: Numbers.nameFor(root.names, threadRow.thread.number) !== ""
                      role: "subtitle"
                      text: threadRow.label.charAt(0).toUpperCase()
                      color: root.ink
                      bodySize: root.bodySize
                    }

                    Chrome.Icon {
                      anchors.centerIn: parent
                      visible: Numbers.nameFor(root.names, threadRow.thread.number) === ""
                      slot: 24
                      size: 18
                      color: root.dim
                      names: ["/usr/share/icons/Adwaita/symbolic/status/avatar-default-symbolic.svg", "avatar-default-symbolic"]
                    }
                  }

                  trailing: Column {
                    spacing: 6

                    Chrome.TypedText {
                      anchors.right: parent.right
                      role: "caption"
                      text: Threads.when(threadRow.thread.last.at, root.now)
                      color: threadRow.thread.unread > 0 ? root.accent : root.dim
                      bodySize: root.bodySize
                    }

                    Rectangle {
                      anchors.right: parent.right
                      visible: threadRow.thread.unread > 0
                      width: Math.max(18, unreadCount.implicitWidth + 10)
                      height: 18
                      radius: 9
                      color: root.accent

                      Text {
                        id: unreadCount
                        anchors.centerIn: parent
                        text: String(threadRow.thread.unread)
                        color: Theme.inkOn(root.colours, root.accent)
                        font.family: Metrics.FONT
                        font.weight: Font.DemiBold
                        font.pixelSize: Metrics.typeSize(root.bodySize, "overline")
                      }
                    }
                  }
                }
              }
            }
          }

          // ========== a conversation ==========

          ColumnLayout {
            anchors.fill: parent
            visible: root.page === "thread"
            spacing: 0

            ListView {
              id: bubbles
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.leftMargin: Metrics.GUTTER
              Layout.rightMargin: Metrics.GUTTER
              clip: true
              spacing: Metrics.GAP
              boundsBehavior: Flickable.StopAtBounds
              // Newest first, drawn from the bottom up: the list opens on the
              // latest text without being scrolled there, and a new one pushes
              // the rest up rather than landing out of sight.
              verticalLayoutDirection: ListView.BottomToTop
              model: root.conversation
              header: Item { width: 1; height: Metrics.GAP }
              footer: Item { width: 1; height: Metrics.GAP }

              delegate: Item {
                id: bubble
                required property var modelData
                readonly property var message: bubble.modelData
                readonly property bool mine: bubble.message.dir === "out"
                readonly property bool failed: bubble.message.status === "failed"

                width: ListView.view.width
                height: box.height

                Rectangle {
                  id: box
                  anchors.right: bubble.mine ? parent.right : undefined
                  anchors.left: bubble.mine ? undefined : parent.left
                  width: Math.min(bubble.width * 0.8,
                                  Math.max(body.implicitWidth, meta.implicitWidth) + Metrics.PAD * 2)
                  height: body.implicitHeight + meta.implicitHeight + Metrics.PAD * 2 + 2
                  radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
                  color: bubble.failed
                         ? Theme.tint(root.colours, root.red, "card")
                         : bubble.mine
                           ? Theme.tint(root.colours, root.accent, "raised")
                           : Theme.surface(root.colours, "card")

                  Text {
                    id: body
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Metrics.PAD
                    // Plain text, always: a text is whatever somebody sent,
                    // and "<b>" in it is three characters, not bold.
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    text: bubble.message.text
                    color: root.ink
                    font.family: Metrics.FONT
                    font.pixelSize: Metrics.typeSize(root.bodySize, "body")
                  }

                  Text {
                    id: meta
                    anchors.top: body.bottom
                    anchors.topMargin: 2
                    anchors.right: bubble.mine ? parent.right : undefined
                    anchors.left: bubble.mine ? undefined : parent.left
                    anchors.leftMargin: Metrics.PAD
                    anchors.rightMargin: Metrics.PAD
                    textFormat: Text.PlainText
                    text: bubble.message.status === "sending" ? "Sending…"
                        : bubble.failed ? "Not sent · tap to retry"
                        : Threads.stamp(bubble.message.at, root.now)
                    color: bubble.failed ? root.red : root.dim
                    font.family: Metrics.FONT
                    font.pixelSize: Metrics.typeSize(root.bodySize, "caption")
                  }

                  MouseArea {
                    anchors.fill: parent
                    enabled: bubble.failed
                    onClicked: root.retry(bubble.message.id)
                  }
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.leftMargin: Metrics.GUTTER
              Layout.rightMargin: Metrics.GUTTER
              Layout.topMargin: Metrics.GAP
              Layout.bottomMargin: Metrics.GAP
              spacing: Metrics.GAP

              Chrome.TextField {
                id: composer
                Layout.fillWidth: true
                Layout.preferredHeight: Metrics.TARGET
                placeholderText: "Text message"
                colours: root.colours
                level: "card"
                foreground: root.ink
                accent: root.accent
                iconColor: root.dim
                bodySize: root.bodySize
                onAccepted: root.send()
              }

              // Send: an arrow in the accent, as a disc the size of the field,
              // dimmed until there is something to send.
              Rectangle {
                id: sendButton
                Layout.preferredWidth: Metrics.TARGET
                Layout.preferredHeight: Metrics.TARGET
                enabled: composer.text.trim().length > 0
                opacity: enabled ? 1 : 0.38
                radius: Metrics.round(root.colours, Metrics.TARGET)
                color: root.accent
                Accessible.role: Accessible.Button
                Accessible.name: "Send"
                Accessible.onPressAction: root.send()

                Chrome.Icon {
                  anchors.centerIn: parent
                  slot: 24
                  size: Metrics.ICON_INK
                  color: Theme.inkOn(root.colours, root.accent)
                  names: ["/usr/share/icons/Adwaita/symbolic/actions/go-up-symbolic.svg", "go-up-symbolic"]
                }

                Chrome.PressVeil {
                  anchors.fill: parent
                  radius: parent.radius
                  ink: Theme.inkOn(root.colours, root.accent)
                  on: sendTap.pressed
                }

                MouseArea {
                  id: sendTap
                  anchors.fill: parent
                  enabled: sendButton.enabled
                  onClicked: root.send()
                }
              }
            }
          }

          // ========== new message ==========

          ColumnLayout {
            anchors.fill: parent
            visible: root.page === "new"
            spacing: 0

            Chrome.TextField {
              id: toField
              Layout.fillWidth: true
              Layout.leftMargin: Metrics.GUTTER
              Layout.rightMargin: Metrics.GUTTER
              Layout.topMargin: 4
              Layout.bottomMargin: Metrics.GAP
              placeholderText: "Name or number"
              colours: root.colours
              level: "card"
              foreground: root.ink
              accent: root.accent
              iconColor: root.dim
              bodySize: root.bodySize
              onTextChanged: root.to = text
              onAccepted: {
                if (root.typedNumber) root.openThread(root.typedNumber)
                else if (root.candidates.length) root.openThread(root.candidates[0].phone)
              }
            }

            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true

              Chrome.ListFrame {
                id: pickFrame
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Metrics.GUTTER
                anchors.rightMargin: Metrics.GUTTER
                height: Math.min(parent.height - Metrics.GUTTER,
                                 pickList.contentHeight + pickFrame.pad * 2)
                visible: root.typedNumber !== "" || root.candidates.length > 0
                colours: root.colours

                ListView {
                  id: pickList
                  anchors.fill: parent
                  boundsBehavior: Flickable.StopAtBounds
                  model: messagesWindow.visible && root.page === "new" ? root.candidates : []

                  // A number nobody in Contacts has, as the first row.
                  header: Chrome.ListRow {
                    width: ListView.view.width
                    height: visible ? implicitHeight : 0
                    visible: root.typedNumber !== ""
                    radius: pickFrame.innerRadius
                    colours: root.colours
                    bodySize: root.bodySize
                    title: root.typedNumber
                    subtitle: "Text this number"
                    onClicked: root.openThread(root.typedNumber)
                  }

                  delegate: Chrome.ListRow {
                    id: pickRow
                    required property var modelData
                    width: ListView.view.width
                    radius: pickFrame.innerRadius
                    colours: root.colours
                    bodySize: root.bodySize
                    title: pickRow.modelData.name
                    subtitle: pickRow.modelData.phone
                    onClicked: root.openThread(pickRow.modelData.phone)
                  }
                }
              }

              Chrome.EmptyState {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Metrics.GUTTER
                anchors.topMargin: 40
                visible: !pickFrame.visible
                colours: root.colours
                bodySize: root.bodySize
                names: ["/usr/share/icons/Adwaita/symbolic/status/avatar-default-symbolic.svg", "avatar-default-symbolic"]
                title: root.to.length ? "Nobody by that name" : "Who to?"
                detail: root.to.length
                        ? "Type their number instead."
                        : "Type a name from Contacts, or a number."
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
        visible: root.page === "threads"
        accent: root.accent
        foreground: Theme.inkOn(root.colours, root.accent)
        names: ["/usr/share/icons/Adwaita/symbolic/actions/chat-message-new-symbolic.svg", "list-add-symbolic"]
        tooltip: "A new message"
        onClicked: root.startNew()
      }

      Chrome.ContextMenu {
        open: root.menuThread !== null
        placement: "center"
        colours: root.colours
        background: root.background
        foreground: root.ink
        danger: root.red
        bodySize: root.bodySize
        onDismissed: { root.menuThread = null; root.armed = false }

        Chrome.MenuItem {
          colours: root.colours
          visible: !!root.menuThread && Numbers.dialable(root.menuThread.number) !== ""
          names: ["/usr/share/icons/Adwaita/symbolic/actions/call-start-symbolic.svg", "call-start-symbolic"]
          text: "Call"
          foreground: root.ink
          bodySize: root.bodySize
          onClicked: {
            var n = root.menuThread.number
            root.menuThread = null
            root.call(n)
          }
        }

        // Twice, because it is every text with somebody and there is no undo.
        Chrome.MenuItem {
          colours: root.colours
          names: ["user-trash-symbolic"]
          text: root.armed ? "Tap again to delete" : "Delete conversation"
          destructive: true
          danger: root.red
          foreground: root.ink
          bodySize: root.bodySize
          onClicked: {
            if (!root.armed) { root.armed = true; return }
            var n = root.menuThread.number
            root.armed = false
            root.menuThread = null
            root.messages = Threads.withoutThread(root.messages, n)
            root.save()
          }
        }
      }

      Chrome.Toast {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 72 + root.shellFurniture
        z: 60
        colours: root.colours
        bodySize: root.bodySize
      }
    }
  }
}

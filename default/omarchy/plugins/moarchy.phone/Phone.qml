// Phone, in the shell: a keypad, the calls that happened, and the one
// happening now.
//
// Three tabs and a screen over them. **Keypad** dials. **Recents** is the log,
// newest first, with the missed calls in red. **Contacts** is everybody in
// Contacts' own file who has a number, one tap from a call. Whenever a call is
// up -- dialling, ringing, answered, ending -- the call screen covers all
// three.
//
// This replaces gnome-calls, and the part of gnome-calls that mattered most
// was never its window: it was the daemon that listened for a ring. Here that
// is the plugin itself. The shell keeps it loaded, and a `gdbus monitor` it
// starts a few seconds after the shell does sleeps on the system bus until
// ModemManager says something about a call. Modem.js has the rest of how the
// modem is spoken to, and Calls.js what is remembered about a call between
// two reads of it.
//
// What it costs while nobody is on the phone: one sleeping gdbus, and nothing
// else. No timer runs while there is no call, and the log's list is not built
// until the window is open.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Calls.js" as Calls
import "Modem.js" as Modem
import "Numbers.js" as Numbers
import "Store.js" as Store

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "moarchy.phone"
  readonly property bool opened: phoneWindow.visible
  readonly property var appWindow: phoneWindow

  property string returnTo: ""
  readonly property var colours: themeFile.colours
  property int bodySize: Metrics.BODY
  readonly property int shellFurniture: root.shell ? 60 : 0

  // The check harness runs with no modem and no system bus. So does a
  // screenshot, which also stages a call to photograph.
  readonly property bool offline: (Quickshell.env("MOARCHY_PHONE_OFFLINE") || "") !== ""
  readonly property string fake: Quickshell.env("MOARCHY_PHONE_FAKE_CALL") || ""

  readonly property string dataDir: Plugin.dataDir(
    "phone", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_PHONE_DIR"))
  readonly property string contactsFile: Plugin.dataDir(
    "contacts", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_CONTACTS_DIR")) + "/contacts.json"

  readonly property color background: root.colours.background
  readonly property color ink: root.colours.foreground
  readonly property color dim: root.colours.dim
  readonly property color accent: root.colours.accent
  readonly property color green: (root.colours.hues && root.colours.hues.green) || "#33d17a"
  readonly property color red: (root.colours.hues && root.colours.hues.red) || "#e01b24"

  // --- state ------------------------------------------------------------------

  // 0 keypad, 1 recents, 2 contacts
  property int page: 0
  property string typed: ""
  property string query: ""

  // Nothing is read from disk until the shell has finished starting or the
  // window opens, whichever is first.
  property bool warm: false
  property bool loaded: false
  property var log: []
  property var strays: []
  property real seenMissed: 0
  property var pendingLog: []

  property var people: []
  property var names: ({})

  // What the modem said last, and what has been learned about each call.
  property var calls: []
  property var seen: ({})
  property int failures: 0
  property bool again: false
  property int backoff: 2000

  property bool audioOn: false
  property bool muted: false
  property bool speaker: false
  property bool dtmfOpen: false
  property string dtmfSent: ""
  property string dtmfQueue: ""

  // The number being dialled before ModemManager has a call for it.
  property string dialling: ""
  property bool hungUp: false
  // A call that just ended, held on the screen for a moment.
  property var ended: null
  property string ringPath: ""
  property bool raisedForCall: false
  property bool wasLocked: false

  property var menuEntry: null
  property real now: Date.now()

  readonly property var live: Calls.live(root.calls)
  readonly property var current: Calls.primary(root.calls)
  readonly property var incoming: Calls.ringing(root.calls)
  readonly property var second: Calls.waiting(root.calls)
  readonly property bool onCall: root.live.length > 0 || root.ended !== null || root.dialling !== ""
  readonly property int missed: Calls.unseenMissed(root.log, root.seenMissed)
  readonly property var shownPeople: Numbers.matching(root.people, root.query)
  readonly property var typedMatch: {
    var d = Numbers.digits(root.typed)
    if (d.length < 3) return null
    var hits = Numbers.matching(root.people, d)
    return hits.length ? hits[0] : null
  }

  readonly property string callLabel: root.current
    ? Numbers.label(root.names, root.current.number)
    : root.ended ? root.ended.label : Numbers.label(root.names, root.dialling)
  readonly property string callNumber: root.current
    ? root.current.number
    : root.ended ? root.ended.number : root.dialling

  readonly property string callState: {
    if (root.ended) return root.ended.text
    var c = root.current
    if (!c) return "Calling…"
    if (c.state === "ringing-in") return "Incoming call"
    if (c.state === "ringing-out") return "Ringing…"
    if (c.state === "active")
      return Calls.duration((root.now - Calls.since(root.seen, c.path)) / 1000)
    if (c.state === "held") return "On hold"
    if (c.state === "waiting") return "Waiting"
    return "Calling…"
  }

  readonly property bool callUp: !!root.current && root.current.state !== "ringing-in"
                                 && root.ended === null

  // --- the plugin contract --------------------------------------------------

  Component.onCompleted: {
    root.bodySize = Metrics.shellBody(root)
    root.applyHarness()
  }

  function open(payloadJson: string): void {
    Plugin.hideOverlays(root.shell)
    root.returnTo = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload.returnTo) root.returnTo = String(payload.returnTo)
      if (payload.dial) {
        root.typed = Numbers.dialable(payload.dial)
        root.page = 0
      }
    } catch (e) {}
    root.warmUp()
    phoneWindow.show()
  }

  // `close()` has to take the window down (Clock.qml says why). The one thing
  // it will not do is hide a call that is ringing: a stray tap on the app drawer
  // icon must not be how somebody misses a call.
  function close(): void {
    root.menuEntry = null
    if (root.incoming) return
    phoneWindow.hide()
  }

  function dismiss(): void {
    if (root.incoming) return
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    var back = root.returnTo
    root.returnTo = ""
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, "{}")
  }

  function back(): void {
    if (root.menuEntry) { root.menuEntry = null; return }
    if (root.dtmfOpen) { root.dtmfOpen = false; return }
    root.dismiss()
  }

  // Up for something the modem decided, not for something a thumb did.
  function raise(): void {
    if (root.shell && typeof root.shell.summon === "function") {
      root.shell.summon(root.pluginId, "{}")
      return
    }
    phoneWindow.show()
  }

  function say(text: string): void { toast.show(text) }

  function warmUp(): void {
    if (root.warm) return
    root.warm = true
    ensureDir.running = true
  }

  // --- the log -----------------------------------------------------------------

  function save(): void {
    if (!root.loaded) return
    store.setText(Store.serialize(root.log, root.strays, root.seenMissed))
  }

  function logCall(entry): void {
    if (!root.loaded) {
      root.pendingLog = root.pendingLog.concat([entry])
      root.warmUp()
      return
    }
    root.log = Calls.withEntry(root.log, entry)
    root.save()
  }

  function forget(id: string): void {
    root.log = Calls.without(root.log, id)
    root.save()
  }

  function markSeen(): void {
    if (!root.loaded || root.missed === 0) return
    root.seenMissed = Date.now()
    root.save()
  }

  // --- listening --------------------------------------------------------------

  function heard(line: string): void {
    root.backoff = 2000
    if (Modem.classify(line, "calls") !== Modem.IGNORE) debounce.restart()
  }

  function refresh(): void {
    if (root.offline || root.fake !== "") return
    debounce.restart()
  }

  function collect(): void {
    if (reader.running) { root.again = true; return }
    reader.running = true
  }

  function collected(code: int, text: string): void {
    if (code !== 0) {
      // No list is not an empty list. Only when the modem has stayed silent
      // for three reads in a row are its calls taken to be gone with it.
      root.failures += 1
      if (root.failures < 3 || root.live.length === 0) return
      text = ""
    } else {
      root.failures = 0
    }
    var at = Date.now()
    var list = Modem.parseLines(text, Modem.parseCall)
    var step = Calls.follow(root.seen, list, at)
    root.seen = step.seen
    root.calls = list
    root.now = at
    if (list.length) root.dialling = ""
    for (var i = 0; i < step.ended.length; i++) root.logCall(step.ended[i])
    if (step.finished.length) Quickshell.execDetached(Modem.deleteCallsCommand(step.finished))
    root.react(step.ended)
  }

  // Everything a change in the calls sets off: the ring, the screen, the
  // audio, and the moment of "Call ended".
  function react(endedNow): void {
    var ringer = root.incoming || root.second
    var path = ringer ? ringer.path : ""
    if (path !== root.ringPath) {
      root.stopRing()
      root.ringPath = path
      if (path) {
        var alone = !!root.incoming
        if (alone) {
          root.raisedForCall = !root.opened
          if (!root.offline) wake.running = true
          root.warmUp()
          root.raise()
        }
        root.startRing(!alone)
      }
    }

    var want = Calls.audioWanted(root.calls)
    if (want !== root.audioOn) {
      root.audioOn = want
      if (!root.offline && root.fake === "") {
        Quickshell.execDetached(Modem.callAudioCommand("SelectMode", "u", want ? 1 : 0))
        if (!want) {
          Quickshell.execDetached(Modem.callAudioCommand("EnableSpeaker", "b", "false"))
          Quickshell.execDetached(Modem.callAudioCommand("MuteMic", "b", "false"))
        }
      }
    }

    if (root.live.length === 0 && endedNow.length > 0 && root.ended === null) {
      var last = endedNow[endedNow.length - 1]
      root.ended = {
        label: Numbers.label(root.names, last.number),
        number: last.number,
        text: last.answered ? "Call ended · " + Calls.duration(last.seconds)
                            : last.missed ? "Missed call" : "Call ended"
      }
      root.muted = false
      root.speaker = false
      root.dtmfOpen = false
      root.dtmfSent = ""
      linger.restart()
    }
  }

  function afterCall(): void {
    root.ended = null
    if (root.live.length > 0) return
    if (root.wasLocked) {
      root.wasLocked = false
      if (!root.offline) Quickshell.execDetached(Modem.lockCommand())
    }
    if (root.raisedForCall) {
      root.raisedForCall = false
      root.dismiss()
    }
  }

  // --- what a thumb does ----------------------------------------------------

  function dial(number: string): void {
    var n = Numbers.dialable(number)
    if (!n) { root.say(Numbers.text(number) ? "That is not a number this can dial." : "Type a number first."); return }
    if (root.offline || root.fake !== "") { root.say("There is no modem here."); return }
    if (root.live.length > 0 || dialer.running) { root.say("There is already a call."); return }
    root.hungUp = false
    root.ended = null
    root.dialling = n
    root.warmUp()
    dialer.command = Modem.dialCommand(n)
    dialer.running = true
  }

  function act(command, failure: string): void {
    if (root.offline || root.fake !== "" || command.length === 0) return
    if (action.running) { Quickshell.execDetached(command); return }
    action.failure = failure
    action.command = command
    action.running = true
  }

  function answer(): void {
    if (root.incoming) root.act(Modem.acceptCommand(root.incoming.path), "Could not answer.")
  }

  function decline(): void {
    var c = root.incoming || root.second
    if (!c) return
    root.seen = Calls.decline(root.seen, c.path)
    root.stopRing()
    root.act(Modem.hangupCommand(c.path), "Could not decline.")
  }

  function hangUp(): void {
    root.hungUp = true
    if (root.current) root.act(Modem.hangupCommand(root.current.path), "Could not hang up.")
    else root.act(Modem.hangupAllCommand(), "Could not hang up.")
    if (!root.current) root.dialling = ""
  }

  function endAndAnswer(): void {
    root.stopRing()
    root.act(Modem.hangupAndAcceptCommand(), "Could not switch calls.")
  }

  function toggleMute(): void {
    root.muted = !root.muted
    if (!root.offline && root.fake === "")
      Quickshell.execDetached(Modem.callAudioCommand("MuteMic", "b", root.muted ? "true" : "false"))
  }

  function toggleSpeaker(): void {
    root.speaker = !root.speaker
    if (!root.offline && root.fake === "")
      Quickshell.execDetached(Modem.callAudioCommand("EnableSpeaker", "b", root.speaker ? "true" : "false"))
  }

  // One tone at a time, in the order they were pressed.
  function sendTone(key: string): void {
    root.dtmfSent = (root.dtmfSent + key).slice(-24)
    if (!root.current || root.current.state !== "active") return
    root.dtmfQueue += key
    root.nextTone()
  }

  function nextTone(): void {
    if (dtmf.running || root.dtmfQueue.length === 0 || !root.current) return
    var key = root.dtmfQueue.charAt(0)
    root.dtmfQueue = root.dtmfQueue.slice(1)
    if (root.offline || root.fake !== "") return
    dtmf.command = Modem.dtmfCommand(root.current.path, key)
    dtmf.running = true
  }

  function press(key: string): void {
    if (root.typed.length >= 32) return
    root.typed += key
  }

  function backspace(): void {
    root.typed = root.typed.slice(0, -1)
  }

  // --- the ring -------------------------------------------------------------

  // Players tried when feedbackd is not there to ask, the way Clock finds one.
  readonly property var players: [
    ["pw-play", "/usr/share/sounds/freedesktop/stereo/phone-incoming-call.oga"],
    ["paplay", "/usr/share/sounds/freedesktop/stereo/phone-incoming-call.oga"],
    ["canberra-gtk-play", "-i", "phone-incoming-call"]
  ]
  property int player: 0
  property bool ringOn: false
  property bool fallback: false
  property real ringStarted: 0

  function startRing(quiet: bool): void {
    if (root.offline || root.fake !== "") return
    root.ringOn = true
    root.fallback = false
    root.ringStarted = Date.now()
    ringer.command = Modem.feedbackCommand("phone-incoming-call", true, quiet)
    ringer.running = true
  }

  function stopRing(): void {
    root.ringOn = false
    root.fallback = false
    gap.stop()
    chime.running = false
    ringer.running = false
  }

  // fbcli is feedbackd's, and feedbackd knows the phone's profile: a ring, a
  // buzz, or nothing. It is only second-guessed when it is not installed or
  // could not reach the daemon -- never when it found that the profile says
  // silent, because that is an answer.
  function ringerEnded(code: int, said: string): void {
    if (!root.ringOn || root.fallback) return
    if (said.indexOf("No feedback found") >= 0) return
    if (code === 127 || Date.now() - root.ringStarted < 2000) {
      root.fallback = true
      root.player = 0
      root.playOnce()
    }
  }

  function playOnce(): void {
    if (!root.ringOn || !root.fallback) return
    if (root.player >= root.players.length) return
    var spec = root.players[root.player]
    var line = "exec \"$0\""
    for (var i = 1; i < spec.length; i++) line += " \"$" + i + "\""
    chime.command = ["sh", "-c", line].concat(spec)
    chime.running = true
  }

  function toneEnded(code: int): void {
    if (!root.ringOn || !root.fallback) return
    if (code !== 0) { root.player += 1; root.playOnce(); return }
    gap.restart()
  }

  // --- the harness ----------------------------------------------------------

  function applyHarness(): void {
    var page = Quickshell.env("MOARCHY_PHONE_PAGE") || ""
    if (page === "recents") root.page = 1
    else if (page === "contacts") root.page = 2
    var typed = Quickshell.env("MOARCHY_PHONE_TYPED") || ""
    if (typed) root.typed = Numbers.dialable(typed)
    if (root.fake === "") return

    var number = Quickshell.env("MOARCHY_PHONE_FAKE_NUMBER") || "+44 7700 900030"
    var at = Date.now()
    var first = { path: "/fake/1", number: number, direction: "incoming", state: "active", reason: "" }
    var list = [first]
    if (root.fake === "ringing") first.state = "ringing-in"
    else if (root.fake === "dialing") { first.state = "ringing-out"; first.direction = "outgoing" }
    else if (root.fake === "waiting")
      list.push({ path: "/fake/2", number: "+49 30 5550188", direction: "incoming", state: "waiting", reason: "" })
    root.calls = list
    var seen = Calls.follow({}, list, at - 83000).seen
    if (first.state === "active") seen["/fake/1"].activeAt = at - 83000
    root.seen = seen
    root.now = at
    if (root.fake === "keypad") { root.dtmfOpen = true; root.dtmfSent = "1#" }
    root.warmUp()
  }

  // --- processes and files ---------------------------------------------------

  Process { id: ensureDir; running: false; command: ["mkdir", "-p", root.dataDir] }

  // The shell is still coming up for the first few seconds, and nothing here
  // needs to be part of that.
  Timer {
    interval: 5000
    running: true
    onTriggered: {
      root.warmUp()
      if (root.offline || root.fake !== "") return
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
    command: Modem.collectCommand("calls")
    stdout: StdioCollector { id: readerOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) {
      root.collected(code, readerOut.text)
      if (root.again) { root.again = false; root.collect() }
    }
    // qmllint enable signal-handler-parameters
  }

  // The clock on the call screen, and a read every five seconds in case a
  // signal went by unheard. Only while there is a call and a window to show it.
  property int ticks: 0
  Timer {
    interval: 1000
    repeat: true
    running: phoneWindow.visible && root.onCall
    onTriggered: {
      root.now = Date.now()
      root.ticks += 1
      if (root.ticks % 5 === 0 && root.live.length > 0) root.refresh()
    }
  }

  Timer {
    id: linger
    interval: 2000
    onTriggered: root.afterCall()
  }

  Process {
    id: dialer
    running: false
    stderr: StdioCollector { id: dialerErr; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) {
      if (code !== 0 && !root.hungUp) root.say(Modem.trouble(dialerErr.text, "Could not call."))
      if (code !== 0 && root.live.length === 0) root.dialling = ""
      root.refresh()
    }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: action
    property string failure: ""
    running: false
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) {
      if (code !== 0) root.say(Modem.trouble(actionErr.text, action.failure))
      root.refresh()
    }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: dtmf
    running: false
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.nextTone() }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: ringer
    running: false
    stdinEnabled: true
    stdout: StdioCollector { id: ringerOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.ringerEnded(code, ringerOut.text) }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: chime
    running: false
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.toneEnded(code) }
    // qmllint enable signal-handler-parameters
  }

  Timer {
    id: gap
    interval: 1200
    onTriggered: root.playOnce()
  }

  Process {
    id: wake
    running: false
    command: Modem.wakeCommand()
    stdout: StdioCollector { id: wakeOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) {
      if (wakeOut.text.indexOf("locked") >= 0) root.wasLocked = true
    }
    // qmllint enable signal-handler-parameters
  }

  // The app is this file's only writer, so it does not watch it: a reload
  // racing the app's own write would put back a log it had just added to.
  Chrome.JsonFile {
    id: store
    path: root.warm ? root.dataDir + "/calls.json" : ""
    watchChanges: false

    onParsed: function (data) {
      if (!store.path) return
      var state = Store.parse(data)
      root.strays = state.strays
      root.seenMissed = state.seen
      var list = state.log
      for (var i = 0; i < root.pendingLog.length; i++) list = Calls.withEntry(list, root.pendingLog[i])
      root.log = list
      root.loaded = true
      // Not from inside the read: a write started in its own completion
      // handler is one FileView drops and complains about.
      if (root.pendingLog.length) { root.pendingLog = []; Qt.callLater(root.save) }
      if (root.page === 1 && phoneWindow.visible) Qt.callLater(root.markSeen)
    }
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
    target: "phone"

    function state(): string {
      if (root.current) return root.current.state || "calling"
      return root.opened ? "open" : "closed"
    }
    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      else { root.warmUp(); phoneWindow.show() }
      return "ok"
    }
    function close(): string { root.dismiss(); return "ok" }
    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }
    // Puts a number on the keypad. Never dials: that is a tap.
    function dial(number: string): string {
      var n = Numbers.dialable(number)
      if (!n) return "not a number: " + number
      root.typed = n
      root.page = 0
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      else { root.warmUp(); phoneWindow.show() }
      return "ok"
    }
    // For testing on the device, where ssh cannot reach the modem itself.
    function call(number: string): string { root.dial(number); return root.dialling || "no" }
    function answer(): string { root.answer(); return "ok" }
    function hangup(): string { root.hangUp(); return "ok" }
    function calls(): string { return JSON.stringify(root.calls) }
    function settled(): bool { return root.loaded }
  }

  // --- the window -----------------------------------------------------------

  Chrome.AppWindow {
    id: phoneWindow
    shell: root.shell
    appName: "Phone"
    pluginId: root.pluginId
    color: root.background
    pageTitle: root.onCall ? "Call" : ["Keypad", "Recents", "Contacts"][root.page]

    onMapped: {
      root.warmUp()
      if (root.page === 1) root.markSeen()
    }

    Rectangle {
      anchors.fill: parent
      color: root.background
      focus: true

      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true; return }
        if (root.onCall || root.page !== 0) return
        if (event.key === Qt.Key_Backspace) { root.backspace(); event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.dial(root.typed); event.accepted = true; return
        }
        if (/^[0-9*#+]$/.test(event.text)) { root.press(event.text); event.accepted = true }
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Chrome.AppBar {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 12
          title: ["Phone", "Recents", "Contacts"][root.page]
          subtitle: root.page === 1 && root.missed > 0
                    ? root.missed + (root.missed === 1 ? " missed call" : " missed calls")
                    : root.page === 2 && root.people.length > 0
                      ? root.people.length + (root.people.length === 1 ? " number" : " numbers")
                      : ""
          foreground: root.ink
          dim: root.dim
          bodySize: root.bodySize
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          // ========== keypad ==========

          ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: Metrics.GUTTER
            anchors.rightMargin: Metrics.GUTTER
            anchors.bottomMargin: Metrics.GUTTER
            visible: root.page === 0
            spacing: Metrics.GAP

            Item { Layout.fillHeight: true }

            // The number, and who it is. A box, like Calculator's display, and
            // for the same reason: what is being typed is the one thing on the
            // screen that has to be read while it changes.
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 92
              radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
              color: Theme.surface(root.colours, "card")

              Chrome.TypedText {
                anchors.left: parent.left
                anchors.right: backKey.left
                anchors.leftMargin: Metrics.PAD + Metrics.TARGET
                anchors.top: parent.top
                anchors.topMargin: root.typedMatch ? 12 : 26
                role: "title"
                font.pixelSize: Math.round(root.bodySize * 1.9)
                font.weight: Font.Normal
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideLeft
                maximumLineCount: 1
                text: root.typed.length ? root.typed : " "
                color: root.ink
                bodySize: root.bodySize
              }

              Chrome.TypedText {
                anchors.left: parent.left
                anchors.right: backKey.left
                anchors.leftMargin: Metrics.PAD + Metrics.TARGET
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                visible: !!root.typedMatch
                role: "caption"
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                text: root.typedMatch ? root.typedMatch.name + " · " + root.typedMatch.phone : ""
                color: root.accent
                bodySize: root.bodySize

                MouseArea {
                  anchors.fill: parent
                  onClicked: if (root.typedMatch) root.typed = Numbers.dialable(root.typedMatch.phone)
                }
              }

              Chrome.IconButton {
                id: backKey
                anchors.right: parent.right
                anchors.rightMargin: Metrics.GAP
                anchors.verticalCenter: parent.verticalCenter
                visible: root.typed.length > 0
                colours: root.colours
                names: ["/usr/share/icons/Adwaita/symbolic/actions/edit-clear-symbolic.svg", "edit-clear-symbolic"]
                color: root.dim
                tooltip: "Delete a digit"

                // Hold to clear. A MouseArea of its own, over IconButton's,
                // because the kit's button has no long press.
                MouseArea {
                  anchors.fill: parent
                  onClicked: root.backspace()
                  onPressAndHold: root.typed = ""
                }
              }
            }

            GridLayout {
              Layout.fillWidth: true
              columns: 3
              columnSpacing: Metrics.GAP
              rowSpacing: Metrics.GAP

              Repeater {
                model: [
                  { d: "1", l: "" }, { d: "2", l: "ABC" }, { d: "3", l: "DEF" },
                  { d: "4", l: "GHI" }, { d: "5", l: "JKL" }, { d: "6", l: "MNO" },
                  { d: "7", l: "PQRS" }, { d: "8", l: "TUV" }, { d: "9", l: "WXYZ" },
                  { d: "*", l: "" }, { d: "0", l: "+" }, { d: "#", l: "" }
                ]

                delegate: DialKey {
                  id: dialKey
                  required property var modelData
                  Layout.fillWidth: true
                  Layout.preferredHeight: 62
                  colours: root.colours
                  bodySize: root.bodySize
                  digit: dialKey.modelData.d
                  letters: dialKey.modelData.l
                  onClicked: root.press(dialKey.modelData.d)
                  onHeld: root.press(dialKey.modelData.d === "0" ? "+" : dialKey.modelData.d)
                }
              }
            }

            CallButton {
              Layout.alignment: Qt.AlignHCenter
              Layout.topMargin: 4
              colours: root.colours
              bodySize: root.bodySize
              size: 64
              hue: root.green
              names: ["/usr/share/icons/Adwaita/symbolic/actions/call-start-symbolic.svg", "call-start-symbolic"]
              text: "Call"
              onClicked: root.dial(root.typed)
            }
          }

          // ========== recents ==========

          Item {
            anchors.fill: parent
            visible: root.page === 1

            Chrome.EmptyState {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Metrics.GUTTER
              anchors.topMargin: 40
              visible: root.loaded && root.log.length === 0
              colours: root.colours
              bodySize: root.bodySize
              names: ["/usr/share/icons/Adwaita/symbolic/actions/document-open-recent-symbolic.svg", "document-open-recent-symbolic"]
              title: "No calls yet"
              detail: "Calls you make and get are listed here."
            }

            Chrome.ListFrame {
              id: recentsFrame
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Metrics.GUTTER
              height: Math.min(parent.height - Metrics.GUTTER * 2,
                               recentsList.contentHeight + recentsFrame.pad * 2)
              visible: root.log.length > 0
              colours: root.colours

              ListView {
                id: recentsList
                anchors.fill: parent
                boundsBehavior: Flickable.StopAtBounds
                model: phoneWindow.visible && root.page === 1 ? root.log : []

                delegate: Chrome.ListRow {
                  id: callRow
                  required property var modelData
                  readonly property var entry: callRow.modelData
                  readonly property string what: Calls.kind(callRow.entry)

                  width: ListView.view.width
                  radius: recentsFrame.innerRadius
                  colours: root.colours
                  bodySize: root.bodySize
                  title: Numbers.label(root.names, callRow.entry.number)
                  titleColour: callRow.what === "missed" ? root.red : root.ink
                  subtitle: Calls.describe(callRow.entry)
                  onClicked: {
                    if (callRow.entry.number) root.dial(callRow.entry.number)
                    else root.say("The number was withheld.")
                  }
                  onHeld: root.menuEntry = callRow.entry

                  leading: Chrome.Icon {
                    slot: 28
                    size: 16
                    color: callRow.what === "missed" ? root.red : root.dim
                    names: callRow.what === "missed"
                           ? ["/usr/share/icons/Adwaita/symbolic/status/call-missed-symbolic.svg", "call-missed-symbolic"]
                           : callRow.what === "out"
                             ? ["/usr/share/icons/Adwaita/symbolic/status/call-outgoing-symbolic.svg", "call-outgoing-symbolic"]
                             : ["/usr/share/icons/Adwaita/symbolic/status/call-incoming-symbolic.svg", "call-incoming-symbolic"]
                  }

                  trailing: Chrome.TypedText {
                    role: "caption"
                    text: Calls.when(callRow.entry.at, root.now)
                    color: root.dim
                    bodySize: root.bodySize
                  }
                }
              }
            }
          }

          // ========== contacts ==========

          ColumnLayout {
            anchors.fill: parent
            visible: root.page === 2
            spacing: 0

            Chrome.TextField {
              Layout.fillWidth: true
              Layout.leftMargin: Metrics.GUTTER
              Layout.rightMargin: Metrics.GUTTER
              Layout.topMargin: 4
              Layout.bottomMargin: Metrics.GAP
              visible: root.people.length > 0
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

            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true

              Chrome.EmptyState {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Metrics.GUTTER
                anchors.topMargin: 40
                visible: root.shownPeople.length === 0
                colours: root.colours
                bodySize: root.bodySize
                names: root.people.length
                       ? ["system-search-symbolic"]
                       : ["/usr/share/icons/Adwaita/symbolic/status/avatar-default-symbolic.svg", "avatar-default-symbolic"]
                title: root.people.length ? "Nobody matches" : "No numbers yet"
                detail: root.people.length
                        ? "Try a different name or number."
                        : "People with a phone number in Contacts are listed here."
              }

              Chrome.ListFrame {
                id: peopleFrame
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Metrics.GUTTER
                anchors.rightMargin: Metrics.GUTTER
                height: Math.min(parent.height - Metrics.GUTTER,
                                 peopleList.contentHeight + peopleFrame.pad * 2)
                visible: root.shownPeople.length > 0
                colours: root.colours

                ListView {
                  id: peopleList
                  anchors.fill: parent
                  boundsBehavior: Flickable.StopAtBounds
                  model: phoneWindow.visible && root.page === 2 ? root.shownPeople : []

                  delegate: Chrome.ListRow {
                    id: personRow
                    required property var modelData
                    width: ListView.view.width
                    radius: peopleFrame.innerRadius
                    colours: root.colours
                    bodySize: root.bodySize
                    title: personRow.modelData.name
                    subtitle: personRow.modelData.phone
                    onClicked: root.dial(personRow.modelData.phone)

                    trailing: Chrome.Icon {
                      slot: 28
                      size: 16
                      color: root.green
                      names: ["/usr/share/icons/Adwaita/symbolic/actions/call-start-symbolic.svg", "call-start-symbolic"]
                    }
                  }
                }
              }
            }
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
          currentIndex: root.page
          onActivated: function (i) {
            root.page = i
            if (i === 1) root.markSeen()
          }

          Chrome.BottomNavItem {
            text: "Keypad"
            names: ["/usr/share/icons/Adwaita/symbolic/devices/input-dialpad-symbolic.svg", "input-dialpad-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }

          Chrome.BottomNavItem {
            id: recentsTab
            text: "Recents"
            names: ["/usr/share/icons/Adwaita/symbolic/actions/document-open-recent-symbolic.svg", "document-open-recent-symbolic"]
            onActivated: bottomNav.selectItem(this)

            // Missed calls nobody has looked at yet.
            Rectangle {
              x: Math.round(recentsTab.width / 2) + 8
              y: 7
              width: 8
              height: 8
              radius: 4
              visible: root.missed > 0 && root.page !== 1
              color: root.red
            }
          }

          Chrome.BottomNavItem {
            text: "Contacts"
            names: ["/usr/share/icons/Adwaita/symbolic/mimetypes/x-office-address-book-symbolic.svg", "x-office-address-book-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }
        }
      }

      // ========== the call ==========

      Rectangle {
        anchors.fill: parent
        visible: root.onCall
        color: root.background
        z: 50

        // Nothing under this screen takes a tap while it is up.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
          anchors.fill: parent
          anchors.leftMargin: Metrics.GUTTER
          anchors.rightMargin: Metrics.GUTTER
          anchors.topMargin: root.dtmfOpen && root.callUp ? 24 : 48
          anchors.bottomMargin: Metrics.GUTTER * 2 + root.shellFurniture
          spacing: 0

          // The face goes when the tones come up: a menu that wants a digit
          // wants the keys more than it wants the picture.
          Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 96
            Layout.preferredHeight: 96
            visible: !(root.dtmfOpen && root.callUp)
            radius: Metrics.round(root.colours, 96)
            color: Theme.surface(root.colours, "raised")

            Chrome.TypedText {
              anchors.centerIn: parent
              visible: Numbers.nameFor(root.names, root.callNumber) !== ""
              role: "title"
              font.pixelSize: Math.round(root.bodySize * 2.4)
              text: root.callLabel.charAt(0).toUpperCase()
              color: root.ink
              bodySize: root.bodySize
            }

            Chrome.Icon {
              anchors.centerIn: parent
              visible: Numbers.nameFor(root.names, root.callNumber) === ""
              slot: 48
              size: 40
              color: root.dim
              names: ["/usr/share/icons/Adwaita/symbolic/status/avatar-default-symbolic.svg", "avatar-default-symbolic"]
            }
          }

          Chrome.TypedText {
            Layout.fillWidth: true
            Layout.topMargin: root.dtmfOpen && root.callUp ? 0 : 16
            role: "title"
            text: root.callLabel
            color: root.ink
            bodySize: root.bodySize
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
          }

          Chrome.TypedText {
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: root.callNumber !== "" && root.callLabel !== root.callNumber
                     && !(root.dtmfOpen && root.callUp)
            role: "body"
            text: root.callNumber
            color: root.dim
            bodySize: root.bodySize
            horizontalAlignment: Text.AlignHCenter
          }

          Chrome.TypedText {
            Layout.fillWidth: true
            Layout.topMargin: 6
            role: "subtitle"
            text: root.callState
            color: root.current && root.current.state === "ringing-in" ? root.green : root.dim
            font.weight: Font.Normal
            bodySize: root.bodySize
            horizontalAlignment: Text.AlignHCenter
          }

          // A second call, on top of the first. No hold and no merge: end the
          // one you are on and take this one, or turn this one away.
          Chrome.Card {
            Layout.fillWidth: true
            Layout.topMargin: 20
            visible: !!root.second && root.ended === null
            colours: root.colours
            tint: root.green
            radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)

            Chrome.TypedText {
              Layout.fillWidth: true
              role: "body"
              text: root.second ? "Also calling: " + Numbers.label(root.names, root.second.number) : ""
              color: root.ink
              bodySize: root.bodySize
              elide: Text.ElideRight
              maximumLineCount: 1
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Metrics.GAP

              Chrome.Button {
                Layout.fillWidth: true
                colours: root.colours
                bodySize: root.bodySize
                kind: "tonal"
                destructive: true
                text: "Decline"
                onClicked: root.decline()
              }

              Chrome.Button {
                Layout.fillWidth: true
                colours: root.colours
                bodySize: root.bodySize
                kind: "filled"
                hue: root.green
                text: "End & answer"
                onClicked: root.endAndAnswer()
              }
            }
          }

          Item { Layout.fillHeight: true }

          // The tones, for a menu that asks for a digit.
          ColumnLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Metrics.GUTTER
            visible: root.dtmfOpen && root.callUp
            spacing: Metrics.GAP

            Chrome.TypedText {
              Layout.fillWidth: true
              role: "subtitle"
              text: root.dtmfSent.length ? root.dtmfSent : " "
              color: root.ink
              bodySize: root.bodySize
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideLeft
              maximumLineCount: 1
            }

            GridLayout {
              Layout.fillWidth: true
              columns: 3
              columnSpacing: Metrics.GAP
              rowSpacing: Metrics.GAP

              Repeater {
                model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]

                delegate: DialKey {
                  id: toneKey
                  required property string modelData
                  Layout.fillWidth: true
                  Layout.preferredHeight: 50
                  colours: root.colours
                  bodySize: root.bodySize
                  digit: toneKey.modelData
                  onClicked: root.sendTone(toneKey.modelData)
                }
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: root.dtmfOpen ? 16 : 28
            visible: root.callUp
            spacing: 0

            Item { Layout.fillWidth: true }

            CallButton {
              colours: root.colours
              bodySize: root.bodySize
              on: root.muted
              names: ["/usr/share/icons/Adwaita/symbolic/status/microphone-disabled-symbolic.svg", "microphone-disabled-symbolic"]
              text: "Mute"
              onClicked: root.toggleMute()
            }

            Item { Layout.fillWidth: true }

            CallButton {
              colours: root.colours
              bodySize: root.bodySize
              on: root.dtmfOpen
              names: ["/usr/share/icons/Adwaita/symbolic/devices/input-dialpad-symbolic.svg", "input-dialpad-symbolic"]
              text: "Keypad"
              onClicked: root.dtmfOpen = !root.dtmfOpen
            }

            Item { Layout.fillWidth: true }

            CallButton {
              colours: root.colours
              bodySize: root.bodySize
              on: root.speaker
              names: ["/usr/share/icons/Adwaita/symbolic/devices/audio-speakers-symbolic.svg", "audio-speakers-symbolic"]
              text: "Speaker"
              onClicked: root.toggleSpeaker()
            }

            Item { Layout.fillWidth: true }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Item { Layout.fillWidth: true }

            CallButton {
              visible: !!root.incoming && root.ended === null
              colours: root.colours
              bodySize: root.bodySize
              size: 72
              hue: root.red
              names: ["/usr/share/icons/Adwaita/symbolic/actions/call-stop-symbolic.svg", "call-stop-symbolic"]
              text: "Decline"
              onClicked: root.decline()
            }

            Item {
              Layout.fillWidth: true
              visible: !!root.incoming && root.ended === null
            }

            CallButton {
              visible: !!root.incoming && root.ended === null
              colours: root.colours
              bodySize: root.bodySize
              size: 72
              hue: root.green
              names: ["/usr/share/icons/Adwaita/symbolic/actions/call-start-symbolic.svg", "call-start-symbolic"]
              text: "Answer"
              onClicked: root.answer()
            }

            CallButton {
              visible: !root.incoming && root.ended === null
              colours: root.colours
              bodySize: root.bodySize
              size: 72
              hue: root.red
              names: ["/usr/share/icons/Adwaita/symbolic/actions/call-stop-symbolic.svg", "call-stop-symbolic"]
              text: "End"
              onClicked: root.hangUp()
            }

            Item { Layout.fillWidth: true }
          }
        }
      }

      Chrome.ContextMenu {
        open: root.menuEntry !== null
        placement: "center"
        colours: root.colours
        background: root.background
        foreground: root.ink
        danger: root.red
        bodySize: root.bodySize
        onDismissed: root.menuEntry = null

        Chrome.MenuItem {
          colours: root.colours
          visible: !!root.menuEntry && root.menuEntry.number !== ""
          names: ["/usr/share/icons/Adwaita/symbolic/actions/call-start-symbolic.svg", "call-start-symbolic"]
          text: "Call"
          foreground: root.ink
          bodySize: root.bodySize
          onClicked: {
            var n = root.menuEntry.number
            root.menuEntry = null
            root.dial(n)
          }
        }

        Chrome.MenuItem {
          colours: root.colours
          visible: !!root.menuEntry && root.menuEntry.number !== ""
          names: ["/usr/share/icons/Adwaita/symbolic/actions/chat-message-new-symbolic.svg", "chat-message-new-symbolic"]
          text: "Send a message"
          foreground: root.ink
          bodySize: root.bodySize
          onClicked: {
            var n = root.menuEntry.number
            root.menuEntry = null
            if (root.shell && typeof root.shell.summon === "function")
              root.shell.summon("moarchy.messages", JSON.stringify({ to: n }))
            else root.say("Messages is not running here.")
          }
        }

        Chrome.MenuItem {
          colours: root.colours
          names: ["user-trash-symbolic"]
          text: "Remove from Recents"
          destructive: true
          danger: root.red
          foreground: root.ink
          bodySize: root.bodySize
          onClicked: {
            var id = root.menuEntry.id
            root.menuEntry = null
            root.forget(id)
          }
        }
      }

      Chrome.Toast {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Metrics.BOTTOM_NAV + 12
        z: 60
        colours: root.colours
        bodySize: root.bodySize
      }
    }
  }
}

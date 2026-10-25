// The chosen coding agent, watched (docs/home.md HM24).
//
// Upstream's own file, ~/.config/omarchy/defaults/agent: one word, written by
// omarchy-default-agent, by Settings > Apps > AI agent and by
// `moarchy-agent set`. Read here and never written -- the prompt bar's menu
// runs `moarchy-agent set`, so there is one writer and the chip, the strip's
// hold and Settings cannot come to disagree.
//
// What is installed and which agent is in use come from `moarchy-agent state`
// (docs/settings.md P17) rather than a table in QML: that script's list is the
// one the selftest already holds against upstream and against Pages.js, and
// its rule for the agent in use is the one `ask` and the tile follow. It is
// read again whenever the choice or mise's global config changes, so an
// install or a removal from Settings reaches the bar within a second.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: agents

  visible: false
  width: 0
  height: 0

  // The agent in use, by command, or "" while none is installed -- which is
  // what a fresh phone has, because Omarchy installs no agent for you.
  readonly property string current: agents.inUse
  // [{ id, name, description, installed, inUse }, ...] in the script's order.
  property var list: []
  // The installed ones only: what the bar's menu offers (home.md HM24).
  readonly property var installed: agents.list.filter(function (a) { return a.installed })

  property string inUse: ""

  function nameOf(id) {
    for (var i = 0; i < agents.list.length; i++) if (agents.list[i].id === id) return agents.list[i].name
    return id
  }

  // Absolute, for moarchy.sim/Sim.qml's reason: a shell restarted from
  // anywhere but a login session has no /usr/lib/moarchy/bin on PATH, and a
  // Process that cannot find its binary fails without a word.
  readonly property string tool: "/usr/lib/moarchy/bin/moarchy-agent"

  // Detached, and not awaited: the file watch is what moves the chip, so a
  // write that lands is seen however it got there.
  function choose(id) {
    if (id) Quickshell.execDetached([agents.tool, "set", id])
  }

  // HM23. One argument, never a shell string.
  function ask(prompt) {
    var p = String(prompt || "").trim()
    if (p !== "") Quickshell.execDetached([agents.tool, "ask", "--", p])
  }

  // Read again; a read already running is let finish and asked once more.
  function refresh(): void {
    if (state.running) again = true
    else state.running = true
  }
  property bool again: false

  // The two files every choice, install and removal writes.
  FileView {
    path: (Quickshell.env("HOME") || "") + "/.config/omarchy/defaults/agent"
    watchChanges: true
    printErrors: false
    onFileChanged: agents.refresh()
  }
  FileView {
    path: (Quickshell.env("HOME") || "") + "/.config/mise/config.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: agents.refresh()
  }

  Probe {
    id: state
    command: [agents.tool, "state"]
    running: true
    onAnswered: {
      var out = []
      var use = ""
      var lines = String(text || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var c = lines[i].split("\t")
        if (c.length < 5 || c[0] === "") continue
        var row = { id: c[0], name: c[1], description: c[2], installed: c[3] === "1", inUse: c[4] === "1" }
        out.push(row)
        if (row.inUse && row.installed) use = row.id
      }
      // An empty answer is a failed read, not a phone with no agents
      // (empty-list-means-unreadable): keep what was there.
      if (out.length > 0) {
        agents.list = out
        agents.inUse = use
      }
    }
    onExited: if (agents.again) { agents.again = false; state.running = true }
  }
}

// The chosen coding agent, watched (docs/home.md HM24).
//
// Upstream's own file, ~/.config/omarchy/defaults/agent: one word, written by
// omarchy-default-agent, by Settings > Apps > AI agent and by
// `moarchy-agent set`. Read here and never written -- the prompt bar's menu
// runs `moarchy-agent set`, so there is one writer and the chip, the strip's
// hold and Settings cannot come to disagree.
//
// The list of agents comes from `moarchy-agent names` rather than a table in
// QML: that script's list is the one the selftest already holds against
// upstream and against Pages.js, and a fourth copy here is the copy that would
// drift.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: agents

  visible: false
  width: 0
  height: 0

  // The chosen agent's command, or "" when none is chosen -- which is what a
  // fresh phone has, because Omarchy picks no agent for you.
  readonly property string current: agents.known(agents.raw) ? agents.raw : ""
  // [{ id: "claude", name: "Claude Code" }, ...] in the script's order.
  property var list: []

  property string raw: ""

  // An empty list means `names` has not answered, not that there are no
  // agents (empty-list-means-unreadable): trust the file until it has.
  function known(id) {
    if (!id) return false
    if (agents.list.length === 0) return true
    for (var i = 0; i < agents.list.length; i++) if (agents.list[i].id === id) return true
    return false
  }

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

  FileView {
    id: file
    path: (Quickshell.env("HOME") || "") + "/.config/omarchy/defaults/agent"
    watchChanges: true
    printErrors: false
    onLoaded: agents.raw = String(file.text() || "").trim().split(/\s+/)[0] || ""
    onLoadFailed: agents.raw = ""
    onFileChanged: Qt.callLater(function () { file.reload() })
  }

  Probe {
    id: names
    command: [agents.tool, "names"]
    running: true
    onAnswered: {
      var out = []
      var lines = String(text || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var cols = lines[i].split("\t")
        if (cols.length >= 2 && cols[0] !== "") out.push({ id: cols[0], name: cols[1] })
      }
      if (out.length > 0) agents.list = out
    }
  }
}

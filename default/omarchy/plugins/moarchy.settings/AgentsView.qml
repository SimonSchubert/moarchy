// The coding agents page (docs/settings.md P14-P19): Omalauncher's
// AgentsScreen, drawn in the Settings window.
//
// One card per agent `moarchy-agent state` lists, each with `[ install ]`, or
// `[ open ]` and `[ remove ]` once mise has it, and the last lines of the job
// while one runs. Everything it knows and does goes through `moarchy-agent`,
// so this page, the prompt bar's menu and the app drawer tile read the same
// answer (P17).
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Upstream
import "../moarchy.common" as Shared

Item {
  id: view

  // Settings itself: its colour roles, radii and shell.
  property var host: null

  // [{ id, name, description, installed, inUse }, ...] in the script's order.
  property var agents: []
  // The job running now: which agent, and "installing" or "removing".
  property string busy: ""
  property string busyAction: ""
  // The last lines a job printed, and the agent whose job failed.
  property var log: []
  property string failed: ""

  // P19. The whole of Settings' stack: back closes the window, to the bar.
  readonly property bool alone: !!view.host && view.host.stack.length === 1

  readonly property string tool: "/usr/lib/moarchy/bin/moarchy-agent"

  readonly property color ink: view.host ? view.host.textOnSurface : "transparent"
  readonly property color muted: view.host ? view.host.subdued : "transparent"
  readonly property color accent: view.host ? view.host.accent : "transparent"
  readonly property int weight: view.host ? view.host.textWeight : Font.Normal

  // Omalauncher's card radius is its frame's 16px at 12, times the corner
  // scale the preset already put into `frame`.
  Shared.UiFile { id: ui }
  readonly property int radiusFrameCard: Math.round(ui.radiusFrame * 12 / 16)

  Component.onCompleted: view.load()

  function load(): void {
    if (!state.running) state.running = true
  }
  Shared.Probe {
    id: state
    command: [view.tool, "state"]
    onAnswered: {
      var out = []
      var lines = String(text || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var c = lines[i].split("\t")
        if (c.length < 5 || c[0] === "") continue
        out.push({ id: c[0], name: c[1], description: c[2], installed: c[3] === "1", inUse: c[4] === "1" })
      }
      // An empty answer is a failed read (empty-list-means-unreadable).
      if (out.length > 0) view.agents = out
    }
  }

  // P15, P16. One job at a time: two mise runs at once fight over its lock.
  function run(id, verb): void {
    if (view.busy !== "") return
    view.busy = id
    view.busyAction = verb === "install" ? "installing" : "removing"
    view.failed = ""
    view.log = []
    job.command = [view.tool, verb, id]
    job.running = true
  }
  Process {
    id: job
    stdout: SplitParser {
      onRead: line => {
        // mise redraws its progress with carriage returns; the last one stands.
        var l = String(line).split("\r").pop().trim()
        if (l === "") return
        var next = view.log.concat([l])
        view.log = next.slice(-4)
      }
    }
    stderr: SplitParser {
      onRead: line => {
        var l = String(line).replace(/^moarchy-agent: /, "").trim()
        if (l !== "") view.log = view.log.concat([l]).slice(-4)
      }
    }
    onExited: (code, status) => {
      if (code !== 0) view.failed = view.busy
      else view.log = []
      view.busy = ""
      view.load()
    }
  }

  // P18. It becomes the choice and opens; Settings gets out of its way.
  function open(id): void {
    Quickshell.execDetached([view.tool, "open", id])
    if (view.host) view.host.dismiss()
  }

  function back(): void {
    if (view.host && !view.host.goBack()) view.host.dismiss()
  }

  // For `settings rows` on this page (P14).
  function report(): string {
    var out = []
    for (var i = 0; i < view.agents.length; i++)
      out.push(view.agents[i].id + " installed=" + (view.agents[i].installed ? 1 : 0)
               + (view.agents[i].inUse ? " in-use" : ""))
    if (view.busy !== "") out.push("busy=" + view.busy + " " + view.busyAction)
    if (view.failed !== "") out.push("failed=" + view.failed + " " + view.log.join(" | "))
    return out.join("\n")
  }

  PanelHeader {
    id: header
    host: view.host
    title: "coding agents"
    backward: !view.alone
    closable: view.alone
    onBack: view.back()
    onClose: if (view.host) view.host.dismiss()
  }

  Text {
    id: intro
    anchors.top: header.bottom
    anchors.topMargin: Style.space(8)
    width: parent.width
    text: "installed with mise, like omarchy. logins open in the browser."
    wrapMode: Text.Wrap
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.weight: view.weight
    color: view.muted
  }

  ListView {
    id: list
    anchors.top: intro.bottom
    anchors.topMargin: Style.space(12)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    spacing: Style.space(8)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: view.agents

    delegate: Rectangle {
      id: card
      required property var modelData
      readonly property var a: card.modelData
      readonly property bool working: view.busy === card.a.id
      readonly property bool broke: view.failed === card.a.id
      width: list.width
      height: Math.max(cardRow.implicitHeight, Style.space(44)) + (logColumn.visible ? logColumn.implicitHeight + Style.space(6) : 0)
              + Style.space(20)
      radius: view.radiusFrameCard
      color: view.host ? view.host.container : "transparent"

      Item {
        id: cardRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(10)
        implicitHeight: Math.max(words.implicitHeight, actions.height)
        height: implicitHeight

        Column {
          id: words
          anchors.left: parent.left
          anchors.right: actions.left
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          Text {
            width: parent.width
            text: card.a.name
            elide: Text.ElideRight
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.weight: view.weight
            color: view.ink
          }
          Text {
            width: parent.width
            text: card.a.description
            elide: Text.ElideRight
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.weight: view.weight
            color: view.muted
          }
        }

        Row {
          id: actions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(44)
          Text {
            visible: card.working
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: view.busyAction + "…"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.weight: view.weight
            color: view.accent
          }
          Bracket {
            visible: !card.working && card.a.installed
            label: "open"
            ink: view.host ? view.host.green : "transparent"
            textWeight: view.weight
            onActivated: view.open(card.a.id)
          }
          Bracket {
            visible: !card.working && card.a.installed
            label: "remove"
            ink: view.host ? view.host.red : "transparent"
            textWeight: view.weight
            enabled: view.busy === ""
            opacity: enabled ? 1 : 0.45
            onActivated: view.run(card.a.id, "remove")
          }
          Bracket {
            visible: !card.working && !card.a.installed
            label: "install"
            ink: view.accent
            textWeight: view.weight
            enabled: view.busy === ""
            opacity: enabled ? 1 : 0.45
            onActivated: view.run(card.a.id, "install")
          }
        }
      }

      // Omalauncher's JobLog: the last lines a job printed, red once it failed.
      Column {
        id: logColumn
        visible: (card.working || card.broke) && view.log.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: cardRow.bottom
        anchors.topMargin: Style.space(6)
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        Repeater {
          model: card.broke ? ["failed:"].concat(view.log) : view.log
          delegate: Text {
            required property var modelData
            width: logColumn.width
            text: String(modelData)
            elide: Text.ElideRight
            maximumLineCount: card.broke ? 3 : 1
            wrapMode: card.broke ? Text.Wrap : Text.NoWrap
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.weight: view.weight
            color: card.broke ? (view.host ? view.host.red : "transparent") : view.muted
          }
        }
      }
    }
  }
}

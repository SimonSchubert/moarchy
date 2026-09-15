// Vitals, in the shell: processor, memory, tasks and network, out of /proc.
//
// The QML half of apps/vitals. It stores nothing -- there is no file, and the
// GTK app has none either -- so unlike every other port here there is no shared
// state to keep honest, only the same numbers read the same way.
//
// The clock stops when the window leaves the screen. An app that walks /proc
// every two seconds from inside a pocket is the battery bug this one is for
// finding.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Sysinfo.js" as Sysinfo
import "Collect.js" as Collect

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "org.moarchy.vitals"
  readonly property bool opened: vitalsWindow.visible
  readonly property var appWindow: vitalsWindow

  property string returnTo: ""
  readonly property var colours: themeFile.colours
  property int bodySize: Metrics.BODY
  Component.onCompleted: {
    root.bodySize = Metrics.shellBody(root)
    var page = Quickshell.env("MOARCHY_VITALS_PAGE") || ""
    var at = ["processor", "memory", "tasks", "network"].indexOf(page)
    if (at >= 0) root.tab = at
  }

  // The last reading, and the one before it that every rate is measured
  // against -- the same reason sysinfo.Sampler is stateful.
  property var sample: null
  property int tab: 0
  property string openPid: ""

  // Sixty seconds of history at the two-second tick, which is the width of the
  // graph and no more: keeping more would be keeping it for nothing.
  property var cpuHistory: []
  property var memHistory: []
  readonly property int historyLength: 30

  readonly property color surface: colours.surface
  readonly property color background: colours.background
  readonly property color textOnSurface: colours.foreground
  readonly property color dim: colours.dim
  readonly property color line: colours.line
  readonly property color accent: colours.accent

  // MOARCHY_VITALS_ROOT is the harness's: a directory shaped like /proc, which
  // is how the GTK app's screenshots are taken against a recorded machine
  // rather than against whatever the container is doing.
  readonly property string sysroot: Quickshell.env("MOARCHY_VITALS_ROOT") || "/"

  function hueColor(name) {
    var hues = root.colours.hues || {}
    return hues[name] || root.accent
  }

  // Green until it is worth noticing, then yellow, then red. The number is
  // beside it in every case, so the colour is the thing that makes a screenful
  // scannable rather than the thing that says what the value is.
  function loadColour(fraction) {
    if (fraction >= 0.85) return root.hueColor("red")
    if (fraction >= 0.6) return root.hueColor("yellow")
    return root.hueColor("green")
  }

  function say(text) { toast.show(text) }

  // --- the shell's plugin contract --------------------------------------

  function open(payloadJson) {
    Plugin.hideOverlays(root.shell)
    root.returnTo = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload.returnTo) root.returnTo = String(payload.returnTo)
    } catch (e) {}
    vitalsWindow.show()
  }

  function close() { root.openPid = "" }

  function dismiss() {
    root.close()
    vitalsWindow.hide()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
    var back = root.returnTo
    root.returnTo = ""
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, "{}")
  }

  // --- the reading ------------------------------------------------------

  function collect() {
    if (reader.running) return
    // The process half is only read on the page that shows it: walking /proc is
    // a few hundred files, and doing it to draw a memory bar is the difference
    // between an app you can leave open and one you cannot.
    reader.command = Collect.command(root.sysroot, root.tab === 2 || !!root.openPid)
    reader.running = true
  }

  function arrived(code, blob) {
    if (code !== 0) return
    var next = Sysinfo.read(blob, root.sample)
    root.sample = next
    root.cpuHistory = root.push(root.cpuHistory, next.cpu.total)
    root.memHistory = root.push(root.memHistory, next.memory.fraction)
  }

  function push(series, value) {
    var out = series.slice()
    out.push(value)
    while (out.length > root.historyLength) out.shift()
    return out
  }

  // pid 1 is refused outright: nothing an app of this shape wants to do is
  // served by signalling init, and in a container -- where this is developed --
  // the kernel would not refuse it.
  function end(pid, force) {
    if (pid <= 1) { root.say("Refusing to signal pid 1."); return }
    killer.command = ["kill", force ? "-KILL" : "-TERM", String(pid)]
    killer.running = true
    root.say((force ? "Killed " : "Ended ") + pid + ".")
    root.openPid = ""
  }

  Timer {
    id: tick
    // Two seconds: fast enough to watch something happen, slow enough that the
    // app is not itself the load.
    interval: 2000
    repeat: true
    running: vitalsWindow.visible
    triggeredOnStart: true
    onTriggered: root.collect()
  }

  Process {
    id: reader
    running: false
    stdout: StdioCollector { id: readOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.arrived(code, readOut.text) }
    // qmllint enable signal-handler-parameters
  }

  Process { id: killer; running: false }

  Chrome.ThemeFile { id: themeFile }

  IpcHandler {
    target: "vitals"
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
    function screen(name: string): string {
      var at = ["processor", "memory", "tasks", "network"].indexOf(name)
      if (at >= 0) root.tab = at
      return ["processor", "memory", "tasks", "network"][root.tab]
    }
    function settled(): bool { return root.sample !== null && !reader.running }
  }

  // --- the window -------------------------------------------------------

  Chrome.AppWindow {
    id: vitalsWindow
    shell: root.shell
    appName: "Vitals"
    pageTitle: ["Processor", "Memory", "Tasks", "Network"][root.tab]
    pluginId: root.pluginId
    color: root.background

    Rectangle {
      anchors.fill: parent
      color: root.background
      focus: true
      Keys.onEscapePressed: {
        if (root.openPid) { root.openPid = ""; return }
        root.dismiss()
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Chrome.AppBar {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 12
          title: ["Processor", "Memory", "Tasks", "Network"][root.tab]
          subtitle: root.sample
                    ? "up " + Sysinfo.humanSeconds(root.sample.uptime)
                    : "Reading /proc…"
          foreground: root.textOnSurface
          dim: root.dim
          bodySize: root.bodySize
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          // --- processor -------------------------------------------------

          Flickable {
            anchors.fill: parent
            visible: root.tab === 0
            clip: true
            contentWidth: width
            contentHeight: cpuCol.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: cpuCol
              width: parent.width
              leftPadding: 12
              rightPadding: 12
              topPadding: 10
              spacing: 12

              Chrome.TypedText {
                role: "title"
                text: root.sample ? Sysinfo.humanPercent(root.sample.cpu.total) : "—"
                color: root.sample ? root.loadColour(root.sample.cpu.total) : root.dim
                bodySize: root.bodySize
              }

              // Sixty seconds of it, as bars. A Repeater and not a Canvas: the
              // scene graph batches thirty solid rectangles into one draw and
              // repaints nothing when nothing changed, where a Canvas would
              // re-upload a texture every tick.
              Row {
                width: cpuCol.width - 24
                height: 56
                spacing: 2
                Repeater {
                  model: root.historyLength
                  delegate: Item {
                    required property int index
                    width: (cpuCol.width - 24 - (root.historyLength - 1) * 2) / root.historyLength
                    height: 56
                    readonly property real value: {
                      var at = index - (root.historyLength - root.cpuHistory.length)
                      return at >= 0 && at < root.cpuHistory.length ? root.cpuHistory[at] : 0
                    }
                    Rectangle {
                      anchors.bottom: parent.bottom
                      width: parent.width
                      height: Math.max(1, parent.height * parent.value)
                      radius: 2
                      color: root.loadColour(parent.value)
                      opacity: parent.value > 0 ? 1 : 0.25
                    }
                  }
                }
              }

              Column {
                width: cpuCol.width - 24
                spacing: 5
                Repeater {
                  model: root.sample ? root.sample.cpu.cores : []
                  delegate: Row {
                    required property var modelData
                    required property int index
                    width: parent.width
                    spacing: 8
                    Chrome.TypedText {
                      width: 26
                      role: "caption"
                      text: "c" + index
                      color: root.dim
                      bodySize: root.bodySize
                    }
                    Rectangle {
                      width: parent.width - 26 - 8 - 44
                      height: 12
                      anchors.verticalCenter: parent.verticalCenter
                      radius: 6
                      color: Theme.mix(root.colours.foreground, root.colours.background, 0.10)
                      Rectangle {
                        width: Math.max(2, parent.width * modelData)
                        height: parent.height
                        radius: 6
                        color: root.loadColour(modelData)
                      }
                    }
                    Chrome.TypedText {
                      width: 44
                      horizontalAlignment: Text.AlignRight
                      role: "caption"
                      text: Sysinfo.humanPercent(modelData)
                      color: root.dim
                      bodySize: root.bodySize
                    }
                  }
                }
              }

              Grid {
                columns: 2
                spacing: 8
                Repeater {
                  model: {
                    if (!root.sample) return []
                    var c = root.sample.cpu
                    var rows = [
                      { label: "Load", value: c.load[0].toFixed(2) + "  " + c.load[1].toFixed(2) + "  " + c.load[2].toFixed(2) },
                      { label: "Tasks", value: c.running + " of " + c.tasks }
                    ]
                    if (c.temperature !== null) rows.push({ label: "Heat", value: Math.round(c.temperature) + "°C" })
                    if (c.frequency !== null) rows.push({ label: "Clock", value: Math.round(c.frequency) + " MHz" })
                    return rows
                  }
                  delegate: Rectangle {
                    required property var modelData
                    width: (cpuCol.width - 32) / 2
                    height: 52
                    radius: Metrics.CARD_RADIUS
                    color: Theme.mix(root.colours.foreground, root.colours.background, 0.06)
                    Column {
                      anchors.centerIn: parent
                      spacing: 2
                      Chrome.TypedText {
                        role: "overline"; text: modelData.label
                        color: root.dim; bodySize: root.bodySize
                      }
                      Chrome.TypedText {
                        role: "body"; text: modelData.value
                        color: root.textOnSurface; bodySize: root.bodySize
                      }
                    }
                  }
                }
              }
              Item { width: 1; height: 10 }
            }
          }

          // --- memory ----------------------------------------------------

          Flickable {
            anchors.fill: parent
            visible: root.tab === 1
            clip: true
            contentWidth: width
            contentHeight: memCol.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: memCol
              width: parent.width
              leftPadding: 12
              rightPadding: 12
              topPadding: 10
              spacing: 12

              Chrome.TypedText {
                role: "title"
                text: root.sample
                      ? Sysinfo.humanBytes(root.sample.memory.used) + " of " +
                        Sysinfo.humanBytes(root.sample.memory.total)
                      : "—"
                color: root.textOnSurface
                bodySize: root.bodySize
              }

              Rectangle {
                width: memCol.width - 24
                height: 20
                radius: 10
                color: Theme.mix(root.colours.foreground, root.colours.background, 0.10)
                Rectangle {
                  width: root.sample ? Math.max(2, parent.width * root.sample.memory.fraction) : 0
                  height: parent.height
                  radius: 10
                  color: root.sample ? root.loadColour(root.sample.memory.fraction) : root.dim
                }
              }

              Column {
                width: memCol.width - 24
                spacing: 6
                Repeater {
                  model: {
                    if (!root.sample) return []
                    var m = root.sample.memory
                    var rows = [
                      { label: "Available", value: Sysinfo.humanBytes(m.available) },
                      { label: "Cached", value: Sysinfo.humanBytes(m.cached) }
                    ]
                    if (m.swap_total > 0)
                      rows.push({ label: "Swap", value: Sysinfo.humanBytes(m.swap_used) + " of " +
                                                        Sysinfo.humanBytes(m.swap_total) })
                    rows.push({ label: "Disk read", value: Sysinfo.humanRate(root.sample.io.read_rate) })
                    rows.push({ label: "Disk write", value: Sysinfo.humanRate(root.sample.io.write_rate) })
                    if (root.sample.battery)
                      rows.push({ label: "Battery", value: root.sample.battery.percent + "%  " +
                                  root.sample.battery.status +
                                  (root.sample.battery.watts !== null
                                   ? "  " + root.sample.battery.watts.toFixed(1) + " W" : "") })
                    return rows
                  }
                  delegate: Row {
                    required property var modelData
                    width: parent.width
                    Chrome.TypedText {
                      width: parent.width / 2
                      role: "body"; text: modelData.label
                      color: root.dim; bodySize: root.bodySize
                    }
                    Chrome.TypedText {
                      width: parent.width / 2
                      horizontalAlignment: Text.AlignRight
                      role: "body"; text: modelData.value
                      color: root.textOnSurface; bodySize: root.bodySize
                    }
                  }
                }
              }
              Item { width: 1; height: 10 }
            }
          }

          // --- tasks -----------------------------------------------------

          Flickable {
            anchors.fill: parent
            visible: root.tab === 2
            clip: true
            contentWidth: width
            contentHeight: taskCol.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: taskCol
              width: parent.width

              Repeater {
                model: root.sample ? root.sample.processes.slice(0, 60) : []

                delegate: Item {
                  id: taskRow
                  required property var modelData
                  readonly property var proc: taskRow.modelData
                  width: taskCol.width
                  height: 56

                  Rectangle {
                    anchors.fill: parent
                    color: String(taskRow.proc.pid) === root.openPid
                           ? Theme.mix(root.colours.foreground, root.colours.background, 0.08)
                           : "transparent"
                  }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.openPid = (String(taskRow.proc.pid) === root.openPid)
                               ? "" : String(taskRow.proc.pid)
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 8

                    Column {
                      Layout.fillWidth: true
                      Layout.alignment: Qt.AlignVCenter
                      spacing: 1
                      Chrome.TypedText {
                        width: parent.width
                        role: "body"
                        text: taskRow.proc.name
                        // A kernel thread has no address space and so no
                        // command line; it is still a row, just a quieter one.
                        color: taskRow.proc.kernel ? root.dim : root.textOnSurface
                        bodySize: root.bodySize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                      }
                      Chrome.TypedText {
                        width: parent.width
                        role: "caption"
                        text: taskRow.proc.pid + " · " + taskRow.proc.state +
                              " · " + Sysinfo.humanBytes(taskRow.proc.rss)
                        color: root.dim
                        bodySize: root.bodySize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                      }
                    }

                    Chrome.TypedText {
                      Layout.alignment: Qt.AlignVCenter
                      role: "body"
                      text: Sysinfo.taskPercent(taskRow.proc.cpu)
                      color: root.loadColour(taskRow.proc.cpu)
                      bodySize: root.bodySize
                    }

                    Chrome.IconButton {
                      Layout.alignment: Qt.AlignVCenter
                      visible: String(taskRow.proc.pid) === root.openPid
                      color: root.hueColor("red")
                      names: ["window-close-symbolic", "edit-clear-symbolic"]
                      tooltip: "End " + taskRow.proc.name
                      onClicked: root.end(taskRow.proc.pid, false)
                    }
                  }

                  Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: root.line
                  }
                }
              }
            }
          }

          // --- network ---------------------------------------------------

          Flickable {
            anchors.fill: parent
            visible: root.tab === 3
            clip: true
            contentWidth: width
            contentHeight: netCol.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: netCol
              width: parent.width

              Repeater {
                model: root.sample ? root.sample.interfaces : []

                delegate: Item {
                  required property var modelData
                  readonly property var iface: modelData
                  width: netCol.width
                  height: iface.wireless ? 84 : 66

                  Column {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 10
                    spacing: 3

                    Row {
                      width: parent.width
                      Chrome.TypedText {
                        width: parent.width / 2
                        role: "body"; text: iface.name
                        color: iface.up ? root.textOnSurface : root.dim
                        bodySize: root.bodySize
                      }
                      Chrome.TypedText {
                        width: parent.width / 2
                        horizontalAlignment: Text.AlignRight
                        role: "caption"; text: iface.state
                        color: iface.up ? root.hueColor("green") : root.dim
                        bodySize: root.bodySize
                      }
                    }

                    Row {
                      width: parent.width
                      Chrome.TypedText {
                        width: parent.width / 2
                        role: "caption"
                        text: "↓ " + Sysinfo.humanRate(iface.rx_rate)
                        color: root.dim; bodySize: root.bodySize
                      }
                      Chrome.TypedText {
                        width: parent.width / 2
                        horizontalAlignment: Text.AlignRight
                        role: "caption"
                        text: "↑ " + Sysinfo.humanRate(iface.tx_rate)
                        color: root.dim; bodySize: root.bodySize
                      }
                    }

                    Row {
                      width: parent.width
                      visible: iface.wireless
                      spacing: 8
                      Rectangle {
                        width: parent.width - 60
                        height: 8
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 4
                        color: Theme.mix(root.colours.foreground, root.colours.background, 0.10)
                        Rectangle {
                          width: Math.max(2, parent.width * (iface.quality === null ? 0 : iface.quality))
                          height: parent.height
                          radius: 4
                          color: root.accent
                        }
                      }
                      Chrome.TypedText {
                        width: 52
                        horizontalAlignment: Text.AlignRight
                        role: "caption"
                        // dBm where the driver reports it, because a percentage
                        // whose denominator is a guess is worse than a number
                        // that means something.
                        text: iface.signal !== null ? iface.signal + " dBm"
                              : (iface.quality !== null ? Sysinfo.humanPercent(iface.quality) : "")
                        color: root.dim; bodySize: root.bodySize
                      }
                    }
                  }

                  Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: root.line
                  }
                }
              }
            }
          }

          Chrome.TypedText {
            anchors.centerIn: parent
            visible: !root.sample
            role: "body"
            text: "Reading /proc…"
            color: root.dim
            bodySize: root.bodySize
          }

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
          onActivated: function (i) { root.tab = i; root.collect() }

          Chrome.BottomNavItem {
            text: "Processor"; names: ["computer-symbolic", "view-list-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }
          Chrome.BottomNavItem {
            text: "Memory"; names: ["drive-harddisk-symbolic", "view-list-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }
          Chrome.BottomNavItem {
            text: "Tasks"; names: ["system-run-symbolic", "view-list-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }
          Chrome.BottomNavItem {
            text: "Network"; names: ["network-wireless-symbolic", "view-list-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }
        }
      }
    }
  }
}

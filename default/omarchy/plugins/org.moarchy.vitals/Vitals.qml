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

  readonly property color background: colours.background
  readonly property color textOnSurface: colours.foreground
  readonly property color dim: colours.dim
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
    // The process half is read on every page that names processes, which is
    // all of them but the network. It is a few hundred files, and reading them
    // to draw an interface's rates is work nobody sees.
    reader.command = Collect.command(root.sysroot, root.tab !== 3 || !!root.openPid)
    reader.running = true
  }

  // Five: enough to say what is using the machine, few enough to leave the
  // rest of the page in reach. The whole list is the Tasks page.
  readonly property int topCount: 5
  readonly property var busiest: root.sample ? Sysinfo.busiest(root.sample.apps, root.topCount) : []
  readonly property var largest: root.sample ? Sysinfo.largest(root.sample.apps, root.topCount) : []

  // The line under an app's name: how many processes it is, and the half of
  // its footprint the page is not about. A row on the processor page says its
  // memory and a row on the memory page its share of the processor, so either
  // list answers both questions.
  function appDetail(app, page) {
    if (app.kernel) return app.pids.length + " threads"
    var parts = [app.pids.length > 1 ? app.pids.length + " processes" : "pid " + app.pids[0]]
    parts.push(page === "processor"
               ? Sysinfo.humanBytes(app.rss)
               : Sysinfo.taskPercent(app.cpu) + " processor")
    return parts.join(" · ")
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
            id: cpuPage
            anchors.fill: parent
            visible: root.tab === 0
            clip: true
            contentWidth: width
            contentHeight: cpuCol.implicitHeight + Metrics.GUTTER * 2
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: cpuCol
              x: Metrics.GUTTER
              y: Metrics.GUTTER
              width: cpuPage.width - Metrics.GUTTER * 2
              spacing: Metrics.GAP

              // The headline and the minute behind it, in one box. They are
              // one fact read two ways -- what the machine is doing now and
              // whether that is new -- and splitting them across two cards
              // would be two boxes saying the same thing at two sizes.
              Chrome.Card {
                Layout.fillWidth: true
                colours: root.colours

                Chrome.TypedText {
                  Layout.fillWidth: true
                  role: "title"
                  text: root.sample ? Sysinfo.humanPercent(root.sample.cpu.total) : "—"
                  color: root.sample ? root.loadColour(root.sample.cpu.total) : root.dim
                  bodySize: root.bodySize
                }

                // Sixty seconds of it, as bars. A Repeater and not a Canvas:
                // the scene graph batches thirty solid rectangles into one
                // draw and repaints nothing when nothing changed, where a
                // Canvas would re-upload a texture every tick.
                Item {
                  id: cpuGraph
                  Layout.fillWidth: true
                  Layout.preferredHeight: 56

                  // The chart area is drawn even when the chart is not. A
                  // minute of history takes a minute to collect, and an app
                  // that opens on 56px of nothing looks like one that failed
                  // rather than one that has not finished counting.
                  Rectangle {
                    anchors.fill: parent
                    radius: Metrics.radius(root.colours, Metrics.RADIUS_SM)
                    color: Theme.surface(root.colours, "raised")
                  }

                  Row {
                    anchors.fill: parent
                    spacing: 2

                    Repeater {
                      model: root.historyLength
                      delegate: Item {
                        required property int index
                        width: (cpuGraph.width - (root.historyLength - 1) * 2) / root.historyLength
                        height: cpuGraph.height
                        readonly property real value: {
                          var at = index - (root.historyLength - root.cpuHistory.length)
                          return at >= 0 && at < root.cpuHistory.length ? root.cpuHistory[at] : 0
                        }
                        Rectangle {
                          anchors.bottom: parent.bottom
                          width: parent.width
                          height: Math.max(2, parent.height * parent.value)
                          radius: Metrics.radius(root.colours, Metrics.RADIUS_XS)
                          color: root.loadColour(parent.value)
                          opacity: parent.value > 0 ? 1 : 0.25
                        }
                      }
                    }
                  }
                }
              }

              // What the percentage is made of, straight under it, because it
              // is the question the percentage asks. Above the cores: which core
              // is busy is the less useful half of the same answer.
              Chrome.Section {
                id: busySection
                Layout.fillWidth: true
                colours: root.colours
                bodySize: root.bodySize
                title: "Busiest"
                pad: Metrics.GROUP_PAD
                radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
                cardSpacing: 0
                visible: root.busiest.length > 0

                Repeater {
                  model: root.busiest
                  delegate: Chrome.ListRow {
                    id: busyRow
                    required property var modelData
                    Layout.fillWidth: true
                    interactive: false
                    radius: busySection.innerRadius
                    colours: root.colours
                    bodySize: root.bodySize
                    title: busyRow.modelData.name
                    titleColour: busyRow.modelData.kernel ? root.dim : root.textOnSurface
                    subtitle: root.appDetail(busyRow.modelData, "processor")

                    trailing: Chrome.TypedText {
                      anchors.verticalCenter: parent.verticalCenter
                      role: "body"
                      text: Sysinfo.taskPercent(busyRow.modelData.cpu)
                      color: root.loadColour(busyRow.modelData.cpu)
                      bodySize: root.bodySize
                    }
                  }
                }
              }

              Chrome.Section {
                Layout.fillWidth: true
                colours: root.colours
                bodySize: root.bodySize
                title: "Cores"
                cardSpacing: 6
                visible: !!root.sample

                Repeater {
                  model: root.sample ? root.sample.cpu.cores : []
                  delegate: RowLayout {
                    id: coreRow
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 8

                    Chrome.TypedText {
                      Layout.preferredWidth: 26
                      role: "caption"
                      text: "c" + coreRow.index
                      color: root.dim
                      bodySize: root.bodySize
                    }

                    Rectangle {
                      Layout.fillWidth: true
                      Layout.preferredHeight: 12
                      radius: Metrics.round(root.colours, height)
                      color: Theme.surface(root.colours, "raised")

                      Rectangle {
                        width: Math.max(parent.height, parent.width * coreRow.modelData)
                        height: parent.height
                        radius: Metrics.round(root.colours, height)
                        color: root.loadColour(coreRow.modelData)
                      }
                    }

                    Chrome.TypedText {
                      Layout.preferredWidth: 44
                      horizontalAlignment: Text.AlignRight
                      role: "caption"
                      text: Sysinfo.humanPercent(coreRow.modelData)
                      color: root.dim
                      bodySize: root.bodySize
                    }
                  }
                }
              }

              // Two across, because that is what fits a number and its name on
              // 360px without either being abbreviated.
              GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Metrics.GAP
                rowSpacing: Metrics.GAP

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
                  delegate: Chrome.Tile {
                    id: cpuTile
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 62
                    colours: root.colours
                    bodySize: root.bodySize
                    label: cpuTile.modelData.label
                    value: cpuTile.modelData.value
                    valueColour: root.textOnSurface
                  }
                }
              }
            }
          }

          // --- memory ----------------------------------------------------

          Flickable {
            id: memPage
            anchors.fill: parent
            visible: root.tab === 1
            clip: true
            contentWidth: width
            contentHeight: memCol.implicitHeight + Metrics.GUTTER * 2
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: memCol
              x: Metrics.GUTTER
              y: Metrics.GUTTER
              width: memPage.width - Metrics.GUTTER * 2
              spacing: Metrics.GAP

              Chrome.Card {
                Layout.fillWidth: true
                colours: root.colours

                Chrome.TypedText {
                  Layout.fillWidth: true
                  role: "title"
                  text: root.sample
                        ? Sysinfo.humanBytes(root.sample.memory.used) + " of " +
                          Sysinfo.humanBytes(root.sample.memory.total)
                        : "—"
                  color: root.textOnSurface
                  bodySize: root.bodySize
                  elide: Text.ElideRight
                }

                Rectangle {
                  Layout.fillWidth: true
                  Layout.preferredHeight: 18
                  radius: Metrics.round(root.colours, height)
                  color: Theme.surface(root.colours, "raised")

                  Rectangle {
                    width: root.sample
                           ? Math.max(parent.height, parent.width * root.sample.memory.fraction) : 0
                    height: parent.height
                    radius: Metrics.round(root.colours, height)
                    color: root.sample ? root.loadColour(root.sample.memory.fraction) : root.dim
                  }
                }
              }

              Chrome.Section {
                id: largeSection
                Layout.fillWidth: true
                colours: root.colours
                bodySize: root.bodySize
                title: "Most memory"
                pad: Metrics.GROUP_PAD
                radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)
                cardSpacing: 0
                visible: root.largest.length > 0

                Repeater {
                  model: root.largest
                  delegate: Chrome.ListRow {
                    id: largeRow
                    required property var modelData
                    Layout.fillWidth: true
                    interactive: false
                    radius: largeSection.innerRadius
                    colours: root.colours
                    bodySize: root.bodySize
                    title: largeRow.modelData.name
                    subtitle: root.appDetail(largeRow.modelData, "memory")

                    // App ink rather than a load colour: a share of the
                    // processor has a level that is worth noticing, and an
                    // app's size on its own does not.
                    trailing: Chrome.TypedText {
                      anchors.verticalCenter: parent.verticalCenter
                      role: "body"
                      text: Sysinfo.humanBytes(largeRow.modelData.rss)
                      color: root.textOnSurface
                      bodySize: root.bodySize
                    }
                  }
                }
              }

              Chrome.Section {
                Layout.fillWidth: true
                colours: root.colours
                bodySize: root.bodySize
                title: "Detail"
                cardSpacing: 7
                visible: !!root.sample

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
                  delegate: RowLayout {
                    id: memRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8

                    Chrome.TypedText {
                      Layout.fillWidth: true
                      role: "body"
                      text: memRow.modelData.label
                      color: root.dim
                      bodySize: root.bodySize
                      elide: Text.ElideRight
                    }

                    Chrome.TypedText {
                      horizontalAlignment: Text.AlignRight
                      role: "body"
                      text: memRow.modelData.value
                      color: root.textOnSurface
                      bodySize: root.bodySize
                    }
                  }
                }
              }
            }
          }

          // --- tasks -----------------------------------------------------

          Chrome.ListFrame {
            id: taskFrame
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Metrics.GUTTER
            // Sixty processes fill the screen and five do not, and a frame
            // that reached the bottom either way would be four hundred pixels
            // of empty box on a machine that is doing nothing.
            height: Math.min(parent.height - Metrics.GUTTER * 2,
                             taskList.contentHeight + taskFrame.pad * 2)
            visible: root.tab === 2 && root.sample !== null && root.sample.processes.length > 0
            colours: root.colours

            ListView {
              id: taskList
              anchors.fill: parent
              spacing: 0
              boundsBehavior: Flickable.StopAtBounds
              model: root.sample ? root.sample.processes.slice(0, 60) : []

              delegate: Chrome.ListRow {
                id: taskRow
                required property var modelData
                readonly property var proc: taskRow.modelData
                width: ListView.view.width
                radius: taskFrame.innerRadius
                colours: root.colours
                bodySize: root.bodySize
                title: taskRow.proc.name
                // A kernel thread has no address space and so no command
                // line; it is still a row, just a quieter one.
                titleColour: taskRow.proc.kernel ? root.dim : root.textOnSurface
                subtitle: taskRow.proc.pid + " · " + taskRow.proc.state +
                          " · " + Sysinfo.humanBytes(taskRow.proc.rss)
                selected: String(taskRow.proc.pid) === root.openPid
                onClicked: root.openPid = taskRow.selected ? "" : String(taskRow.proc.pid)

                trailing: [
                  Chrome.TypedText {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "body"
                    text: Sysinfo.taskPercent(taskRow.proc.cpu)
                    color: root.loadColour(taskRow.proc.cpu)
                    bodySize: root.bodySize
                  },
                  Chrome.IconButton {
                    colours: root.colours
                    anchors.verticalCenter: parent.verticalCenter
                    visible: taskRow.selected
                    width: visible ? Metrics.TARGET : 0
                    color: root.hueColor("red")
                    names: ["window-close-symbolic", "edit-clear-symbolic"]
                    tooltip: "End " + taskRow.proc.name
                    onClicked: root.end(taskRow.proc.pid, false)
                  }
                ]
              }
            }
          }

          // --- network ---------------------------------------------------

          Flickable {
            id: netPage
            anchors.fill: parent
            visible: root.tab === 3
            clip: true
            contentWidth: width
            contentHeight: netCol.implicitHeight + Metrics.GUTTER * 2
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: netCol
              x: Metrics.GUTTER
              y: Metrics.GUTTER
              width: netPage.width - Metrics.GUTTER * 2
              spacing: Metrics.GAP

              Repeater {
                model: root.sample ? root.sample.interfaces : []

                // One interface, one box. They were rows with a rule between
                // them, which made four unrelated machines look like one list.
                delegate: Chrome.Card {
                  id: ifaceCard
                  required property var modelData
                  readonly property var iface: ifaceCard.modelData
                  Layout.fillWidth: true
                  colours: root.colours
                  spacing: 7

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Chrome.Icon {
                      Layout.preferredWidth: 18
                      Layout.preferredHeight: 18
                      slot: 18
                      size: 16
                      color: ifaceCard.iface.up ? root.hueColor("green") : root.dim
                      names: ifaceCard.iface.wireless
                             ? ["network-wireless-symbolic"]
                             : ["computer-symbolic", "network-wireless-symbolic"]
                    }

                    Chrome.TypedText {
                      Layout.fillWidth: true
                      role: "subtitle"
                      text: ifaceCard.iface.name
                      color: ifaceCard.iface.up ? root.textOnSurface : root.dim
                      bodySize: root.bodySize
                      elide: Text.ElideRight
                    }

                    Chrome.TypedText {
                      role: "caption"
                      text: ifaceCard.iface.state
                      color: ifaceCard.iface.up ? root.hueColor("green") : root.dim
                      bodySize: root.bodySize
                    }
                  }

                  // Only for an interface that is up. A down one has no rates
                  // and never will; two boxes of "0 B/s" under it are a claim
                  // that something is being measured.
                  GridLayout {
                    Layout.fillWidth: true
                    visible: ifaceCard.iface.up
                    columns: 2
                    columnSpacing: 6
                    rowSpacing: 6

                    Chrome.Tile {
                      Layout.fillWidth: true
                      colours: root.colours
                      bodySize: root.bodySize
                      level: "raised"
                      radius: ifaceCard.innerRadius
                      pad: 10
                      label: "Down"
                      value: Sysinfo.humanRate(ifaceCard.iface.rx_rate)
                      valueColour: root.textOnSurface
                      valueRole: "body"
                    }

                    Chrome.Tile {
                      Layout.fillWidth: true
                      colours: root.colours
                      bodySize: root.bodySize
                      level: "raised"
                      radius: ifaceCard.innerRadius
                      pad: 10
                      label: "Up"
                      value: Sysinfo.humanRate(ifaceCard.iface.tx_rate)
                      valueColour: root.textOnSurface
                      valueRole: "body"
                    }
                  }

                  RowLayout {
                    Layout.fillWidth: true
                    visible: ifaceCard.iface.wireless
                    spacing: 8

                    Rectangle {
                      Layout.fillWidth: true
                      Layout.preferredHeight: 8
                      radius: Metrics.round(root.colours, height)
                      color: Theme.surface(root.colours, "raised")

                      Rectangle {
                        width: Math.max(parent.height, parent.width *
                               (ifaceCard.iface.quality === null ? 0 : ifaceCard.iface.quality))
                        height: parent.height
                        radius: Metrics.round(root.colours, height)
                        color: root.accent
                      }
                    }

                    Chrome.TypedText {
                      Layout.preferredWidth: 56
                      horizontalAlignment: Text.AlignRight
                      role: "caption"
                      // dBm where the driver reports it, because a percentage
                      // whose denominator is a guess is worse than a number
                      // that means something.
                      text: ifaceCard.iface.signal !== null
                            ? ifaceCard.iface.signal + " dBm"
                            : (ifaceCard.iface.quality !== null
                               ? Sysinfo.humanPercent(ifaceCard.iface.quality) : "")
                      color: root.dim
                      bodySize: root.bodySize
                    }
                  }
                }
              }
            }
          }

          Chrome.EmptyState {
            anchors.centerIn: parent
            width: parent.width - Metrics.GUTTER * 2
            visible: !root.sample
            colours: root.colours
            bodySize: root.bodySize
            names: ["system-run-symbolic"]
            title: "Reading /proc"
            detail: "The first sample is two seconds away; every rate on these screens is measured against it."
          }

          // Arriving from the network page, which does not read processes, the
          // reading on screen has none in it until the next tick. An empty
          // frame there read as a phone running nothing.
          Chrome.EmptyState {
            anchors.centerIn: parent
            width: parent.width - Metrics.GUTTER * 2
            visible: root.tab === 2 && root.sample !== null && root.sample.processes.length === 0
            colours: root.colours
            bodySize: root.bodySize
            names: ["system-run-symbolic"]
            title: "Reading processes"
            detail: "The list is on the next sample, two seconds away at most."
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

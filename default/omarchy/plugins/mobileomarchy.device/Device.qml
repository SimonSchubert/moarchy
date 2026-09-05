// Device: what this phone is doing right now.
//
// ---------------------------------------------------------------------------
// Why a plugin rather than an app
// ---------------------------------------------------------------------------
// btm and htop already exist and are better at this. What they cannot do is
// open instantly: launching a terminal emulator and a Rust TUI on a 1.15GHz A53
// takes long enough that you stop reaching for it to answer "is it charging?".
// The shell is already resident, so a plugin screen is on-screen in one frame.
//
// It is still launched from the drawer like an app, via a .desktop entry whose
// Exec asks the shell to summon it. That is the whole trick to a plugin
// behaving like an app: nothing new starts, but the affordance is identical.
//
// ---------------------------------------------------------------------------
// Why one shell process and not FileView per value
// ---------------------------------------------------------------------------
// Fifteen separate sysfs reads on this SoC cost more in QML/JS round trips than
// the reads themselves. A single sh -c that prints key=value lines is one
// process per refresh, parsed in one pass.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  // Injected by the host.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
                               || (Quickshell.env("HOME") + "/.local/share/omarchy")
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "mobileomarchy.device"

  property bool opened: false
  property string returnTo: ""

  // Palette, from the shell's theme singleton where it exists so this screen
  // recolours with everything else, with literals only as a fallback.
  readonly property color surface: (typeof Color !== "undefined" && Color.surface) ? Color.surface : "#1a1b26"
  readonly property color container: (typeof Color !== "undefined" && Color.surfaceContainer) ? Color.surfaceContainer : "#24283b"
  readonly property color textOnSurface: (typeof Color !== "undefined" && Color.onSurface) ? Color.onSurface : "#c0caf5"
  readonly property color subdued: (typeof Color !== "undefined" && Color.onSurfaceVariant) ? Color.onSurfaceVariant : "#787c99"
  readonly property color accent: (typeof Color !== "undefined" && Color.primary) ? Color.primary : "#7aa2f7"

  property var facts: ({})

  function open(payloadJson) {
    // Only one full-screen plugin should be up at a time, or the one underneath
    // keeps its keyboard grab and swallows the back gesture.
    if (root.shell && typeof root.shell.isPluginOpen === "function") {
      if (root.shell.isPluginOpen("mobileomarchy.shade")) root.shell.hide("mobileomarchy.shade")
      if (root.shell.isPluginOpen("mobileomarchy.drawer")) root.shell.hide("mobileomarchy.drawer")
    }
    try {
      const payload = payloadJson ? JSON.parse(payloadJson) : {}
      root.returnTo = payload.returnTo || ""
    } catch (e) {
      root.returnTo = ""
    }
    root.opened = true
    probe.running = true
    ticker.start()
  }

  // close() is the host's teardown hook: it must only drop local state. The
  // shell calls it *because* it is hiding this plugin, so anything in here that
  // asks the shell to hide it re-enters immediately and recurses until
  // RangeError -- which is exactly what an earlier version of this file did, on
  // every shell start. dismiss() is the one that tells the shell to hide, and
  // is what a Back tap or the IPC close routes to.
  function close() {
    root.opened = false
    ticker.stop()
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    const back = root.returnTo
    root.returnTo = ""
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, "{}")
  }

  IpcHandler {
    target: "mobileomarchy.device"
    function open(): string { root.open("{}"); return "ok" }
    function close(): string { root.dismiss(); return "ok" }
  }

  Timer {
    id: ticker
    interval: 3000
    repeat: true
    onTriggered: probe.running = true
  }

  Process {
    id: probe
    running: false
    command: ["sh", "-c", `
      printf 'model=%s\\n' "$(tr -d '\\0' < /proc/device-tree/model 2>/dev/null)"
      printf 'cores=%s\\n' "$(grep -c ^processor /proc/cpuinfo)"
      f=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
      [ -n "$f" ] && printf 'mhz=%s\\n' "$((f/1000))"
      printf 'batt=%s\\n' "$(cat /sys/class/power_supply/axp20x-battery/capacity 2>/dev/null)"
      printf 'battstatus=%s\\n' "$(cat /sys/class/power_supply/axp20x-battery/status 2>/dev/null)"
      hot=0
      for z in /sys/class/thermal/thermal_zone*/temp; do
        t=$(cat "$z" 2>/dev/null); t=$((t/1000))
        [ "$t" -gt "$hot" ] && hot=$t
      done
      printf 'temp=%s\\n' "$hot"
      free -m | awk '/Mem:/{printf "memused=%s\\nmemtotal=%s\\n", $3, $2}'
      df -m / | awk 'NR==2{printf "diskfree=%s\\ndisktotal=%s\\n", $4, $2}'
      printf 'uptime=%s\\n' "$(cut -d. -f1 /proc/uptime)"
      printf 'kernel=%s\\n' "$(uname -r)"
    `]
    stdout: StdioCollector {
      onStreamFinished: {
        const next = {}
        for (const line of text.split("\n")) {
          const i = line.indexOf("=")
          if (i > 0) next[line.slice(0, i)] = line.slice(i + 1).trim()
        }
        root.facts = next
      }
    }
  }

  function human(seconds) {
    const s = parseInt(seconds || "0")
    if (!s) return "—"
    const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60)
    if (d) return d + "d " + h + "h"
    if (h) return h + "h " + m + "m"
    return m + "m"
  }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "mobileomarchy-device"
    WlrLayershell.layer: WlrLayer.Top
    exclusiveZone: 0
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive
                                             : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: root.surface

      Keys.onEscapePressed: root.dismiss()

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        // Header: back chevron, title. Mirrors every other screen in this shell
        // so the plugin does not announce itself as something different.
        RowLayout {
          Layout.fillWidth: true
          spacing: 10

          Rectangle {
            width: 40; height: 40; radius: 20
            color: backArea.pressed ? root.container : "transparent"
            Text {
              anchors.centerIn: parent
              text: "‹"
              font.pixelSize: 30
              color: root.textOnSurface
            }
            MouseArea {
              id: backArea
              anchors.fill: parent
              onClicked: root.dismiss()
            }
          }

          Text {
            Layout.fillWidth: true
            text: "Device"
            font.pixelSize: 22
            font.bold: true
            color: root.textOnSurface
          }
        }

        Text {
          Layout.fillWidth: true
          text: root.facts.model || "…"
          font.pixelSize: 13
          color: root.subdued
          wrapMode: Text.WordWrap
        }

        // Battery and temperature get the top slot: they are the two things you
        // open this for, and the only two that change on their own.
        RowLayout {
          Layout.fillWidth: true
          spacing: 12

          Repeater {
            model: [
              {
                label: (root.facts.battstatus === "Charging") ? "Charging" : "Battery",
                value: (root.facts.batt || "—") + "%"
              },
              { label: "Hottest zone", value: (root.facts.temp || "—") + "°C" }
            ]
            Rectangle {
              required property var modelData
              Layout.fillWidth: true
              Layout.preferredHeight: 84
              radius: 14
              color: root.container
              ColumnLayout {
                anchors.centerIn: parent
                spacing: 2
                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: modelData.value
                  font.pixelSize: 26
                  font.bold: true
                  color: root.accent
                }
                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: modelData.label
                  font.pixelSize: 11
                  color: root.subdued
                }
              }
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.fillHeight: true
          radius: 14
          color: root.container

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 0

            Repeater {
              model: [
                { k: "CPU",     v: (root.facts.cores || "—") + " cores @ " + (root.facts.mhz || "—") + " MHz" },
                { k: "Memory",  v: (root.facts.memused || "—") + " / " + (root.facts.memtotal || "—") + " MB" },
                { k: "Storage", v: (root.facts.diskfree || "—") + " MB free of " + (root.facts.disktotal || "—") },
                { k: "Uptime",  v: root.human(root.facts.uptime) },
                { k: "Kernel",  v: root.facts.kernel || "—" }
              ]
              RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                spacing: 8
                Text {
                  text: modelData.k
                  font.pixelSize: 14
                  color: root.subdued
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: modelData.v
                  font.pixelSize: 14
                  color: root.textOnSurface
                  elide: Text.ElideLeft
                  Layout.maximumWidth: 210
                  horizontalAlignment: Text.AlignRight
                }
              }
            }

            Item { Layout.fillHeight: true }
          }
        }

        Text {
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
          text: "updates every 3s"
          font.pixelSize: 10
          color: root.subdued
        }
      }
    }
  }
}

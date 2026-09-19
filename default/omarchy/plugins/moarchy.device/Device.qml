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
// It is still launched from the app drawer like an app, via a .desktop entry whose
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
import qs.Ui as Ui
import "../moarchy.common/Theme.js" as Theme
import "../moarchy.common" as Shared
import "../moarchy.common/Sheet.js" as Sheet

Item {
  id: root

  // Injected by the host after construction, and not `readonly` or `required` --
  // see the app drawer, which also says why this is the only one declared (J8).
  property var shell: null

  readonly property string pluginId: "moarchy.device"

  property bool opened: false
  property string returnTo: ""

  // Palette, C1's full-screen block: this is a Top layer surface like the app drawer
  // and the theme picker, so it reads `Color.menu.*`.
  //
  // It read `Color.surface`, `Color.surfaceContainer`, `Color.onSurface`,
  // `Color.onSurfaceVariant` and `Color.primary` until 2026-09-15. Those are
  // Material role names and upstream's `Color` singleton has never had any of
  // them -- it carries `foreground`, `background`, `accent`, `urgent`, `muted`
  // and a nested object per layer. So all five guards were false, every colour
  // on this screen was the hex written beside it, and the comment here said the
  // screen recoloured with everything else while it had never recoloured once.
  //
  // C4 permits a hex behind a `typeof Color` guard, which is exactly why no
  // check caught this: the guard was the thing that was wrong. It is the third
  // time this one file has claimed in a comment to match the others while
  // matching none of them -- raw pixels, then no font family, now the palette.
  readonly property color surface: Color.menu.background
  readonly property color textOnSurface: Color.menu.text
  readonly property color container: Util.alpha(Color.menu.text, 0.08)
  readonly property color accent: Color.accent

  // C3: computed against the surface it is read on, never fixed at an alpha.
  readonly property color subdued: Theme.readableOn(root.surface, Color.menu.text,
                                                   0.55, 4.5)

  // The veil is shared (docs/refactor.md E2); the default ink is this
  // surface's own, which is the half a shared type cannot know (style.md H2).
  component PressVeil: Shared.PressVeil { ink: root.textOnSurface }

  // The weight the bar and every other screen in this shell run at. This file
  // used to say `font.bold` on two lines and nothing on the rest, which is how
  // it came to be the one screen that did not match (docs/style.md B3).
  readonly property int textWeight: Font.DemiBold

  // The card radius, from the four this shell has (docs/style.md D1). Was a
  // bare Style.space(14) -- a fifth radius nobody chose, which left this
  // screen's two panels 4px sharper than every card on the phone next to them.
  Shared.UiFile { id: ui }
  readonly property int radiusTile: ui.radiusTile
  readonly property int radiusCard: ui.radiusCard

  property var facts: ({})

  function open(payloadJson) {
    // Only one full-screen plugin should be up at a time, or the one underneath
    // keeps its keyboard grab and swallows the back gesture.
    Sheet.cover(root.shell, root.pluginId, Sheet.TOP)
    root.returnTo = Sheet.payload(payloadJson).returnTo || ""
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

  // Short target, matching every other plugin here -- the selftest and
  // moarchy-* scripts address these as `omarchy-shell device state`, not
  // by plugin id.
  //
  // open() goes through the shell rather than calling root.open() directly.
  // root.open() is the host's summon hook, the mirror of close(): calling it
  // ourselves sets local state without the shell ever learning the plugin is
  // up, so the surface does not take focus and toggle() disagrees with what is
  // on screen. Same host-versus-self distinction that made close() recurse,
  // pointing the other way.
  IpcHandler {
    target: "device"

    function state(): string { return root.opened ? "open" : "closed" }
    function open(): string { Sheet.summon(root.shell, root.pluginId); return "ok" }
    function close(): string { root.dismiss(); return "ok" }

    // The control for docs/gestures.md I2. This surface takes no bottom margin,
    // so its `h` is what a Top surface with a zero exclusive zone gets when it
    // is arranged normally -- the number the three extended sheets must each
    // exceed by exactly one strip. `strip=0` and `gap=-1` say "not applicable"
    // rather than "measured zero".
    function geometry(): string {
      return "w=" + deviceWindow.width
           + " h=" + deviceWindow.height
           + " margin=" + deviceWindow.margins.bottom
           + " strip=0"
           + " gap=-1"
           + " screen=" + (deviceWindow.screen
               ? deviceWindow.screen.width + "x" + deviceWindow.screen.height : "?")
    }

    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }
  }

  Timer {
    id: ticker
    interval: 3000
    repeat: true
    onTriggered: probe.running = true
  }

  Shared.Probe {
    id: probe
    running: false
    command: ["sh", "-c", `
      printf 'model=%s\\n' "$(tr -d '\\0' < /proc/device-tree/model 2>/dev/null)"
      printf 'cores=%s\\n' "$(grep -c ^processor /proc/cpuinfo)"
      f=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
      [ -n "$f" ] && printf 'mhz=%s\\n' "$((f/1000))"
      # The first supply that says it is a battery, not a named one
      # (refactor.md N3, devices.md D3). This read axp20x-battery -- the PinePhone's PMIC --
      # behind the same 2>/dev/null the other reads use, so on any other phone
      # the screen reported no battery rather than reporting an error.
      for d in /sys/class/power_supply/*/; do
        [ "$(cat "$d/type" 2>/dev/null)" = Battery ] && { b=$d; break; }
      done
      printf 'batt=%s\\n' "$(cat "$b/capacity" 2>/dev/null)"
      printf 'battstatus=%s\\n' "$(cat "$b/status" 2>/dev/null)"
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
    onAnswered: {
      const next = {}
      for (const line of text.split("\n")) {
        const i = line.indexOf("=")
        if (i > 0) next[line.slice(0, i)] = line.slice(i + 1).trim()
      }
      root.facts = next
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
    id: deviceWindow

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "moarchy-device"
    WlrLayershell.layer: WlrLayer.Top

    // No bottom margin here, deliberately, and this is the one surface that
    // must not get one. The app drawer, Settings and the theme picker extend under
    // the gesture strip; this stays arranged inside the usable area so it can
    // be the control they are measured against -- same layer, same zero zone,
    // no margin, so the difference between its height and theirs is the margin
    // and nothing else (docs/gestures.md I2).
    //
    // An absolute assertion would not do instead: the workspace rect carries a
    // `gaps inner` inset that layer-surface arrangement does not, so it would
    // fail on arithmetic rather than on behaviour. Before removing the
    // asymmetry, read I2.
    exclusiveZone: 0
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive
                                             : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: root.surface

      Keys.onEscapePressed: root.dismiss()

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(14)

        // Header: back chevron, title. Mirrors every other screen in this shell
        // so the plugin does not announce itself as something different -- a
        // claim this header made in a comment long before it was true. It was
        // drawn in raw pixels at a font the theme does not set, with a
        // typographic ‹ where the other three headers use the Nerd Font
        // chevron through Ui.OpticalGlyph (docs/style.md A1-A3, B1).
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)

          Item {
            width: Style.space(40); height: width

            // 40 drawn, 44 answering, so the veil takes the 40 (docs/style.md
            // H8, E2). This replaces the one hand-rolled press state in the
            // shell -- container against "transparent", snapping with no fade,
            // and fading *from* "transparent" is the grey wash H3 rules out.
            PressVeil {
              anchors.fill: parent
              radius: ui.radiusOn(width)
              on: backArea.pressed
            }

            // Centred on the ink rather than on the advance, for the reason
            // the Settings header's own back button spells out: a Nerd Font
            // glyph is rarely centred inside the box the font reserves for it.
            Ui.OpticalGlyph {
              anchors.fill: parent
              text: ""
              fontFamily: Style.font.family
              fontSize: Style.font.icon
              color: root.textOnSurface
            }

            // 40 drawn, 44 answering (docs/style.md E1, E2). Nothing
            // sits within 2px of this circle: the title is 10px to its right
            // and the surface margin is 16px to its left.
            MouseArea {
              id: backArea
              anchors.fill: parent
              anchors.margins: -Style.space(2)
              onClicked: root.dismiss()
            }
          }

          Text {
            Layout.fillWidth: true
            text: "Device"
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: root.textWeight
            color: root.textOnSurface
          }
        }

        Text {
          Layout.fillWidth: true
          text: root.facts.model || "…"
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.weight: root.textWeight
          color: root.subdued
          wrapMode: Text.WordWrap
        }

        // Battery and temperature get the top slot: they are the two things you
        // open this for, and the only two that change on their own.
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(12)

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
              Layout.preferredHeight: Style.space(84)
              radius: root.radiusCard
              color: root.container
              ColumnLayout {
                anchors.centerIn: parent
                spacing: Style.space(2)
                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: modelData.value
                  font.family: Style.font.family
                  font.pixelSize: Style.font.display
                  font.weight: root.textWeight
                  color: root.accent
                }
                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: modelData.label
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.weight: root.textWeight
                  color: root.subdued
                }
              }
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.fillHeight: true
          radius: root.radiusCard
          color: root.container

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.space(14)
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
                Layout.preferredHeight: Style.space(44)
                spacing: Style.space(8)
                Text {
                  text: modelData.k
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.weight: root.textWeight
                  color: root.subdued
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: modelData.v
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.weight: root.textWeight
                  color: root.textOnSurface
                  elide: Text.ElideLeft
                  Layout.maximumWidth: Style.space(210)
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
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: root.textWeight
          color: root.subdued
        }
      }
    }
  }
}

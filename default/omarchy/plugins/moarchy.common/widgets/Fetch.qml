// The system at a glance, neofetch-style (docs/home.md HM14).
//
// Omalauncher's `fetch` tile in this phone's terms: the Arch logo and
// `user@host` over the theme's colours, then label/value rows -- os, host,
// kernel, uptime, packages, shell, theme, memory, disk, battery. A home tile,
// so the host hands it both its width and its height (HM9) and draws the frame
// (HM10). Rows are dropped from the bottom when the tile is too short for all
// ten, rather than squeezed or overflowed: the top of a fetch is the part
// people read.
//
// All of it comes from ONE process printing `key=value` lines (W3: the widget
// owns its own wiring). Ten probes would be ten forks a minute on an A53 for
// numbers that are all read at the same moment anyway. Nothing the user typed
// goes into the script; it is a constant.
import QtQuick
import qs.Commons
import qs.Ui as Ui
import ".." as Shared

Item {
  id: widget

  property var host: null
  property var shell: null
  property bool preview: false

  // W6. There is always a system to describe.
  readonly property bool available: true

  implicitHeight: Style.space(230)

  // What the script said, keyed as it said it. Empty until the first answer,
  // which draws the header and no rows rather than ten rows of dashes.
  property var facts: ({})

  // W26. Canned, and shaped like the phone this ships on.
  readonly property var canned: ({
    user: "moarchy", host: "moarchy", os: "Arch Linux ARM",
    model: "Google Pixel 3a", kernel: "6.12.4-1-sargo", uptime: "9000",
    packages: "812", shell: "bash", theme: "Tokyo Night",
    mem: "1932735283 3865470566", disk: "9234567890 51234567890",
    battery: "84 Discharging"
  })

  // The script. One fork of bash a minute while home is on screen.
  //
  //   packages  the local db's directories, not `pacman -Qq | wc -l`: the same
  //             count without starting pacman, which takes a lock-free but
  //             full read of the db every minute for one number.
  //   theme     upstream's own file, reworded the way `omarchy-theme-current`
  //             rewords it ("tokyo-night" -> "Tokyo Night"), inline rather than
  //             by calling it so a missing helper is an empty row, not a fork
  //             that fails.
  //   model     the device tree's name for the board (NUL-terminated, hence
  //             the `tr`), and DMI's on a machine without one.
  //   battery   the first supply that calls itself a Battery: the charger
  //             and the USB port are supplies too, and have no capacity.
  readonly property string script: [
    ". /etc/os-release 2>/dev/null",
    "echo \"user=$(id -un)\"",
    "echo \"host=$(cat /proc/sys/kernel/hostname 2>/dev/null)\"",
    "echo \"os=${PRETTY_NAME:-${NAME:-Linux}}\"",
    "m=$(tr -d '\\0' 2>/dev/null < /sys/firmware/devicetree/base/model)",
    "[ -n \"$m\" ] || m=$(cat /sys/class/dmi/id/product_name 2>/dev/null)",
    "echo \"model=$m\"",
    "echo \"kernel=$(uname -r)\"",
    "echo \"uptime=$(cut -d' ' -f1 /proc/uptime)\"",
    "echo \"packages=$(find /var/lib/pacman/local -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)\"",
    "echo \"shell=$(basename \"${SHELL:-sh}\")\"",
    "t=\"$HOME/.local/state/omarchy/current/theme.name\"",
    "[ -f \"$t\" ] && echo \"theme=$(sed -E 's/(^|-)([a-z])/\\1\\u\\2/g; s/-/ /g' \"$t\")\"",
    "free -b | awk '/^Mem:/ { print \"mem=\" $3 \" \" $2 }'",
    "df -B1 / | awk 'NR == 2 { print \"disk=\" $3 \" \" $2 }'",
    "for b in /sys/class/power_supply/*; do",
    "  [ \"$(cat \"$b/type\" 2>/dev/null)\" = Battery ] || continue",
    "  echo \"battery=$(cat \"$b/capacity\" 2>/dev/null) $(cat \"$b/status\" 2>/dev/null)\"",
    "  break",
    "done",
    "true"
  ].join("\n")

  function parse(text) {
    var out = {}
    var lines = String(text).split("\n")
    for (var i = 0; i < lines.length; i++) {
      var at = lines[i].indexOf("=")
      if (at <= 0) continue
      out[lines[i].slice(0, at)] = lines[i].slice(at + 1).trim()
    }
    return out
  }

  // The host calls this when home opens (the W-column convention), so the
  // uptime is right the moment the tile is looked at and not up to a minute
  // later. A run already in flight is the answer to this call too.
  function refresh() {
    if (widget.preview || probe.running) return
    probe.running = true
  }

  Shared.Probe {
    id: probe
    command: ["bash", "-c", widget.script]
    onAnswered: function (text) { widget.facts = widget.parse(text) }
  }

  // One fork a minute for as long as this tile's page is built. Not stopped
  // behind an app: home's surface stays mapped under every window, so nothing
  // here becomes invisible when one opens. The host's refresh() on the way back
  // to home is what makes the numbers current when someone looks.
  Timer {
    interval: 60000
    running: !widget.preview && widget.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: widget.refresh()
  }

  // --- the numbers as somebody reads them ---------------------------------

  // "1.8G", one decimal under ten and none above, as free -h and fastfetch do.
  function bytes(n) {
    var units = ["B", "K", "M", "G", "T"]
    var v = Number(n) || 0
    var i = 0
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
    return (v < 10 && i > 0 ? v.toFixed(1) : String(Math.round(v))) + units[i]
  }

  function usage(pair) {
    var parts = String(pair || "").split(" ")
    var used = Number(parts[0]), total = Number(parts[1])
    if (!isFinite(used) || !isFinite(total) || total <= 0) return ""
    return widget.bytes(used) + " / " + widget.bytes(total)
      + " (" + Math.round(used / total * 100) + "%)"
  }

  function since(seconds) {
    var s = Math.floor(Number(seconds) || 0)
    if (s <= 0) return ""
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
    if (d > 0) return d + "d " + h + "h"
    if (h > 0) return h + "h " + m + "m"
    return m + "m"
  }

  function charge(value) {
    var parts = String(value || "").split(" ")
    if (!parts[0].length) return ""
    var state = (parts.slice(1).join(" ") || "").toLowerCase()
    // "Not charging" is what a full phone on its charger says, and "unknown"
    // is a supply that does not say: neither is worth the width.
    return parts[0] + "%" + (state === "charging" || state === "discharging"
                             ? " · " + (state === "charging" ? "charging" : "on battery")
                             : "")
  }

  readonly property var source: widget.preview ? widget.canned : widget.facts

  readonly property string who: {
    var f = widget.source
    if (!f.user && !f.host) return ""
    return (f.user || "?") + "@" + (f.host || "?")
  }

  // In fetch's order. A row with nothing to say is left out rather than
  // printed as a dash, so a desktop with no battery has nine rows, not a
  // tenth reading "battery —".
  readonly property var rows: {
    var f = widget.source
    var all = [
      { label: "os",       value: f.os || "" },
      { label: "host",     value: f.model || "" },
      { label: "kernel",   value: f.kernel || "" },
      { label: "uptime",   value: widget.since(f.uptime) },
      { label: "packages", value: f.packages && f.packages !== "0" ? f.packages + " (pacman)" : "" },
      { label: "shell",    value: f.shell || "" },
      { label: "theme",    value: f.theme || "" },
      { label: "memory",   value: widget.usage(f.mem) },
      { label: "disk",     value: widget.usage(f.disk) },
      { label: "battery",  value: widget.charge(f.battery) }
    ]
    var out = []
    for (var i = 0; i < all.length; i++) if (all[i].value.length) out.push(all[i])
    return out
  }

  // --- drawing ------------------------------------------------------------

  // The type every row is set in, measured once so the row count is
  // arithmetic and not a layout pass that discovers the overflow.
  FontMetrics {
    id: rowMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  TextMetrics {
    id: labelMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    text: "packages"
  }

  Shared.PressVeil {
    anchors.fill: parent
    radius: widget.host ? widget.host.radiusCard : 0
    ink: widget.host.textOnSurface
    on: tileArea.pressed && !widget.host.sheetDragging
  }

  Item {
    id: content
    anchors.fill: parent
    anchors.margins: Style.space(10)

    readonly property int rowHeight: Math.ceil(rowMetrics.height)
    // As many rows as fit under the header, and never a partial one.
    readonly property int fits: Math.max(0, Math.floor(
      (content.height - header.height - Style.space(8)) / content.rowHeight))

    Row {
      id: header
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(8)

      // linux-archlinux, from the Nerd Font logos range rather than Material:
      // md-arch (U+F08C7) is an archway, not the distribution. Read out of
      // glyphnames.json by name and checked against JetBrainsMono Nerd Font's
      // cmap.
      Ui.OpticalGlyph {
        id: logo
        anchors.verticalCenter: parent.verticalCenter
        width: Style.font.display + Style.space(8)
        height: width
        text: ""
        fontFamily: Style.font.family
        fontSize: Style.font.display
        color: widget.host.accent
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: header.width - logo.width - header.spacing
        spacing: Style.space(4)

        Text {
          width: parent.width
          text: widget.who
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.weight: widget.host.textWeight
          color: widget.host.accent
          elide: Text.ElideRight
        }
        // The palette strip under the name. Only the host's roles (W4): a
        // tile does not get the terminal's sixteen, and these are the colours
        // home is actually drawn in.
        Row {
          spacing: Style.space(2)
          Repeater {
            model: [widget.host.accent, widget.host.textOnSurface,
                    widget.host.subdued, widget.host.containerHigh,
                    widget.host.textOnAccent]
            delegate: Rectangle {
              required property var modelData
              width: Style.space(12)
              height: Style.space(6)
              color: modelData
            }
          }
        }
      }
    }

    Column {
      anchors.top: header.bottom
      anchors.topMargin: Style.space(8)
      anchors.left: parent.left
      anchors.right: parent.right

      Repeater {
        model: widget.rows.slice(0, content.fits)
        delegate: Row {
          required property var modelData
          width: content.width
          height: content.rowHeight
          spacing: Style.space(6)

          Text {
            width: Math.ceil(labelMetrics.advanceWidth)
            text: modelData.label
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.weight: widget.host.textWeight
            color: widget.host.accent
          }
          Text {
            width: parent.width - Math.ceil(labelMetrics.advanceWidth) - parent.spacing
            text: modelData.value
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.weight: widget.host.textWeight
            color: widget.host.textOnSurface
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // The tile opens the Device screen, which is these numbers live and in full.
  // Through the host (W5). A drag that starts here still turns home's page
  // (HM14b).
  Shared.SheetDragArea {
    id: tileArea
    sheet: widget.host.sheet
    anchors.fill: parent
    onClicked: if (!widget.preview && !widget.host.sheetWasDrag)
      widget.host.openScreen("moarchy.device")
  }
}

// The brightness slider (docs/control-center.md S12, S13, S15).
//
// A widget: one file, no manifest, no id of its own (docs/widgets.md W1). It
// owns its own plumbing -- the probe and the write are here, not on the host --
// which is what lets a second surface have a working brightness slider by
// naming it in an arrangement (W3).
import QtQuick
import Quickshell
import ".." as Shared

Item {
  id: widget

  // Handed in by WidgetColumn before the first binding evaluates (W10).
  property var host: null
  property var shell: null

  // W37. Drawn in the Settings arrangement list rather than on the surface.
  // The values are canned and every action is a no-op: the list is a list of
  // real widgets, so without this, arranging them would toggle the radio,
  // move the brightness and open screens from inside a settings page.
  property bool preview: false

  // W6. The screen is the one piece of hardware a phone always has, so this
  // one is never absent. A widget that could not draw says so here and the
  // column closes the gap.
  readonly property bool available: true

  implicitHeight: slider.implicitHeight

  // S13. Never below 1%. The screen is the only way to see the control that
  // would put it back, so a slider that reached 0 would be a slider you cannot
  // find again.
  property int percent: 50

  // Pulled when the host opens rather than on a timer: it does not change while
  // the surface is shut, and a phone that forks brightnessctl every ten seconds
  // for a panel nobody is looking at is just a slower phone.
  function refresh(): void {
    if (widget.preview) return
    if (!probe.running) probe.running = true
  }

  Component.onCompleted: widget.refresh()

  Shared.Probe {
    id: probe
    command: ["bash", "-c", "brightnessctl -d backlight -m | cut -d, -f4 | tr -d '%\\n'"]
    onAnswered: {
      var v = parseInt(text.trim(), 10)
      if (isFinite(v)) widget.percent = Math.max(1, Math.min(100, v))
    }
  }

  function set(value): void {
    if (widget.preview) return
    var v = Math.max(1, Math.min(100, Math.round(value)))
    widget.percent = v
    Quickshell.execDetached(["brightnessctl", "-d", "backlight", "set", v + "%"])
  }

  Shared.FatSlider {
    id: slider
    host: widget.host
    width: widget.width
    glyph: "󰃟"
    // S12. Commits on release, not while dragging: each write forks
    // brightnessctl, and one fork per frame of a drag is a drag that stutters.
    live: false
    value: (widget.preview ? 70 : widget.percent) / 100
    onCommitted: v => widget.set(v * 100)
  }
}

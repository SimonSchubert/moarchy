// The volume slider (docs/control-center.md S14, S15).
//
// The second widget, and the one that proves the contract: it and Brightness
// draw the same primitive with different plumbing behind it, and neither knows
// which surface it is on (docs/widgets.md W3).
import QtQuick
import Quickshell.Services.Pipewire
import ".." as Shared

Item {
  id: widget

  property var host: null
  property var shell: null

  // W37. Drawn in the Settings arrangement list rather than on the surface.
  // The values are canned and every action is a no-op: the list is a list of
  // real widgets, so without this, arranging them would toggle the radio,
  // move the brightness and open screens from inside a settings page.
  property bool preview: false

  // S14. Hidden entirely when there is no sink, not drawn dead. A slider that
  // moves and changes nothing is the worse of the two answers, and W6 is the
  // general form of that rule.
  readonly property bool available: widget.preview || (widget.sink && widget.sink.audio)

  implicitHeight: slider.implicitHeight

  readonly property var sink: Pipewire.defaultAudioSink
  // Without the tracker the sink's `audio` object is never bound and `volume`
  // reads as a constant.
  PwObjectTracker { objects: widget.sink ? [widget.sink] : [] }

  readonly property real level:
    widget.preview ? 0.45
    : (widget.sink && widget.sink.audio ? widget.sink.audio.volume : 0)

  function set(value): void {
    if (widget.preview) return
    if (widget.sink && widget.sink.audio) widget.sink.audio.volume = value
  }

  Shared.FatSlider {
    id: slider
    host: widget.host
    width: widget.width
    glyph: "󰕾"
    // In-process, so it follows the finger. Brightness cannot: it forks per
    // write and waits for the release instead.
    live: true
    value: widget.level
    onCommitted: v => widget.set(v)
  }
}

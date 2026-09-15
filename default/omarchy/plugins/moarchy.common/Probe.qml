// Ask the system a question and hand back what it said (docs/refactor.md J2).
//
// Usage:
//     Shared.Probe {
//       id: airplaneProbe
//       command: ["bash", "-c", "cat /sys/class/rfkill/*/soft | sort -u"]
//       onAnswered: root.airplane = text.trim() === "1"
//     }
//
// Seventeen of these stood in seven plugins, each writing out the same three
// lines -- `stdout: StdioCollector {`, `onStreamFinished:`, and the brace that
// closes them -- around a body that only ever wanted the text. A `Process` is
// how this shell reads anything the compositor and the QML APIs do not expose:
// rfkill, brightnessctl, busctl, mmcli, pacman, and the plain files that are
// easier to `cat` than to watch.
//
// `text` in the handler is this signal's argument and is already a string, so a
// body that read `String(text || "")` can simply read `text`. That defensive
// wrapper was in most of the seventeen and was never needed in any of them:
// StdioCollector's `text` is a QString.
//
// ---------------------------------------------------------------------------
// What it does not own
// ---------------------------------------------------------------------------
// **The command, and when to run it.** Both are `Process`'s own properties and
// every caller sets them differently -- some on a timer, some on a tap, some
// once at startup. This adds a signal and takes nothing away.
//
// **stderr.** Left to `Process`'s default, which is what all seventeen did. A
// probe that needs it declares `stderr:` itself, and that does not collide with
// the `stdout` collector below.
//
// Declaring `stdout` on an instance replaces this one rather than adding to it,
// and the probe then answers nothing at all -- `scripts/style-check.sh` fails on
// that, the same way it does for SheetDragArea's four handlers.
import QtQuick
import Quickshell.Io

Process {
  id: probe

  // What the command printed, with the trailing newline the shell adds still on
  // it: trimming here would take it from the callers that parse whitespace.
  signal answered(string text)

  stdout: StdioCollector {
    onStreamFinished: probe.answered(this.text)
  }
}

// A control on a sheet that also drags it (docs/refactor.md H3).
//
// Usage:
//     // once per plugin, beside `component PressVeil:`
//     component SheetArea: Shared.SheetDragArea { sheet: root }
//
//     // at each of the twelve call sites
//     SheetArea {
//       id: tileArea
//       anchors.fill: parent
//       onClicked: if (!root.sheetWasDrag) tile.activated()
//     }
//
// Every full-screen sheet in this shell is dragged by the controls drawn on it
// rather than by a handler over them: `AppDrawer.qml` and `ControlCenter.qml` both record,
// from measurement, that a `DragHandler` across the content receives one
// translation event per gesture, because each content `MouseArea` holds the
// exclusive grab. So the sheet's drag is fed by hand from every control, and
// the four lines that do it stood twelve times -- eight in the control center, four in
// the app drawer.
//
// It is not a tidiness question. A control that omits one of the four is not
// obviously wrong on screen: it still lights, it still clicks, and the sheet
// simply cannot be dragged from it. Since F2 gave every tracker a watchdog,
// omitting the *release* is worse than that -- the press arms the watchdog, and
// four seconds later the tracker concludes the touch was stranded and puts
// progress back, which lands on whatever gesture came next. Two controls had
// exactly that shape for as long as they had existed (F8).
//
// ---------------------------------------------------------------------------
// What it does not own
// ---------------------------------------------------------------------------
// **The tracker, and the mapping into scene coordinates.** Those live on the
// sheet, in `sheetPress`/`sheetMove`/`sheetRelease`/`sheetCancel`, because each
// sheet does something of its own on the way in: the app drawer clears `holdFired`,
// the control center resets its trace. This forwards to them and knows neither.
//
// **The press state.** `pressed` comes from MouseArea, and what a control does
// with it is style.md H1 and H6 -- including the drag guard, since `pressed`
// stays true for the whole drag on exactly these areas.
//
// ---------------------------------------------------------------------------
// The one trap
// ---------------------------------------------------------------------------
// Declaring `onPressed` (or any of the other three) on an *instance* replaces
// the handler below rather than adding to it, and the control then silently
// stops driving the sheet -- which is the failure this component exists to make
// impossible. Extra work goes through the three hooks, and
// `scripts/style-check.sh` fails the day an instance declares one of the four.
import QtQuick

MouseArea {
  id: area

  // The sheet being dragged: the plugin's own root, which owns the tracker.
  property var sheet: null

  // Extra work this particular control needs. `area` is handed over rather
  // than reached for as `this`, because `this` inside a handler declared at the
  // call site is the call site's scope and not reliably this item.
  signal grabbed(var area, var mouse)
  signal dragged(var area, var mouse)
  signal ungrabbed()

  // The sheet first on the way in, the control's own work first on the way out,
  // which is the order the twelve hand-written copies used.
  //
  // A null sheet is a host that is not dragged at all, not a mistake
  // (docs/widgets.md W13): the same widget draws on the control center, which
  // is a sheet, and on a host that is not one. Guarded here rather than at the
  // call sites, because a widget that had to ask would be a widget that knows
  // what kind of surface it is on -- which is the coupling this whole
  // arrangement exists to remove.
  onPressed: mouse => {
    if (area.sheet) area.sheet.sheetPress(area, mouse)
    area.grabbed(area, mouse)
  }
  onPositionChanged: mouse => {
    if (area.sheet) area.sheet.sheetMove(area, mouse)
    area.dragged(area, mouse)
  }
  onReleased: { area.ungrabbed(); if (area.sheet) area.sheet.sheetRelease() }
  onCanceled: { area.ungrabbed(); if (area.sheet) area.sheet.sheetCancel() }
}

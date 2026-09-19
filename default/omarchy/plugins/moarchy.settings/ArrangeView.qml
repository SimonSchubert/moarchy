// Arranging what a surface draws, by dragging it (docs/widgets.md §E).
//
// The list is the surface: each card is the real widget drawn with mock data
// (Shared.Preview) with a handle beside it, and nothing else. No name over it
// and no switch next to it -- a row that looks like the thing it arranges
// needs neither, and both were chrome between you and the picture.
//
// Whether a widget is shown is **where it is**. Everything above the divider is
// drawn on the surface, in that order; everything below it is not. Dragging a
// card across the divider is how it goes away and how it comes back, so there
// is one gesture on this page rather than a gesture and a control.
//
// ---------------------------------------------------------------------------
// The divider is a row in the model
// ---------------------------------------------------------------------------
// It could have been a flag per card and a line drawn between the groups. It is
// a row instead, and that removes the flag entirely: "shown" is
// `index < dividerIndex`, and a plain `ListModel.move()` across that index both
// reorders and hides in one operation, with no case analysis about which group
// a card is leaving and which it is joining.
//
// ---------------------------------------------------------------------------
// A ListModel, and the cards are laid out by hand
// ---------------------------------------------------------------------------
// **ListModel, not a JS array.** A Repeater over an array rebuilds every
// delegate when the array changes, so the first reorder would destroy the card
// under the thumb -- the drag dies on its own first success. `move()` moves the
// rows and keeps the instances.
//
// **Laid out by hand, not by a Column.** A positioner assigns `y` to its
// children, so a dragged card cannot also follow a finger: the positioner wins
// and the binding is gone on the first frame. A ListView repositions delegates
// underneath a drag for the same reason. Eight cards is small enough that
// summing the heights above each one is cheaper than either, and it is the only
// version where the card under the thumb is the card that moves.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui
import "../moarchy.common" as Shared
import "../moarchy.common/Widgets.js" as Catalogue
import "Pages.js" as Pages

Item {
  id: view

  // The host the previews draw with -- Settings itself, whose palette is
  // Color.menu where the control center's is Color.popups. One Preview serves
  // both because it takes the host (docs/style.md C2).
  property var host: null
  property string surface: ""

  // W24c. A card whose widget arranges a list of its own carries a way in to
  // it. The page is pushed by Settings, which owns the stack -- this only says
  // where.
  signal navigate(string page)

  // The one row that is not a widget. An id no catalogue can answer to, so a
  // stray `-` in the file can never collide with it.
  readonly property string dividerId: "--divider--"

  Shared.WidgetsFile { id: arrangement }

  ListModel { id: order }

  property bool seeded: false

  // Where the line sits, as a **property** and not as a function call in a
  // binding. A function that walks the ListModel is not a dependency QML can
  // track, so `index > dividerIndex()` would only re-evaluate when the row's
  // own index happened to change -- which is true today and is the kind of
  // thing that stops being true the first time a card is added or removed
  // rather than moved.
  property int dividerAt: 0

  function findDivider(): void {
    for (var i = 0; i < order.count; i++)
      if (order.get(i).itemId === view.dividerId) { view.dividerAt = i; return }
    view.dividerAt = order.count
  }

  // The order the file should hold for what is on screen: shown first, in
  // their order, then the hidden ones in theirs.
  function layoutFor(rows) {
    var out = []
    for (var i = 0; i < rows.length; i++) if (rows[i].on) out.push(rows[i].id)
    out.push(view.dividerId)
    for (var j = 0; j < rows.length; j++) if (!rows[j].on) out.push(rows[j].id)
    return out
  }

  function matches(want) {
    if (!view.seeded || want.length !== order.count) return false
    for (var i = 0; i < want.length; i++)
      if (order.get(i).itemId !== want[i]) return false
    return true
  }

  function seed(): void {
    var want = view.layoutFor(arrangement.resolve(view.surface))

    // Nothing to do, and returning here is the whole fix for a list that
    // jumped back to the top after every change. Every commit comes back
    // through the file watch as a change, so this ran after every drop -- and
    // `order.clear()` takes the content height to zero, which makes the
    // Flickable clamp contentY to 0 before the rows are put back. The list was
    // right and the scroll was gone.
    if (view.matches(want)) return

    // A real external change -- another session, a hand edit. Rebuild, but put
    // the viewport back where it was rather than at the top.
    var keepY = flick.contentY
    order.clear()
    for (var i = 0; i < want.length; i++)
      order.append({ itemId: want[i] })
    view.seeded = true
    view.findDivider()
    Qt.callLater(function () {
      flick.contentY = Math.max(0, Math.min(keepY,
                                            Math.max(0, flick.contentHeight - flick.height)))
    })
  }

  readonly property string body: arrangement.body
  onBodyChanged: if (!pile.dragging) view.seed()
  Component.onCompleted: view.seed()

  // Navigating between the two arrangement pages does not build a second view:
  // Settings' Loader keeps one item and hands it a new `surface`. Without this
  // the model still held the previous surface's ids, and since none of them is
  // in the new surface's catalogue every card collapsed to a bare handle --
  // which reads as "the previews are broken" rather than "this is the wrong
  // list". Both pages were debugged as rendering faults before `report()`
  // showed the widgets page listing the toggles' arrangement.
  //
  // The measured heights go too: they are keyed by id, and the ids are the
  // thing that just changed.
  onSurfaceChanged: {
    view.cardHeight = ({})
    view.seeded = false
    view.seed()
  }

  function idsLine(): string {
    var out = []
    var past = false
    for (var i = 0; i < order.count; i++) {
      var id = order.get(i).itemId
      if (id === view.dividerId) { past = true; continue }
      out.push((past ? "-" : "") + id)
    }
    return out.join(", ")
  }

  function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

  // W24a. What this page is actually showing, for a check that has no finger:
  // one row per card, `id  shown  height`, in the order they are drawn. The
  // divider is a row like any other and reports as `--divider--`, so "which
  // side of the line is this on" is answerable from a terminal.
  //
  // It exists because the first version of this page could only be checked by
  // looking at a screenshot and counting rectangles, which is how a collapsed
  // preview got mistaken for a missing widget twice.
  function report(): string {
    var out = []
    for (var i = 0; i < order.count; i++) {
      var id = order.get(i).itemId
      out.push([id,
                id === view.dividerId ? "divider" : (i < view.dividerAt ? "shown" : "hidden"),
                Math.round(view.heightOf(id))].join("\t"))
    }
    return out.join("\n")
  }

  // W30. One write for the whole order. A drag that ends four places down is
  // one decision, not four: four `up` calls would each race the file watch and
  // each leave a frame of a different arrangement on screen.
  function commit(): void {
    if (writer.running) writer.running = false
    writer.command = ["bash", "-lc",
                      "moarchy-widgets set " + view.shellQuote(view.surface)
                      + " " + view.shellQuote(view.idsLine())]
    writer.running = true
  }

  Process { id: writer }

  // ------------------------------------------------------------- geometry
  //
  // Each row measures itself once its preview has loaded and writes its height
  // in here by id -- by id and not by index, because the index is exactly what
  // a drag changes.
  property var cardHeight: ({})
  readonly property int gap: Style.space(10)

  function noteHeight(itemId, h): void {
    if (h <= 0 || view.cardHeight[itemId] === h) return
    var next = ({})
    for (var k in view.cardHeight) next[k] = view.cardHeight[k]
    next[itemId] = h
    view.cardHeight = next
  }

  function heightOf(itemId) {
    var h = view.cardHeight[itemId]
    return (h === undefined || h <= 0) ? Style.space(90) : h
  }

  function slotY(index) {
    var y = 0
    for (var i = 0; i < index && i < order.count; i++)
      y += view.heightOf(order.get(i).itemId) + view.gap
    return y
  }

  // Which slot a card dragged to this y belongs in: the one whose span holds
  // the dragged card's own middle. Against the middle and not the top, so a
  // tall card need not be dragged past a short one's whole height before
  // anything moves.
  function slotAt(centre) {
    var y = 0
    for (var i = 0; i < order.count; i++) {
      var h = view.heightOf(order.get(i).itemId)
      if (centre < y + h / 2 + view.gap / 2) return i
      y += h + view.gap
    }
    return Math.max(0, order.count - 1)
  }

  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: width
    contentHeight: pile.height + Style.space(24)
    boundsBehavior: Flickable.StopAtBounds
    // A flick and a card drag cannot both own the gesture. The Flickable loses
    // while a card is held: it is the one that can be given back.
    interactive: !pile.dragging && contentHeight > height
    clip: true

    Item {
      id: pile
      width: flick.width
      height: order.count ? view.slotY(order.count) : 0

      // The held card by **id**, never by index: a move renumbers every card
      // after it, so an index would follow whichever card took its place and
      // the drag would jump to a different widget on its first swap.
      property string heldId: ""
      readonly property bool dragging: pile.heldId !== ""

      Repeater {
        model: order

        delegate: Item {
          id: row
          required property string itemId
          required property int index

          readonly property bool isDivider: row.itemId === view.dividerId

          // The surface this card's widget arranges, if any, and the page that
          // arranges it. Only the toggles have one today.
          readonly property string arranges: {
            var e = Catalogue.entry(view.surface, row.itemId)
            return (e && e.arranges) ? String(e.arranges) : ""
          }
          readonly property bool held: pile.heldId === row.itemId
          // Below the line is not drawn on the surface. Derived, never stored:
          // the position *is* the state (§E).
          readonly property bool hidden: row.index > view.dividerAt

          width: pile.width
          height: row.isDivider ? divider.height
                                : Math.max(grips.height, preview.implicitHeight)
                                  + Style.space(16)

          z: row.held ? 2 : 1
          scale: row.held ? 1.03 : 1
          Behavior on scale { NumberAnimation { duration: 120 } }

          property real dragY: 0
          y: row.held ? row.dragY : view.slotY(row.index)
          Behavior on y {
            enabled: !row.held
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
          }

          onHeightChanged: view.noteHeight(row.itemId, row.height)
          Component.onCompleted: view.noteHeight(row.itemId, row.height)

          // ------------------------------------------------------- drag
          //
          // The handle is the only way. A long press on the body used to do it
          // too, and with a preview under the finger that is a trap: the card
          // is a working-looking slider, and holding a slider to move a row is
          // the one gesture somebody would expect to set the brightness.
          //
          // `startedAt` is the order as it was when the card came up; the
          // release only writes if it differs, so a tap on the handle does not
          // write the file and set the whole watch-and-re-read cycle going for
          // nothing.
          property string startedAt: ""

          function pickUp(): void {
            pile.heldId = row.itemId
            row.dragY = view.slotY(row.index)
            row.startedAt = view.idsLine()
          }

          // A relative delta and not an absolute position, because the handle
          // travels with the card: once it has moved, the finger is back where
          // it grabbed in the handle's own coordinates, so the difference is
          // exactly the distance left to travel. An absolute mapping would
          // double every movement.
          //
          // The move is across the whole list, divider included. Crossing that
          // one index is what hides a widget or brings it back, and it needs no
          // special case: `move()` past it leaves the card on the other side.
          function dragBy(dy): void {
            if (!row.held) return
            row.dragY = Math.max(0, Math.min(pile.height - row.height,
                                             row.dragY + dy))
            var want = view.slotAt(row.dragY + row.height / 2)
            if (want !== row.index) {
              order.move(row.index, want, 1)
              view.findDivider()
            }
          }

          // ------------------------------------------------- auto-scroll
          //
          // Held against the top or bottom of the window, the list scrolls
          // under the card. Without it a drag can only reach as far as the
          // screen: moving the last widget to the top meant dragging as far as
          // it would go, letting go, scrolling, and picking it up again --
          // three gestures for one decision, and the file written twice on the
          // way.
          //
          // Everything here is in the Flickable's **content** coordinates,
          // which is what `dragY` already is, so no mapping is needed: the
          // viewport is the band from `contentY` to `contentY + height`, and
          // the card is near an edge when it overlaps that band's margin.
          readonly property real scrollStep: {
            if (!row.held) return 0
            var span = Math.max(0, flick.contentHeight - flick.height)
            if (span <= 0) return 0

            var band = Style.space(64)
            var top = flick.contentY
            var bottom = flick.contentY + flick.height
            var over = 0
            if (row.dragY < top + band)
              over = row.dragY - (top + band)
            else if (row.dragY + row.height > bottom - band)
              over = (row.dragY + row.height) - (bottom - band)
            if (over === 0) return 0

            // Nowhere left to go in that direction: stop, rather than tick
            // sixty times a second moving nothing.
            if (over < 0 && flick.contentY <= 0) return 0
            if (over > 0 && flick.contentY >= span) return 0

            // Proportional to how far into the band the card has reached, so
            // the edge is a gentle creep and the very edge is quick. 10px a
            // tick at 60Hz is ~600px/s flat out, which crosses a full list in
            // a bit over a second -- fast enough to be worth having, slow
            // enough to stop on the row you wanted.
            var f = Math.max(-1, Math.min(1, over / band))
            return f * Style.space(10)
          }

          Timer {
            running: row.scrollStep !== 0
            interval: 16
            repeat: true
            onTriggered: row.autoScroll()
          }

          function autoScroll(): void {
            var span = Math.max(0, flick.contentHeight - flick.height)
            var next = Math.max(0, Math.min(span, flick.contentY + row.scrollStep))
            var dy = next - flick.contentY
            if (dy === 0) return
            flick.contentY = next
            // The same delta into the card, so it stays under a finger that
            // has not moved -- and `dragBy` re-slots it, which is what makes
            // the reorder happen while the finger is still.
            row.dragBy(dy)
          }

          function drop(): void {
            if (!row.held) return
            pile.heldId = ""
            if (view.idsLine() !== row.startedAt) view.commit()
          }

          // A cancel is the compositor or a second touch taking the gesture,
          // not a decision. The file is the truth, so go back to it rather
          // than writing whatever the half-finished drag had arrived at.
          function abandon(): void {
            if (!row.held) return
            pile.heldId = ""
            view.seeded = false
            view.seed()
          }

          // ---------------------------------------------------- divider
          Item {
            id: divider
            visible: row.isDivider
            width: row.width
            height: Style.space(44)

            Text {
              id: dividerLabel
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              text: "Hidden"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.weight: view.host.textWeight
              color: view.host.subdued
            }

            Rectangle {
              anchors.left: dividerLabel.right
              anchors.leftMargin: Style.space(10)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              height: 1
              color: Util.alpha(view.host.textOnSurface, 0.18)
            }
          }

          // ------------------------------------------------------- card
          Rectangle {
            visible: !row.isDivider
            anchors.fill: parent
            radius: view.host.radiusCard
            color: view.host.container
            // Below the line, faded. The list is about where things are, and a
            // blank card would lose the one thing that says what you are about
            // to bring back.
            opacity: row.hidden ? 0.45 : 1

            // The left rail: the drag handle, and under it the way in to this
            // widget's own list where it has one. Both are here and not on the
            // sheet, because they are controls you want while rearranging and
            // nowhere else.
            Column {
              id: grips
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              // The handle. Sized here rather than from `glyphSlot`, which is
              // what it first used and which changed nothing: that slot is
              // `iconLarge * 1.35` = round(18 * 1.35) = 24, the same 24 the
              // handle already had. Only the ink inside it grew, 14 to 18.
              //
              // This is a control somebody puts a thumb on and holds, not a
              // status glyph, so it takes `display` (24px) in a 34px box, in a
              // target of at least 52 -- deliberately larger than E1's 44,
              // because a thumb that slips off a drag handle drops the card
              // somewhere it was not meant to go.
              Item {
                id: handleSlot
                width: Math.max(Style.space(44), Style.space(34) + Style.space(16))
                height: Math.max(Style.space(52), Style.space(34) + Style.space(16))

                Ui.OpticalGlyph {
                  id: handle
                  anchors.centerIn: parent
                  width: Style.space(34)
                  height: Style.space(34)
                  text: "󰇛"
                  fontFamily: Style.font.family
                  fontSize: Style.font.display
                  color: row.held ? view.host.accent : view.host.subdued
                }

                MouseArea {
                  id: handleArea
                  anchors.fill: parent
                  // Once this has the card, the Flickable must not be able to
                  // take the gesture back mid-drag.
                  preventStealing: true
                  property real grabY: 0

                  onPressed: mouse => { row.pickUp(); handleArea.grabY = mouse.y }
                  onPositionChanged: mouse => row.dragBy(mouse.y - handleArea.grabY)
                  onReleased: row.drop()
                  onCanceled: row.abandon()
                }
              }

              // Under it, and only where there is something to open.
              Item {
                id: editSlot
                visible: row.arranges !== ""
                width: handleSlot.width
                height: visible ? Style.space(44) : 0

                Shared.PressVeil {
                  anchors.centerIn: parent
                  width: Style.space(36)
                  height: width
                  radius: width / 2
                  ink: view.host.textOnSurface
                  on: editArea.pressed
                }

                // md-pencil, read out of the font's cmap
                // (verify-glyphs-against-font-cmap).
                Ui.OpticalGlyph {
                  anchors.centerIn: parent
                  width: Style.space(22)
                  height: Style.space(22)
                  text: "󰏫"
                  fontFamily: Style.font.family
                  fontSize: Style.font.icon
                  color: view.host.subdued
                }

                MouseArea {
                  id: editArea
                  anchors.fill: parent
                  onClicked: {
                    var page = Pages.pageForArrange(row.arranges)
                    if (page !== "") view.navigate(page)
                  }
                }
              }
            }

            Shared.Preview {
              id: preview
              anchors.left: grips.right
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              host: view.host
              surface: view.surface
              itemId: row.itemId
            }

            // Over the preview, so the widget's own controls never see a
            // press. The previews are inert by construction (W26), but a
            // slider that answered a tap here would be a settings page that
            // changes the thing it is describing.
            MouseArea {
              anchors.left: grips.right
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
            }
          }
        }
      }
    }
  }

  // --------------------------------------------------------------- empty
  Text {
    anchors.centerIn: parent
    visible: view.seeded && order.count <= 1
    text: "Nothing to arrange"
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.weight: view.host.textWeight
    color: view.host.subdued
  }
}

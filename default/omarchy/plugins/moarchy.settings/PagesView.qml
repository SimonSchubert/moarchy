// Home's pages, arranged (docs/home.md HM56).
//
// Omalauncher's PagesScreen: one row per page, left to right as home has them,
// a face by its name and a page of tiles by what is on it. The `≡` handle drags
// a row; past the middle of its neighbour the two trade places, and letting go
// writes the new order through `moarchy-home set` -- the one writer of
// home.toml (HM19). A face can be edited by the agent; any page can be removed,
// after saying what goes, except the only page of tiles, which is page 1.
//
// The pages that wait (the face invite, the empty page after the last) are not
// here: they are not in the file, and they are not pages anybody arranges.
//
// The drag is ArrangeView's, for ArrangeView's reasons: a ListModel so a move
// keeps the card under the thumb, laid out by hand so the held card can follow
// the finger, the handle the only way to pick one up.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Upstream
import qs.Ui as Ui
import "../moarchy.common" as Shared
import "../moarchy.common/ShellApps.js" as ShellApps

Item {
  id: view

  // Settings itself: its colour roles, radii and shell.
  property var host: null

  ListModel { id: order }
  property bool seeded: false
  // The row asking whether to remove its page, by key; "" when none is.
  property string confirming: ""
  property int serial: 0

  Shared.AgentFile { id: agents }

  function seed(): void {
    if (!reader.running) reader.running = true
  }
  Component.onCompleted: view.seed()

  // The file changing under the page -- an agent, `moarchy-home`, home's own
  // arranging -- reads it again, so the rows are never an order nobody has.
  // Not while a row is held: the drag's order is the one being decided.
  FileView {
    path: (Quickshell.env("HOME") || "") + "/.config/omarchy/home.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: if (!pile.dragging) Qt.callLater(view.seed)
  }

  Shared.Probe {
    id: reader
    command: ["moarchy-home", "json"]
    onAnswered: {
      var pages = []
      try { pages = JSON.parse(String(text)).page || [] } catch (e) { pages = [] }
      var keepY = flick.contentY
      order.clear()
      for (var i = 0; i < pages.length; i++) {
        view.serial++
        order.append({ key: "p" + view.serial, page: JSON.stringify(pages[i]) })
      }
      view.tilePages = pages.filter(function (p) { return !p.face }).length
      view.confirming = ""
      view.seeded = true
      Qt.callLater(function () {
        flick.contentY = Math.max(0, Math.min(keepY, flick.contentHeight - flick.height))
      })
    }
  }

  function pageAt(i) { return JSON.parse(order.get(i).page) }
  function pagesNow() {
    var out = []
    for (var i = 0; i < order.count; i++) out.push(view.pageAt(i))
    return out
  }
  function orderLine() {
    var out = []
    for (var i = 0; i < order.count; i++) out.push(order.get(i).key)
    return out.join(",")
  }
  // How many pages of tiles there are: the last one has no `remove`. Set when
  // the file is read rather than bound -- a binding cannot see into a
  // ListModel's rows -- and a move does not change it.
  property int tilePages: 0

  // HM4. Page 1 is the first page of tiles; the rest are numbered from it.
  function firstTiles() {
    for (var i = 0; i < order.count; i++) if (!view.pageAt(i).face) return i
    return 0
  }

  // What a page of tiles is called: its widgets by name, as Omalauncher does,
  // because its number changes as pages move.
  function summary(p) {
    if (p.face) return p.face
    var names = (p.tiles || []).map(function (t) { return String(t.widget) })
    return names.length ? names.join(", ") : "empty"
  }

  // One write for the whole order, through the one writer. argv, not a shell
  // string: the JSON carries names the user typed.
  function commit(pages): void {
    if (writer.running) writer.running = false
    writer.command = ["moarchy-home", "set", JSON.stringify({ page: pages })]
    writer.running = true
  }
  Process {
    id: writer
    onExited: Qt.callLater(view.seed)
  }

  function removeAt(i): void {
    var pages = view.pagesNow()
    pages.splice(i, 1)
    view.confirming = ""
    view.commit(pages)
  }

  // HM56. A face's edit is the agent's; a shipped face is copied first,
  // because the packaged file is not the user's to change.
  function editFace(name): void {
    ShellApps.goToFreeWorkspace(view.host ? view.host.shell : null)
    agents.ask("Use the moarchy skill. My home face \"" + name + "\" is "
               + "~/.config/omarchy/faces/" + name + ".qml, or if that does not exist the shipped "
               + "/usr/share/moarchy/plugins/moarchy.home/faces/" + name + ".qml -- in that case copy it "
               + "to ~/.config/omarchy/faces/" + name + ".qml first, which replaces it by name. "
               + "Read it, then ask me what I want changed.")
  }

  // For `settings rows` on this page: one line per page, in order.
  function report(): string {
    var out = []
    var first = view.firstTiles()
    for (var i = 0; i < order.count; i++) {
      var p = view.pageAt(i)
      out.push([i - first + 1, p.face ? "face" : "tiles", view.summary(p)].join("\t"))
    }
    return out.join("\n")
  }

  // ------------------------------------------------------------- geometry
  readonly property int cardHeight: Style.space(96)
  readonly property int gap: Style.space(10)
  function slotY(index) { return index * (view.cardHeight + view.gap) }
  function slotAt(centre) {
    return Math.max(0, Math.min(order.count - 1,
                                Math.floor((centre + view.gap / 2) / (view.cardHeight + view.gap))))
  }

  Text {
    id: intro
    width: parent.width
    text: "Home's pages, left to right. Drag one by ≡ to move it. Home opens on the first with tiles; faces before it sit left of it."
    wrapMode: Text.Wrap
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.weight: view.host ? view.host.textWeight : Font.Normal
    color: view.host ? view.host.subdued : "transparent"
  }

  Flickable {
    id: flick
    anchors.top: intro.bottom
    anchors.topMargin: Style.space(12)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: pile.height + Style.space(24)
    boundsBehavior: Flickable.StopAtBounds
    interactive: !pile.dragging && contentHeight > height
    clip: true

    Item {
      id: pile
      width: flick.width
      height: order.count ? view.slotY(order.count) : 0

      property string heldKey: ""
      readonly property bool dragging: pile.heldKey !== ""

      Repeater {
        model: order

        delegate: Item {
          id: row
          required property string key
          required property string page
          required property int index

          readonly property var data_: JSON.parse(row.page)
          readonly property bool isFace: !!row.data_.face
          readonly property bool held: pile.heldKey === row.key
          readonly property bool asking: view.confirming === row.key
          readonly property bool removable: row.isFace || view.tilePages > 1

          width: pile.width
          height: view.cardHeight
          z: row.held ? 2 : 1
          scale: row.held ? 1.03 : 1
          Behavior on scale { NumberAnimation { duration: 120 } }

          property real dragY: 0
          y: row.held ? row.dragY : view.slotY(row.index)
          Behavior on y {
            enabled: !row.held
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
          }

          property string startedAt: ""
          function pickUp(): void {
            view.confirming = ""
            pile.heldKey = row.key
            row.dragY = view.slotY(row.index)
            row.startedAt = view.orderLine()
          }
          function dragBy(dy): void {
            if (!row.held) return
            row.dragY = Math.max(0, Math.min(pile.height - row.height, row.dragY + dy))
            var want = view.slotAt(row.dragY + row.height / 2)
            if (want !== row.index) order.move(row.index, want, 1)
          }
          function drop(): void {
            if (!row.held) return
            pile.heldKey = ""
            if (view.orderLine() !== row.startedAt) view.commit(view.pagesNow())
          }
          // A cancel is not a decision: the file is the truth.
          function abandon(): void {
            if (!row.held) return
            pile.heldKey = ""
            view.seed()
          }

          Rectangle {
            anchors.fill: parent
            radius: view.host ? view.host.radiusCard : 0
            color: view.host ? view.host.container : "transparent"
            border.width: row.held ? Style.space(2) : 0
            border.color: view.host ? view.host.accent : "transparent"

            // The handle: the row's whole height, wide enough for a thumb.
            Item {
              id: handleSlot
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: Style.space(56)

              Ui.OpticalGlyph {
                anchors.centerIn: parent
                width: Style.space(34)
                height: Style.space(34)
                text: "󰇛"
                fontFamily: Style.font.family
                fontSize: Style.font.display
                color: view.host ? (row.held ? view.host.accent : view.host.subdued) : "transparent"
              }
              MouseArea {
                id: handleArea
                anchors.fill: parent
                preventStealing: true
                property real grabY: 0
                // no press state (style.md H7): a drag handle; the card lifting is its press
                onPressed: mouse => { row.pickUp(); handleArea.grabY = mouse.y }
                onPositionChanged: mouse => row.dragBy(mouse.y - handleArea.grabY)
                onReleased: row.drop()
                onCanceled: row.abandon()
              }
            }

            Column {
              anchors.left: handleSlot.right
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Item {
                width: parent.width
                height: title.implicitHeight
                Text {
                  id: title
                  anchors.left: parent.left
                  anchors.right: tag.left
                  anchors.rightMargin: Style.space(8)
                  text: row.asking ? "remove this page?" : view.summary(row.data_)
                  elide: Text.ElideRight
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.weight: view.host ? view.host.textWeight : Font.Normal
                  color: view.host ? view.host.textOnSurface : "transparent"
                }
                Text {
                  id: tag
                  anchors.right: parent.right
                  text: row.isFace ? "face" : (row.index === view.firstTiles() ? "home" : "")
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.weight: view.host ? view.host.textWeight : Font.Normal
                  color: view.host ? view.host.subdued : "transparent"
                }
              }

              // What goes, said before it goes.
              Text {
                width: parent.width
                visible: row.asking
                text: row.isFace ? "The face comes off home; its file stays."
                                 : view.summary(row.data_) + " come off home; their widget files stay."
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: view.host ? view.host.textWeight : Font.Normal
                color: view.host ? view.host.subdued : "transparent"
              }

              Row {
                x: -Style.space(8)
                component Action: Item {
                  id: action
                  property string label: ""
                  property color ink: view.host ? view.host.accent : "transparent"
                  signal activated()
                  width: actionText.implicitWidth + Style.space(16)
                  height: Style.space(44)
                  Shared.PressVeil {
                    anchors.fill: parent
                    ink: action.ink
                    on: actionArea.pressed
                  }
                  Text {
                    id: actionText
                    anchors.centerIn: parent
                    text: "[ " + action.label + " ]"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.weight: view.host ? view.host.textWeight : Font.Normal
                    color: action.ink
                  }
                  MouseArea {
                    id: actionArea
                    anchors.fill: parent
                    onClicked: action.activated()
                  }
                }

                Action {
                  visible: row.isFace && !row.asking
                  label: "edit"
                  onActivated: view.editFace(row.data_.face)
                }
                Action {
                  visible: row.removable && !row.asking
                  label: "remove"
                  ink: Upstream.Color.urgent
                  onActivated: view.confirming = row.key
                }
                Action {
                  visible: row.asking
                  label: "remove"
                  ink: Upstream.Color.urgent
                  onActivated: view.removeAt(row.index)
                }
                Action {
                  visible: row.asking
                  label: "keep"
                  onActivated: view.confirming = ""
                }
              }
            }
          }
        }
      }
    }
  }
}

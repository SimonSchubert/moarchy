// One month, as a grid of days you can tap.
//
// Its own file because it is drawn twice: three at a time inside the pager on
// the month screen, where a swipe slides one out and the next in, and once
// more inside the editor, where picking a date is the same grid made smaller.
// A date picker that does not look like the calendar it came from is two
// things to learn instead of one.
//
// It holds no state. The day that is selected, the day that is today and the
// events that put dots under a date all come in as properties, so the pager
// can keep three of these alive without three copies of anything mattering.
// Bound because the delegates are the whole screen. The month pager, the
// day's list, the agenda and the editor's chips all read `root` from inside
// a component boundary, and saying so is what turns forty lines of qmllint
// info into a promise the compiler can keep.
pragma ComponentBehavior: Bound

import QtQuick
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "Dates.js" as Dates
import "Events.js" as Events

Item {
  id: root

  property int year: 1970
  property int month: 1
  // 0 Sunday, 1 Monday -- whatever Qt.locale().firstDayOfWeek says the phone's
  // week starts on.
  property int weekStart: 1

  property string today: ""
  property string selected: ""

  property var events: []
  property int revision: 0

  property var colours: null
  property color accentInk: "#ffffff"
  property int bodySize: Metrics.BODY

  // The editor's copy: smaller rows, no dots, no weekend wash. A picker is
  // asked one question and a month screen answers several.
  property bool compact: false

  signal picked(string iso)

  readonly property var cells: Dates.grid(root.year, root.month, root.weekStart)
  readonly property var dots: {
    var r = root.revision
    return root.compact ? [] : Events.marks(root.events, root.cells)
  }

  readonly property var labels: Dates.weekdayLabels(root.weekStart, "initial")
  readonly property real cellWidth: root.width / 7
  readonly property real headerHeight: root.compact ? 20 : 26
  readonly property real cellHeight: (root.height - root.headerHeight) / Dates.ROWS
  readonly property real disc: Math.min(root.cellWidth - 8,
                                        root.compact ? root.cellHeight - 6
                                                     : root.cellHeight - 12)

  function ink(cell) {
    if (!root.colours) return "#ffffff"
    if (cell.iso === root.selected) return root.selected === root.today
                                           ? root.accentInk : root.colours.foreground
    // A day either side of this month is still a day, so it is dimmed rather
    // than left out -- far enough back to read as somewhere else, near enough
    // to aim at when the month has just turned.
    if (!cell.inMonth) return Theme.mix(root.colours.dim, root.colours.background, 0.55)
    if (cell.iso === root.today) return root.colours.accent
    return root.colours.foreground
  }

  // The weekend, one shade off the window. Small enough that nobody sees a
  // colour, large enough that the week reads as a week -- which is the whole
  // job of a seven-column grid.
  readonly property color weekendWash: root.colours
    ? Theme.alpha(root.colours.foreground, root.colours.dark ? 0.05 : 0.022)
    : "transparent"

  // --- the weekday row ------------------------------------------------------

  Row {
    id: header
    width: root.width
    height: root.headerHeight

    Repeater {
      model: root.labels

      delegate: Item {
        id: head
        required property int index
        required property string modelData

        width: root.cellWidth
        height: header.height

        Text {
          anchors.centerIn: parent
          text: head.modelData
          color: root.colours
                 ? (Dates.isWeekend((head.index + root.weekStart) % 7)
                    ? Theme.mix(root.colours.dim, root.colours.background, 0.7)
                    : root.colours.dim)
                 : "#9a9996"
          font.family: Metrics.FONT
          font.pixelSize: Metrics.typeSize(root.bodySize, "overline")
          font.weight: Font.DemiBold
          font.letterSpacing: 1.2
        }
      }
    }
  }

  // --- the weekend columns --------------------------------------------------

  // Behind the grid rather than inside a cell, so that it is one column of
  // colour down the screen instead of six rectangles that happen to line up.
  Row {
    anchors.top: header.bottom
    width: root.width
    height: root.cellHeight * Dates.ROWS
    visible: !root.compact

    Repeater {
      model: 7

      delegate: Rectangle {
        id: column
        required property int index

        width: root.cellWidth
        // The Row's own height and not `parent.height`: a delegate is built
        // before it is given to its parent, so the binding runs once against a
        // null and says so in the log of every run.
        height: root.cellHeight * Dates.ROWS
        // Rounded, like everything else on this phone -- when the phone is. A
        // hard-edged rectangle of grey down the side of a rounded screen reads
        // as a panel somebody forgot to finish; the same wash with the
        // screen's own corner on it reads as part of the grid, and on a square
        // phone that corner is none.
        radius: Metrics.radius(root.colours, Metrics.RADIUS_MD)
        color: Dates.isWeekend((column.index + root.weekStart) % 7)
               ? root.weekendWash : "transparent"
      }
    }
  }

  // --- the days -------------------------------------------------------------

  Grid {
    anchors.top: header.bottom
    width: root.width
    columns: 7

    Repeater {
      model: root.cells

      delegate: Item {
        id: cell
        required property var modelData
        required property int index

        readonly property bool isToday: cell.modelData.iso === root.today
        readonly property bool isSelected: cell.modelData.iso === root.selected
        readonly property var colourList: root.dots.length > cell.index ? root.dots[cell.index] : []

        width: root.cellWidth
        height: root.cellHeight

        Accessible.role: Accessible.Button
        Accessible.name: Dates.fullDayLabel(cell.modelData.iso)
              + (cell.colourList.length ? ", " + cell.colourList.length + " events" : "")
        Accessible.onPressAction: root.picked(cell.modelData.iso)

        Rectangle {
          id: pip
          anchors.horizontalCenter: parent.horizontalCenter
          y: root.compact ? Math.round((cell.height - height) / 2) : 3
          width: root.disc
          height: root.disc
          radius: Metrics.round(root.colours, width)

          color: {
            if (!root.colours) return "transparent"
            if (cell.isSelected)
              return cell.isToday ? root.colours.accent
                                  : Theme.surface(root.colours, "pressed")
            // Today is a wash of the accent until it is chosen, and the accent
            // itself once it is. It used to be a 1.5px ring, which on a phone
            // is the first thing to go in daylight -- and this app is read
            // outdoors more than most.
            if (cell.isToday) return Theme.tint(root.colours, root.colours.accent, "well")
            return "transparent"
          }
          Behavior on color { ColorAnimation { duration: Metrics.PRESS_MS } }

          Text {
            anchors.centerIn: parent
            text: cell.modelData.day
            color: root.ink(cell.modelData)
            font.family: Metrics.FONT
            font.pixelSize: Metrics.typeSize(root.bodySize, root.compact ? "caption" : "body")
            font.weight: cell.isToday || cell.isSelected ? Font.DemiBold : Font.Normal
          }
        }

        // What is on that day, one dot an event. A number would be smaller and
        // would say less: four dots in four colours is the difference between
        // a day with the dentist in it and a day with four meetings.
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: pip.bottom
          anchors.topMargin: 2
          spacing: 3
          visible: !root.compact

          Repeater {
            model: cell.colourList

            delegate: Rectangle {
              required property string modelData

              width: 5
              height: 5
              radius: Metrics.round(root.colours, width)
              color: Events.hue(root.colours, modelData)
              opacity: cell.modelData.inMonth ? 1.0 : 0.45
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: root.picked(cell.modelData.iso)
        }
      }
    }
  }
}

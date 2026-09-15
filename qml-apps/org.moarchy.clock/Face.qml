// The dial: sixty ticks, three hands, and no numerals.
//
// Numerals are what a clock face has when it is 40mm across on a wrist and
// needs to be read at arm's length. At 148px, six pixels of "12" is a smudge,
// and four smudges at the quarters is what makes a drawn clock look like a
// skin rather than an instrument. The ticks do the same job better: twelve of
// them are long, the other forty-eight are short, and the eye reads the hour
// from where the hand points between them without ever having to read a digit.
//
// What is drawn once and what is drawn per frame is the whole of the
// performance story on a Mali-400. The ticks are a Canvas that repaints only
// when the palette or the size changes -- never on a tick of the clock. The
// hands are three Items with a `rotation`, which is a transform on something
// already rasterised, so a second passing costs no fill at all.
//
// The seconds hand sweeps rather than ticks, and it sweeps without JavaScript:
// a RotationAnimator drives it on the render thread for a minute at a time,
// phase-locked whenever the app re-reads the clock. A ticking hand would need
// a wakeup a second to look right and would still stall for a beat every two
// minutes, because a QML Timer fires on the frame after its interval and that
// error accumulates.
import QtQuick
import "ui/Theme.js" as Theme

Item {
  id: root

  // Fractional, all three: the hour hand sits between two ticks at half past,
  // which is what makes a drawn clock look right.
  property real hours: 0
  property real minutes: 0
  property real seconds: 0

  property color ink: "#ffffff"
  property color dim: "#9a9996"
  property color accent: "#3584e4"
  property color behind: "#1d1d20"

  // The seconds hand is animated rather than placed. False under the
  // screenshot harness, where the clock is pinned and a hand that moved would
  // make two pictures of the same second disagree.
  property bool sweeping: true

  implicitWidth: 148
  implicitHeight: 148

  readonly property real centre: Math.min(root.width, root.height) / 2
  readonly property real hourAngle: (root.hours % 12) * 30 + root.minutes * 0.5
  readonly property real minuteAngle: root.minutes * 6 + root.seconds * 0.1
  readonly property real secondAngle: root.seconds * 6

  Canvas {
    id: dial
    anchors.fill: parent
    antialiasing: true
    // Cooperative keeps the paint off the render thread, which on a phone is
    // the thread the compositor is waiting on.
    renderStrategy: Canvas.Cooperative

    // Canvas has no dependency tracking, so every colour it draws with is a
    // property here and every one of them asks for a repaint. Reading
    // root.ink inside onPaint alone would leave the dial in last theme's
    // colours after omarchy-theme-set.
    property color inkColour: root.ink
    property color dimColour: root.dim
    property color accentColour: root.accent

    onInkColourChanged: dial.requestPaint()
    onDimColourChanged: dial.requestPaint()
    onAccentColourChanged: dial.requestPaint()
    onWidthChanged: dial.requestPaint()
    onHeightChanged: dial.requestPaint()

    onPaint: {
      var ctx = dial.getContext("2d")
      var size = Math.min(dial.width, dial.height)
      ctx.reset()
      if (size <= 0) return

      var mid = size / 2
      var outer = mid - 1

      // The rim. Barely there -- it closes the shape without drawing a border
      // around it, which is the difference between a face and a button.
      ctx.beginPath()
      ctx.arc(mid, mid, outer - 1, 0, Math.PI * 2)
      ctx.lineWidth = 1
      ctx.strokeStyle = Theme.alpha(dial.dimColour, 0.28)
      ctx.stroke()

      for (var i = 0; i < 60; i++) {
        var hour = i % 5 === 0
        var length = hour ? size * 0.075 : size * 0.032
        var width = hour ? Math.max(2, size * 0.017) : 1
        var angle = (i / 60) * Math.PI * 2 - Math.PI / 2
        var from = outer - 5
        var to = from - length
        ctx.beginPath()
        ctx.moveTo(mid + Math.cos(angle) * from, mid + Math.sin(angle) * from)
        ctx.lineTo(mid + Math.cos(angle) * to, mid + Math.sin(angle) * to)
        ctx.lineWidth = width
        ctx.lineCap = "round"
        // The twelve are the theme's ink and the rest are a whisper of it. One
        // colour for all sixty reads as a gear, not a dial.
        ctx.strokeStyle = hour ? Theme.alpha(dial.inkColour, 0.85)
                               : Theme.alpha(dial.inkColour, 0.3)
        ctx.stroke()
      }

      // Twelve o'clock, in the accent, so that a face photographed upside
      // down is still the right way up.
      ctx.beginPath()
      ctx.arc(mid, size * 0.135, Math.max(2, size * 0.019), 0, Math.PI * 2)
      ctx.fillStyle = dial.accentColour
      ctx.fill()
    }
  }

  // --- the hands ------------------------------------------------------------
  //
  // Each hand is a full-size Item rotated about its own centre, with the bar
  // drawn inside it from the middle outwards. Rotating the container rather
  // than the bar is what keeps the pivot exactly on the centre of the dial
  // whatever the bar's width.

  Item {
    anchors.fill: parent
    rotation: root.hourAngle
    // A quarter of a second, so that switching to this page or coming back
    // after an hour moves the hands rather than teleporting them.
    Behavior on rotation {
      RotationAnimation { duration: 260; direction: RotationAnimation.Clockwise }
    }

    Rectangle {
      x: (parent.width - width) / 2
      y: parent.height / 2 - root.centre * 0.52
      width: Math.max(3, root.centre * 0.085)
      height: root.centre * 0.52 + root.centre * 0.12
      radius: width / 2
      color: root.ink
    }
  }

  Item {
    anchors.fill: parent
    rotation: root.minuteAngle
    Behavior on rotation {
      RotationAnimation { duration: 260; direction: RotationAnimation.Clockwise }
    }

    Rectangle {
      x: (parent.width - width) / 2
      y: parent.height / 2 - root.centre * 0.78
      width: Math.max(2, root.centre * 0.055)
      height: root.centre * 0.78 + root.centre * 0.14
      radius: width / 2
      color: root.ink
    }
  }

  Item {
    id: secondHand
    anchors.fill: parent
    // Not a binding. The animator below writes this property, and a binding
    // and an animator on one property is a fight the animator wins silently
    // until the first time it does not.
    rotation: 0

    Rectangle {
      x: (parent.width - width) / 2
      y: parent.height / 2 - root.centre * 0.82
      width: Math.max(1, root.centre * 0.022)
      height: root.centre * 0.82 + root.centre * 0.2
      radius: width / 2
      color: root.accent
    }

    // The counterweight. It is what tells the eye which end of a thin bar is
    // pointing at something.
    Rectangle {
      x: (parent.width - width) / 2
      y: parent.height / 2 + root.centre * 0.1
      width: Math.max(3, root.centre * 0.07)
      height: width
      radius: width / 2
      color: root.accent
    }
  }

  RotationAnimator {
    id: sweep
    target: secondHand
    from: root.secondAngle
    to: root.secondAngle + 360
    duration: 60000
    loops: Animation.Infinite
    running: false
  }

  // Put the hand where the clock says and, if it is sweeping, start the minute
  // again from there. Called by the app whenever it re-reads the clock after
  // not having watched it -- opening the window, mainly.
  function lock(): void {
    sweep.stop()
    secondHand.rotation = root.secondAngle
    if (root.sweeping) sweep.restart()
  }

  onSweepingChanged: root.lock()
  onSecondsChanged: if (!sweep.running) secondHand.rotation = root.secondAngle
  Component.onCompleted: root.lock()

  // The cap, over the hands, which is what makes three bars look like one
  // mechanism.
  Rectangle {
    anchors.centerIn: parent
    width: Math.max(7, root.centre * 0.13)
    height: width
    radius: width / 2
    color: root.behind
    border.width: Math.max(1.5, root.centre * 0.025)
    border.color: root.accent
  }
}

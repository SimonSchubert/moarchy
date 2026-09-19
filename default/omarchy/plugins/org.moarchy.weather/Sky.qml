// The weather, drawn.
//
// Eleven symbols -- clear, mainly clear, partly cloudy, overcast, fog,
// drizzle, rain, showers, sleet, snow and storm -- built out of rectangles and
// circles at whatever size they are asked for. The three with a sun in them
// have a night half as well, which makes fourteen pictures.
//
// Adwaita ships weather symbolics and the kit's Icon.qml could have loaded
// them, and they were not used for two reasons: they are drawn on a 16px canvas
// and the hero on this screen is 84px of it, and the rain in them is the ink
// colour, where the point of this screen is that rain is the theme's blue
// against a temperature that is its own colour.
//
// Rectangles rather than a Canvas, which is Vitals' rule and for its reason: a
// Rectangle repaints nothing when nothing changed, and thirty-two of these are
// on screen at once -- the hero, twenty-four hours and seven days. A Canvas
// would hold thirty-two framebuffers on a Mali-400 to draw a sun that never
// moves.
//
// Everything is expressed in hundredths of `size`, so one set of numbers draws
// the 26px glyph in the hourly strip and the 84px one above it.

// Bound because the rays, the drops and the flakes are delegates: each of them
// reads `root` from inside a Repeater, and the pragma is what says so rather
// than letting it resolve by accident.
pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  // clear, mostly-clear, partly, cloud, fog, drizzle, rain, showers, sleet,
  // snow, storm -- and the first three again with "-night" on the end.
  property string kind: "cloud"
  property int size: 24

  // The cloud and the sun.
  property color ink: "#ffffff"
  // The rain, the snow and the bolt. Never the only thing that distinguishes
  // two symbols: drizzle has two drops and rain three, whatever colour they
  // are drawn in.
  property color accent: "#3584e4"
  // The bolt, which is the one thing in the sky that is not the colour of the
  // rain. Drawn in the theme's yellow because a blue zigzag under a blue cloud
  // is a shape nobody reads as lightning -- which is exactly how it looked
  // before somebody looked at it.
  property color spark: "#f5c211"
  // What is behind the moon, which is how the crescent is cut. The one number
  // here a caller has to get right: on a band of colour it is that band's
  // colour, not the window's.
  property color behind: "#1d1d20"

  width: root.size
  height: root.size

  readonly property real u: root.size / 100

  readonly property bool night: root.kind.indexOf("-night") > 0
  readonly property string base: root.night
    ? root.kind.substring(0, root.kind.length - 6) : root.kind

  // Where the sun or moon sits, and how big, for each symbol that has one. A
  // disc alone is the whole sky; a disc with a cloud under it is a corner of
  // one, so it moves up and to the left and loses a third of its radius.
  readonly property var discs: ({
    "clear":        { x: 50, y: 50, r: 24, ray: 38, rw: 6, rh: 13 },
    "mostly-clear": { x: 35, y: 33, r: 16, ray: 26, rw: 5, rh: 9 },
    "partly":       { x: 33, y: 32, r: 16, ray: 26, rw: 5, rh: 9 },
    "showers":      { x: 29, y: 28, r: 13, ray: 22, rw: 4, rh: 8 }
  })

  readonly property var disc: root.discs[root.base] || null
  readonly property bool hasDisc: !!root.disc

  // The cloud, as a size and a point for its middle to sit on. Precipitation
  // needs the bottom third of the box, so every symbol that has any lifts its
  // cloud clear of it.
  readonly property var clouds: ({
    "mostly-clear": { s: 0.66, x: 60, y: 63 },
    "partly":       { s: 0.82, x: 57, y: 60 },
    "cloud":        { s: 1.00, x: 50, y: 52 },
    "fog":          { s: 0.84, x: 50, y: 38 },
    "drizzle":      { s: 0.86, x: 50, y: 40 },
    "rain":         { s: 0.86, x: 50, y: 40 },
    "showers":      { s: 0.76, x: 58, y: 46 },
    "sleet":        { s: 0.86, x: 50, y: 40 },
    "snow":         { s: 0.86, x: 50, y: 40 },
    "storm":        { s: 0.86, x: 50, y: 38 }
  })

  readonly property var cloud: root.clouds[root.base] || null

  // Drops, flakes and fog bars, as points in the same hundred-wide box. Two
  // drops is drizzle and three is rain, which is the distinction the symbols
  // are actually carrying.
  readonly property var drops: ({
    "drizzle": [{ x: 40, y: 76 }, { x: 60, y: 76 }],
    "rain":    [{ x: 33, y: 76 }, { x: 50, y: 82 }, { x: 67, y: 76 }],
    "showers": [{ x: 45, y: 82 }, { x: 65, y: 82 }],
    "sleet":   [{ x: 38, y: 78 }]
  })

  readonly property var flakes: ({
    "snow":  [{ x: 33, y: 76 }, { x: 50, y: 84 }, { x: 67, y: 76 }],
    "sleet": [{ x: 62, y: 80 }]
  })

  readonly property var dropList: root.drops[root.base] || []
  readonly property var flakeList: root.flakes[root.base] || []

  // --- the sun ------------------------------------------------------------

  Item {
    id: rays
    visible: root.hasDisc && !root.night
    anchors.fill: parent

    Repeater {
      model: root.hasDisc ? 8 : 0

      delegate: Item {
        id: ray
        required property int index

        width: root.size
        height: root.size
        x: root.disc.x * root.u - root.size / 2
        y: root.disc.y * root.u - root.size / 2
        rotation: ray.index * 45

        Rectangle {
          width: root.disc.rw * root.u
          height: root.disc.rh * root.u
          radius: width / 2
          color: root.ink
          x: (root.size - width) / 2
          y: root.size / 2 - (root.disc.ray + root.disc.rh) * root.u
        }
      }
    }
  }

  // The disc itself, sun or moon. One rectangle for both: a moon is a sun with
  // a bite taken out of it, and the bite is the rectangle below.
  Rectangle {
    id: face
    visible: root.hasDisc
    width: root.hasDisc ? root.disc.r * 2 * root.u : 0
    height: width
    radius: width / 2
    color: root.ink
    x: root.hasDisc ? root.disc.x * root.u - width / 2 : 0
    y: root.hasDisc ? root.disc.y * root.u - height / 2 : 0
  }

  Rectangle {
    visible: root.hasDisc && root.night
    width: face.width * 0.88
    height: width
    radius: width / 2
    color: root.behind
    x: face.x + face.width * 0.34
    y: face.y - face.height * 0.28
  }

  // --- the cloud ----------------------------------------------------------

  Item {
    id: puff
    visible: !!root.cloud
    width: root.cloud ? root.size * root.cloud.s : 0
    height: width
    // The cloud's ink sits between 0.16 and 0.74 of its own box, so its middle
    // is at 0.45 of it rather than at the half.
    x: root.cloud ? root.cloud.x * root.u - width / 2 : 0
    y: root.cloud ? root.cloud.y * root.u - height * 0.45 : 0

    Rectangle {
      x: puff.width * 0.10
      y: puff.width * 0.52
      width: puff.width * 0.80
      height: puff.width * 0.22
      radius: height / 2
      color: root.ink
    }

    Rectangle {
      x: puff.width * 0.10
      y: puff.width * 0.32
      width: puff.width * 0.40
      height: width
      radius: width / 2
      color: root.ink
    }

    Rectangle {
      x: puff.width * 0.26
      y: puff.width * 0.16
      width: puff.width * 0.52
      height: width
      radius: width / 2
      color: root.ink
    }

    Rectangle {
      x: puff.width * 0.54
      y: puff.width * 0.36
      width: puff.width * 0.36
      height: width
      radius: width / 2
      color: root.ink
    }
  }

  // --- what falls out of it -----------------------------------------------

  Repeater {
    model: root.dropList

    delegate: Rectangle {
      id: drop
      required property var modelData

      width: 5 * root.u
      height: 15 * root.u
      radius: width / 2
      color: root.accent
      x: drop.modelData.x * root.u - width / 2
      y: drop.modelData.y * root.u - height / 2
      rotation: 14
    }
  }

  // A flake is three bars through one point, which is what a snowflake is if
  // you draw it with six arms and no crystals.
  Repeater {
    model: root.flakeList

    delegate: Item {
      id: flake
      required property var modelData

      width: 21 * root.u
      height: width
      x: flake.modelData.x * root.u - width / 2
      y: flake.modelData.y * root.u - height / 2

      Repeater {
        model: 3

        delegate: Rectangle {
          id: arm
          required property int index

          width: 3.2 * root.u
          height: flake.width
          radius: width / 2
          color: root.accent
          anchors.centerIn: parent
          rotation: arm.index * 60
        }
      }
    }
  }

  // Fog is the sky one cannot see through, so it is the cloud with the ground
  // under it drawn as three bars of it.
  Repeater {
    model: root.base === "fog" ? 3 : 0

    delegate: Rectangle {
      id: bar
      required property int index

      width: (bar.index === 1 ? 70 : 58) * root.u
      height: 7 * root.u
      radius: height / 2
      color: root.ink
      opacity: 0.75
      x: (50 + (bar.index === 1 ? 4 : 0)) * root.u - width / 2
      y: (66 + bar.index * 13) * root.u - height / 2
    }
  }

  // The bolt: two strokes leaning opposite ways, the foot of the first against
  // the head of the second, which is a zigzag drawn with the two shapes this
  // file is allowed. The numbers are not free -- with both strokes leaning the
  // same way, which is what they did first, it is one fat diagonal line and
  // reads as a smear.
  Item {
    visible: root.base === "storm"
    anchors.fill: parent

    Rectangle {
      width: 7 * root.u
      height: 20 * root.u
      radius: width / 3
      color: root.spark
      x: 48 * root.u - width / 2
      y: 72 * root.u - height / 2
      rotation: 26
    }

    Rectangle {
      width: 7 * root.u
      height: 18 * root.u
      radius: width / 3
      color: root.spark
      x: 47.5 * root.u - width / 2
      y: 89 * root.u - height / 2
      rotation: -26
    }
  }
}

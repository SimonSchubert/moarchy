// Run moarchy.common/Edge.js against the geometry the three sheets shipped with
// (docs/gestures.md Q2, Q2a).
//
//   node scripts/edge-test.js
//
// The table this file checks is the one thing standing between "the overview
// rises from the bottom" and every sheet on the phone arriving sideways. It is
// pure arithmetic with no host and no Qt in it, so it runs here rather than on
// a Mali-400 over ssh -- and the first group is a regression guard rather than
// a new rule: each sheet's own pre-Q formula, asserted against the general one.
//
// The shipped file is read and evaluated rather than copied: a test against a
// copy passes while the copy is the thing that has drifted.
const fs = require("fs")
const path = require("path")

const src = fs.readFileSync(
  path.join(__dirname, "..", "default", "omarchy", "plugins",
            "moarchy.common", "Edge.js"), "utf8")

// `.pragma library` is a QML engine directive and not JavaScript.
const edge = {}
new Function("exports", src.replace(/^\s*\.pragma\s+library\s*$/m, "") +
  "\n;Object.assign(exports, { BOTTOM, TOP, RIGHT, LEFT, EDGES, norm, axis," +
  " horizontal, openDirection, closeLatchSign, near, anchors, offset, travel })")(edge)

const { BOTTOM, TOP, RIGHT, LEFT } = edge

let fail = 0
const check = (ok, what, detail) => {
  if (!ok) fail++
  console.log(`  ${ok ? "\x1b[32mok\x1b[0m  " : "\x1b[31mNO\x1b[0m  "} ${what}${detail ? "  -- " + detail : ""}`)
}
const near = (a, b) => Math.abs(a - b) < 0.001

// A phone-shaped surface: 360x720 logical, the drawer's latched 694, and the
// shade's content height on a quiet day.
const W = 360, H = 720, FULL_H = 694, SHADE_H = 300

console.log("offset(): each sheet's shipped formula, from the general one")
// Drawer, y: parent.height * (1 - progress) -- a sheet as tall as its surface.
for (const p of [0, 0.25, 0.5, 0.91, 1]) {
  const got = edge.offset(BOTTOM, p, W, FULL_H, W, FULL_H)
  check(near(got.y, FULL_H * (1 - p)) && got.x === 0,
        `drawer at ${p}`, `y=${got.y} want ${FULL_H * (1 - p)}`)
}
// Overview, x: parent.width - sheet.width * progress.
for (const p of [0, 0.5, 1]) {
  const got = edge.offset(RIGHT, p, W, H, W, H)
  check(near(got.x, W - W * p) && got.y === 0,
        `overview at ${p}`, `x=${got.x} want ${W - W * p}`)
}
// Shade, y: -sheetHeight * (1 - progress) -- content-height, not surface-height.
for (const p of [0, 0.35, 1]) {
  const got = edge.offset(TOP, p, W, H, W, SHADE_H)
  check(near(got.y, -SHADE_H * (1 - p)) && got.x === 0,
        `shade at ${p}`, `y=${got.y} want ${-SHADE_H * (1 - p)}`)
}

console.log("offset(): a sheet bigger than the box rests flush and overflows (D2b)")
// The drawer's first drag of a session: its size falls back to the screen,
// which is taller than the surface by the bar's zone. Open, its top must be at
// 0 -- an over-tall sheet held to the bottom would cut off its search field.
for (const [name, box, size, want] of [
  ["an over-tall bottom sheet opens flush at the top", H, H + 26, 0],
  ["...and is still off screen shut", H, H + 26, H],
]) {
  const p = want === 0 ? 1 : 0
  const got = edge.offset(BOTTOM, p, W, box, W, size)
  check(near(got.y, want), name, `y=${got.y} want ${want}`)
}
check(near(edge.offset(RIGHT, 1, W, H, W + 12, H).x, 0),
      "an over-wide right sheet opens flush at the left")

console.log("offset(): a sheet rests against the edge it came from (Q2a)")
for (const [name, e, want] of [
  ["a short sheet on the bottom rests on the bottom", BOTTOM, { x: 0, y: H - SHADE_H }],
  ["a short sheet on the top rests on the top", TOP, { x: 0, y: 0 }],
  ["a narrow sheet on the right rests on the right", RIGHT, { x: W - SHADE_H, y: 0 }],
  ["a narrow sheet on the left rests on the left", LEFT, { x: 0, y: 0 }],
]) {
  const got = edge.offset(e, 1, W, H, SHADE_H, SHADE_H)
  check(near(got.x, want.x) && near(got.y, want.y), name, JSON.stringify(got))
}

console.log("offset(): shut, the sheet is entirely off its own edge")
for (const [e, sw, sh, inside] of [
  [BOTTOM, W, SHADE_H, g => g.y >= H],
  [TOP, W, SHADE_H, g => g.y + SHADE_H <= 0],
  [RIGHT, SHADE_H, H, g => g.x >= W],
  [LEFT, SHADE_H, H, g => g.x + SHADE_H <= 0],
]) {
  const got = edge.offset(e, 0, W, H, sw, sh)
  check(inside(got), `${e} at 0 is off screen`, JSON.stringify(got))
}

console.log("anchors(): shut is a one-pixel band, grown is all four (N3, P8)")
for (const [e, missing] of [[BOTTOM, "top"], [TOP, "bottom"], [RIGHT, "left"], [LEFT, "right"]]) {
  const shut = edge.anchors(e, false)
  const grown = edge.anchors(e, true)
  const others = ["top", "bottom", "left", "right"].filter(k => k !== missing)
  check(shut[missing] === false && others.every(k => shut[k] === true),
        `${e} shut anchors everything but ${missing}`, JSON.stringify(shut))
  check(["top", "bottom", "left", "right"].every(k => grown[k] === true),
        `${e} grown anchors all four`, JSON.stringify(grown))
}

console.log("axis(), openDirection(), closeLatchSign(): the way in and the way back")
for (const [e, ax, dir] of [[BOTTOM, "y", -1], [TOP, "y", 1], [RIGHT, "x", -1], [LEFT, "x", 1]]) {
  check(edge.axis(e) === ax, `${e} travels on ${ax}`, edge.axis(e))
  check(edge.openDirection(e) === dir, `${e} opens ${dir > 0 ? "+" : "-"}${ax}`,
        String(edge.openDirection(e)))
  check(edge.closeLatchSign(e) === -dir, `${e} closes the other way`,
        String(edge.closeLatchSign(e)))
}
check(edge.horizontal(RIGHT) && edge.horizontal(LEFT)
      && !edge.horizontal(TOP) && !edge.horizontal(BOTTOM),
      "horizontal() is the x pair and only the x pair")

console.log("travel(): the sheet's extent on the axis the finger moves (D2a)")
check(edge.travel(BOTTOM, W, FULL_H) === FULL_H, "a bottom sheet is dragged by its height")
check(edge.travel(RIGHT, W, FULL_H) === W, "a right sheet is dragged by its width")

console.log("norm(): unknown falls back to the caller's own edge, never a fourth answer (Q1)")
for (const [name, given, fallback, want] of [
  ["a word the table knows is taken", "right", BOTTOM, RIGHT],
  ["case and space do not matter", "  RIGHT ", BOTTOM, RIGHT],
  ["a typo falls back to the caller's", "rihgt", TOP, TOP],
  ["empty falls back to the caller's", "", RIGHT, RIGHT],
  ["undefined falls back to the caller's", undefined, TOP, TOP],
  ["a bad fallback is still an edge", "nonsense", "nonsense", BOTTOM],
]) {
  check(edge.norm(given, fallback) === want, name, edge.norm(given, fallback))
}

console.log("EDGES: the table is internally consistent, so a wrong row is caught here")
for (const [name, e] of Object.entries(edge.EDGES)) {
  const opposite = { top: "bottom", bottom: "top", left: "right", right: "left" }
  check(e.far === opposite[e.near], `${name}: far is the opposite of near`,
        `${e.near}/${e.far}`)
  check((e.axis === "y") === (e.near === "top" || e.near === "bottom"),
        `${name}: near lies on ${e.axis}`, e.near)
  check((e.sign < 0) === (e.near === "bottom" || e.near === "right"),
        `${name}: sign agrees with which end it rests at`, String(e.sign))
  check(edge.norm(name) === name, `${name}: its own key round-trips`)
}

console.log(fail ? `\n${fail} failed` : "\nall passed")
process.exit(fail ? 1 : 0)

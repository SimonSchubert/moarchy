// Numbers every plugin chrome should mean the same way.
//
// 44 is the shell's thumb floor. 40 is Keep's pill search: large enough to
// hit, short enough to sit in an AppBar. Type roles are multiples of a body
// size: the shell's own when we run inside it, BODY when we do not.
.pragma library

var TARGET = 44
// Material's 24dp icon is ~20dp of ink inside the asset. Adwaita symbolics
// are drawn to the edges of their 16px canvas, so the same pixel size reads
// ~1.2× larger. ICON is the Material-named size; ICON_INK is what we draw.
var ICON = 22
var ICON_INK = 18
var PILL = 40
var FAB = 56
var CHECK = 22
var MENU_WIDTH = 220
var MENU_ROW = 40
var BOTTOM_NAV = 56

// --- shape -------------------------------------------------------------
//
// Every app on this phone draws the same three shapes: a box on the page, a
// box inside a box, and a chip inside that. One scale for the three, so a
// card in Weather and a card in Files are the same object seen twice rather
// than 12 in one file and 14 in another.
//
// XXS is below all three: a mark rather than a box -- a heat-map cell, a dot
// under a date, a tick. It is the same ratio of radius to size that RADIUS_SM
// has on a 30px square, which is what keeps a 15px cell a rounded square
// instead of a circle.
var RADIUS_XXS = 4
var RADIUS_XS = 6
var RADIUS_SM = 8
var RADIUS_MD = 14
var RADIUS_LG = 20
// The name the plugins already use for "a box on the page".
var CARD_RADIUS = RADIUS_MD

// The rule for a box inside a box: the inner radius is the outer one less the
// gap between the two edges, so the curves stay concentric. Anything else
// leaves a crescent of the outer fill at each corner -- the tell that a card
// was dropped into a list rather than designed into it. Floored at RADIUS_XS
// because a 2px corner reads as a mistake rather than as a square one -- and
// capped at the outer radius, because a box rounder than the box it sits in is
// the same mistake the other way round, and `modest` corners are small enough
// to reach it.
//
//   inner(RADIUS_LG, GROUP_PAD) === RADIUS_MD
//   inner(RADIUS_MD, GROUP_PAD) === RADIUS_SM
function inner(outer, pad) {
  var o = Number(outer)
  if (!isFinite(o) || o <= 0) return 0
  var p = Number(pad)
  if (!isFinite(p) || p <= 0) return Math.round(o)
  return Math.min(Math.round(o), Math.max(RADIUS_XS, Math.round(o - p)))
}

// --- corners -----------------------------------------------------------
//
// The scale above is drawn at `corners = "large"`, the look this phone shipped
// with. `~/.config/omarchy/ui.toml` can say `modest` or `square` instead, and
// the shell's sheets, tiles and cards follow it (moarchy's docs/style.md D1).
// An app that read the scale straight off this file was the one rounded thing
// left on a square phone, so every corner an app draws goes through one of
// these two:
//
//   radius(colours, px)    a box -- a card, a group, a key, a heat-map cell.
//                          The px is the large one; modest scales it down by
//                          the ratio of the two tile radii, square is 0.
//   round(colours, size)   a capsule or a circle -- a button, a field, a chip,
//                          the ring round today's date. Fully round at large;
//                          at modest and square it is a box with the tile's
//                          corner, capped at half the side the way the shell's
//                          own Pill is.
//
// Neither is for artwork. A sun, a clock face, a reversi disc and a mine are
// round because the thing drawn is round, and squaring them would be squaring
// the content rather than the chrome.
//
// The shape arrives on `colours`, which ThemeFile folds ui.toml into. That is
// not where it belongs by name, and it is where it has to be: `colours` is the
// one object every box on every screen is already handed, and a second
// property would be two hundred call sites of which the one a new screen
// forgets is the corner this section exists for. No colours, or colours with
// no shape on them, is large -- the scale above, unchanged.
var LARGE_TILE = 20

// The part of ui.toml an app draws with, from UiFile's `chrome`.
function shape(chrome) {
  var c = chrome || {}
  var tile = Number(c.tile)
  return {
    corners: String(c.corners || "large"),
    scale: isFinite(tile) && tile >= 0 ? tile / LARGE_TILE : 1
  }
}

// `colours` with the shape on it. A copy, so the palette Theme.parse returned
// is never the object a binding sees change.
function shaped(colours, chrome) {
  var out = {}
  for (var k in (colours || {})) out[k] = colours[k]
  out.shape = shape(chrome)
  return out
}

function scale(colours) {
  var s = colours && colours.shape ? Number(colours.shape.scale) : 1
  return isFinite(s) && s >= 0 ? s : 1
}

function radius(colours, px) {
  var n = Number(px)
  if (!isFinite(n) || n <= 0) return 0
  var s = scale(colours)
  return s === 1 ? n : Math.round(n * s)
}

function round(colours, size) {
  var half = Number(size) / 2
  if (!isFinite(half) || half <= 0) return 0
  var s = scale(colours)
  if (s >= 1) return half
  return Math.min(half, Math.round(LARGE_TILE * s))
}

// --- spacing -----------------------------------------------------------
//
// Five numbers, and the first four nest: the page insets its content by
// GUTTER, a box insets its own by PAD, two boxes are GAP apart, and a box that
// holds boxes insets them by GROUP_PAD -- which is the number `inner()`
// subtracts.
var GUTTER = 12
var PAD = 12
var GAP = 8
var GROUP_PAD = 6
// Label to the box under it. Closer than GAP on purpose: the two are one
// thing, and equal spacing would make the label read as a caption for the box
// above it instead.
var LABEL_GAP = 5

var FONT = "Adwaita Sans"
// What Style.font.body is on a stock image, and what every type role
// multiplies when the shell is not there to say otherwise.
var BODY = 16

// Motion. One turn of a refresh icon while something is in flight, and the
// press feedback every control shares. Slow enough to read as "working"
// rather than "spinning", which also costs a Mali-400 less.
var SPIN_MS = 1000
var PRESS_MS = 120

// The shell's body size inside omarchy-shell, BODY anywhere else.
//
// `qs.Commons` is a module the plugin host puts on the import path. On a
// plain Quickshell it does not exist, and an import that cannot resolve
// fails the whole file at load time -- there is no catching it from the
// caller. Compiling that import as a string is what makes it optional.
// It runs once per app, at startup, and yields an int; nothing here is
// consulted again, let alone per frame.
function shellBody(parent) {
  try {
    var probe = Qt.createQmlObject(
      "import QtQuick\nimport qs.Commons\n" +
      "QtObject { readonly property int body: Style.font.body }",
      parent, "ShellStyleProbe")
    if (!probe) return BODY
    var body = probe.body
    probe.destroy()
    return body > 0 ? body : BODY
  } catch (e) {
    return BODY
  }
}

// The shell's spacing scale, or 1.0 anywhere else.
//
// The fourth coupling, and the one the kit's README does not list because no
// app needed it until Keep came off `qs.Commons`. `Style.space(px)` is the
// shell's rem for margins and gaps -- px times a scale that follows the text
// size, so a roomier theme moves the gaps with the type. Probed exactly as
// shellBody is, once, and for the same reason: an import that cannot resolve
// fails the whole file, so it has to be compiled as a string to be optional.
var SPACING_SCALE = -1

function spacingScale(parent) {
  if (SPACING_SCALE >= 0) return SPACING_SCALE
  SPACING_SCALE = 1.0
  try {
    var probe = Qt.createQmlObject(
      "import QtQuick\nimport qs.Commons\n" +
      "QtObject { readonly property real scale: Style.effectiveSpacingScale }",
      parent, "ShellSpacingProbe")
    if (probe) {
      var scale = probe.scale
      probe.destroy()
      if (scale > 0) SPACING_SCALE = scale
    }
  } catch (e) {
    // Not in the shell: the numbers an app was written with are the numbers.
  }
  return SPACING_SCALE
}

// px at the shell's scale, never below one. `Style.space` rounds and floors at
// 1 for the same reason: a gap that scales to nothing is a layout that has
// quietly lost a separator.
function space(px, parent) {
  var n = Number(px)
  if (!isFinite(n) || n <= 0) return 0
  return Math.max(1, Math.round(n * spacingScale(parent)))
}

function typeSize(body, role) {
  var b = body || BODY
  if (role === "title") return Math.round(b * 1.4)
  if (role === "subtitle") return Math.round(b * 1.15)
  if (role === "body") return Math.round(b)
  if (role === "caption") return Math.round(b * 0.85)
  if (role === "overline") return Math.round(b * 0.75)
  return Math.round(b)
}

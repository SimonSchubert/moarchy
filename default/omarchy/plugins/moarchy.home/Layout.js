// Home's pages, from ~/.config/omarchy/home.toml (docs/home.md §D).
//
//     import "Layout.js" as Layout
//
//     var pages = Layout.pages(parsed)            // parsed: Toml.parse(...).data, or null
//     var placed = Layout.place(page.tiles, 6, 9) // { tiles: [...], dropped: [...] }
//     var edges = Layout.edgesAt(r, x, y, 20, 36)  // §K's geometry, in pixels
//
// `.pragma library` and pure, so `node scripts/home-layout-test.js` runs the
// rules without a phone. Nothing here knows a screen size: the grid's rows come
// from the view, which is the only thing that has measured one.

.pragma library

// HM16. What home is while ~/.config/omarchy/home.toml does not exist, and what
// /usr/share/moarchy/home.toml documents line by line. scripts/home-layout-test.js
// reads that file and fails if the two differ, so the documentation cannot
// drift from the behaviour.
var SHIPPED = [
  { face: "start" },
  { tiles: [
    { widget: "fetch",    x: 0, y: 0, w: 3, h: 4 },
    { widget: "today",    x: 3, y: 0, w: 3, h: 4 },
    { widget: "media",    x: 0, y: 4, w: 6, h: 2 },
    { widget: "calendar", x: 0, y: 6, w: 6, h: 1 }
  ] }
]

// A name a face or a user widget may have: what is safe to put into a file
// path. Anything else is not loaded from anywhere, so `face = "../../x"` names
// no file outside the two directories.
function safeName(s) {
  var n = String(s === undefined || s === null ? "" : s).trim()
  return /^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(n) ? n : ""
}

function int(v, fallbackValue) {
  var n = Number(v)
  return isFinite(n) ? Math.round(n) : fallbackValue
}

// The pages a parsed file asks for, in the order home draws them.
//
// HM4. In the file's order: page 1 is the first page of tiles, so whatever is
// left of it is faces by definition, and right of it faces and tiles mix as
// listed. There is always at least one page of tiles, because page 1 is where
// home opens and where the prompt bar is: a file of nothing but faces gets an
// empty one after them.
//
// A page holding neither key, or a face whose name is not a safe file name, is
// left out and reported, which is the same "say it, don't break" rule as an
// unknown widget id.
function pages(data) {
  var raw = (data && Array.isArray(data.page)) ? data.page : SHIPPED
  var out = []
  var skipped = []
  var firstTiles = -1
  for (var i = 0; i < raw.length; i++) {
    var p = raw[i] || {}
    if (p.face !== undefined) {
      var name = safeName(p.face)
      if (name) out.push({ kind: "face", face: name })
      else skipped.push("page " + (i + 1) + ": face \"" + p.face + "\" is not a file name")
    } else if (Array.isArray(p.tiles)) {
      var tiles = []
      for (var j = 0; j < p.tiles.length; j++) {
        var t = p.tiles[j] || {}
        var id = safeName(t.widget)
        if (!id) { skipped.push("page " + (i + 1) + ": tile " + (j + 1) + " names no widget"); continue }
        tiles.push({ widget: id,
                     x: t.x === undefined ? -1 : int(t.x, -1),
                     y: t.y === undefined ? -1 : int(t.y, -1),
                     w: Math.max(1, int(t.w, 2)),
                     h: Math.max(1, int(t.h, 2)) })
      }
      if (firstTiles < 0) firstTiles = out.length
      out.push({ kind: "tiles", tiles: tiles })
    } else {
      skipped.push("page " + (i + 1) + ": neither face nor tiles")
    }
  }
  if (firstTiles < 0) { firstTiles = out.length; out.push({ kind: "tiles", tiles: [] }) }
  return { pages: out, skipped: skipped, firstTiles: firstTiles }
}

// HM51. The pages home draws: the file's, with the two that wait for something
// -- the face invite left of the leftmost and an empty page of tiles after the
// last. Neither is in the file; `waiting` marks them so a write leaves them
// out, until a tile lands on the spare one and makes it a page.
function withWaiting(r) {
  var out = [{ kind: "invite", waiting: true }]
  for (var i = 0; i < r.pages.length; i++) out.push(r.pages[i])
  out.push({ kind: "tiles", tiles: [], waiting: true })
  return { pages: out, skipped: r.skipped, firstTiles: r.firstTiles + 1 }
}

// HM48, HM52. What a write puts in the file for pages as drawn: the waiting
// ones only if a tile has landed there, and a page of tiles only while it holds
// one -- except that the last one left stays, as page 1.
function written(drawn) {
  var out = []
  var tilePages = 0
  for (var i = 0; i < drawn.length; i++) {
    var p = drawn[i]
    if (p.kind === "invite") continue
    if (p.kind === "face") { out.push({ face: p.face }); continue }
    if (p.tiles.length === 0) continue
    tilePages++
    out.push({ tiles: p.tiles.map(function (t) {
      return t.x < 0 ? { widget: t.widget, w: t.w, h: t.h }
                     : { widget: t.widget, x: t.x, y: t.y, w: t.w, h: t.h }
    }) })
  }
  if (tilePages === 0) out.push({ tiles: [] })
  return out
}

// HM9, HM17. Each tile at its cell rectangle, or at the first free spot of its
// size when it is off the grid or on top of one listed before it. Wider than the
// grid is clamped to the grid rather than dropped: a 6-wide tile on a phone set
// to 4 columns is still the tile somebody asked for. A tile with no room left
// on the page at all is dropped and named, never drawn over another.
function place(tiles, columns, rows) {
  var cols = Math.max(1, int(columns, 6))
  var maxRows = Math.max(1, int(rows, 1))
  var taken = []
  for (var r = 0; r < maxRows; r++) {
    var row = []
    for (var c = 0; c < cols; c++) row.push(false)
    taken.push(row)
  }

  function fits(x, y, w, h) {
    if (x < 0 || y < 0 || x + w > cols || y + h > maxRows) return false
    for (var yy = y; yy < y + h; yy++)
      for (var xx = x; xx < x + w; xx++)
        if (taken[yy][xx]) return false
    return true
  }

  function take(x, y, w, h) {
    for (var yy = y; yy < y + h; yy++)
      for (var xx = x; xx < x + w; xx++)
        taken[yy][xx] = true
  }

  var placed = []
  var dropped = []
  for (var i = 0; i < (tiles || []).length; i++) {
    var t = tiles[i]
    var w = Math.min(t.w, cols)
    var h = Math.min(t.h, maxRows)
    var x = t.x
    var y = t.y
    if (!fits(x, y, w, h)) {
      var found = false
      for (var sy = 0; sy + h <= maxRows && !found; sy++)
        for (var sx = 0; sx + w <= cols && !found; sx++)
          if (fits(sx, sy, w, h)) { x = sx; y = sy; found = true }
      if (!found) { dropped.push(t.widget); continue }
    }
    take(x, y, w, h)
    // `i` is the tile's place in its page's list as written, which is how an
    // edit names it (HM49): a dropped tile before it would shift a count of
    // the placed ones.
    placed.push({ widget: t.widget, x: x, y: y, w: w, h: h, i: i })
  }
  return { tiles: placed, dropped: dropped }
}

// HM9. The grid on a page of a given size: square cells, `gapIn` between them,
// `gapOut` from the edges. Rows are what fits, never fewer than one.
function grid(width, height, columns, gapIn, gapOut) {
  var cols = Math.max(1, int(columns, 6))
  var inner = Math.max(0, width - 2 * gapOut)
  var cell = Math.max(1, Math.floor((inner - (cols - 1) * gapIn) / cols))
  var usable = Math.max(0, height - 2 * gapOut)
  var rows = Math.max(1, Math.floor((usable + gapIn) / (cell + gapIn)))
  return { columns: cols, rows: rows, cell: cell, gapIn: gapIn, gapOut: gapOut }
}

// A cell rectangle in pixels on that grid.
function rect(g, t) {
  return {
    x: g.gapOut + t.x * (g.cell + g.gapIn),
    y: g.gapOut + t.y * (g.cell + g.gapIn),
    width: t.w * g.cell + (t.w - 1) * g.gapIn,
    height: t.h * g.cell + (t.h - 1) * g.gapIn
  }
}

// HM5. Where a page drag settles: the nearer page, or one page on in the
// direction of a fling. `travelled` is in pages from the left edge of page 0,
// `velocity` is toward higher pages in px/ms, and the answer is clamped to the
// pages that exist.
function settle(start, travelled, velocity, fling, count) {
  var last = Math.max(0, count - 1)
  var target = Math.round(travelled)
  if (velocity >= fling) target = Math.max(target, Math.floor(travelled) + 1)
  else if (velocity <= -fling) target = Math.min(target, Math.ceil(travelled) - 1)
  // Never more than one page from where the drag began: a long fast drag is
  // still one page turn, as on every phone launcher.
  target = Math.max(start - 1, Math.min(start + 1, target))
  return Math.max(0, Math.min(last, target))
}

// ------------------------------------------------------------------ §K
//
// Arranging tiles (HM42-HM50). Everything here is in the page's own pixels and
// cells; the view hands in where the finger is and gets back a cell rectangle,
// so the rules run under node without a screen.

// The pitch from one cell's left edge to the next one's.
function pitch(g) { return g.cell + g.gapIn }

// HM44, HM45. The grid line nearest a position: 0 is the left (top) edge of the
// first column (row), `columns` (`rows`) the far edge of the last. A line sits
// in the middle of its gutter, so a finger half way across a gutter is on it.
function colLine(g, px) {
  var k = Math.round((px - g.gapOut + g.gapIn / 2) / pitch(g))
  return Math.max(0, Math.min(g.columns, k))
}
function rowLine(g, py) {
  var k = Math.round((py - g.gapOut + g.gapIn / 2) / pitch(g))
  return Math.max(0, Math.min(g.rows, k))
}

function overlaps(a, b) {
  return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}

function contains(r, px, py) {
  return px >= r.x && px < r.x + r.width && py >= r.y && py < r.y + r.height
}

// HM45. Which edges of a tile's rectangle a press at (px, py) grabs: within
// `grab` of the frame, inside or just outside it, and at the sides `sideGrab`
// inward, because at the screen's edge there is no outside to reach and the
// back gesture has the outermost strip. Never more than a third of the tile
// in, so a small tile keeps a middle to move it by. Omalauncher's edgesAt().
function edgesAt(r, px, py, grab, sideGrab) {
  var inY = py > r.y - grab && py < r.y + r.height + grab
  var inX = px > r.x - grab && px < r.x + r.width + grab
  var gx = Math.min(sideGrab, r.width / 3)
  var gy = Math.min(grab, r.height / 3)
  var e = {
    left: inY && px > r.x - grab && px < r.x + gx,
    top: inX && py > r.y - grab && py < r.y + gy,
    right: inY && px < r.x + r.width + grab && px > r.x + r.width - gx,
    bottom: inX && py < r.y + r.height + grab && py > r.y + r.height - gy
  }
  e.any = e.left || e.top || e.right || e.bottom
  return e
}

// HM45. The cell a resize gives: the grabbed edges follow the finger to the
// nearest grid line, a tile stays at least one cell each way, and null when
// the result would overlap one of `others` -- the caller keeps what it had,
// so the edge stops at the other tile rather than pushing it.
function resized(g, cell, edges, px, py, others) {
  var right = cell.x + cell.w
  var bottom = cell.y + cell.h
  var x0 = edges.left ? Math.min(colLine(g, px), right - 1) : cell.x
  var x1 = edges.right ? Math.max(colLine(g, px), cell.x + 1) : right
  var y0 = edges.top ? Math.min(rowLine(g, py), bottom - 1) : cell.y
  var y1 = edges.bottom ? Math.max(rowLine(g, py), cell.y + 1) : bottom
  var next = { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }
  for (var i = 0; i < (others || []).length; i++)
    if (overlaps(others[i], next)) return null
  return next
}

// HM44. Where a carried tile would land: its top-left corner (the finger less
// where the finger holds it) snapped to the nearest lines, kept on the grid,
// and null where that would overlap one of `others`.
function dropCell(g, cell, topLeftX, topLeftY, others) {
  var x = Math.max(0, Math.min(g.columns - cell.w, colLine(g, topLeftX)))
  var y = Math.max(0, Math.min(g.rows - cell.h, rowLine(g, topLeftY)))
  var next = { x: x, y: y, w: cell.w, h: cell.h }
  for (var i = 0; i < (others || []).length; i++)
    if (overlaps(others[i], next)) return null
  return next
}

// HM44. Which of `tiles` (placed cells) the finger is over, or -1: the last one
// listed, as the one drawn on top.
function under(g, tiles, px, py) {
  for (var i = (tiles || []).length - 1; i >= 0; i--)
    if (contains(rect(g, tiles[i]), px, py)) return i
  return -1
}

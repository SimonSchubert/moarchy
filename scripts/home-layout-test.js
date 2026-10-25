// Run moarchy.home/Layout.js against the rules in docs/home.md §B-§D.
//
//   node scripts/home-layout-test.js
//
// Also holds /usr/share/moarchy/home.toml -- default/omarchy/home.toml here --
// to the layout home actually ships with (HM16): the documented default and the
// real one are two files, and this is what stops them disagreeing.
const fs = require("fs")
const path = require("path")

const root = path.join(__dirname, "..")
const plugins = path.join(root, "default", "omarchy", "plugins")
const load = (file, names) => {
  const out = {}
  const src = fs.readFileSync(file, "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "")
  new Function("exports", src + "\n;Object.assign(exports, {" + names.join(",") + "})")(out)
  return out
}
const L = load(path.join(plugins, "moarchy.home", "Layout.js"),
               ["SHIPPED", "pages", "withWaiting", "written", "place", "grid", "rect", "settle", "safeName",
                "colLine", "rowLine", "overlaps", "edgesAt", "resized", "dropCell", "under"])
const Toml = load(path.join(plugins, "moarchy.common", "Toml.js"), ["parse", "get"])

let fail = 0
const check = (ok, what, detail) => {
  if (!ok) fail++
  console.log(`  ${ok ? "\x1b[32mok\x1b[0m  " : "\x1b[31mNO\x1b[0m  "} ${what}${detail ? "  -- " + detail : ""}`)
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b)

console.log("pages (HM4, HM16)")
{
  const r = L.pages(null)
  check(r.pages[0].kind === "face" && r.pages[0].face === "start" && r.firstTiles === 1,
        "no file is the shipped layout: the start face, then page 1")
  const shipped = Toml.parse(fs.readFileSync(path.join(root, "default", "omarchy", "home.toml"), "utf8"))
  check(shipped.ok && same(shipped.data.page, L.SHIPPED),
        "the packaged home.toml is exactly Layout.SHIPPED")

  const mixed = L.pages({ page: [ { face: "a" }, { tiles: [] }, { face: "b" }, { tiles: [] } ] })
  check(same(mixed.pages.map(p => p.kind + (p.face || "")), ["facea", "tiles", "faceb", "tiles"]),
        "pages are drawn in the file's order, faces right of page 1 included (HM4)")
  check(mixed.firstTiles === 1, "page 1 is the first page of tiles")

  const onlyFaces = L.pages({ page: [ { face: "a" } ] })
  check(onlyFaces.pages.length === 2 && onlyFaces.pages[1].kind === "tiles",
        "a file of faces only still gets a page 1 to open on")

  const bad = L.pages({ page: [ { face: "../../etc/passwd" }, { nothing: 1 }, { tiles: [ { x: 1 } ] } ] })
  check(bad.skipped.length === 3, "an unsafe face name, an empty page and a tile with no widget are reported",
        bad.skipped.join("; "))
  check(!bad.pages.some(p => p.face), "an unsafe face name loads nothing")
}

console.log("waiting pages (HM51, HM52)")
{
  const w = L.withWaiting(L.pages(null))
  check(same(w.pages.map(p => p.kind + (p.waiting ? "*" : "")), ["invite*", "face", "tiles", "tiles*"]),
        "the face invite waits left of the leftmost page, an empty page after the last",
        w.pages.map(p => p.kind).join(","))
  check(w.firstTiles === 2 && w.pages[w.firstTiles].tiles.length === 4, "page 1 is still the first page of tiles")
  const back = L.written(w.pages)
  check(same(back, [ { face: "start" }, { tiles: L.SHIPPED[1].tiles } ]),
        "neither waiting page is written while it is empty", JSON.stringify(back))
  const used = w.pages.map(p => p.waiting && p.kind === "tiles"
    ? { kind: "tiles", tiles: [ { widget: "clock", x: 0, y: 0, w: 2, h: 2 } ], waiting: true } : p)
  check(L.written(used).length === 3 && L.written(used)[2].tiles[0].widget === "clock",
        "a tile on the waiting page makes it a page in the file")
  const emptied = [ { kind: "tiles", tiles: [ { widget: "a", x: 0, y: 0, w: 1, h: 1 } ] }, { kind: "tiles", tiles: [] } ]
  check(L.written(emptied).length === 1, "a page of tiles that was emptied goes away")
  check(same(L.written([ { kind: "face", face: "f" }, { kind: "tiles", tiles: [] } ]), [ { face: "f" }, { tiles: [] } ]),
        "but the last page of tiles stays, however empty")
  const unplaced = L.written([ { kind: "tiles", tiles: [ { widget: "a", x: -1, y: -1, w: 2, h: 3 } ] } ])
  check(same(unplaced[0].tiles[0], { widget: "a", w: 2, h: 3 }), "a tile with no cell is written with its size only")
  // The round trip a write and a read-back make: what home draws after reading
  // what it wrote is what it drew, so nothing rebuilds (HM48).
  const again = L.withWaiting(L.pages({ page: L.written(used) }))
  check(same(again.pages.slice(0, 4).map(p => p.kind), ["invite", "face", "tiles", "tiles"]) &&
        again.pages[again.pages.length - 1].waiting === true,
        "written and read back, a used spare is a page and a new spare follows")
}

console.log("place (HM9, HM17)")
{
  const r = L.place([
    { widget: "a", x: 0, y: 0, w: 3, h: 2 },
    { widget: "b", x: 0, y: 0, w: 3, h: 2 },   // on top of a
    { widget: "c", x: 9, y: 9, w: 2, h: 2 },   // off the grid
    { widget: "d", x: -1, y: -1, w: 9, h: 1 }, // wider than the grid, no position (row 4 is the first one free)
  ], 6, 5)
  const at = id => r.tiles.find(t => t.widget === id)
  check(same(at("a"), { widget: "a", x: 0, y: 0, w: 3, h: 2, i: 0 }), "a tile where it asked to be stays there")
  check(at("c").i === 2 && at("d").i === 3, "a placed tile keeps its index in the page as written (HM49)")
  const gap = L.place([ { widget: "big", x: 0, y: 0, w: 6, h: 1 }, { widget: "lost", x: 0, y: 0, w: 6, h: 1 },
                        { widget: "after", x: 0, y: 0, w: 1, h: 1 } ], 6, 1)
  check(gap.tiles.length === 1 && gap.dropped[0] === "lost", "(fixture: the second tile is dropped)")
  check(at("b").x === 3 && at("b").y === 0, "a tile on top of an earlier one takes the first free spot",
        JSON.stringify(at("b")))
  check(at("c").x === 0 && at("c").y === 2, "a tile off the grid takes the first free spot", JSON.stringify(at("c")))
  check(at("d").w === 6 && at("d").y === 4, "a tile wider than the grid is clamped, not dropped", JSON.stringify(at("d")))
  const full = L.place([ { widget: "big", x: 0, y: 0, w: 6, h: 4 }, { widget: "late", x: 0, y: 0, w: 1, h: 1 } ], 6, 4)
  check(same(full.dropped, ["late"]) && full.tiles.length === 1, "a tile with no room left is dropped and named")
  // No overlap, whatever was asked.
  const many = L.place(Array.from({ length: 30 }, (_, i) => ({ widget: "w" + i, x: i % 5, y: 0, w: 2, h: 2 })), 6, 9)
  const cells = new Set()
  let overlap = false
  for (const t of many.tiles) for (let y = t.y; y < t.y + t.h; y++) for (let x = t.x; x < t.x + t.w; x++) {
    const k = x + "," + y
    if (cells.has(k) || x >= 6 || y >= 9) overlap = true
    cells.add(k)
  }
  check(!overlap, "thirty colliding requests never overlap and never leave the grid",
        `${many.tiles.length} placed, ${many.dropped.length} dropped`)
}

console.log("grid (HM9)")
{
  const g = L.grid(360, 540, 6, 6, 6)
  check(g.columns === 6 && g.cell === 53, "360 wide, 6 columns, 6px gaps: 53px cells", JSON.stringify(g))
  const last = L.rect(g, { x: 5, y: 0, w: 1, h: 1 })
  check(last.x + last.width <= 360 - 6, "the last column ends inside the outer gap", JSON.stringify(last))
  const r = L.rect(g, { x: 0, y: 0, w: 3, h: 2 })
  check(r.width === 3 * 53 + 2 * 6 && r.height === 2 * 53 + 6, "a 3x2 tile spans its gutters")
  check(g.rows * (g.cell + 6) - 6 <= 540 - 12, "the rows fit the height", "rows=" + g.rows)
}

console.log("settle (HM5)")
check(L.settle(1, 1.4, 0, 0.3, 3) === 1, "a short drag springs back")
check(L.settle(1, 1.6, 0, 0.3, 3) === 2, "past halfway it turns the page")
check(L.settle(1, 1.1, 0.5, 0.3, 3) === 2, "a fling turns it from a short drag")
check(L.settle(1, 0.9, -0.5, 0.3, 3) === 0, "a fling the other way turns it back")
check(L.settle(0, -0.4, -2, 0.3, 3) === 0, "there is nothing left of page 0")
check(L.settle(0, 2.9, 0, 0.3, 4) === 1, "one drag is at most one page")

console.log("arranging (HM44, HM45, HM50)")
{
  // 360 wide, 6 columns, 6px gaps: 53px cells on a 59px pitch from x=6.
  const g = L.grid(360, 694, 6, 6, 6)
  check(L.colLine(g, 6) === 0 && L.colLine(g, 6 + 59) === 1 && L.colLine(g, 354) === 6,
        "column lines sit at each cell's left edge, and the last at the far edge")
  check(L.colLine(g, 6 + 59 - 25) === 1 && L.colLine(g, 6 + 59 - 35) === 0,
        "a finger snaps to the nearer line")
  check(L.colLine(g, -50) === 0 && L.colLine(g, 999) === 6, "lines are clamped to the grid")

  const r = L.rect(g, { x: 1, y: 1, w: 3, h: 3 })   // 65..236 across, 65..236 down
  const e = (x, y) => { const v = L.edgesAt(r, x, y, 20, 36); return ["left", "top", "right", "bottom"].filter(k => v[k]).join("+") || "none" }
  check(e(r.x + r.width / 2, r.y + r.height / 2) === "none", "the middle of a tile is for moving it")
  check(e(r.x + r.width / 2, r.y - 10) === "top", "just outside the top frame grabs the top")
  check(e(r.x + 30, r.y + r.height / 2) === "left", "36px in at a side grabs the side")
  check(e(r.x + r.width + 10, r.y + r.height + 10) === "right+bottom", "outside a corner grabs the corner")
  check(e(r.x + r.width / 2, r.y - 30) === "none", "beyond the grab is not the frame")
  const small = L.rect(g, { x: 0, y: 0, w: 1, h: 1 })
  const sv = L.edgesAt(small, small.x + small.width / 2, small.y + small.height / 2, 20, 36)
  check(!sv.any, "a one-cell tile keeps its middle third for moving")

  const cell = { x: 1, y: 1, w: 3, h: 3 }
  const down2 = L.resized(g, cell, { bottom: true }, 0, L.rect(g, { x: 0, y: 6, w: 1, h: 1 }).y, [])
  check(same(down2, { x: 1, y: 1, w: 3, h: 5 }), "dragging the bottom edge two rows down grows it by two",
        JSON.stringify(down2))
  const collapse = L.resized(g, cell, { right: true }, 0, 0, [])
  check(collapse.w === 1, "a tile is at least one cell wide, however far the edge goes", JSON.stringify(collapse))
  const blocked = L.resized(g, cell, { right: true }, 354, 0, [ { x: 5, y: 2, w: 1, h: 1 } ])
  check(blocked === null, "growing into another tile is refused")
  const offGrid = L.resized(g, cell, { left: true }, -200, 0, [])
  check(offGrid.x === 0 && offGrid.w === 4, "an edge stops at the grid's edge", JSON.stringify(offGrid))

  const others = [ { x: 0, y: 0, w: 3, h: 4 } ]
  const land = L.dropCell(g, { x: 3, y: 0, w: 3, h: 2 }, L.rect(g, { x: 3, y: 5, w: 1, h: 1 }).x + 10,
                          L.rect(g, { x: 3, y: 5, w: 1, h: 1 }).y + 10, others)
  check(same(land, { x: 3, y: 5, w: 3, h: 2 }), "a carried tile lands on the nearest cells", JSON.stringify(land))
  check(L.dropCell(g, { x: 3, y: 0, w: 3, h: 2 }, 6, 6, others) === null, "not on top of another tile")
  const edge = L.dropCell(g, { x: 0, y: 0, w: 3, h: 2 }, 999, 999, [])
  check(edge.x === 3 && edge.y === g.rows - 2, "and never off the grid", JSON.stringify(edge))

  const tiles = [ { x: 0, y: 0, w: 3, h: 4 }, { x: 3, y: 0, w: 3, h: 4 } ]
  check(L.under(g, tiles, 300, 100) === 1 && L.under(g, tiles, 50, 100) === 0 && L.under(g, tiles, 50, 600) === -1,
        "the tile under a finger is found by its drawn rectangle")
  check(L.overlaps({ x: 0, y: 0, w: 2, h: 2 }, { x: 1, y: 1, w: 2, h: 2 }) &&
        !L.overlaps({ x: 0, y: 0, w: 2, h: 2 }, { x: 2, y: 0, w: 2, h: 2 }), "touching is not overlapping")
}

console.log("names")
check(L.safeName("start") === "start" && L.safeName("my-face_2") === "my-face_2", "plain names pass")
check(L.safeName("../x") === "" && L.safeName("a/b") === "" && L.safeName(".hidden") === "", "paths do not")

if (fail) { console.log(`\n${fail} failed`); process.exit(1) }
console.log("\nall passed")

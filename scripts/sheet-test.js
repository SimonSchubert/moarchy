// Run moarchy.common/Sheet.js against a fake host (docs/refactor.md I1a).
//
//   node scripts/sheet-test.js
//
// B6's rule -- "a sheet opening puts away every sheet on its own layer or above
// it, and none of the ones below it" -- was argued in prose and implemented four
// times, and each of the four got a different part of it wrong. It is one
// function now, and a rule that decides what leaves the screen is worth a check
// that does not need the phone to run.
//
// The shipped file is read and evaluated rather than copied: a test against a
// copy passes while the copy is the thing that has drifted.
const fs = require("fs")
const path = require("path")

const src = fs.readFileSync(
  path.join(__dirname, "..", "default", "omarchy", "plugins",
            "moarchy.common", "Sheet.js"), "utf8")

// `.pragma library` is a QML engine directive and not JavaScript.
const sheet = {}
new Function("exports", src.replace(/^\s*\.pragma\s+library\s*$/m, "") +
  "\n;Object.assign(exports, { SHEETS, SHADE, DRAWER, THEMES, WINDOW, TOP," +
  " OVERLAY, ids, cover, payload, summon })")(sheet)

const { SHADE, DRAWER, THEMES, WINDOW, TOP, OVERLAY } = sheet
const ALL = [SHADE, DRAWER, THEMES]

let fail = 0
const check = (ok, what, detail) => {
  if (!ok) fail++
  console.log(`  ${ok ? "\x1b[32mok\x1b[0m  " : "\x1b[31mNO\x1b[0m  "} ${what}${detail ? "  -- " + detail : ""}`)
}
const host = open => ({
  hidden: [],
  isPluginOpen(id) { return open.includes(id) },
  hide(id) { this.hidden.push(id) },
  summon(id, json) { this.summoned = [id, json] },
})
const same = (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort())

console.log("cover(): every sheet at or above the caller, never itself (B6)")
for (const [name, mine, rank, up, want] of [
  ["the shade covers nothing -- it is the only sheet on Overlay", SHADE, OVERLAY, ALL, []],
  ["the drawer covers the picker beside it and the shade above", DRAWER, TOP, ALL, [SHADE, THEMES]],
  ["the picker covers the drawer beside it and the shade above", THEMES, TOP, ALL, [SHADE, DRAWER]],
  ["a shell app is a window, so it covers all three", "moarchy.wifi", WINDOW, ALL, ALL],
  ["...including the picker on its own (I2a)", "moarchy.wifi", WINDOW, [THEMES], [THEMES]],
  ["nothing open, nothing hidden", DRAWER, TOP, [], []],
  ["a sheet never hides itself", DRAWER, TOP, [DRAWER], []],
]) {
  const h = host(up)
  sheet.cover(h, mine, rank)
  check(same(h.hidden, want), name, `hid [${h.hidden}]`)
}

console.log("cover(): a host that is not ready yet")
let threw = null
try { sheet.cover(null, DRAWER, TOP); sheet.cover({}, DRAWER, TOP) } catch (e) { threw = e }
check(!threw, "a missing or half-built shell is a no-op", threw && String(threw))

console.log("payload(): a malformed summon must not stop a screen opening")
for (const [raw, want] of [
  ["{}", {}], ['{"returnTo":"moarchy.shade"}', { returnTo: "moarchy.shade" }],
  ["", {}], ["not json", {}], [null, {}], [undefined, {}], ["null", {}],
]) {
  const got = sheet.payload(raw)
  check(JSON.stringify(got) === JSON.stringify(want),
        `payload(${JSON.stringify(raw)})`, JSON.stringify(got))
}

console.log("ids(): topmost first, which is the order the back gesture walks (G11)")
check(JSON.stringify(sheet.ids()) === JSON.stringify(ALL), "shade, drawer, themes",
      sheet.ids().join(" "))

console.log("summon(): goes through the host, so openPanelIds stays its record")
const h = host([])
sheet.summon(h, DRAWER)
check(same(h.summoned || [], [DRAWER, "{}"]), "summon(shell, DRAWER)", String(h.summoned))

console.log(fail ? `\n${fail} failed` : "\nall passed")
process.exit(fail ? 1 : 0)

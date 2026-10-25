// Run the minimal app drawer's glyph table (docs/app-drawer-minimal.md M10,
// M11).
//
//   node scripts/glyph-test.js
//
// Two kinds of thing are checked here, and they fail in two different ways on
// the phone.
//
// **The literals.** A Nerd Font codepoint is above the BMP, and `\uXXXX` in
// QML takes exactly four hex digits -- so a codepoint written as an escape is
// truncated and the fifth digit is left behind as a literal character. The
// invariant that catches it is the one these strings actually have: a glyph is
// exactly ONE code point. Measured in code points and not in `.length`, which
// is 2 for every one of these because JavaScript counts UTF-16 units.
// `bin/moarchy-selftest` asks fontconfig the other half of the question --
// whether an installed font covers the codepoint -- and that one needs the
// phone; this one does not.
//
// **The order.** `BY_CATEGORY` is an ordered list precisely because almost
// every entry on this phone also claims `Utility`, `System` or `Network`. A
// Calculator matched against an unordered map is a coin flip between a
// calculator and a wrench, and the failure is silent and looks like a taste
// decision rather than a bug. So the cases below are the real category lines
// off the desktop entries this repo ships.
//
// The shipped file is read and evaluated rather than copied: a test against a
// copy passes while the copy is the thing that has drifted.
const fs = require("fs")
const path = require("path")

const pluginDir = path.join(__dirname, "..", "default", "omarchy", "plugins")
const src = fs.readFileSync(
  path.join(pluginDir, "moarchy.app-drawer-minimal", "Glyphs.js"), "utf8")

// `.pragma library` is a QML engine directive and not JavaScript.
const glyphs = {}
new Function("exports", src.replace(/^\s*\.pragma\s+library\s*$/m, "") +
  "\n;Object.assign(exports, { GENERIC, BY_ID, BY_PREFIX, BY_CATEGORY," +
  " categoriesOf, forEntry, letterFor })")(glyphs)

const { GENERIC, BY_ID, BY_PREFIX, BY_CATEGORY, forEntry, letterFor } = glyphs

let fail = 0
const check = (ok, what, detail) => {
  if (!ok) fail++
  console.log(`  ${ok ? "\x1b[32mok\x1b[0m  " : "\x1b[31mNO\x1b[0m  "} ${what}${detail ? "  -- " + detail : ""}`)
}

// A desktop entry, as much of one as forEntry() reads.
const entry = (id, categories) => ({ id, categories })

// ---------------------------------------------------------------- M11
console.log("every glyph is one code point in a private use area (M11)")
const PUA = cp => (cp >= 0xe000 && cp <= 0xf8ff) || (cp >= 0xf0000 && cp <= 0xffffd)
const every = [["GENERIC", GENERIC]]
for (const k of Object.keys(BY_ID)) every.push([`BY_ID[${k}]`, BY_ID[k]])
for (const p of BY_PREFIX) every.push([`BY_PREFIX[${p.prefix}]`, p.glyph])
for (const [k, g] of BY_CATEGORY) every.push([`BY_CATEGORY[${k}]`, g])

let bad = []
for (const [where, g] of every) {
  const points = [...String(g)]
  if (points.length !== 1 || !PUA(points[0].codePointAt(0)))
    bad.push(`${where} = ${JSON.stringify(g)}`)
}
check(bad.length === 0, `${every.length} literals, each one glyph`, bad.join("; "))

// A table with nothing in it passes every test above, which is the shape a
// check has to be able to fail. Counted out loud for the same reason
// bin/moarchy-selftest prints how many files it read.
check(BY_CATEGORY.length > 20 && Object.keys(BY_ID).length > 0,
      "the table is not empty", `${BY_CATEGORY.length} categories, `
      + `${Object.keys(BY_ID).length} id overrides`)

const seen = {}
const dupes = []
for (const [k] of BY_CATEGORY) {
  const key = k.toLowerCase()
  if (seen[key]) dupes.push(k)
  seen[key] = true
}
check(dupes.length === 0, "no category is listed twice", dupes.join(", "))

// ---------------------------------------------------------------- M10
console.log("\nthe specific category wins over the parent every entry also claims (M10)")
for (const [id, categories, want, why] of [
  // The category lines are verbatim from the .desktop files this repo ships.
  ["org.moarchy.Calculator.plugin", ["Utility", "Calculator"], "Calculator", "not Utility's wrench"],
  ["org.moarchy.Clock.plugin", ["Utility", "Clock"], "Clock", "not Utility's wrench"],
  ["org.moarchy.Files.plugin", ["Utility", "Core", "FileTools", "FileManager"], "FileManager", "not Utility's wrench"],
  ["org.moarchy.Calendar.plugin", ["Office", "Calendar"], "Calendar", "not Office's document"],
  ["org.moarchy.Contacts.plugin", ["Office", "ContactManagement"], "ContactManagement", "not Office's document"],
  ["org.moarchy.Mail.plugin", ["Network", "Email"], "Email", "not Network's cloud"],
  ["org.moarchy.Messages.plugin", ["Network", "Chat"], "Chat", "not Network's cloud"],
  ["org.moarchy.Phone.plugin", ["Network", "Telephony"], "Telephony", "not Network's cloud"],
  ["org.moarchy.Minesweeper.plugin", ["Game", "LogicGame"], "Game", "LogicGame is not a key"],
  ["org.moarchy.Sim.plugin", ["System", "Settings"], "Settings", "not System's cog by accident"],
  ["org.moarchy.Vitals.plugin", ["System", "Monitor"], "Monitor", "not System"],
  ["org.moarchy.Editor.plugin", ["Utility", "TextEditor"], "TextEditor", "not Utility's wrench"],
]) {
  const table = {}
  for (const [k, g] of BY_CATEGORY) if (table[k] === undefined) table[k] = g
  check(forEntry(entry(id, categories)) === table[want],
        `${id} takes ${want}`, why)
}

// Case is folded on the way in, because a desktop file is written by hand.
check(forEntry(entry("x", ["audiovideo"])) === forEntry(entry("y", ["AudioVideo"])),
      "a lower-cased category still matches")

console.log("\nan id override beats the categories it exists to correct (M10)")
check(forEntry(entry("org.moarchy.Weather.plugin", ["Utility"])) !== forEntry(entry("z", ["Utility"])),
      "Weather does not get Utility's wrench",
      JSON.stringify(forEntry(entry("org.moarchy.Weather.plugin", ["Utility"]))))
check(forEntry(entry("waydroid.com.example.app", ["Network"])) === BY_PREFIX[0].glyph,
      "an Android id beats whatever the APK claimed")

console.log("\nnothing to go on is the generic glyph, never a blank (M10)")
for (const [what, e] of [
  ["no categories at all", entry("Discord.something", [])],
  ["categories undefined", { id: "q" }],
  ["an unknown category", entry("q", ["Nonsense"])],
  ["a null entry", null],
  ["categories that throw", { id: "q", get categories() { throw new Error("boom") } }],
]) {
  let got, threw = null
  try { got = forEntry(e) } catch (err) { threw = err }
  check(!threw && got === GENERIC, what, threw ? String(threw) : JSON.stringify(got))
}

// ---------------------------------------------------------------- M12
console.log("\nthe rail's letter (M12)")
for (const [name, want] of [
  ["Files", "F"], ["files", "F"], ["  Weather", "W"],
  ["btop", "B"], ["2048", "#"], ["", "#"], [null, "#"], ["Éclair", "#"],
]) {
  check(letterFor(name) === want, `letterFor(${JSON.stringify(name)}) is ${want}`,
        letterFor(name))
}

// ---------------------------------------------------------------- upkeep
//
// An override that no longer names anything is worse than none: it reads as a
// decision somebody made about an app that is not there. Only the ids this
// repo itself ships can be checked -- Discord and X are upstream's entries and
// a Waydroid prefix names nothing until an APK is installed.
console.log("\nevery moarchy id override still names an entry this repo ships")
const shipped = new Set()
for (const dir of fs.readdirSync(pluginDir)) {
  const full = path.join(pluginDir, dir)
  if (!fs.statSync(full).isDirectory()) continue
  for (const f of fs.readdirSync(full))
    if (f.endsWith(".desktop")) shipped.add(f.slice(0, -".desktop".length))
}
const stale = Object.keys(BY_ID).filter(id => id.indexOf("org.moarchy.") === 0 && !shipped.has(id))
check(stale.length === 0, `${shipped.size} entries scanned`, stale.join(", "))

console.log(fail === 0 ? "\nall passed" : `\n${fail} failed`)
process.exit(fail === 0 ? 0 : 1)

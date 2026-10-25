// Run moarchy.common/Toml.js against what this tree's files hold (docs/home.md HM30).
//
//   node scripts/toml-test.js
//
// One reader serves every surface, so a fault in it is a fault on all of them at
// once. The packaged ui.toml and home.toml are also read by Python's tomllib
// (`moarchy-ui`, `moarchy-home`), and the two readers must agree on them, or the
// shell and the command that writes for it see different files. That half runs
// when python3 is on PATH and says so when it is not.
//
// The shipped file is evaluated rather than copied, for sheet-test.js's reason.
const fs = require("fs")
const path = require("path")
const { execFileSync } = require("child_process")

const root = path.join(__dirname, "..")
const common = path.join(root, "default", "omarchy", "plugins", "moarchy.common")
const src = fs.readFileSync(path.join(common, "Toml.js"), "utf8")

const Toml = {}
new Function("exports", src.replace(/^\s*\.pragma\s+library\s*$/m, "") +
  "\n;Object.assign(exports, { parse, flat, get })")(Toml)

let fail = 0
const check = (ok, what, detail) => {
  if (!ok) fail++
  console.log(`  ${ok ? "\x1b[32mok\x1b[0m  " : "\x1b[31mNO\x1b[0m  "} ${what}${detail ? "  -- " + detail : ""}`)
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b)

console.log("values")
for (const [text, want, what] of [
  ['a = "x"', { a: "x" }, "basic string"],
  ["a = 'C:\\x'", { a: "C:\\x" }, "literal string keeps backslashes"],
  ['a = "tab\\there \\"q\\" \\u00e9"', { a: "tab\there \"q\" é" }, "escapes"],
  ["a = 42\nb = -3\nc = 1_000", { a: 42, b: -3, c: 1000 }, "integers"],
  ["a = 0.88\nb = 1e3", { a: 0.88, b: 1000 }, "floats"],
  ["a = true\nb = false", { a: true, b: false }, "booleans"],
  ["a = [1, 2,\n  3, # three\n]", { a: [1, 2, 3] }, "a multi-line array, a comment and a trailing comma"],
  ['a = { x = 1, y = "two" }', { a: { x: 1, y: "two" } }, "inline table"],
  ['"quoted key" = 1\nbare-key_2 = 2', { "quoted key": 1, "bare-key_2": 2 }, "key spellings"],
  ["a.b.c = 1", { a: { b: { c: 1 } } }, "dotted keys"],
  ["a = 1 # trailing comment", { a: 1 }, "trailing comment"],
  ["", {}, "empty text"],
]) {
  const r = Toml.parse(text)
  check(r.ok && same(r.data, want), what, r.ok ? JSON.stringify(r.data) : `line ${r.line}: ${r.error}`)
}

console.log("tables")
{
  const r = Toml.parse([
    "top = 1",
    "[shape]",
    'corners = "square"',
    "[control-center]",
    'density = "compact"',
    "[[page]]",
    'face = "start"',
    "[[page]]",
    "tiles = [",
    '  { widget = "fetch", x = 0, y = 0, w = 3, h = 4 },',
    '  { widget = "today", x = 3, y = 0, w = 3, h = 4 },',
    "]",
    "[page.extra]",
    "n = 2",
  ].join("\n"))
  check(r.ok, "a sectioned file with arrays of tables parses", r.error)
  check(Toml.get(r.data, "shape.corners") === "square", "get() walks a section")
  check(Toml.get(r.data, "control-center.density") === "compact", "a kebab section name")
  check(r.data.top === 1, "a key above the first header is top-level")
  check(Array.isArray(r.data.page) && r.data.page.length === 2, "[[page]] twice is two pages")
  check(r.data.page[1].tiles.length === 2 && r.data.page[1].tiles[1].widget === "today",
        "inline tables inside a multi-line array")
  check(r.data.page[1].extra && r.data.page[1].extra.n === 2, "[page.extra] lands in the last page")
  check(Toml.get(r.data, "shape.nope", "dflt") === "dflt", "a missing key is the fallback")
  check(Toml.get(r.data, "top.deeper", "dflt") === "dflt", "a path through a value is the fallback, not a throw")
}

console.log("errors, with the line they are on (HM16 shows it)")
for (const [text, line, what] of [
  ["a = 1\n[shape\nb = 2", 2, "an unclosed header"],
  ['a = 1\nb = "open\n', 2, "an unterminated string"],
  ["a = 1\na = 2", 2, "a key set twice"],
  ["a = 1\n\nb = yes", 3, "a bare word that is not a value"],
  ["a = [1, 2", 1, "an unclosed array"],
  ["a = 1 b = 2", 1, "two keys on one line"],
  ["a = 1979-05-27", 1, "a date, which this reader does not take"],
]) {
  const r = Toml.parse(text)
  check(!r.ok && r.line === line, what, r.ok ? "parsed" : `line ${r.line}: ${r.error}`)
}
{
  const r = Toml.parse("kept = 1\n[shape\nlost = 2")
  check(!r.ok && r.data.kept === 1, "a failed parse still hands back what it read before the error")
}

console.log("flat(), the forgiving read (HM29)")
{
  const d = Toml.flat("corners = large\n# c\n[home]\nopacity = 0.5 # half\n[a.b]\nx = 'y'\n")
  check(d.corners === "large" && d.home.opacity === "0.5" && d.a.b.x === "y",
        "unquoted values, sections, dotted headers and trailing comments", JSON.stringify(d))
}

console.log("the packaged files")
let python = true
try { execFileSync("python3", ["-c", "import tomllib"], { stdio: "ignore" }) } catch (e) { python = false }
for (const rel of ["default/omarchy/ui.toml", "default/omarchy/home.toml"]) {
  const file = path.join(root, rel)
  if (!fs.existsSync(file)) { check(false, rel + " exists"); continue }
  const r = Toml.parse(fs.readFileSync(file, "utf8"))
  check(r.ok, rel + " parses", r.ok ? "" : `line ${r.line}: ${r.error}`)
  if (!python) { console.log("  --   python3 with tomllib not found; " + rel + " not cross-checked"); continue }
  const py = JSON.parse(execFileSync("python3", ["-c",
    "import json,sys,tomllib; print(json.dumps(tomllib.load(open(sys.argv[1],'rb'))))", file]).toString())
  check(same(r.data, py), rel + " reads the same in Toml.js and in tomllib")
}

console.log("Ui.js against the packaged ui.toml (HM27, HM29)")
{
  // Ui.js `.import`s Sheet.js and Toml.js; handed in here as the engine would.
  const Sheet = {}
  new Function("exports", fs.readFileSync(path.join(common, "Sheet.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "") +
    "\n;Object.assign(exports, { APP_DRAWER, APP_DRAWER_MINIMAL, WORKSPACE_OVERVIEW, CONTROL_CENTER })")(Sheet)
  const Ui = {}
  new Function("exports", "Sheet", "Toml", fs.readFileSync(path.join(common, "Ui.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "").replace(/^\s*\.import .*$/mg, "") +
    "\n;Object.assign(exports, { fallback, parse, merge })")(Ui, Sheet, Toml)

  const packaged = fs.readFileSync(path.join(root, "default", "omarchy", "ui.toml"), "utf8")
  check(same(Ui.parse(packaged), Ui.fallback()),
        "the packaged file's values are exactly what the shell does with no file")

  const flat = 'corners = "modest"\ncontrol_center = "compact"\ngesture_bottom = "control-center"\ntile = 7\n'
  const sectioned = '[shape]\ncorners = "modest"\ntile = 7\n[control-center]\ndensity = "compact"\n[gestures]\nbottom = "control-center"\n'
  check(same(Ui.parse(flat), Ui.parse(sectioned)), "a flat file and its sectioned twin read the same")
  const loose = Ui.parse("corners = square\n[home]\nopacity = 0.5\nprompt-bar = false\n")
  check(loose.corners === "square" && loose.homeOpacity === 0.5 && loose.homePromptBar === false,
        "unquoted values still read, sections and all", JSON.stringify(loose))
  check(Ui.parse("[home]\ncolumns = 40\n").homeColumns === 6, "an out-of-range value is the default")
  const m = Ui.merge(Ui.parse('[shape]\ncorners = "large"\nsheet = 3\n[home]\nopacity = 0.4\n'), { corners: "square" })
  check(m.corners === "square" && m.sheet === 0 && m.homeOpacity === 0.4,
        "merge: a preset drops its overrides and keeps every other setting", JSON.stringify(m))
}

if (fail) { console.log(`\n${fail} failed`); process.exit(1) }
console.log("\nall passed")

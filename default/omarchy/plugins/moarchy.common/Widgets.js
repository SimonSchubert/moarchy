// Every widget that exists, and what a host actually draws (docs/widgets.md).
//
//     import "../moarchy.common/Widgets.js" as Widgets
//
//     Widgets.resolve(file.text(), "control-center")
//       -> [ { id: "connectivity", on: true }, { id: "volume", on: false }, ... ]
//
// `.pragma library`, so there is one instance rather than a copy per importing
// component, and it reaches nothing: the arrangement text is handed in, which
// is what lets a library script answer a question about a file it cannot read
// (docs/refactor.md E3's shape).
.pragma library

.import "Ui.js" as Ui

// ---------------------------------------------------------------------------
// The catalogue (W8)
// ---------------------------------------------------------------------------
// One list, in the order a host draws them when nothing has been arranged --
// which is the control center exactly as it shipped, top to bottom. A second
// hand-kept list of widgets is the failure `gestures.md` A8 already records
// about overlay ids, so there is not one: Settings builds its rows from this
// through `moarchy-widgets`, and the host builds its column from this.
//
// `hosts` is the surfaces an entry may appear on. A widget that is fine
// anywhere says `null` rather than naming every host, so adding a host does
// not mean editing six rows to let it have what it should already have had.
//
// Glyphs are read out of the font's cmap and their names written beside them.
// Not copied from a neighbour and not picked off a chart: `control-center.md`
// S29 records how that goes, and the media card proved it again -- it had been
// drawing a SIM card for play and a paper shredder for skip-next since the day
// it was written, because those are what U+F04A7 and U+F049C are in
// JetBrainsMono Nerd Font, which is what actually renders the Material range
// (omarchy.ttf carries none of it).
//
//   md-wifi_strength_4  md-network_strength_4  md-airplane
//   md-brightness_6     md-volume_high         md-music
var WIDGETS = [
  { id: "connectivity", name: "Wi-Fi & Bluetooth", glyph: "󰤨",
    hosts: null, on: true },
  { id: "mobile-data",  name: "Mobile data",       glyph: "󰣺",
    hosts: null, on: true },
  // `arranges` is the surface this widget has a list of its own for. The
  // arrangement page puts a way in to it on this card and nowhere else -- the
  // control center itself has no edit button on it, because a control you only
  // want while rearranging does not belong on the thing being rearranged.
  { id: "toggles",      name: "Quick toggles",     glyph: "󰕰",
    hosts: ["control-center"], on: true, arranges: "quick-toggles" },
  { id: "brightness",   name: "Brightness",        glyph: "󰃟",
    hosts: null, on: true },
  { id: "volume",       name: "Volume",            glyph: "󰕾",
    hosts: null, on: true },
  { id: "media",        name: "Now playing",       glyph: "󰝚",
    hosts: null, on: true },
  { id: "calendar",     name: "Next event",        glyph: "󰃰",
    hosts: null, on: false }
]

// ---------------------------------------------------------------------------
// The quick toggles
// ---------------------------------------------------------------------------
// The tiles inside the `toggles` widget, arranged the same way widgets are and
// by the same code below -- a catalogue, an order, an on/off per entry. They
// are NOT widgets: a toggle cannot be hosted on its own, it has no `available`
// and it draws a fixed SmallTile. What it shares with a widget is only that
// the user arranges it, which is what these functions are.
//
// Four of them are wired in QML because their state is a service the shell
// already holds -- notifications, rfkill, the LED, the compositor. The rest are
// a `read` and two commands, so a fifth is a row here and no QML at all. That
// split is the whole reason this is data: `Toggles.qml` interprets it.
//
//   read     prints true/false; absent means the tile is momentary
//   cmdOn    run to switch on, or to act at all when momentary
//   cmdOff   run to switch off
//   native   the state comes from QML, not from `read`
var TOGGLES = [
  { id: "silent",     name: "Silent",      glyph: "󰂛", on: true,  native: true },
  { id: "airplane",   name: "Airplane",    glyph: "󰀝", on: true,  native: true },
  { id: "torch",      name: "Torch",       glyph: "󰉄", on: true,  native: true },
  { id: "rotate",     name: "Rotate",      glyph: "󰑥", on: true,  native: true },
  { id: "nightlight", name: "Night light", glyph: "󰔎", on: false,
    read: "moarchy-toggle-nightlight --status | jq -r .enabled",
    cmdOn: "moarchy-toggle-nightlight on",
    cmdOff: "moarchy-toggle-nightlight off" },
  { id: "stay-awake", name: "Stay awake",  glyph: "󰅶", on: false,
    read: "omarchy-toggle-idle status | jq -r .enabled",
    cmdOn: "omarchy-toggle-idle stay-awake",
    cmdOff: "omarchy-toggle-idle allow-idle" },
  { id: "location",   name: "Location",    glyph: "󰆤", on: true,
    read: "moarchy-toggle-location --status | jq -r .enabled",
    cmdOn: "moarchy-toggle-location on",
    cmdOff: "moarchy-toggle-location off" },
  { id: "keyboard",   name: "Keyboard",    glyph: "󰌌", on: false,
    cmdOn: "moarchy-toggle-keyboard" },
  // Three things were wrong with this tile, and together they meant the phone
  // could not take a screenshot at all (measured on an fp4 2026-09-22).
  //
  //   the command did not exist   `moarchy-capture-screenshot` is not a
  //                               binary. The wrapper is omarchy's, and
  //                               `omarchy-capture-screenshot fullscreen save`
  //                               writes a PNG to ~/Pictures. A tile calling a
  //                               missing command fails silently, because
  //                               execDetached does not report.
  //   no glyph                    an empty string, so the tile drew blank.
  //   off by default              which, with the other two, is why nobody
  //                               noticed them.
  //
  // It closes the control centre before capturing. Not politeness: the panel
  // fills the screen when the tile is tapped, so without the close every
  // screenshot is a picture of the screenshot button -- verified by capturing
  // the phone with the panel open, which is exactly what came out. The 0.4s is
  // the close animation. `control-center` is the IpcHandler target and NOT the
  // plugin id: `moarchy.control-center` is what `shell summon` takes, and
  // answers "Target not found." here.
  { id: "screenshot", name: "Screenshot",  glyph: "󰄀", on: true,
    cmdOn: "omarchy-shell control-center close; sleep 0.4; omarchy-capture-screenshot fullscreen save" }
]

// ---------------------------------------------------------------------------
// The surfaces that arrange something
// ---------------------------------------------------------------------------
// One row per key in `widgets.toml`. `kind` is what the entries are, which is
// what decides whether an id resolves to a file (W2) or to a tile, and it is
// the only thing that differs between arranging a control center and arranging
// the row of toggles inside it.
var SURFACES = {
  "control-center": { kind: "widget", items: WIDGETS },
  "quick-toggles":  { kind: "toggle", items: TOGGLES }
}

// ---------------------------------------------------------------------------
// Ids, files and keys
// ---------------------------------------------------------------------------

// W2. The file a widget is drawn from, derived rather than stored: `mobile-data`
// is `MobileData.qml`. Written down twice, an id and a file name drift, and the
// symptom is a widget that vanishes from one host and not the other.
function fileFor(id) {
  var parts = String(id || "").split("-")
  var out = ""
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] === "") continue
    out += parts[i].charAt(0).toUpperCase() + parts[i].slice(1)
  }
  return out === "" ? "" : out + ".qml"
}

// W16. The key one host's arrangement is stored under. Dashes to underscores,
// the spelling every other key in this project's TOML already uses.
function keyFor(hostId) {
  return String(hostId || "").replace(/-/g, "_")
}

function kindOf(surface) {
  var s = SURFACES[surface]
  return s ? s.kind : "widget"
}

// W9. What a surface may draw at all, in catalogue order. `hosts` filters the
// widget catalogue for a particular host; a toggle is available wherever the
// toggles widget is, so it has none.
function catalogue(surface) {
  var def = SURFACES[surface]
  if (!def) return []
  var out = []
  for (var i = 0; i < def.items.length; i++) {
    var e = def.items[i]
    if (e.hosts && e.hosts.indexOf(surface) < 0) continue
    out.push(e)
  }
  return out
}

function entry(surface, id) {
  var items = catalogue(surface)
  for (var i = 0; i < items.length; i++)
    if (items[i].id === id) return items[i]
  return null
}

function nameFor(surface, id) {
  var e = entry(surface, id)
  return e ? e.name : String(id || "")
}

function glyphFor(surface, id) {
  var e = entry(surface, id)
  return e ? e.glyph : ""
}

// ---------------------------------------------------------------------------
// The file
// ---------------------------------------------------------------------------
// Flat `key = "value"` lines, the same subset of TOML `Ui.js` reads, and read
// by that function rather than by a second copy of it (docs/refactor.md E7).

// The raw list for one host, or "" when the file, the key or the file itself
// is missing. W18: absent is not empty, and the difference is made below in
// resolve() rather than here -- this only reports what the file said.
function rawFor(text, hostId) {
  var data = Ui.parseToml(text)
  var v = data[keyFor(hostId)]
  return v === undefined ? "" : String(v)
}

// ---------------------------------------------------------------------------
// The arrangement (W18-W20)
// ---------------------------------------------------------------------------
// One list, in draw order. Three rules, and each of them is a failure this
// project has already had in another form:
//
//   W18  nothing said -> the catalogue's own order and states. A package that
//        writes no file into a home means absence is the shipping state
//        (structure.md P1), so absence has to be the good one.
//   W19  named nothing -> appended, in catalogue order, in its default state.
//        Without it, an upgrade that adds a widget is invisible to everyone who
//        has ever opened the Settings page.
//   W20  named nobody -> dropped. A hand-edited file and a widget removed by an
//        upgrade are the same case and neither is worth a complaint.
function resolve(text, surface) {
  var allowed = catalogue(surface)
  var seen = {}
  var out = []

  var raw = rawFor(text, surface).split(",")
  for (var i = 0; i < raw.length; i++) {
    var token = raw[i].trim()
    if (token === "") continue
    var on = true
    if (token.charAt(0) === "-") { on = false; token = token.slice(1).trim() }
    if (seen[token]) continue                      // a duplicate is the first one
    var e = entry(surface, token)
    if (!e) continue                               // W20
    seen[token] = true
    out.push({ id: e.id, on: on })
  }

  for (var j = 0; j < allowed.length; j++)         // W18 and W19 are the same line
    if (!seen[allowed[j].id])
      out.push({ id: allowed[j].id, on: allowed[j].on })

  return out
}

// Just the ids a host draws, in order -- what a column iterates.
function shown(text, surface) {
  var list = resolve(text, surface)
  var out = []
  for (var i = 0; i < list.length; i++) if (list[i].on) out.push(list[i].id)
  return out
}

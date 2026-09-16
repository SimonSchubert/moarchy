// The nine colours a note can wear.
//
// All Keep keeps of its own theme now that the rest comes from the kit. The
// nine are named for what they look like rather than for the hue role
// underneath, because "coral" is a colour a person picks and "red" is a slot in
// a palette -- and the slot is what changes when the theme does.
//
// The fill is a wash of the hue over the window's own background rather than
// the hue itself: a solid colour with the theme's text on it is unreadable on
// a yellow note in a light theme, and unreadable on half the palettes people
// actually run. The two amounts differ because a light theme needs more of the
// colour before a wash reads as deliberate.
.pragma library
.import "ui/Theme.js" as Theme

var ROLES = {
  default: "",
  coral: "red",
  peach: "orange",
  sand: "yellow",
  mint: "green",
  sage: "cyan",
  fog: "blue",
  dusk: "magenta",
  clay: "brown"
}

var KEYS = ["default", "coral", "peach", "sand", "mint", "sage", "fog", "dusk", "clay"]

var MIX_DARK = 0.24
var MIX_LIGHT = 0.30

function fill(palette, key) {
  var p = palette || Theme.fallback(true)
  // A note with no colour is the kit's ordinary box, which is what lets the
  // border come off it: it used to be `p.surface` -- a colour from the theme
  // that is near the window's own on half of them -- outlined in a hairline so
  // you could tell where the card was.
  if (!key || key === "default") return Theme.surface(p, "card")
  var role = ROLES[key] || ""
  var hue = (p.hues && p.hues[role]) || p.accent
  return Theme.mix(hue, p.background, p.dark ? MIX_DARK : MIX_LIGHT)
}

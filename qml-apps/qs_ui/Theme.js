// The phone's palette, from the same file GTK apps read.
//
// `~/.local/state/omarchy/current/theme/colors.toml` is what
// `omarchy-theme-set` stages. Mixing lives here so chrome in every plugin
// is the same ink as the rest of the shell, not a hardcoded GNOME blue.
.pragma library

var GNOME = {
  red: "#e01b24",
  orange: "#ff7800",
  yellow: "#f5c211",
  green: "#33d17a",
  cyan: "#00b8c4",
  blue: "#3584e4",
  magenta: "#c061cb",
  brown: "#986a44"
}

function hexOk(s) {
  return typeof s === "string" && /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(s.trim())
}

function normHex(s) {
  var h = String(s).trim()
  if (h.length === 4) {
    return ("#" + h[1] + h[1] + h[2] + h[2] + h[3] + h[3]).toLowerCase()
  }
  return h.toLowerCase()
}

function rgb(hex) {
  var h = normHex(hex).slice(1)
  return [
    parseInt(h.slice(0, 2), 16),
    parseInt(h.slice(2, 4), 16),
    parseInt(h.slice(4, 6), 16)
  ]
}

function mix(colour, into, amount) {
  var src = rgb(colour), dst = rgb(into)
  function ch(i) {
    var n = Math.round(src[i] * amount + dst[i] * (1 - amount))
    var t = n.toString(16)
    return t.length === 1 ? "0" + t : t
  }
  return "#" + ch(0) + ch(1) + ch(2)
}

// `Util.alpha` in qs.Commons is this function. Ours is a copy rather than an
// import so that fading a press does not drag the whole kit onto a shell that
// only exists on our image.
function alpha(colour, a) {
  return Qt.rgba(colour.r, colour.g, colour.b, a)
}

function pick(data, names) {
  for (var i = 0; i < names.length; i++) {
    var v = data[names[i]]
    if (hexOk(v)) return normHex(v)
  }
  return ""
}

function parseToml(text) {
  var data = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/\s+#.*$/, "").trim()
    if (!line || line[0] === "#" || line[0] === "[") continue
    var eq = line.indexOf("=")
    if (eq < 1) continue
    var key = line.slice(0, eq).trim()
    var raw = line.slice(eq + 1).trim()
    if ((raw[0] === "\"" && raw[raw.length - 1] === "\"") ||
        (raw[0] === "'" && raw[raw.length - 1] === "'"))
      raw = raw.slice(1, -1)
    data[key] = raw
  }
  return data
}

// Stand-ins for a desktop with no Omarchy, a theme with no colors.toml, or a
// malformed one. Themed by the file's presence, never broken by its absence --
// which is theme.py's rule (docs/style.md I2), and these are its own two sets.
var GNOME_DARK = { background: "#1d1d20", surface: "#28282c", foreground: "#ffffff" }
var GNOME_LIGHT = { background: "#fafafa", surface: "#ffffff", foreground: "#2e3436" }

// `dark` defaults true because that is what an app has before it has read
// anything. A light desktop that has never run omarchy-theme-set used to get
// white text on near-black here, which is not a fallback so much as a bug with
// a palette.
function fallback(dark) {
  var light = dark === false
  var base = light ? GNOME_LIGHT : GNOME_DARK
  return {
    accent: "#3584e4",
    background: base.background,
    surface: base.surface,
    raised: base.surface,
    foreground: base.foreground,
    dim: "#9a9996",
    line: mix(base.foreground, base.background, 0.16),
    hues: GNOME,
    dark: !light
  }
}

function fromData(data) {
  // `mode` is read before the bail-out on purpose: a theme can name a mode and
  // still be missing the three colours below, and a light desktop should get
  // the light stand-ins rather than the dark ones.
  var dark = String(data.mode || "dark").toLowerCase() !== "light"
  var accent = pick(data, ["accent", "blue"])
  var background = pick(data, ["background"])
  var foreground = pick(data, ["bright_foreground", "foreground"])
  // Missing any of these leaves half the app themed and half not, which looks
  // worse than not theming it at all -- theme.py:load() says the same.
  if (!(accent && background && foreground)) return fallback(dark)
  var hues = {}
  for (var role in GNOME) {
    hues[role] = pick(data, [role, "bright_" + role]) || GNOME[role]
  }
  var surface = pick(data, ["lighter_background", "selection"]) || background
  var raised = pick(data, ["selection", "lighter_background"]) || background
  var dim = pick(data, ["dark_foreground", "muted"]) || foreground
  return {
    accent: accent,
    background: background,
    surface: surface,
    raised: raised,
    foreground: foreground,
    dim: dim,
    line: mix(foreground, background, 0.16),
    hues: hues,
    dark: dark
  }
}

function parse(text) {
  return fromData(parseToml(text))
}

// What a row on the minimal app drawer draws instead of artwork
// (docs/app-drawer-minimal.md M8-M11).
//
//     import "Glyphs.js" as Glyphs
//     readonly property string glyph: Glyphs.forEntry(entry)
//
// ---------------------------------------------------------------------------
// Why a table and not the app's own icon
// ---------------------------------------------------------------------------
// M8. The app drawer draws artwork, and artwork is what a grid is for: 42px of
// colour you recognise before you have read anything. A list is read rather
// than recognised, and a column of full-colour squares at half that size is a
// column of coloured squares -- so this screen draws one ink, and an ink can
// only come from a font or from a symbolic SVG.
//
// A symbolic SVG was the other candidate and is not used, for a reason that is
// about this phone rather than about taste: the apps here mostly do not ship
// one. Every moarchy screen is a full-colour `icon.svg` of its own, the two web
// apps are upstream's artwork, and Adwaita's symbolic set is generic icons
// rather than app marks. A ladder that tried the symbolic name first would
// find one for three apps in thirty and draw the other twenty-seven from this
// table anyway -- a list in two idioms, which is worse than a list in one.
//
// ---------------------------------------------------------------------------
// Where the codepoints come from
// ---------------------------------------------------------------------------
// M11. Every one is a Material Design Icons name out of Nerd Fonts'
// `glyphnames.json`, checked against the cmap of the font the phone actually
// renders with -- `ttf-jetbrains-mono-nerd`, which is what covers this range
// (moarchy.common/Widgets.js says the same thing about the same font). The
// `md-` name is in the comment beside every entry so the next edit can be
// checked the same way rather than by copying a neighbour, which is how a
// glyph comes to be a paper shredder.
//
// `.pragma library`, so there is one table rather than a copy per delegate,
// and `node scripts/glyph-test.js` can run it without a phone.
.pragma library

// M10. Anything the table below does not answer for. A generic glyph and not
// an empty string: a blank slot in a list of 34 rows reads as a row that
// failed rather than as an app nobody has categorised.
var GENERIC = "󰘔"   // U+F0614  md-application_outline

// M10. Desktop ids whose `Categories` do not say what the app is. Consulted
// before the categories, because an override that lost to the table it exists
// to correct would be an override that does nothing.
//
// Short on purpose. Every entry here is a promise to maintain, and the right
// fix for an app that lands on the wrong glyph is usually its own
// `Categories=` line.
var BY_ID = {
  "org.moarchy.Weather.plugin":  "󰖕",  // U+F0595  md-weather_partly_cloudy     Categories=Utility; and nothing else
  "org.moarchy.Launches.plugin": "󱓟",  // U+F14DF  md-rocket_launch_outline     Astronomy, but it is rocket launches
  "org.moarchy.Habits.plugin":   "󰝖",  // U+F0756  md-format_list_checks        Utility;Office;
  "org.moarchy.Keep.plugin":     "󰎛",  // U+F039B  md-note_outline              Utility;Office;
  "org.moarchy.Device.plugin":   "󰄜",  // U+F011C  md-cellphone                 Monitor, but it is this phone
  "Discord":                     "󰻞",  // U+F0EDE  md-chat_outline              a web app, no Categories at all
  "X":                           "󰖟",  // U+F059F  md-web                       a web app, no Categories at all
}

// M10. Prefix matches, for a whole family of ids that arrives at once.
// Waydroid generates one entry per installed Android app with whatever
// categories the APK declared, and they are not XDG's.
var BY_PREFIX = [
  { prefix: "waydroid.", glyph: "󰀲" }  // U+F0032  md-android           every Android app, whatever it claims
]

// M10. XDG menu categories, MOST SPECIFIC FIRST, and the order carries the
// whole meaning: almost every entry on the phone also claims `Utility`,
// `System` or `Network`, so a Calculator matched against an unordered map is a
// coin flip between a calculator and a wrench. An array and not an object for
// exactly that -- JavaScript object key order is not something to bet a screen
// on.
//
// Case-folded on the way in, because a desktop file is written by hand and
// `AudioVideo` has been spelt `audiovideo` in the wild.
var BY_CATEGORY = [
  ["WebBrowser",        "󰖟"],  // U+F059F  md-web                         a browser
  ["Email",             "󰇰"],  // U+F01F0  md-email_outline               mail
  ["InstantMessaging",  "󰻞"],  // U+F0EDE  md-chat_outline                chat
  ["Chat",              "󰻞"],  // U+F0EDE  md-chat_outline                chat
  ["IRCClient",         "󰻞"],  // U+F0EDE  md-chat_outline                chat
  ["Telephony",         "󰷰"],  // U+F0DF0  md-phone_outline               the dialler
  ["TelephonyTools",    "󰷰"],  // U+F0DF0  md-phone_outline               the dialler
  ["Calendar",          "󰭧"],  // U+F0B67  md-calendar_outline            a calendar
  ["ContactManagement", "󰀓"],  // U+F0013  md-account_outline             contacts
  ["Clock",             "󰅐"],  // U+F0150  md-clock_outline               a clock
  ["Calculator",        "󱖦"],  // U+F15A6  md-calculator_variant_outline  a calculator
  ["FileManager",       "󰉖"],  // U+F0256  md-folder_outline              files
  ["FileTools",         "󰉖"],  // U+F0256  md-folder_outline              files
  ["TextEditor",        "󰲶"],  // U+F0CB6  md-pencil_outline              an editor
  ["TerminalEmulator",  "󰞷"],  // U+F07B7  md-console_line                a terminal
  ["Photography",       "󰵝"],  // U+F0D5D  md-camera_outline              a camera
  ["Maps",              "󰟙"],  // U+F07D9  md-map_marker_outline          maps
  ["Music",             "󰽴"],  // U+F0F74  md-music_note_outline          music
  ["Player",            "󰽴"],  // U+F0F74  md-music_note_outline          music
  ["Audio",             "󰽴"],  // U+F0F74  md-music_note_outline          music
  ["Video",             "󰯜"],  // U+F0BDC  md-video_outline               video
  ["TV",                "󰯜"],  // U+F0BDC  md-video_outline               video
  ["AudioVideo",        "󰯜"],  // U+F0BDC  md-video_outline               video
  ["RasterGraphics",    "󰥶"],  // U+F0976  md-image_outline               pictures
  ["VectorGraphics",    "󰥶"],  // U+F0976  md-image_outline               pictures
  ["Graphics",          "󰥶"],  // U+F0976  md-image_outline               pictures
  ["Game",              "󰺷"],  // U+F0EB7  md-gamepad_variant_outline     a game
  ["IDE",               "󰅩"],  // U+F0169  md-code_braces                 code
  ["Development",       "󰅩"],  // U+F0169  md-code_braces                 code
  ["Astronomy",         "󰭎"],  // U+F0B4E  md-telescope                   the sky
  ["Science",           "󰂖"],  // U+F0096  md-flask_outline               science
  ["Education",         "󱆀"],  // U+F1180  md-school_outline              learning
  ["Finance",           "󰄔"],  // U+F0114  md-cash                        money
  ["Security",          "󰒙"],  // U+F0499  md-shield_outline              security
  ["PackageManager",    "󰏗"],  // U+F03D7  md-package_variant_closed      packages
  ["Archiving",         "󱈎"],  // U+F120E  md-archive_outline             archives
  ["Compression",       "󱈎"],  // U+F120E  md-archive_outline             archives
  ["News",              "󱀄"],  // U+F1004  md-newspaper_variant_outline   news
  ["Feed",              "󱀄"],  // U+F1004  md-newspaper_variant_outline   news
  ["Documentation",     "󰭣"],  // U+F0B63  md-book_open_outline           a book
  ["Literature",        "󰭣"],  // U+F0B63  md-book_open_outline           a book
  ["WordProcessor",     "󰧮"],  // U+F09EE  md-file_document_outline       a document
  ["Spreadsheet",       "󰧮"],  // U+F09EE  md-file_document_outline       a document
  ["Presentation",      "󰧮"],  // U+F09EE  md-file_document_outline       a document
  ["Office",            "󰧮"],  // U+F09EE  md-file_document_outline       a document
  ["Monitor",           "󰍹"],  // U+F0379  md-monitor                     a readout
  ["Settings",          "󰢻"],  // U+F08BB  md-cog_outline                 settings
  ["Network",           "󰅣"],  // U+F0163  md-cloud_outline               the network
  ["System",            "󰢻"],  // U+F08BB  md-cog_outline                 settings
  ["Utility",           "󰯠"],  // U+F0BE0  md-wrench_outline              a tool
]

// The categories a desktop entry declares, as lowercase strings.
//
// Guarded, and not out of habit: `categories` is a `QVector<QString>` on
// Quickshell's DesktopEntry, which reaches JavaScript as something array-like
// rather than as an Array -- and an entry with no Categories line at all is
// every web app on this phone. A throw here would take the whole delegate with
// it, which on a virtualised list is a hole that scrolls.
function categoriesOf(entry) {
  var out = []
  try {
    var raw = entry && entry.categories
    if (!raw) return out
    for (var i = 0; i < raw.length; i++) {
      var c = String(raw[i] || "").toLowerCase().trim()
      if (c) out.push(c)
    }
  } catch (e) {
  }
  return out
}

// M10. The id override, then a prefix, then the categories in table order,
// then the generic. One function, because a delegate asking three questions is
// three places for the order to come apart.
function forEntry(entry) {
  var id = String((entry && entry.id) || "")
  if (BY_ID[id] !== undefined) return BY_ID[id]

  for (var p = 0; p < BY_PREFIX.length; p++)
    if (id.indexOf(BY_PREFIX[p].prefix) === 0) return BY_PREFIX[p].glyph

  var cats = categoriesOf(entry)
  if (cats.length) {
    for (var i = 0; i < BY_CATEGORY.length; i++) {
      var key = BY_CATEGORY[i][0].toLowerCase()
      for (var j = 0; j < cats.length; j++)
        if (cats[j] === key) return BY_CATEGORY[i][1]
    }
  }
  return GENERIC
}

// M12. The rail's letter for a name: its first character, upper-cased, or "#"
// for a name that does not start with a letter. Here rather than in the
// delegate because the rail and the rows have to agree about it, and two
// spellings of "first letter" is how a rail comes to offer a letter the list
// has no row under.
function letterFor(name) {
  var c = String(name || "").trim().charAt(0).toUpperCase()
  return (c >= "A" && c <= "Z") ? c : "#"
}

if (typeof module !== "undefined") {
  module.exports = { GENERIC: GENERIC, BY_ID: BY_ID, BY_PREFIX: BY_PREFIX,
                     BY_CATEGORY: BY_CATEGORY, categoriesOf: categoriesOf,
                     forEntry: forEntry, letterFor: letterFor }
}

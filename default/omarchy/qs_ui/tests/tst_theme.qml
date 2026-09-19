// The palette, against the same rules shared/moarchy_ui/theme.py follows.
//
// Two readers of one colors.toml disagreeing is the bug this directory exists
// to stop, so the cases below are the ones theme.py's own tests cover: what a
// good file yields, what a half-written one yields, and what happens when
// there is no file at all.
//
// Run by qmltestrunner rather than by node, which was the first attempt: these
// modules are `.pragma library` JavaScript and node's parser stops at the
// leading dot, so it needs the directive stripped -- and a stripped file is a
// small lie about the file under test, run on a different engine. QtTest
// imports this one verbatim, on the V4 the phone runs.
import QtQuick
import QtTest
import "../Theme.js" as Theme

TestCase {
  name: "Theme"

  readonly property string full: "
mode = \"dark\"
background = \"#11121a\"
foreground = \"#c8d3f5\"
bright_foreground = \"#ffffff\"
accent = \"#82aaff\"
lighter_background = \"#1e2030\"
selection = \"#2d3f76\"
dark_foreground = \"#828bb8\"
red = \"#ff757f\"
"

  function test_a_full_theme_is_read_not_approximated() {
    var p = Theme.parse(full)
    compare(p.accent, "#82aaff")
    compare(p.background, "#11121a")
    // bright_foreground wins over foreground, as in theme.py's _colour order.
    compare(p.foreground, "#ffffff")
    compare(p.surface, "#1e2030")
    compare(p.raised, "#2d3f76")
    compare(p.dim, "#828bb8")
    compare(p.hues.red, "#ff757f")
    // Not named in the file, so GNOME's own stands in.
    compare(p.hues.green, "#33d17a")
    compare(p.dark, true)
  }

  function test_no_file_at_all_is_the_dark_fallback() {
    var p = Theme.parse("")
    compare(p.background, "#1d1d20")
    compare(p.foreground, "#ffffff")
    compare(p.dark, true)
  }

  function test_a_light_theme_missing_its_colours_falls_back_light() {
    // The regression this test exists for: fallback() was dark-only, so a
    // light desktop with a malformed colors.toml got white on near-black.
    var p = Theme.parse("mode = \"light\"\n")
    compare(p.background, "#fafafa")
    compare(p.surface, "#ffffff")
    compare(p.foreground, "#2e3436")
    compare(p.dark, false)
    // And the line is drawn against the light ground, not the dark one.
    compare(p.line, Theme.mix("#2e3436", "#fafafa", 0.16))
  }

  function test_mode_decides_dark_and_nothing_else_does() {
    compare(Theme.parse(full.replace("mode = \"dark\"", "mode = \"light\"")).dark, false)
    // A theme that names no mode is dark, which is theme.py's default too.
    compare(Theme.parse(full.replace("mode = \"dark\"", "")).dark, true)
  }

  function test_a_value_that_is_not_a_colour_is_not_a_colour() {
    // theme.py validates every value against a hex regex before it reaches a
    // stylesheet: a theme is data, not code.
    var p = Theme.parse("accent = \"red; }\"\nbackground = \"#000000\"\nforeground = \"#ffffff\"\n")
    compare(p.accent, "#3584e4")
  }

  function test_three_digit_hex_is_expanded() {
    var p = Theme.parse("accent = \"#abc\"\nbackground = \"#000\"\nforeground = \"#fff\"\n")
    compare(p.accent, "#aabbcc")
    compare(p.background, "#000000")
  }

  function test_comments_and_quotes_stripped_sections_ignored() {
    var p = Theme.parse("[colors]\naccent = \"#82aaff\"  # the blue\nbackground = \"#000000\"\nforeground = \"#ffffff\"\n")
    compare(p.accent, "#82aaff")
  }

  function test_alpha_is_the_same_call_qs_commons_makes() {
    // Qt.rgba is real here, not a stub -- which is half the reason this runs
    // under QtTest rather than under a shim.
    var c = Theme.alpha(Qt.rgba(1, 0, 0, 1), 0.5)
    compare(c.a, 0.5)
    compare(c.r, 1)
  }

  // --- the elevation ramp ----------------------------------------------

  function test_a_box_is_the_theme_ink_mixed_into_the_theme_background() {
    var p = Theme.parse(full)
    compare(Theme.surface(p, "card"), Theme.mix(p.foreground, p.background, 0.07))
    compare(Theme.surface(p, "raised"), Theme.mix(p.foreground, p.background, 0.12))
  }

  function test_the_ramp_only_ever_goes_up() {
    var p = Theme.parse(full)
    var names = ["well", "card", "raised", "pressed", "edge"]
    var last = Theme.shade(p.background)
    for (var i = 0; i < names.length; i++) {
      var here = Theme.shade(Theme.surface(p, names[i]))
      verify(here > last, names[i] + " is not a step up from " + names[i - 1])
      last = here
    }
  }

  function test_an_unknown_level_is_an_ordinary_box_rather_than_nothing() {
    var p = Theme.parse(full)
    compare(Theme.surface(p, "nonsense"), Theme.surface(p, "card"))
  }

  // A light theme has to get a *darker* box, or the ramp reads as fog rather
  // than as depth. It falls out of mixing the foreground in, and this is the
  // assertion that stops anyone replacing that with white at an alpha.
  function test_a_light_theme_boxes_downwards() {
    var light = Theme.fallback(false)
    verify(Theme.shade(Theme.surface(light, "card")) < Theme.shade(light.background))
    verify(Theme.shade(Theme.surface(light, "raised"))
           < Theme.shade(Theme.surface(light, "card")))
  }

  function test_ink_on_a_fill_is_whichever_of_the_two_is_further_from_it() {
    var dark = Theme.fallback(true)
    // Near-black accent on a dark theme: the foreground is the readable one.
    compare(Theme.inkOn(dark, "#101010"), dark.foreground)
    compare(Theme.inkOn(dark, "#f3f3f3"), dark.background)
    var light = Theme.fallback(false)
    compare(Theme.inkOn(light, "#f5c211"), light.foreground)
  }

  function test_a_tint_keeps_the_hue_and_the_ramp() {
    var p = Theme.parse(full)
    compare(Theme.tint(p, p.hues.red, "card"), Theme.mix(p.hues.red, p.background, 0.20))
    verify(Theme.shade(Theme.tint(p, p.hues.red, "pressed"))
           > Theme.shade(Theme.tint(p, p.hues.red, "card")))
  }
}

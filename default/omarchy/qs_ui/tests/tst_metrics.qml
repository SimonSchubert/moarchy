// The spacing scale, off the shell.
//
// Nothing here can test the *in-shell* answer -- that needs omarchy-shell on
// the import path -- so what is pinned is the half that has to be right
// everywhere else: with no shell to ask, an app gets the numbers it was
// written with, and a gap never scales away to nothing.
import QtQuick
import QtTest
import "../Metrics.js" as Metrics
import "../Ui.js" as Ui

TestCase {
  name: "Metrics"

  function test_off_the_shell_px_is_px() {
    compare(Metrics.space(10, null), 10)
    compare(Metrics.space(12, null), 12)
    compare(Metrics.space(40, null), 40)
  }

  function test_a_gap_never_scales_away_to_nothing() {
    // Style.space floors at 1 for the same reason: a separator that rounds to
    // zero is a layout that has quietly lost it.
    compare(Metrics.space(0.2, null), 1)
    compare(Metrics.space(0, null), 0)
    compare(Metrics.space(-4, null), 0)
  }

  function test_the_type_ladder_is_ratios_of_the_body() {
    compare(Metrics.typeSize(16, "body"), 16)
    compare(Metrics.typeSize(16, "title"), 22)
    compare(Metrics.typeSize(16, "subtitle"), 18)
    compare(Metrics.typeSize(16, "caption"), 14)
    compare(Metrics.typeSize(16, "overline"), 12)
    // An unknown role is the body rather than nothing.
    compare(Metrics.typeSize(16, "nonsense"), 16)
  }

  function test_body_falls_back_when_there_is_no_shell_to_ask() {
    compare(Metrics.shellBody(null), Metrics.BODY)
  }

  // The rule the whole shape scale exists for: a box inset inside another box
  // keeps the two curves concentric only if the inner radius is the outer one
  // less the inset. The two steps below are the ones every screen draws --
  // a group holding rows, and a row holding a chip.
  function test_a_nested_box_is_the_outer_radius_less_the_inset() {
    compare(Metrics.inner(Metrics.RADIUS_LG, Metrics.GROUP_PAD), Metrics.RADIUS_MD)
    compare(Metrics.inner(Metrics.RADIUS_MD, Metrics.GROUP_PAD), Metrics.RADIUS_SM)
    compare(Metrics.inner(20, 4), 16)
  }

  function test_a_nested_corner_never_rounds_away_to_a_square_one() {
    // 20 less 18 is 2, and a 2px corner reads as a mistake rather than as a
    // decision, so the floor is the smallest radius on the scale.
    compare(Metrics.inner(20, 18), Metrics.RADIUS_XS)
    compare(Metrics.inner(20, 40), Metrics.RADIUS_XS)
  }

  function test_a_nested_box_is_never_rounder_than_its_parent() {
    // Modest corners put a card at 6, and the XS floor is 6: without the cap a
    // row inside a 3px box would come out at 6.
    compare(Metrics.inner(3, 12), 3)
    compare(Metrics.inner(8, 6), Metrics.RADIUS_XS)
  }

  function test_no_inset_leaves_the_radius_alone() {
    compare(Metrics.inner(14, 0), 14)
    compare(Metrics.inner(14, -3), 14)
    compare(Metrics.inner(0, 6), 0)
  }

  // The clip rectangle a ListFrame insets by GROUP_PAD has to sit *inside* the
  // arc of the group's own corner, or a row scrolling past the top pokes out
  // of it. It does, but only just, so it is pinned.
  function test_a_group_clips_inside_its_own_corner() {
    var r = Metrics.RADIUS_LG
    var p = Metrics.GROUP_PAD
    var dx = r - p
    verify(Math.sqrt(dx * dx + dx * dx) < r)
  }

  // --- corners, from ui.toml ---------------------------------------------
  //
  // What the three presets make of the scale. `Ui.fallback()` is the missing
  // file, which has to be the scale exactly as it was drawn -- every app was
  // designed at large, and a missing ui.toml is not a request to change it.

  function colours(corners) {
    return Metrics.shaped({ accent: "#3584e4" }, Ui.parse('corners = "' + corners + '"'))
  }

  function test_no_ui_toml_is_the_scale_as_drawn() {
    var c = Metrics.shaped({ accent: "#3584e4" }, Ui.fallback())
    compare(Metrics.radius(c, Metrics.RADIUS_LG), Metrics.RADIUS_LG)
    compare(Metrics.radius(c, Metrics.CARD_RADIUS), Metrics.CARD_RADIUS)
    compare(Metrics.round(c, 50), 25)
    compare(Metrics.round(c, 5), 2.5)
  }

  function test_no_colours_is_the_scale_as_drawn() {
    // A kit control nobody handed `colours` to must not change shape.
    compare(Metrics.radius(null, Metrics.RADIUS_MD), Metrics.RADIUS_MD)
    compare(Metrics.radius({ accent: "#fff" }, Metrics.RADIUS_MD), Metrics.RADIUS_MD)
    compare(Metrics.round(null, 40), 20)
  }

  function test_square_is_square() {
    var c = colours("square")
    compare(Metrics.radius(c, Metrics.RADIUS_LG), 0)
    compare(Metrics.radius(c, Metrics.RADIUS_XXS), 0)
    compare(Metrics.round(c, 56), 0)
    compare(Metrics.round(c, 5), 0)
    compare(Metrics.inner(Metrics.radius(c, Metrics.RADIUS_LG), Metrics.GROUP_PAD), 0)
  }

  function test_modest_is_the_shell_modest() {
    // The shell's modest is tile 8 and card 6. The app scale lands on the same
    // two numbers: a group is a tile, a card is a card.
    var c = colours("modest")
    compare(Metrics.radius(c, Metrics.RADIUS_LG), 8)
    compare(Metrics.radius(c, Metrics.RADIUS_MD), 6)
    // A capsule is a box with the tile's corner, and a dot stays a dot.
    compare(Metrics.round(c, 50), 8)
    compare(Metrics.round(c, 5), 2.5)
  }

  function test_the_aliases_the_shell_accepts_reach_the_apps() {
    compare(Metrics.radius(colours("none"), Metrics.RADIUS_LG), 0)
    compare(Metrics.radius(colours("small"), Metrics.RADIUS_LG), 8)
    compare(Metrics.radius(colours("rounded"), Metrics.RADIUS_LG), Metrics.RADIUS_LG)
    compare(Metrics.radius(colours("nonsense"), Metrics.RADIUS_LG), Metrics.RADIUS_LG)
  }

  function test_a_tile_override_moves_the_apps_with_it() {
    var c = Metrics.shaped({}, Ui.parse('corners = "large"\ntile = 10'))
    compare(Metrics.radius(c, Metrics.RADIUS_LG), 10)
    compare(Metrics.round(c, 50), 10)
  }

  function test_the_shape_does_not_touch_the_palette() {
    var palette = { accent: "#3584e4", hues: { red: "#e01b24" } }
    var c = Metrics.shaped(palette, Ui.parse('corners = "square"'))
    compare(c.accent, "#3584e4")
    compare(c.hues.red, "#e01b24")
    compare(c.shape.corners, "square")
    verify(palette.shape === undefined)
  }
}

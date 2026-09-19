// The two things every plugin does identically.
import QtQuick
import QtTest
import "../Plugin.js" as Plugin

TestCase {
  name: "Plugin"

  function test_xdg_wins_when_it_is_set() {
    compare(Plugin.dataDir("keep", "/home/moarchy", "/data", ""), "/data/moarchy-keep")
  }

  function test_home_is_the_fallback() {
    compare(Plugin.dataDir("coins", "/home/moarchy", "", ""),
            "/home/moarchy/.local/share/moarchy-coins")
    compare(Plugin.dataDir("coins", "/home/moarchy", null, null),
            "/home/moarchy/.local/share/moarchy-coins")
  }

  function test_the_harness_override_beats_both() {
    // A screenshot run points at a fixture without touching anybody's notes.
    compare(Plugin.dataDir("habits", "/home/moarchy", "/data", "/tmp/fixture"), "/tmp/fixture")
  }

  function test_the_four_overlays_are_the_ones_that_cover_the_screen() {
    // The shell's own Sheet.js list, read from this side of the repo boundary.
    // A sheet added there and not here is a sheet left standing over a window
    // that has just opened.
    compare(Plugin.OVERLAYS.join(","),
            "moarchy.shade,moarchy.drawer,moarchy.overview,moarchy.themes")
  }

  function test_hiding_is_a_no_op_off_the_shell() {
    // `shell` is null on a plain Quickshell and there is nothing to hide.
    Plugin.hideOverlays(null)
    Plugin.hideOverlays(({}))
    verify(true)
  }

  function test_only_what_is_open_is_hidden() {
    var asked = [], hidden = []
    var shell = {
      isPluginOpen: function (id) { asked.push(id); return id === "moarchy.drawer" },
      hide: function (id) { hidden.push(id) }
    }
    Plugin.hideOverlays(shell)
    compare(asked.join(","),
            "moarchy.shade,moarchy.drawer,moarchy.overview,moarchy.themes")
    compare(hidden.join(","), "moarchy.drawer")
  }
}

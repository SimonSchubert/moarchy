// The minefield and the rules, against apps/minesweeper/moarchy_minesweeper.
//
// The mine lists below came out of Python. They are the whole point of porting
// the Mersenne Twister: a saved game is a seed and a list of taps, so if these
// differ by one cell then a game started in the GTK app and resumed here is a
// different board with the flags in the wrong places.
import QtQuick
import QtTest
import "../Minesweeper.js" as M

TestCase {
  name: "Minesweeper"

  function mineList(game) {
    var out = []
    for (var k in game.mines) out.push(parseInt(k, 10))
    out.sort(function (a, b) { return a - b })
    return out
  }

  function test_the_levels_are_shaped_for_a_phone() {
    // Taller than wide, unlike the classic three -- 30x16 is twice as wide as
    // a phone screen.
    for (var i = 0; i < M.LEVELS.length; i++)
      verify(M.LEVELS[i].height > M.LEVELS[i].width)
    compare(M.levelFor("standard").width, 10)
    compare(M.levelFor("standard").mines, 22)
    compare(M.levelFor("nonsense").key, "standard")
  }

  function test_the_minefield_is_pythons_minefield() {
    var level = M.levelFor("standard")
    var mines = M.place(level, 12345, 60)
    var got = []
    for (var k in mines) got.push(parseInt(k, 10))
    got.sort(function (a, b) { return a - b })
    compare(got.join(","),
      "7,12,21,24,26,27,28,32,43,47,48,54,62,64,76,81,93,94,113,116,120,128")
    compare(got.length, level.mines)
  }

  function test_a_second_level_and_seed_agree_too() {
    var mines = M.place(M.levelFor("gentle"), 7, 44)
    var got = []
    for (var k in mines) got.push(parseInt(k, 10))
    got.sort(function (a, b) { return a - b })
    compare(got.join(","), "1,11,15,29,54,67,69,72,73,79")
  }

  function test_the_first_tap_is_always_safe_and_opens_a_space() {
    // The tapped cell and all eight around it are excluded, so the first tap
    // cannot be a mine and always floods.
    var g = M.create(M.levelFor("standard"), 12345, [])
    compare(M.started(g), false)
    verify(M.tap(g, 60))
    compare(M.lost(g), false)
    compare(M.neighbourCount(g, 60), 0)
    compare(M.openedCount(g), 10)
  }

  function test_the_neighbourhood_is_eight_cells_and_fewer_at_an_edge() {
    compare(M.around(0, 10, 13).length, 3)
    compare(M.around(9, 10, 13).length, 3)
    compare(M.around(11, 10, 13).length, 8)
    compare(M.around(129, 10, 13).length, 3)
  }

  function test_a_flag_stops_the_tap_it_is_there_to_stop() {
    var g = M.create(M.levelFor("standard"), 12345, [])
    M.tap(g, 60)
    var mine = mineList(g)[0]
    verify(M.mark(g, mine))
    compare(M.flagCount(g), 1)
    // Not a convenience: the flag exists precisely to stop this tap.
    compare(M.tap(g, mine), false)
    compare(M.lost(g), false)
  }

  function test_a_flag_latches_and_unlatches() {
    var g = M.create(M.levelFor("gentle"), 7, [])
    M.tap(g, 44)
    verify(M.mark(g, 0))
    compare(M.remaining(g), 9)
    verify(M.mark(g, 0))
    compare(M.flagCount(g), 0)
    compare(M.remaining(g), 10)
  }

  function test_remaining_may_go_negative_and_says_so() {
    // Clamping it at zero would hide the most useful thing it ever says.
    var g = M.create(M.levelFor("gentle"), 7, [])
    M.tap(g, 44)
    var n = 0
    for (var c = 0; c < 80 && n < 12; c++) if (M.mark(g, c)) n += 1
    verify(M.remaining(g) < 0)
  }

  function test_stepping_on_a_mine_ends_it() {
    var g = M.create(M.levelFor("standard"), 12345, [])
    M.tap(g, 60)
    var mine = mineList(g)[0]
    verify(M.tap(g, mine))
    compare(M.lost(g), true)
    compare(M.boomOf(g), mine)
    compare(M.isOver(g), true)
    // Nothing moves after the end.
    compare(M.tap(g, 0), false)
  }

  function test_a_chord_refuses_when_the_flags_do_not_add_up() {
    // Not politeness: the difference between a move and a gamble, and a gamble
    // that ends the game is not something a thumb should do by resting on a
    // number.
    var g = M.create(M.levelFor("standard"), 12345, [])
    M.tap(g, 60)
    // Find an opened cell with a number on it.
    var numbered = -1
    for (var k in g.opened) {
      var c = parseInt(k, 10)
      if (M.neighbourCount(g, c) > 0) { numbered = c; break }
    }
    verify(numbered >= 0)
    compare(M.clearAround(g, numbered), false)
  }

  function test_a_chord_on_a_blank_does_nothing() {
    var g = M.create(M.levelFor("standard"), 12345, [])
    M.tap(g, 60)
    compare(M.clearAround(g, 60), false)
  }

  function test_the_move_list_replays_to_the_same_board() {
    // The file stores the seed and the taps; this is what makes that safe.
    var a = M.create(M.levelFor("standard"), 12345, [])
    M.tap(a, 60)
    M.mark(a, 7)
    M.tap(a, 99)
    var replayed = M.create(M.levelFor("standard"), 12345, a.moves)
    compare(M.openedCount(replayed), M.openedCount(a))
    compare(M.flagCount(replayed), M.flagCount(a))
    compare(mineList(replayed).join(","), mineList(a).join(","))
    compare(M.lost(replayed), M.lost(a))
  }

  function test_a_move_encodes_a_cell_and_an_action() {
    compare(M.encode(41, M.FLAG), 41 * 3 + 1)
    var d = M.decode(M.encode(41, M.CHORD))
    compare(d.cell, 41)
    compare(d.action, M.CHORD)
  }

  function test_a_nonsense_move_in_a_file_is_refused_not_fatal() {
    var g = M.create(M.levelFor("gentle"), 7, [])
    compare(M.applyMove(g, -5), false)
    compare(M.applyMove(g, 99999), false)
    compare(g.moves.length, 0)
  }

  function test_winning_is_every_safe_cell_opened() {
    var level = M.levelFor("gentle")
    var g = M.create(level, 7, [])
    M.tap(g, 44)
    var mines = mineList(g)
    for (var c = 0; c < M.cellCount(level); c++) {
      if (mines.indexOf(c) >= 0) continue
      M.tap(g, c)
    }
    compare(M.won(g), true)
    compare(M.lost(g), false)
    compare(M.openedCount(g), M.cellCount(level) - level.mines)
  }
}

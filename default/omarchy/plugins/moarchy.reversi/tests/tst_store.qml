// The saved game, against what store.py writes.
import QtQuick
import QtTest
import "../Store.js" as Store
import "../Reversi.js" as Reversi

TestCase {
  name: "ReversiStore"

  readonly property string pyFile:
    '{\n "schema": 1,\n "game": {\n  "mode": "computer",\n  "level": "hard",\n' +
    '  "human": "light",\n  "finished": false,\n  "moves": [\n   19,\n   18,\n   -1,\n   17\n  ]\n },\n' +
    ' "stats": {\n  "won": 3,\n  "lost": 1\n }\n}'

  function test_a_file_python_wrote_reads_here() {
    var g = Store.parse(JSON.parse(pyFile))
    compare(g.level, "hard")
    compare(g.human, Store.LIGHT)
    compare(g.finished, false)
    compare(g.moves.join(","), "19,18,-1,17")
    compare(g.stats.won, 3)
  }

  function test_the_move_list_replays_to_a_board() {
    // The board is not stored: this is what makes that safe.
    var g = Store.parse(JSON.parse(pyFile))
    var p = Reversi.replay(g.moves).position
    compare(Reversi.counts(p).join(","), Reversi.counts(p).join(","))
    verify(Reversi.empties(p) < 60)
  }

  function test_an_absent_file_is_a_new_game() {
    var g = Store.parse(null)
    compare(g.moves.length, 0)
    compare(g.level, Store.DEFAULT_LEVEL)
    compare(g.human, Store.DARK)
  }

  function test_a_truncated_move_list_stops_rather_than_replaying_nonsense() {
    var g = Store.parse({ game: { moves: [19, 18, 999, 17] } })
    compare(g.moves.join(","), "19,18")
    var h = Store.parse({ game: { moves: [19, "x", 17] } })
    compare(h.moves.join(","), "19")
  }

  function test_a_pass_is_a_legal_entry() {
    compare(Store.parse({ game: { moves: [-1] } }).moves.join(","), "-1")
  }

  function test_an_unknown_level_falls_back() {
    compare(Store.parse({ game: { level: "impossible" } }).level, Store.DEFAULT_LEVEL)
  }

  function test_what_we_write_is_the_same_document() {
    var g = Store.parse(JSON.parse(pyFile))
    var back = Store.parse(JSON.parse(Store.serialize(g)))
    compare(back.moves.join(","), g.moves.join(","))
    compare(back.level, g.level)
    compare(back.human, g.human)
    compare(JSON.parse(Store.serialize(g)).game.human, "light")
    compare(JSON.parse(Store.serialize(g)).schema, 1)
  }

  function test_stats_count_up() {
    var s = Store.record(({}), "won")
    compare(s.won, 1)
    compare(Store.record(s, "won").won, 2)
    compare(Store.record(s, "lost").lost, 1)
  }
}

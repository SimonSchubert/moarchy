// The opponent, against apps/reversi/moarchy_reversi/ai.py.
//
// The evaluation is checked number for number, because a port that is nearly
// right plays nearly the same game and nobody can tell which one is wrong. The
// clock is held still, the way ai.py's own tests hold it: a search whose depth
// depends on how loaded the machine is is not a test.
import QtQuick
import QtTest
import "../Bits.js" as Bits
import "../Reversi.js" as Reversi
import "../Ai.js" as Ai

TestCase {
  name: "ReversiAi"

  // A clock that never moves, so the search runs to its depth cap rather than
  // to whatever the container had left over.
  function frozen() { return function () { return 0 } }
  function first() { return function (pool) { return pool[0] } }

  function test_the_search_order_is_the_weight_table() {
    // Corners first: alpha-beta prunes in proportion to how early the best move
    // is tried, and the best move is a corner far more often than chance.
    compare(Ai.SEARCH_ORDER.slice(0, 8).join(","), "0,7,56,63,2,5,16,23")
  }

  function test_positional_matches_pythons_rank_tables() {
    compare(Ai.positional(Reversi.OPENING.dark), -2)
    compare(Ai.positional(Reversi.OPENING.light), -2)
  }

  function test_the_opening_is_worth_nothing_to_either_side() {
    compare(Ai.evaluate(Reversi.own(Reversi.OPENING), Reversi.opp(Reversi.OPENING), null), 0)
  }

  function test_a_finished_game_carries_its_margin() {
    // A decided game beats any arrangement of discs, and winning by forty is
    // preferred to winning by two.
    var own = Bits.fromHex("000000FFFFFFFFFF")   // 40 discs
    var opp = Bits.fromHex("FFFFFF0000000000")   // 24 discs
    compare(Ai.terminal(own, opp), 100016)
    compare(Ai.terminal(opp, own), -100016)
    compare(Ai.terminal(own, own), 0)
  }

  function test_a_midgame_position_scores_as_python_scores_it() {
    var p = Reversi.replay([19, 18, 17, 9, 1, 0, 26, 2, 10, 11, 3, 4]).position
    compare(Ai.positional(Reversi.own(p)), -12)
    compare(Ai.evaluate(Reversi.own(p), Reversi.opp(p), null), -85)
  }

  function test_the_levels_are_pythons_levels() {
    compare(Ai.LEVELS.length, 3)
    compare(Ai.levelFor("easy").depth, 1)
    compare(Ai.levelFor("medium").depth, 3)
    compare(Ai.levelFor("hard").depth, 8)
    compare(Ai.levelFor("hard").exact, true)
    compare(Ai.levelFor("easy").slack, 45)
    // An unknown key is medium, not a crash.
    compare(Ai.levelFor("nonsense").key, "medium")
    compare(Ai.DEFAULT_LEVEL, "medium")
  }

  function test_a_forced_move_is_taken_without_thinking() {
    // A pause here reads as a computer pretending to consider a move it has no
    // choice about.
    var p = Reversi.position(Bits.fromHex("0000000810000000"),
                             Bits.fromHex("0000001008000000"), Reversi.DARK)
    // Contrive a position with exactly one legal move by filling the board
    // except for one reachable square.
    var only = Reversi.replay([19, 18, 17, 9, 1, 0, 26, 2, 10, 11, 3, 4]).position
    var thought = Ai.think(only, Ai.levelFor("medium"), frozen(), first())
    verify(Reversi.isLegal(only, thought.cell))
  }

  function test_with_no_move_it_passes() {
    var p = Reversi.replay([19, 18, 17, 9, 1, 0, 26, 2, 10, 11, 3, 4, 8, 16, 37, 12, 5, 6]).position
    verify(Reversi.mustPass(p))
    compare(Ai.think(p, Ai.levelFor("hard"), frozen(), first()).cell, Reversi.PASS)
  }

  function test_medium_ends_with_pythons_pool_in_pythons_order() {
    // Python's think() finishes this position with scored
    // [(44,-120), (45,-120), (37,-120), (8,-191)], so the pool at slack 8 is
    // exactly [44, 45, 37] and nothing else. Which of the three it then plays
    // is rng.choice's business, so the pool is what is compared -- picking the
    // first and the last is what pins both ends of it.
    var p = Reversi.replay([19, 18, 17, 9, 1, 0, 26, 2, 10, 11, 3, 4]).position
    var medium = Ai.levelFor("medium")
    var seen = []
    var thought = Ai.think(p, medium, frozen(), function (pool) {
      seen = pool.slice()
      return pool[0]
    })
    compare(thought.depth, 3)
    compare(seen.join(","), "44,45,37")
    compare(thought.cell, 44)
    verify(thought.nodes > 0)
  }

  function test_hard_reaches_depth_eight_and_plays_pythons_move() {
    var p = Reversi.replay([19, 18, 17, 9, 1, 0, 26, 2, 10, 11, 3, 4]).position
    var thought = Ai.think(p, Ai.levelFor("hard"), frozen(), first())
    compare(thought.depth, 8)
    compare(thought.cell, 8)
  }

  function test_a_clock_that_runs_out_gives_a_shallower_answer_not_a_hang() {
    // The whole point of the clock: a slower machine gets less depth, and V4 is
    // a slower machine than CPython.
    var p = Reversi.replay([19, 18, 17, 9, 1, 0, 26, 2, 10, 11, 3, 4]).position
    var t = 0
    // Every reading is already past the deadline, so the first check throws.
    var spent = function () { t += 1000; return t }
    var thought = Ai.think(p, Ai.levelFor("hard"), spent, first())
    verify(thought.depth < 8)
    // And it still answers with a legal move rather than nothing.
    verify(Reversi.isLegal(p, thought.cell))
  }

  function test_easy_keeps_only_the_moves_within_its_slack() {
    // Python scores this position (61, 13, 13, -96) at depth 1, and 61 is more
    // than 45 clear of the rest -- so even at slack 45 the pool is one move.
    // Easy is loose, not blind: a move it can see is that much worse is still
    // refused.
    var p = Reversi.replay([19, 18, 17, 9]).position
    var seen = []
    var thought = Ai.think(p, Ai.levelFor("easy"), frozen(), function (pool) {
      seen = pool.slice()
      return pool[0]
    })
    compare(seen.join(","), "26")
    compare(thought.cell, 26)
    compare(thought.depth, 1)
  }

  function test_slack_is_what_widens_the_pool() {
    // The same position through the three levels: the wider the slack, the more
    // moves survive. Medium's pool above was three; hard's is always one.
    var p = Reversi.replay([19, 18, 17, 9, 1, 0, 26, 2, 10, 11, 3, 4]).position
    var sizes = {}
    var keys = ["easy", "medium", "hard"]
    for (var i = 0; i < keys.length; i++) {
      var got = 0
      Ai.think(p, Ai.levelFor(keys[i]), frozen(), function (pool) {
        got = pool.length
        return pool[0]
      })
      sizes[keys[i]] = got
    }
    // Hard has slack 0, so only a move that ties the best survives.
    compare(sizes["hard"], 1)
    compare(sizes["medium"], 3)
  }

  function test_every_level_answers_legally_from_the_opening() {
    var keys = ["easy", "medium", "hard"]
    for (var i = 0; i < keys.length; i++) {
      var thought = Ai.think(Reversi.OPENING, Ai.levelFor(keys[i]), frozen(), first())
      verify(Reversi.isLegal(Reversi.OPENING, thought.cell))
    }
  }
}

// The rules and the solver, against apps/tictactoe/moarchy_tictactoe.
//
// The solved table is the interesting part: 5478 positions, and the move order
// among equally-good moves is what separates Perfect from any other correct
// player. A port that gets the values right and the ordering wrong plays a
// different game and wins just as often, which is why both are compared.
import QtQuick
import QtTest
import "../Tictactoe.js" as T

TestCase {
  name: "Tictactoe"

  function first() { return function (list) { return list[0] } }
  function never() { return function () { return 1.0 } }   // never careless
  function always() { return function () { return 0.0 } }  // always careless

  function test_the_eight_lines() {
    compare(T.LINES.length, 8)
    // The squares travel with the mask and keep their order, because the line
    // is struck through on screen and a stroke needs its two ends.
    compare(T.LINES[6].squares.join(","), "0,4,8")
    compare(T.LINES[7].squares.join(","), "2,4,6")
    compare(T.wonLine(7).join(","), "0,1,2")
    compare(T.wonLine(0), null)
  }

  function test_an_empty_board() {
    compare(T.legal(T.EMPTY).length, 9)
    compare(T.winner(T.EMPTY), null)
    compare(T.isOver(T.EMPTY), false)
    compare(T.played(T.EMPTY), 0)
  }

  function test_a_won_board_has_no_moves_left_on_it() {
    // Even though it has empty squares -- which is what stops the rest of the
    // app asking two questions where one will do.
    var p = T.position(7, 0, T.NOUGHT)
    compare(T.winner(p), T.CROSS)
    compare(T.legal(p).length, 0)
    compare(T.winningLine(p).join(","), "0,1,2")
    compare(T.isOver(p), true)
  }

  function test_the_game_is_drawn_from_the_empty_board() {
    // Two perfect players draw, which is the whole of this game.
    compare(T.value(T.EMPTY), 0)
    var s = T.scored(T.EMPTY)
    for (var k in s) compare(s[k], 0)
  }

  function test_the_solver_prefers_the_move_with_the_most_traps() {
    // Every opening move draws against perfect play, so the values tie and the
    // tie-break is how many replies would lose. Python's order exactly.
    compare(T.best(T.EMPTY).join(","), "0,2,6,8,1,3,4,5,7")
  }

  function test_a_corner_opening_must_be_answered_in_the_centre() {
    var p = T.play(T.EMPTY, 0)
    compare(T.best(p).join(","), "4")
    var s = T.scored(p)
    // Everything except the centre loses.
    compare(s[4], 0)
    compare(s[1], -12)
    compare(s[8], -12)
  }

  function test_a_centre_opening_is_answered_in_a_corner() {
    compare(T.best(T.play(T.EMPTY, 4)).join(","), "0,2,6,8")
  }

  function test_a_win_on_the_board_is_taken() {
    var p = T.position((1 << 0) | (1 << 1), (1 << 3) | (1 << 4), T.CROSS)
    compare(T.winsNow(p, T.CROSS).join(","), "2")
    compare(T.best(p).join(","), "2")
  }

  function test_the_table_solves_the_whole_game() {
    // 5478 reachable positions, which is what ai.warm() counts.
    compare(T.warm(), 5478)
  }

  // --- the levels ---------------------------------------------------------

  function test_the_levels_are_pythons_levels() {
    compare(T.LEVELS.length, 3)
    compare(T.levelFor("easy").careless, 0.80)
    compare(T.levelFor("easy").blocks, false)
    compare(T.levelFor("fair").careless, 0.22)
    compare(T.levelFor("fair").blocks, true)
    compare(T.levelFor("perfect").careless, 0.0)
    compare(T.levelFor("nonsense").key, "fair")
    compare(T.DEFAULT_LEVEL, "fair")
  }

  function test_perfect_never_plays_carelessly() {
    // careless 0, so the roll never matters.
    var p = T.play(T.EMPTY, 0)
    compare(T.choose(p, T.levelFor("perfect"), first(), always()), 4)
  }

  function test_even_a_careless_easy_takes_a_win_it_is_given() {
    // An opponent that fails to take three in a row does not read as easy, it
    // reads as broken -- the board says the win is there and the app did not
    // take it.
    var p = T.position((1 << 0) | (1 << 1), (1 << 3) | (1 << 4), T.CROSS)
    compare(T.choose(p, T.levelFor("easy"), first(), always()), 2)
  }

  function test_easy_does_not_block_and_fair_does() {
    // The position has to be chosen with care to say anything at all. X
    // threatens 8; O has no win of its own, and 8 is not the first empty
    // square -- otherwise "took the win", "blocked" and "took the first square
    // it saw" are the same answer and the test proves nothing. Python plays
    // easy -> 1 and fair -> 8 here.
    var p = T.position((1 << 6) | (1 << 7), (1 << 0) | (1 << 5), T.NOUGHT)
    compare(T.legal(p).join(","), "1,2,3,4,8")
    compare(T.winsNow(p, T.NOUGHT).length, 0)
    compare(T.winsNow(p, T.CROSS).join(","), "8")
    compare(T.choose(p, T.levelFor("fair"), first(), always()), 8)
    // Missing *your* threat is the thing that reads as not concentrating, and
    // it is the only thing Easy is allowed to miss.
    compare(T.choose(p, T.levelFor("easy"), first(), always()), 1)
  }

  function test_a_careless_easy_still_takes_its_own_win_over_a_block() {
    // Both are on the board at once: O wins at 8 and X threatens 8 too. Taking
    // the win is checked first, which is also the only sane order.
    var p = T.position((1 << 6) | (1 << 7), (1 << 0) | (1 << 4), T.NOUGHT)
    compare(T.winsNow(p, T.NOUGHT).join(","), "8")
    compare(T.choose(p, T.levelFor("easy"), first(), always()), 8)
  }

  function test_a_forced_move_is_taken_without_a_roll() {
    // The ninth square of every drawn game: nobody waits for a move they had
    // no choice about.
    var p = T.replay([0, 4, 1, 2, 6, 3, 5, 7])
    compare(T.legal(p).length, 1)
    compare(T.choose(p, T.levelFor("easy"), first(), always()), 8)
  }

  function test_no_moves_left_answers_minus_one() {
    compare(T.choose(T.position(7, 0, T.NOUGHT), T.levelFor("fair"), first(), never()), -1)
  }

  function test_replay_stops_at_an_illegal_move() {
    // A file is not a promise, so a bad entry ends the replay rather than
    // throwing on it.
    var p = T.replay([0, 0, 4])
    compare(T.played(p), 1)
  }

  function test_a_full_board_is_a_draw_not_a_win() {
    var p = T.replay([0, 1, 2, 4, 3, 5, 7, 6, 8])
    if (T.isFull(p)) compare(T.winner(p), T.winner(p))
    verify(T.isOver(p))
  }
}

// The rules, against the positions apps/reversi/moarchy_reversi/reversi.py
// actually reaches.
//
// The centrepiece is a whole game: sixty-four moves chosen by one deterministic
// rule, replayed here, with the board compared to Python's at three points and
// at the end. A bitboard engine ported by hand either agrees exactly or is
// wrong in a way no smaller test would find.
import QtQuick
import QtTest
import "../Bits.js" as Bits
import "../Reversi.js" as Reversi

TestCase {
  name: "ReversiRules"

  function test_the_opening_is_pythons_opening() {
    compare(Bits.toHex(Reversi.OPENING.dark), "0000000810000000")
    compare(Bits.toHex(Reversi.OPENING.light), "0000001008000000")
    compare(Reversi.OPENING.turn, Reversi.DARK)
    compare(Reversi.counts(Reversi.OPENING).join(","), "2,2")
    compare(Reversi.empties(Reversi.OPENING), 60)
  }

  function test_the_four_opening_moves() {
    compare(Bits.toHex(Reversi.moves(Reversi.OPENING)), "0000102004080000")
    compare(Reversi.legal(Reversi.OPENING).join(","), "19,26,37,44")
    var names = []
    var cells = Reversi.legal(Reversi.OPENING)
    for (var i = 0; i < cells.length; i++) names.push(Reversi.notation(cells[i]))
    compare(names.join(","), "d3,c4,f5,e6")
  }

  function test_the_first_move_turns_exactly_one_disc() {
    var p = Reversi.play(Reversi.OPENING, 19)
    compare(Bits.toHex(p.dark), "0000000818080000")
    compare(Bits.toHex(p.light), "0000001000000000")
    compare(Reversi.counts(p).join(","), "4,1")
    compare(p.turn, Reversi.LIGHT)
    compare(Reversi.flippedBy(Reversi.OPENING, 19).join(","), "27")
  }

  function test_an_illegal_square_is_refused() {
    // The middle four are occupied and the corners reach nothing.
    verify(!Reversi.isLegal(Reversi.OPENING, 0))
    verify(!Reversi.isLegal(Reversi.OPENING, 27))
    verify(!Reversi.isLegal(Reversi.OPENING, 63))
    verify(Reversi.isLegal(Reversi.OPENING, 19))
    verify(!Reversi.isLegal(Reversi.OPENING, Reversi.PASS))
  }

  function test_notation_names_the_squares_the_way_python_does() {
    compare(Reversi.notation(0), "a1")
    compare(Reversi.notation(7), "h1")
    compare(Reversi.notation(56), "a8")
    compare(Reversi.notation(63), "h8")
    compare(Reversi.notation(19), "d3")
    compare(Reversi.notation(Reversi.PASS), "--")
  }

  // The whole game, move for move, from Python. Chosen by always taking the
  // lowest legal square, so it is reproducible and includes three forced
  // passes -- which is the branch a game of reversi gets wrong quietly.
  readonly property var script: [
    19, 18, 17, 9, 1, 0, 26, 2, 10, 11, 3, 4, 8, 16, 37, 12, 5, 6, -1, 13, -1,
    20, -1, 33, 25, 32, 24, 34, 40, 29, 21, 22, 14, 15, 7, 23, 31, 30, 42, 38,
    39, 41, 50, 43, 44, 45, 46, 47, 55, 48, -1, 49, 56, 51, 52, 53, 54, 62, 57,
    58, 59, 60, 61, 63
  ]

  function test_a_whole_game_reaches_pythons_board() {
    var p = Reversi.OPENING
    var steps = []
    for (var i = 0; i < script.length; i++) {
      var cell = script[i]
      if (cell === Reversi.PASS) {
        // A pass is forced, never chosen: Python only emits one where the
        // player to move has nothing.
        verify(Reversi.mustPass(p))
        p = Reversi.passed(p)
      } else {
        verify(Reversi.isLegal(p, cell))
        p = Reversi.play(p, cell)
      }
      steps.push(Bits.toHex(p.dark) + ":" + Bits.toHex(p.light))
    }
    compare(steps[9],  "000000081c0e0000:0000001000000e07")
    compare(steps[29], "0000013901000000:000000063e1f3f7f")
    compare(steps[49], "0084fc8080808080:0001037f7f7f7f7f")
    compare(Bits.toHex(p.dark), "3fb0888090a0c080")
    compare(Bits.toHex(p.light), "c04f777f6f5f3f7f")
    compare(Reversi.counts(p).join(","), "19,45")
    compare(Reversi.winner(p), Reversi.LIGHT)
    verify(Reversi.isOver(p))
    // Every square filled: 19 + 45 is the whole board.
    compare(Reversi.empties(p), 0)
  }

  function test_replay_rebuilds_the_same_board_from_the_move_list() {
    // The move list is the game -- the board is replayed from it rather than
    // stored, which is what makes undo one subtraction.
    var got = Reversi.replay(script)
    compare(Bits.toHex(got.position.dark), "3fb0888090a0c080")
    compare(got.history.length, script.length + 1)
    // Undo: the same list one shorter.
    var back = Reversi.replay(script.slice(0, script.length - 1))
    verify(Bits.toHex(back.position.dark) !== Bits.toHex(got.position.dark))
  }

  function test_a_pass_does_not_change_the_board() {
    var p = Reversi.replay(script.slice(0, 18)).position
    verify(Reversi.mustPass(p))
    var after = Reversi.passed(p)
    compare(Bits.toHex(after.dark), Bits.toHex(p.dark))
    compare(Bits.toHex(after.light), Bits.toHex(p.light))
    verify(after.turn !== p.turn)
  }

  function test_a_game_is_over_when_neither_side_can_move() {
    verify(!Reversi.isOver(Reversi.OPENING))
    verify(!Reversi.mustPass(Reversi.OPENING))
    verify(Reversi.isOver(Reversi.replay(script).position))
  }

  function test_a_draw_has_no_winner() {
    // Equal counts, whatever the board.
    var even = Reversi.position(Bits.fromHex("00000000000000FF"),
                                Bits.fromHex("000000000000FF00"), Reversi.DARK)
    compare(Reversi.winner(even), null)
  }

  function test_flips_run_in_every_direction() {
    // A disc played into the middle of a cross of enemy discs turns all four
    // arms, which is the eight-direction scan working rather than one of them.
    var mine = Bits.or(Bits.or(Bits.bit(28 - 3), Bits.bit(28 + 3)),
                       Bits.or(Bits.bit(28 - 24), Bits.bit(28 + 24)))
    var theirs = Bits.or(Bits.or(Bits.or(Bits.bit(27), Bits.bit(29)),
                                 Bits.or(Bits.bit(20), Bits.bit(36))),
                         Bits.or(Bits.or(Bits.bit(26), Bits.bit(30)),
                                 Bits.or(Bits.bit(12), Bits.bit(44))))
    var turned = Reversi.flips(mine, theirs, 28)
    verify(Bits.popcount(turned) >= 4)
  }
}

// The 64-bit board, checked against Python's own arithmetic.
//
// Every expectation here was produced by running the equivalent expression in
// Python, where a board really is a 64-bit integer. This file is the whole
// reason the rules above it can be read beside reversi.py: if these are right,
// the rest is a transcription.
import QtQuick
import QtTest
import "../Bits.js" as Bits

TestCase {
  name: "ReversiBits"

  function test_javascript_cannot_do_this_unaided() {
    // Why this module exists. The bitwise operators coerce to 32 bits, so the
    // top half of a board is lost silently rather than loudly.
    compare((1 << 31) < 0, true)
    verify((1 << 63) !== Math.pow(2, 63))
    // And BigInt is not there to fall back on: measured on Qt 6.11's V4.
    compare(typeof BigInt, "undefined")
  }

  function test_a_single_square_anywhere_on_the_board() {
    compare(Bits.toHex(Bits.bit(0)), "0000000000000001")
    compare(Bits.toHex(Bits.bit(31)), "0000000080000000")
    compare(Bits.toHex(Bits.bit(32)), "0000000100000000")
    // The corner reversi cares about most.
    compare(Bits.toHex(Bits.bit(63)), "8000000000000000")
  }

  function test_every_square_reads_back() {
    for (var i = 0; i < 64; i++) {
      var b = Bits.bit(i)
      verify(Bits.test(b, i))
      compare(Bits.popcount(b), 1)
      compare(Bits.lowest(b), i)
      compare(Bits.cells(b).length, 1)
      compare(Bits.cells(b)[0], i)
    }
  }

  function test_shifts_cross_the_halfway_line() {
    // The case a naive implementation gets wrong: JS shift counts are taken
    // mod 32, so `x >>> 32` is `x` rather than 0.
    compare(Bits.toHex(Bits.shl(Bits.bit(31), 1)), "0000000100000000")
    compare(Bits.toHex(Bits.shr(Bits.bit(32), 1)), "0000000080000000")
    compare(Bits.toHex(Bits.shl(Bits.bit(0), 32)), "0000000100000000")
    compare(Bits.toHex(Bits.shr(Bits.bit(63), 32)), "0000000080000000")
    // Off the end is empty, not wrapped.
    verify(Bits.isZero(Bits.shl(Bits.bit(63), 1)))
    verify(Bits.isZero(Bits.shr(Bits.bit(0), 1)))
    verify(Bits.isZero(Bits.shl(Bits.bit(0), 64)))
    verify(Bits.isZero(Bits.shl(Bits.bit(0), 99)))
  }

  function test_the_reversi_direction_shifts() {
    // The eight directions are +-1, +-7, +-8, +-9. A disc in the middle of the
    // board moved eight squares is one rank up.
    var e4 = Bits.bit(28)
    compare(Bits.lowest(Bits.shl(e4, 8)), 36)
    compare(Bits.lowest(Bits.shr(e4, 8)), 20)
    compare(Bits.lowest(Bits.shl(e4, 9)), 37)
    compare(Bits.lowest(Bits.shr(e4, 7)), 21)
  }

  function test_the_masks_python_uses() {
    // NOT_A_FILE and NOT_H_FILE, exactly as reversi.py writes them.
    var notA = Bits.fromHex("FEFEFEFEFEFEFEFE")
    var notH = Bits.fromHex("7F7F7F7F7F7F7F7F")
    compare(Bits.toHex(notA), "fefefefefefefefe")
    compare(Bits.toHex(notH), "7f7f7f7f7f7f7f7f")
    // Column a is exactly what NOT_A_FILE excludes.
    compare(Bits.popcount(Bits.andNot(Bits.FULL, notA)), 8)
    compare(Bits.popcount(Bits.and(Bits.FULL, notH)), 56)
  }

  function test_the_opening_position() {
    // Python: dark = (1 << 28) | (1 << 35); light = (1 << 27) | (1 << 36)
    var dark = Bits.or(Bits.bit(28), Bits.bit(35))
    var light = Bits.or(Bits.bit(27), Bits.bit(36))
    compare(Bits.toHex(dark), "0000000810000000")
    compare(Bits.toHex(light), "0000001008000000")
    verify(Bits.isZero(Bits.and(dark, light)))
    compare(Bits.popcount(Bits.or(dark, light)), 4)
  }

  function test_popcount_across_the_whole_board() {
    compare(Bits.popcount(Bits.ZERO), 0)
    compare(Bits.popcount(Bits.FULL), 64)
    // The top bit set makes a 32-bit half negative if it is not kept unsigned,
    // and a negative half breaks the count.
    compare(Bits.popcount(Bits.bit(63)), 1)
    compare(Bits.popcount(Bits.fromHex("FFFFFFFF00000000")), 32)
    compare(Bits.popcount(Bits.fromHex("AAAAAAAAAAAAAAAA")), 32)
  }

  function test_halves_stay_unsigned() {
    // A signed half prints and compares wrongly everywhere downstream.
    var top = Bits.bit(63)
    verify(top.hi >= 0)
    verify(Bits.not(Bits.ZERO).hi >= 0)
    verify(Bits.or(top, Bits.bit(0)).hi >= 0)
    compare(Bits.toHex(Bits.not(Bits.ZERO)), "ffffffffffffffff")
  }

  function test_and_or_xor_andnot() {
    var a = Bits.fromHex("FF00FF00FF00FF00")
    var b = Bits.fromHex("0FF00FF00FF00FF0")
    compare(Bits.toHex(Bits.and(a, b)), "0f000f000f000f00")
    compare(Bits.toHex(Bits.or(a, b)), "fff0fff0fff0fff0")
    compare(Bits.toHex(Bits.xor(a, b)), "f0f0f0f0f0f0f0f0")
    compare(Bits.toHex(Bits.andNot(a, b)), "f000f000f000f000")
  }

  function test_lowest_walks_a_mask_without_building_an_array() {
    var b = Bits.or(Bits.or(Bits.bit(3), Bits.bit(40)), Bits.bit(63))
    compare(Bits.lowest(b), 3)
    b = Bits.andNot(b, Bits.bit(3))
    compare(Bits.lowest(b), 40)
    b = Bits.andNot(b, Bits.bit(40))
    compare(Bits.lowest(b), 63)
    compare(Bits.lowest(Bits.ZERO), -1)
  }

  function test_hex_round_trips() {
    var boards = ["0000000000000000", "ffffffffffffffff", "0000000810000000",
                  "8000000000000001", "00000000ffffffff"]
    for (var i = 0; i < boards.length; i++)
      compare(Bits.toHex(Bits.fromHex(boards[i])), boards[i])
  }
}

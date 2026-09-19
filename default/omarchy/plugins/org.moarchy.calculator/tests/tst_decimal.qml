// Arithmetic in tens, checked against the answers a person would write down.
//
// The reason this file exists at all is the first test in it. Every other app
// in this repository could take JavaScript's numbers as they come; a calculator
// cannot, because `0.1 + 0.2` as a double is 0.30000000000000004 and there is
// no rounding on the way to the label that turns that into an honest app --
// 0.1 + 0.2 - 0.3 would still be a millionth of a millionth rather than nought.
import QtQuick
import QtTest
import "../Decimal.js" as D

TestCase {
  name: "Decimal"

  function n(text) { return D.fromString(text) }
  function s(value) { return D.toString(value) }

  function test_the_sum_every_calculator_is_judged_on() {
    compare(s(D.add(n("0.1"), n("0.2"))), "0.3")
    compare(s(D.sub(D.add(n("0.1"), n("0.2")), n("0.3"))), "0")
    compare(s(D.mul(n("1.1"), n("3"))), "3.3")
    compare(s(D.mul(n("0.07"), n("100"))), "7")
  }

  function test_the_four_operations() {
    compare(s(D.add(n("12"), n("3"))), "15")
    compare(s(D.sub(n("12"), n("30"))), "-18")
    compare(s(D.mul(n("999"), n("999"))), "998001")
    compare(s(D.div(n("1"), n("8"))), "0.125")
    compare(s(D.div(n("2"), n("4"))), "0.5")
  }

  function test_signs() {
    compare(s(D.add(n("-5"), n("3"))), "-2")
    compare(s(D.add(n("5"), n("-5"))), "0")
    compare(s(D.mul(n("-3"), n("-4"))), "12")
    compare(s(D.div(n("-9"), n("3"))), "-3")
    // Zero has no sign. A calculator that can show "-0" has a bug somebody will
    // photograph.
    compare(s(D.mul(n("-1"), n("0"))), "0")
  }

  function test_numbers_longer_than_a_double_can_hold() {
    // Sixteen significant digits is where a double gives up. These are exact.
    compare(s(D.mul(n("12345678901234567890"), n("2"))), "24691357802469135780")
    compare(s(D.add(n("9007199254740993"), n("1"))), "9007199254740994")
  }

  function test_division_stops_at_the_digits_it_carries() {
    // Thirty, which is Decimal.js's PRECISION, and the eighteen past the twelve
    // shown are the guard digits that make 1/3 x 3 come back as 1.
    var third = D.div(n("1"), n("3"))
    compare(third.d.length, 30)
    compare(s(D.roundSig(third, 12)), "0.333333333333")
    compare(s(D.roundSig(D.mul(third, n("3")), 12)), "1.00000000000")
  }

  function test_dividing_by_nothing_is_not_an_answer() {
    compare(D.div(n("1"), n("0")), null)
    compare(D.div(n("0"), n("0")), null)
  }

  function test_rounding_is_half_away_from_zero() {
    // Not Python's default half-to-even. A calculator showing 2.5 as 2 is a
    // calculator arguing with its owner about a convention they have never met.
    compare(s(D.roundSig(n("2.5"), 1)), "3")
    compare(s(D.roundSig(n("-2.5"), 1)), "-3")
    compare(s(D.roundSig(n("2.45"), 2)), "2.5")
    // 999.9 to three digits carries all the way and gains a place.
    compare(s(D.roundSig(n("999.9"), 3)), "1000")
  }

  function test_a_number_too_small_to_reach_cannot_change_one() {
    // Aligning these would build a string as long as the gap between them, to
    // produce the larger one back.
    var huge = n("1" + Array(40).join("0"))
    compare(s(D.add(huge, n("0.00001"))), s(huge))
  }

  function test_what_is_not_a_number() {
    compare(D.fromString(""), null)
    compare(D.fromString("."), null)
    compare(D.fromString("12x"), null)
    compare(D.fromString("1.2.3"), null)
    compare(s(D.fromString("-007.50")), "-7.50")
  }

  function test_trailing_zeros_mean_nothing_here() {
    compare(s(D.trimZeros(n("1.500"))), "1.5")
    compare(s(D.trimZeros(n("1500"))), "1500")
    compare(D.compare(n("1.10"), n("1.1")), 0)
  }
}

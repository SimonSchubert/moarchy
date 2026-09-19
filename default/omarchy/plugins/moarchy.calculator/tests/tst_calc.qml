// The keypad and the parser: what a key does to the sum, and what the sum
// comes to.
//
// Two of these carry the weight. **The percentage rules** are the arithmetic
// every calculator is expected to get right and a good half get wrong, and they
// are four different answers depending on the operator in front. **The key
// functions** are the app's only validation: if one of them can produce an
// expression that does not evaluate, the running answer under the display goes
// blank while somebody is typing and nothing says why.
import QtQuick
import QtTest
import "../Calc.js" as Calc

TestCase {
  name: "Calc"

  // What the display would say for a sum typed and left as it is.
  function sum(text) {
    var answer = Calc.evaluate(Calc.complete(text))
    return answer.ok ? Calc.formatNumber(answer.value) : answer.why
  }

  function test_the_operators_bind_the_way_they_do_on_paper() {
    compare(sum("12+3*4"), "24")
    compare(sum("(12+3)*4"), "60")
    compare(sum("2+3*4-6/3"), "12")
    compare(sum("6*-2"), "-12")
    compare(sum("-5+3"), "-2")
  }

  function test_a_percentage_means_what_it_is_read_as() {
    // Added or taken away, it is a percentage *of* the thing in front of it.
    compare(sum("200+10%"), "220")
    compare(sum("50-10%"), "45")
    // Multiplied or divided, it is an ordinary tenth.
    compare(sum("200*10%"), "20")
    compare(sum("200/10%"), "2000")
    // On its own, and one step further on, where the rule must not reach.
    compare(sum("10%"), "0.1")
    compare(sum("200+2*10%"), "200.2")
  }

  function test_a_sum_half_typed_still_has_an_answer() {
    compare(sum("12+3*"), "15")
    compare(sum("(12+3"), "15")
    compare(sum("12+("), "12")
    compare(Calc.complete("12+"), "12")
    compare(Calc.complete("+"), "")
    compare(Calc.running("") , null)
  }

  function test_dividing_by_nothing_is_said_in_words() {
    compare(sum("1/0"), Calc.DIVIDE)
    compare(sum("5+1/(3-3)"), Calc.DIVIDE)
  }

  function test_how_a_number_is_written_out() {
    compare(sum("1234567*2"), "2,469,134")
    // Four figures are left alone; five get a separator.
    compare(sum("1000+0"), "1000")
    compare(sum("9999+1"), "10,000")
    compare(sum("17.50*3"), "52.5")
    // Both ends of what twelve digits can say.
    compare(sum("999999999999*999999999999"), "9.99999999998e23")
    compare(sum("1/100000000000000"), "1e-14")
  }

  function test_the_keys_cannot_build_a_sum_that_will_not_evaluate() {
    // Every one of these is somebody changing their mind, not an error.
    compare(Calc.operator(Calc.operator("12", "+"), "*"), "12*")
    compare(Calc.operator("6*-", "+"), "6+")
    compare(Calc.operator("", "+"), "")
    compare(Calc.operator("", "-"), "-")
    compare(Calc.operator("5.", "+"), "5+")
    // A minus straight after x, / or ( is a sign rather than a second operator.
    compare(Calc.operator("6*", "-"), "6*-")
    compare(Calc.operator("(", "-"), "(-")
  }

  function test_the_digit_and_point_keys() {
    compare(Calc.digit("0", "5"), "5")          // a leading zero is a placeholder
    compare(Calc.digit("10", "5"), "105")
    compare(Calc.digit("(1+2)", "3"), "(1+2)*3")  // meant as x3
    compare(Calc.digit("50%", "2"), "50%*2")
    compare(Calc.point(""), "0.")               // never a bare point
    compare(Calc.point("1.5"), "1.5")           // one point to a number
    compare(Calc.point("12+"), "12+0.")
    // Twelve digits is what the display says, so it is what a number takes.
    compare(Calc.digit("123456789012", "3"), "123456789012")
    compare(Calc.digit("0.00000000001", "2"), "0.000000000012")
  }

  function test_one_bracket_key_for_both_brackets() {
    compare(Calc.bracket(""), "(")
    compare(Calc.bracket("12+"), "12+(")
    compare(Calc.bracket("12+(3"), "12+(3)")
    compare(Calc.bracket("12+(3)"), "12+(3)*(")
    compare(Calc.bracket("12"), "12*(")
  }

  function test_the_percent_key_needs_a_number_in_front_of_it() {
    compare(Calc.percent("12"), "12%")
    compare(Calc.percent("(1+2)"), "(1+2)%")
    compare(Calc.percent("12+"), "12+")
    compare(Calc.percent(""), "")
    compare(Calc.percent("12."), "12%")
  }

  function test_what_the_display_shows_of_what_was_typed() {
    compare(Calc.pretty("1234567+0.50*(12-3)"), "1,234,567+0.50×(12−3)")
    // A number too long for the display is the one thing shown differently
    // from how it was typed, and only `=` can put one there.
    compare(Calc.pretty("0.333333333333333333333333333333"), "0.333333333333")
    compare(Calc.isPlain("-12.5"), true)
    compare(Calc.isPlain("1+2"), false)
  }

  function test_the_keypad_is_the_layout_everybody_already_knows() {
    compare(Calc.KEYS.length, 20)
    compare(Calc.COLUMNS, 4)
    var tokens = ""
    for (var i = 0; i < Calc.KEYS.length; i++) tokens += Calc.KEYS[i].t + " "
    compare(tokens.trim(), "AC () % / 7 8 9 * 4 5 6 - 1 2 3 + 0 . < =")
  }
}

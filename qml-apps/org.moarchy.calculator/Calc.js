// What the keys do to the sum, and what the sum comes to.
//
// The arithmetic underneath is Decimal.js and is in tens. This file is the
// layer a person touches, and it is three things: reading an expression,
// writing a number back out, and the twenty keys.
//
// **The whole sum, then the answer.** This is formula entry -- you build
// `12+3x4` and the app tells you it is 24 -- rather than the four-function
// chain calculator, which applies each operator as it is typed and answers 60.
// The chain is the right design for a device with an eight-digit display and
// nowhere to show what you typed; a phone has room, so the expression stays on
// the screen, x and / bind tighter than + and - the way they do on paper, and
// the running answer sits under it before `=` is ever pressed.
//
// **A percentage means what it is read as.** `200+10%` is 220 and not 200.1,
// because a percentage added to something is a percentage *of* that something.
// That rule is in `expression()` below and it is four lines; it is also the one
// piece of arithmetic every calculator is expected to get right and a good half
// of them do not.
//
// **A key that cannot be pressed does something instead of nothing.** Typing
// `+` twice is not an error to reject, it is somebody changing their mind, so
// the second replaces the first. A digit after `)` inserts the multiplication
// that was meant. One bracket key opens or closes by where the sum has got to.
// Those are the `digit`/`point`/`operator`/`bracket`/`percent` functions, and
// they exist so that **nothing else in the app has to ask whether the
// expression is valid** -- it cannot be made invalid from the keypad, which is
// what lets the answer be recomputed on every keystroke.
//
// Every one of them takes the expression and returns the new one. No state
// lives here: the app owns one string, and this file is the list of things that
// can happen to it.
.pragma library
.import "Decimal.js" as D

var DIGITS = "0123456789"
var OPERATORS = "+-*/"
var POINT = "."
var OPEN = "("
var CLOSE = ")"
var PERCENT = "%"

// How many significant digits the display says. The arithmetic carries thirty
// (Decimal.js), and the eighteen in between are the guard digits: they are why
// 1/3 x 3 comes back as 1.
var SHOWN = 12

// The longest expression the keypad will build, and the most significant digits
// it will take in one number. Twelve because that is what the display shows: a
// thirteenth digit typed into a number would be one the app then rounded away
// in front of the person typing it.
var MAX_LENGTH = 120
var MAX_DIGITS = 12

// Said to the person, so they are sentences rather than the names of errors.
var DIVIDE = "Cannot divide by zero"
var BROKEN = "That is not a sum"

// Typed, stored and parsed as ASCII -- a saved file full of multiplication
// signs is a file that needs an encoding argument on every read -- and turned
// into these on the way to a label. The minus is a real minus sign and not a
// hyphen: it is the width of a digit, so a column of negative numbers lines up.
var GLYPHS = { "*": "×", "/": "÷", "-": "−" }

// The decimal point is a point, so the separator is a comma. One of the two has
// to be, and these are the pair a phone sold in an English-speaking country is
// set to.
var GROUP = ","

// The keypad, in reading order: four to a row, five rows.
//
// The layout is the one every calculator has had since the nineteen-seventies,
// and that is the entire argument for it -- the digits are where a hand already
// knows they are, the operators are down the right-hand edge under a thumb, and
// `=` is in the corner. A calculator is the one app on a phone where an
// original layout is a cost with nothing behind it.
//
// What is not here is worth stating too. No scientific mode, no memory, no
// second page of keys behind a toggle: each of those is a row answering a
// question somebody standing at a till does not have, and there is a
// gnome-calculator for anybody who does.
//
// `t` is the token, and it is deliberately the ASCII the expression is stored
// in -- `*` and not `x` -- so that a key and a keystroke arrive at the same
// place by the same name.
var COLUMNS = 4
var KEYS = [
  { t: "AC", label: "AC", kind: "clear", say: "Clear" },
  { t: "()", label: "( )", kind: "aux", say: "Brackets" },
  { t: "%", label: "%", kind: "aux", say: "Per cent" },
  { t: "/", label: "\u00f7", kind: "operator", say: "Divide" },

  { t: "7", label: "7", kind: "digit", say: "Seven" },
  { t: "8", label: "8", kind: "digit", say: "Eight" },
  { t: "9", label: "9", kind: "digit", say: "Nine" },
  { t: "*", label: "\u00d7", kind: "operator", say: "Multiply" },

  { t: "4", label: "4", kind: "digit", say: "Four" },
  { t: "5", label: "5", kind: "digit", say: "Five" },
  { t: "6", label: "6", kind: "digit", say: "Six" },
  { t: "-", label: "\u2212", kind: "operator", say: "Minus" },

  { t: "1", label: "1", kind: "digit", say: "One" },
  { t: "2", label: "2", kind: "digit", say: "Two" },
  { t: "3", label: "3", kind: "digit", say: "Three" },
  { t: "+", label: "+", kind: "operator", say: "Plus" },

  { t: "0", label: "0", kind: "digit", say: "Zero" },
  { t: ".", label: ".", kind: "digit", say: "Point" },
  { t: "<", label: "\u232b", kind: "aux", say: "Backspace" },
  { t: "=", label: "=", kind: "equals", say: "Equals" }
]

function isDigit(ch) {
  return ch.length === 1 && DIGITS.indexOf(ch) >= 0
}

function isOperator(ch) {
  return ch.length === 1 && OPERATORS.indexOf(ch) >= 0
}

// --- reading an expression -------------------------------------------------

// Numbers and single characters. Anything else is dropped rather than refused,
// because this reads saved files as well as keypads, and a stray character in
// calculator.json should cost the sum it is in and not the app.
function tokenize(text) {
  var out = []
  var number = ""
  var source = String(text || "")
  for (var i = 0; i < source.length; i++) {
    var ch = source.charAt(i)
    if (isDigit(ch) || ch === POINT) {
      number += ch
      continue
    }
    if (number) {
      out.push(number)
      number = ""
    }
    if (isOperator(ch) || ch === OPEN || ch === CLOSE || ch === PERCENT) out.push(ch)
  }
  if (number) out.push(number)
  return out
}

function peek(st) {
  return st.at < st.tokens.length ? st.tokens[st.at] : ""
}

function take(st) {
  var token = peek(st)
  st.at += 1
  return token
}

// Recursive descent, four operators deep. `bare` is the one thing here that is
// not out of a textbook: whether the value just parsed was written as a plain
// percentage, which is what `expression` needs to know to read `200+10%` the
// way a person reads it.
function expression(st) {
  var left = term(st)
  while (!st.why && (peek(st) === "+" || peek(st) === "-")) {
    var op = take(st)
    var right = term(st)
    if (st.why) break
    var amount = right.value
    // A percentage added to something is a percentage *of* that something.
    // `amount` has already been divided by a hundred, so the whole rule is this
    // multiplication -- and it is deliberately not applied under x or /, where
    // `200x10%` means twenty by the ordinary reading of a tenth.
    if (right.bare) amount = D.mul(left.value, amount)
    left = {
      value: op === "+" ? D.add(left.value, amount) : D.sub(left.value, amount),
      bare: false
    }
  }
  return left.value
}

function term(st) {
  var left = factor(st)
  while (!st.why && (peek(st) === "*" || peek(st) === "/")) {
    var op = take(st)
    var right = factor(st)
    if (st.why) break
    if (op === "*") {
      left = { value: D.mul(left.value, right.value), bare: false }
      continue
    }
    var quotient = D.div(left.value, right.value)
    if (quotient === null) {
      st.why = DIVIDE
      return { value: D.zero(), bare: false }
    }
    left = { value: quotient, bare: false }
  }
  return left
}

function factor(st) {
  var sign = peek(st)
  if (sign === "-" || sign === "+") {
    take(st)
    var inner = factor(st)
    return {
      value: sign === "-" ? D.negate(inner.value) : inner.value,
      bare: inner.bare
    }
  }
  var value = primary(st)
  var bare = false
  while (!st.why && peek(st) === PERCENT) {
    take(st)
    value = D.div(value, D.fromString("100"))
    bare = true
  }
  return { value: value, bare: bare }
}

function primary(st) {
  var token = take(st)
  if (token === OPEN) {
    var inner = expression(st)
    if (peek(st) === CLOSE) take(st)
    return inner
  }
  var number = D.fromString(token)
  if (number === null) {
    st.why = BROKEN
    return D.zero()
  }
  return number
}

// { ok: true, value } or { ok: false, why: "a sentence" }.
function evaluate(text) {
  var tokens = tokenize(text)
  if (!tokens.length) return { ok: false, why: BROKEN }
  var st = { tokens: tokens, at: 0, why: "" }
  var value = expression(st)
  if (st.why) return { ok: false, why: st.why }
  if (st.at < tokens.length) return { ok: false, why: BROKEN }
  return { ok: true, value: value }
}

// The expression as it would read if the person stopped typing now.
//
// A sum half typed is not a sum with a mistake in it, and the running answer
// under the display has to be able to say something about `12+3x`. So a
// trailing operator is dropped and an unclosed bracket is closed. Pressing `=`
// comes through here too: a calculator that refuses to answer because you left
// a bracket open is a calculator counting brackets at you.
function complete(text) {
  var out = String(text || "")
  while (out.length) {
    var last = out.charAt(out.length - 1)
    if (!isOperator(last) && last !== OPEN) break
    out = out.slice(0, -1)
  }
  if (!out.length) return ""
  var depth = 0
  for (var i = 0; i < out.length; i++) {
    if (out.charAt(i) === OPEN) depth++
    else if (out.charAt(i) === CLOSE) depth--
  }
  while (depth > 0) {
    out += CLOSE
    depth--
  }
  return out
}

// The answer so far, or null while there is not one worth showing.
function running(text) {
  var ready = complete(text)
  if (!ready.length) return null
  var answer = evaluate(ready)
  return answer.ok ? answer.value : null
}

// Is this a number rather than a sum? The display uses it to decide whether a
// running answer would say anything: `12` under `12` is a line of the screen
// spent saying that twelve is twelve.
function isPlain(text) {
  var source = String(text || "")
  if (source.charAt(0) === "-") source = source.slice(1)
  if (!source.length) return true
  for (var i = 0; i < source.length; i++) {
    var ch = source.charAt(i)
    if (!isDigit(ch) && ch !== POINT) return false
  }
  return true
}

// --- writing a number out --------------------------------------------------

function grouped(text) {
  var sign = text.charAt(0) === "-" ? "-" : ""
  var body = sign ? text.slice(1) : text
  var dot = body.indexOf(POINT)
  var whole = dot < 0 ? body : body.slice(0, dot)
  var rest = dot < 0 ? "" : body.slice(dot)
  // Four figures are left alone: 1000, not 1,000. A separator in a year, a
  // house number or a price that small reads as punctuation left in by mistake.
  if (whole.length > 4) {
    var out = ""
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 === 0) out += GROUP
      out += whole.charAt(i)
    }
    whole = out
  }
  return sign + whole + rest
}

function scientific(v) {
  var r = D.trimZeros(D.roundSig(v, SHOWN))
  var mantissa = r.d.charAt(0)
  if (r.d.length > 1) mantissa += POINT + r.d.slice(1)
  return (r.neg ? "-" : "") + mantissa + "e" + D.adjusted(r)
}

// A number as the display says it: twelve significant digits, no trailing
// zeros, separators in, and `e` notation at the two ends where the alternative
// is a row of zeros nobody can count.
function formatNumber(v, group) {
  if (!v) return ""
  if (D.isZero(v)) return "0"
  var exponent = D.adjusted(v)
  if (exponent >= SHOWN || exponent < -SHOWN) return scientific(v)
  var text = D.toString(D.trimZeros(D.roundSig(v, SHOWN)))
  return group === false ? text : grouped(text)
}

// The answer, as something the keypad can carry on typing into.
function toEntry(v) {
  return D.toString(v)
}

function significant(token) {
  var digits = String(token).split(POINT).join("")
  var i = 0
  while (i < digits.length && digits.charAt(i) === "0") i++
  return digits.length - i
}

// An expression as it is shown: real operator glyphs, grouped numbers.
//
// Numbers are shown as they were typed -- `5.` keeps its point while somebody
// is mid-number, and `0.50` keeps its zero -- with one exception: a number
// longer than the display can say goes through `formatNumber`. The only way to
// get one of those into an expression is to press `=` and carry on, and the
// alternative is a display showing thirty digits of a third.
function pretty(text) {
  var out = ""
  var number = ""
  var source = String(text || "")

  function flush() {
    if (!number.length) return
    var whole = number.split(POINT)[0]
    var i = 0
    while (i < whole.length && whole.charAt(i) === "0") i++
    if (significant(number) > SHOWN || whole.length - i > SHOWN) {
      out += formatNumber(D.fromString(number))
    } else {
      out += grouped(number)
    }
    number = ""
  }

  for (var k = 0; k < source.length; k++) {
    var ch = source.charAt(k)
    if (isDigit(ch) || ch === POINT) {
      number += ch
      continue
    }
    flush()
    out += GLYPHS[ch] !== undefined ? GLYPHS[ch] : ch
  }
  flush()
  return out
}

// --- the keys ---------------------------------------------------------------

// The number being typed, or "" if the last key was not part of one.
function tail(text) {
  var out = ""
  for (var i = text.length - 1; i >= 0; i--) {
    var ch = text.charAt(i)
    if (!isDigit(ch) && ch !== POINT) break
    out = ch + out
  }
  return out
}

function full(text) {
  return text.length >= MAX_LENGTH
}

function digit(text, ch) {
  if (!isDigit(ch) || full(text)) return text
  var out = text
  var last = out.charAt(out.length - 1)
  // 3)4 was meant as 3)x4.
  if (out.length && (last === CLOSE || last === PERCENT)) out += "*"
  var number = tail(out)
  if (significant(number) >= MAX_DIGITS && significant(number) > 0) return text
  // A leading zero is a placeholder rather than a digit: 0 then 5 is 5.
  if (number === "0") return out.slice(0, -1) + ch
  return out + ch
}

function point(text) {
  if (full(text)) return text
  var number = tail(text)
  if (number.indexOf(POINT) >= 0) return text
  if (number.length) return text + POINT
  var out = text
  var last = out.charAt(out.length - 1)
  if (out.length && (last === CLOSE || last === PERCENT)) out += "*"
  // Never a bare point: the zero in front of it is what makes `.5` a number
  // rather than a key pressed by mistake.
  return out + "0" + POINT
}

function operator(text, ch) {
  if (!isOperator(ch)) return text
  var last = text.charAt(text.length - 1)
  // A minus straight after x, / or ( is a sign and not a second operator:
  // 6 x -2 is a sum somebody means.
  if (ch === "-" && text.length && (last === "*" || last === "/" || last === OPEN)) {
    return full(text) ? text : text + ch
  }
  var head = text
  while (head.length && isOperator(head.charAt(head.length - 1))) {
    head = head.slice(0, -1)
  }
  // Nothing to operate on. A minus still starts a negative number; the others
  // have nothing to apply to and are ignored.
  if (!head.length) return ch === "-" ? "-" : ""
  var end = head.charAt(head.length - 1)
  if (end === OPEN) return head + (ch === "-" ? "-" : "")
  if (end === POINT) head = head.slice(0, -1)  // 5. then + is 5+
  return head + ch
}

// One key, opening or closing by where the sum has got to.
//
// Two keys is the honest layout and it costs a column the digits need more.
// Which one is meant is never in doubt anyway: after an operator only an open
// bracket can follow, after a number only a close one can, and there is nothing
// in between.
function bracket(text) {
  if (full(text)) return text
  var out = text
  var last = out.charAt(out.length - 1)
  if (last === POINT) {
    out = out.slice(0, -1)
    last = out.charAt(out.length - 1)
  }
  if (!out.length || isOperator(last) || last === OPEN) return out + OPEN
  var depth = 0
  for (var i = 0; i < out.length; i++) {
    if (out.charAt(i) === OPEN) depth++
    else if (out.charAt(i) === CLOSE) depth--
  }
  if (depth > 0) return out + CLOSE
  return out + "*" + OPEN  // 3( was meant as 3x(
}

function percent(text) {
  if (full(text) || !text.length) return text
  var last = text.charAt(text.length - 1)
  if (last === POINT) return text.slice(0, -1) + PERCENT
  if (isDigit(last) || last === CLOSE) return text + PERCENT
  return text
}

function back(text) {
  return text.slice(0, -1)
}

// Arithmetic in tens, because JavaScript's is in twos.
//
// `0.1 + 0.2` in QML is 0.30000000000000004, and every language with IEEE
// doubles says the same thing for the same good reason. A calculator is the one
// app on a phone where that is not a rounding detail to be tidied up on the way
// to a label: it is a wrong answer, on the screen, in the one program whose
// entire product is being right about arithmetic. Python's half of this repo
// reaches for `decimal` and the question does not arise. QML has no decimal, so
// this is one.
//
// A number here is three fields:
//
//     { neg: false, d: "1234", e: -2 }        =  12.34
//
// a sign, a string of digits, and a power of ten. Nothing is ever a `Number`
// except the exponent and the loop counters, which is the property the whole
// file exists to have -- one cast to double anywhere below would put the error
// straight back.
//
// The four operations are the ones taught at school, on strings, because that
// is what the school ones are: add and subtract align the exponents and work
// right to left with a carry, multiply accumulates partial products into an
// array and normalises once at the end, and divide takes one digit at a time by
// repeated subtraction. Thirty digits at a time makes all four instant -- the
// longest of them, a thirty-by-thirty multiply, is nine hundred digit products,
// and a phone does that in the time between two frames several thousand times
// over.
//
// Two bounds keep it that way. Every result is rounded back to `PRECISION`
// significant digits, so a chain of sums cannot grow its own operands; and an
// addition whose operands are more than that many orders of magnitude apart
// returns the larger one, because the smaller cannot reach the last digit kept
// and aligning them would build a string as long as the gap.
.pragma library

// What the arithmetic carries. The display shows twelve (see Calc.js), and the
// eighteen in between are what make 1/3 x 3 come back as 1 rather than as
// 0.999999999999 -- the same trick a pocket calculator plays with its guard
// digits, for the same reason.
var PRECISION = 30

function rep(text, n) {
  var out = ""
  for (var i = 0; i < n; i++) out += text
  return out
}

// Leading zeros, gone. "007" is seven and "000" is zero, and every routine
// below assumes it has been through here.
function strip(d) {
  var i = 0
  while (i < d.length - 1 && d.charAt(i) === "0") i++
  return d.slice(i)
}

function make(neg, d, e) {
  var digits = strip(String(d))
  if (digits === "0") return { neg: false, d: "0", e: 0 }
  return { neg: !!neg, d: digits, e: e | 0 }
}

function zero() {
  return { neg: false, d: "0", e: 0 }
}

function isZero(v) {
  return !v || v.d === "0"
}

// Where the leading digit sits, as a power of ten: 12.34 is 1 and 0.0012 is -3.
// The one number every decision about how to show a value is made from.
function adjusted(v) {
  return v.d.length - 1 + v.e
}

function negate(v) {
  if (isZero(v)) return zero()
  return { neg: !v.neg, d: v.d, e: v.e }
}

function abs(v) {
  return { neg: false, d: v.d, e: v.e }
}

// --- digit strings ---------------------------------------------------------

function cmpDigits(a, b) {
  var x = strip(a), y = strip(b)
  if (x.length !== y.length) return x.length > y.length ? 1 : -1
  if (x === y) return 0
  return x > y ? 1 : -1
}

function addDigits(a, b) {
  var out = "", carry = 0
  var i = a.length - 1, j = b.length - 1
  while (i >= 0 || j >= 0 || carry) {
    var sum = carry
    if (i >= 0) sum += a.charCodeAt(i) - 48
    if (j >= 0) sum += b.charCodeAt(j) - 48
    out = String(sum % 10) + out
    carry = sum > 9 ? 1 : 0
    i--
    j--
  }
  return out
}

// `a` must be the larger. Every caller compares first, which is also where the
// sign of the answer is decided.
function subDigits(a, b) {
  var out = "", borrow = 0
  var i = a.length - 1, j = b.length - 1
  while (i >= 0) {
    var diff = (a.charCodeAt(i) - 48) - borrow - (j >= 0 ? b.charCodeAt(j) - 48 : 0)
    if (diff < 0) {
      diff += 10
      borrow = 1
    } else {
      borrow = 0
    }
    out = String(diff) + out
    i--
    j--
  }
  return strip(out)
}

// Partial products into a column each, then one carry pass. Accumulating
// without a modulo inside the loop is what keeps this obviously right: the most
// any column can hold is 81 times the length of the shorter number, which for
// the thirty digits above is nowhere near the size an integer stops being exact.
function mulDigits(a, b) {
  if (a === "0" || b === "0") return "0"
  var columns = []
  var width = a.length + b.length
  for (var k = 0; k < width; k++) columns.push(0)
  for (var i = 0; i < a.length; i++) {
    var x = a.charCodeAt(i) - 48
    if (!x) continue
    for (var j = 0; j < b.length; j++) {
      columns[i + j + 1] += x * (b.charCodeAt(j) - 48)
    }
  }
  var carry = 0
  for (var p = width - 1; p >= 0; p--) {
    var cur = columns[p] + carry
    columns[p] = cur % 10
    carry = Math.floor(cur / 10)
  }
  return strip(columns.join(""))
}

// One quotient digit at a time, by taking the divisor away until it will not go
// -- which is long division written out, and is nine subtractions at worst per
// digit. Fast enough by a very wide margin, and short enough to be read.
function divDigits(num, den) {
  var quotient = "", rest = "0"
  for (var i = 0; i < num.length; i++) {
    rest = strip(rest === "0" ? num.charAt(i) : rest + num.charAt(i))
    var digit = 0
    while (cmpDigits(rest, den) >= 0) {
      rest = subDigits(rest, den)
      digit++
    }
    quotient += String(digit)
  }
  return { q: strip(quotient), rest: rest }
}

// --- rounding --------------------------------------------------------------

// Half away from zero, which is the rule everybody was taught and the one a
// calculator has to use. Python's default is half-to-even, and a calculator
// that showed 2.5 as 2 would be arguing with its owner about a convention they
// have never heard of.
function roundSig(v, n) {
  if (v.d.length <= n) return v
  var keep = v.d.slice(0, n)
  var next = v.d.charCodeAt(n) - 48
  var e = v.e + (v.d.length - n)
  if (next >= 5) {
    keep = addDigits(keep, "1")
    if (keep.length > n) {
      // 999 became 1000: one digit more, so one power of ten more and the last
      // digit falls off the end.
      keep = keep.slice(0, n)
      e += 1
    }
  }
  return make(v.neg, keep, e)
}

function trimZeros(v) {
  var d = v.d, e = v.e
  while (d.length > 1 && d.charAt(d.length - 1) === "0") {
    d = d.slice(0, -1)
    e += 1
  }
  return make(v.neg, d, e)
}

// --- the four operations ---------------------------------------------------

function add(a, b) {
  if (isZero(a)) return b
  if (isZero(b)) return a
  // Orders of magnitude apart: the smaller one cannot reach the last digit that
  // is kept, so adding it is a very long string operation to produce the larger
  // one back. `+ 2` of headroom so this can never decide a rounding.
  var gap = adjusted(a) - adjusted(b)
  if (gap > PRECISION + 2) return a
  if (-gap > PRECISION + 2) return b

  var e = Math.min(a.e, b.e)
  var pa = a.d + rep("0", a.e - e)
  var pb = b.d + rep("0", b.e - e)
  if (a.neg === b.neg) return limit(make(a.neg, addDigits(pa, pb), e))
  var order = cmpDigits(pa, pb)
  if (order === 0) return zero()
  if (order > 0) return limit(make(a.neg, subDigits(pa, pb), e))
  return limit(make(b.neg, subDigits(pb, pa), e))
}

function sub(a, b) {
  return add(a, negate(b))
}

function mul(a, b) {
  if (isZero(a) || isZero(b)) return zero()
  return limit(make(a.neg !== b.neg, mulDigits(a.d, b.d), a.e + b.e))
}

// Null for a division by zero. A sentinel rather than a thrown error because
// the only caller is an expression evaluator that has a sentence to say about
// it, and QML's exception handling across a `.pragma library` boundary is not
// somewhere to find that out.
function div(a, b, prec) {
  if (isZero(b)) return null
  if (isZero(a)) return zero()
  var want = (prec || PRECISION) + 3
  // Enough zeros on the numerator that the integer quotient has the digits
  // wanted. Three spare: the quotient is rounded to `prec` afterwards, and
  // truncating below that can never turn a value under a half into one over it.
  var shift = want - (a.d.length - b.d.length)
  if (shift < 0) shift = 0
  var answer = divDigits(a.d + rep("0", shift), b.d)
  var value = roundSig(make(a.neg !== b.neg, answer.q, a.e - b.e - shift), prec || PRECISION)
  return trimZeros(value)
}

// Every result goes through here: rounded back to the digits carried, and with
// the zeros that mean nothing taken off the end. Trimming is not cosmetic --
// half of 1 is 0.5 and not 0.500000000000000000000000000000, and without this
// every division would hand the next operation thirty digits to chew on.
function limit(v) {
  return trimZeros(roundSig(v, PRECISION))
}

function compare(a, b) {
  var diff = sub(a, b)
  if (isZero(diff)) return 0
  return diff.neg ? -1 : 1
}

// --- text ------------------------------------------------------------------

// Null for anything that is not plainly a number. The tokenizer in Calc.js can
// only hand this digits and points, but a JSON file written by hand can hand it
// anything at all.
function fromString(s) {
  var text = String(s === null || s === undefined ? "" : s).trim()
  var neg = false
  if (text.charAt(0) === "+") text = text.slice(1)
  else if (text.charAt(0) === "-") { neg = true; text = text.slice(1) }
  if (!/^[0-9]*\.?[0-9]*$/.test(text)) return null
  var digits = text.replace(".", "")
  if (!digits.length) return null
  var dot = text.indexOf(".")
  var e = dot < 0 ? 0 : -(text.length - dot - 1)
  return make(neg, digits, e)
}

function fromInt(n) {
  return fromString(String(Math.round(n)))
}

// Always plain: a row of zeros rather than an exponent, because this is what
// goes into the saved file and into the expression being typed, and neither can
// read `1e21`. Calc.js is where a number becomes something to look at.
function toString(v) {
  if (isZero(v)) return "0"
  var sign = v.neg ? "-" : ""
  if (v.e >= 0) return sign + v.d + rep("0", v.e)
  var point = v.d.length + v.e
  if (point > 0) return sign + v.d.slice(0, point) + "." + v.d.slice(point)
  return sign + "0." + rep("0", -point) + v.d
}

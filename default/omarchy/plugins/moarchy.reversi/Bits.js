// A 64-bit board, on an engine that has no 64-bit integers.
//
// reversi.py is a bitboard engine: `own` and `opp` are Python ints with one bit
// per square, and every rule in it is a shift and a mask. None of that survives
// a direct port, and the reason is worth stating once because chess and mill
// are the same shape:
//
//   * JavaScript numbers are doubles. They hold 53 bits of integer exactly, so
//     a 64-bit board does not fit in one even before any operator runs.
//   * The bitwise operators are worse than that: `&`, `|`, `<<` and friends
//     coerce their operands to *32-bit* integers. `1 << 63` is not 2^63, it
//     wraps, and it does so silently.
//   * BigInt would solve it and is not there. Measured on Qt 6.11's V4:
//     `typeof BigInt` is "undefined", and the QML parser rejects the `1n`
//     literal syntax outright at compile time.
//
// So a board is two 32-bit halves, `hi` and `lo`, and the ugliness is confined
// to this file. Everything above it -- legal moves, flips, the search -- reads
// the way reversi.py reads, because the awkward part is named and boxed rather
// than spread through the rules.
//
// Halves are kept *unsigned* (`>>> 0` after every operation). A 32-bit bitwise
// result in JS is signed, so the top bit of `hi` makes the whole half negative,
// and a negative half compares and prints wrongly everywhere downstream.
.pragma library

function make(hi, lo) {
  return { hi: hi >>> 0, lo: lo >>> 0 }
}

var ZERO = { hi: 0, lo: 0 }
var FULL = { hi: 0xFFFFFFFF, lo: 0xFFFFFFFF }

function isZero(b) { return b.hi === 0 && b.lo === 0 }
function equals(a, b) { return a.hi === b.hi && a.lo === b.lo }

function or(a, b) { return make(a.hi | b.hi, a.lo | b.lo) }
function and(a, b) { return make(a.hi & b.hi, a.lo & b.lo) }
function xor(a, b) { return make(a.hi ^ b.hi, a.lo ^ b.lo) }
function not(a) { return make(~a.hi, ~a.lo) }

// a & ~b, which is what every "remove these squares" line in the rules wants.
function andNot(a, b) { return make(a.hi & ~b.hi, a.lo & ~b.lo) }

// Bit 0 is the low bit of `lo`; bit 63 is the high bit of `hi`. A shift left by
// 32 or more moves the whole low half up and empties it, which is the case a
// naive `lo >>> (32 - n)` gets wrong: JS shift counts are taken mod 32, so
// `x >>> 32` is `x`, not 0.
function shl(b, n) {
  if (n <= 0) return make(b.hi, b.lo)
  if (n >= 64) return { hi: 0, lo: 0 }
  if (n >= 32) return make(b.lo << (n - 32), 0)
  return make((b.hi << n) | (b.lo >>> (32 - n)), b.lo << n)
}

function shr(b, n) {
  if (n <= 0) return make(b.hi, b.lo)
  if (n >= 64) return { hi: 0, lo: 0 }
  if (n >= 32) return make(0, b.hi >>> (n - 32))
  return make(b.hi >>> n, (b.lo >>> n) | (b.hi << (32 - n)))
}

// One square, as a board.
function bit(index) {
  return index < 32 ? make(0, 1 << index) : make(1 << (index - 32), 0)
}

function test(b, index) {
  return index < 32 ? ((b.lo >>> index) & 1) === 1 : ((b.hi >>> (index - 32)) & 1) === 1
}

function withBit(b, index) { return or(b, bit(index)) }

// How many discs. The half-word trick from Hacker's Delight rather than a loop
// over 64 bits: this is called for every leaf of the search.
function count32(x) {
  var v = x >>> 0
  v = v - ((v >>> 1) & 0x55555555)
  v = (v & 0x33333333) + ((v >>> 2) & 0x33333333)
  v = (v + (v >>> 4)) & 0x0F0F0F0F
  return ((v * 0x01010101) >>> 24) & 0x3F
}

function popcount(b) { return count32(b.hi) + count32(b.lo) }

// The squares that are set, low to high. Used to draw and to iterate moves, not
// inside the search's inner loop.
function cells(b) {
  var out = []
  for (var i = 0; i < 32; i++) if ((b.lo >>> i) & 1) out.push(i)
  for (var j = 0; j < 32; j++) if ((b.hi >>> j) & 1) out.push(32 + j)
  return out
}

// The lowest set square, or -1. Math.clz32 is exact and is what a search uses
// to walk a move mask without building an array for it.
function lowest(b) {
  if (b.lo !== 0) return 31 - Math.clz32(b.lo & -b.lo)
  if (b.hi !== 0) return 32 + (31 - Math.clz32(b.hi & -b.hi))
  return -1
}

// For a store file and for a test's sake: sixteen hex digits, high half first.
function toHex(b) {
  function pad(x) {
    var s = (x >>> 0).toString(16)
    while (s.length < 8) s = "0" + s
    return s
  }
  return pad(b.hi) + pad(b.lo)
}

function fromHex(text) {
  var s = String(text || "").replace(/^0x/, "")
  while (s.length < 16) s = "0" + s
  return make(parseInt(s.slice(0, 8), 16) || 0, parseInt(s.slice(8, 16), 16) || 0)
}

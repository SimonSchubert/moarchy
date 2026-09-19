// CPython's random.Random, as far as this app needs it.
//
// minesweeper.py stores a seed, not a minefield, and its own docstring says why
// that is safe: "the saved game is a seed, so a layout has to come back the
// same in six months and on another machine". Keeping that promise across the
// port means keeping the stream, and the stream is CPython's Mersenne Twister.
// An engine's own Math.random would give the same app two different minefields
// for one saved game.
//
// So: MT19937, Python's `init_by_array` seeding, and `genrand_res53` for
// random(). All three are pinned by tests against CPython's actual output --
// which is the only way to know this is right, since "looks random" is true of
// every wrong implementation too.
.pragma library

var N = 624
var M = 397
var MATRIX_A = 0x9908b0df
var UPPER_MASK = 0x80000000
var LOWER_MASK = 0x7fffffff

function create(seed) {
  var r = { mt: new Array(N), index: N + 1 }
  seedByArray(r, keyFrom(seed))
  return r
}

// Python seeds from the absolute value of an int, as a little-endian array of
// 32-bit words. A seed of 0 is the one-element key [0], not an empty one.
function keyFrom(seed) {
  var n = Math.abs(Math.floor(seed || 0))
  var key = []
  if (n === 0) return [0]
  while (n > 0) {
    // `n % 2^32` and not `n >>> 0`: they agree, but only because ToUint32
    // happens to take the same modulo, and a reader should not have to know
    // that to believe this line.
    key.push((n % 4294967296) >>> 0)
    // Not `n >>>= 32`: the shift operators are 32-bit, so a seed above 2^32
    // would shift by zero and loop forever. Division is the only way up here.
    n = Math.floor(n / 4294967296)
  }
  return key
}

function initGenrand(r, s) {
  r.mt[0] = s >>> 0
  for (var i = 1; i < N; i++) {
    var prev = r.mt[i - 1] ^ (r.mt[i - 1] >>> 30)
    // The multiply is done in halves: 1812433253 * prev overflows a double's
    // exact integer range, and a 32-bit result computed loosely is a different
    // generator.
    var lo = (prev & 0xffff) * 1812433253
    var hi = (((prev >>> 16) * 1812433253) & 0xffff) << 16
    r.mt[i] = ((lo + hi) + i) >>> 0
  }
  r.index = N
}

function seedByArray(r, key) {
  initGenrand(r, 19650218)
  var i = 1, j = 0
  var k = Math.max(N, key.length)
  for (; k > 0; k--) {
    var prev = r.mt[i - 1] ^ (r.mt[i - 1] >>> 30)
    var lo = (prev & 0xffff) * 1664525
    var hi = (((prev >>> 16) * 1664525) & 0xffff) << 16
    r.mt[i] = (((r.mt[i] ^ (lo + hi)) + key[j] + j) >>> 0)
    i += 1; j += 1
    if (i >= N) { r.mt[0] = r.mt[N - 1]; i = 1 }
    if (j >= key.length) j = 0
  }
  for (k = N - 1; k > 0; k--) {
    var p2 = r.mt[i - 1] ^ (r.mt[i - 1] >>> 30)
    var lo2 = (p2 & 0xffff) * 1566083941
    var hi2 = (((p2 >>> 16) * 1566083941) & 0xffff) << 16
    r.mt[i] = (((r.mt[i] ^ (lo2 + hi2)) - i) >>> 0)
    i += 1
    if (i >= N) { r.mt[0] = r.mt[N - 1]; i = 1 }
  }
  r.mt[0] = 0x80000000
}

function genrandInt32(r) {
  var y
  if (r.index >= N) {
    var kk
    for (kk = 0; kk < N - M; kk++) {
      y = (r.mt[kk] & UPPER_MASK) | (r.mt[kk + 1] & LOWER_MASK)
      r.mt[kk] = r.mt[kk + M] ^ (y >>> 1) ^ ((y & 1) ? MATRIX_A : 0)
    }
    for (; kk < N - 1; kk++) {
      y = (r.mt[kk] & UPPER_MASK) | (r.mt[kk + 1] & LOWER_MASK)
      r.mt[kk] = r.mt[kk + (M - N)] ^ (y >>> 1) ^ ((y & 1) ? MATRIX_A : 0)
    }
    y = (r.mt[N - 1] & UPPER_MASK) | (r.mt[0] & LOWER_MASK)
    r.mt[N - 1] = r.mt[M - 1] ^ (y >>> 1) ^ ((y & 1) ? MATRIX_A : 0)
    r.index = 0
  }
  y = r.mt[r.index++]
  y ^= (y >>> 11)
  y ^= (y << 7) & 0x9d2c5680
  y ^= (y << 15) & 0xefc60000
  y ^= (y >>> 18)
  return y >>> 0
}

// Python's random(): 53 bits out of two 32-bit draws, in that order.
function random(r) {
  var a = genrandInt32(r) >>> 5
  var b = genrandInt32(r) >>> 6
  return (a * 67108864.0 + b) * (1.0 / 9007199254740992.0)
}

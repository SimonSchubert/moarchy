// CPython's stream, digit for digit.
//
// Every number below came out of `random.Random(seed).random()`. A minefield is
// replayed from a seed, so a stream that is merely random-looking gives the
// same saved game two different boards -- which is the one thing the seed was
// chosen to prevent.
import QtQuick
import QtTest
import "../Random.js" as R

TestCase {
  name: "MinesweeperRandom"

  function take(seed, n) {
    var r = R.create(seed)
    var out = []
    for (var i = 0; i < n; i++) out.push(R.random(r))
    return out
  }

  function test_the_stream_matches_cpython_data() {
    return [
      { tag: "seed 0", seed: 0,
        want: [0.8444218515250481, 0.7579544029403025, 0.420571580830845, 0.25891675029296335] },
      { tag: "seed 1", seed: 1,
        want: [0.13436424411240122, 0.8474337369372327, 0.763774618976614, 0.2550690257394217] },
      { tag: "seed 42", seed: 42,
        want: [0.6394267984578837, 0.02501075522266694, 0.27502931836911926, 0.22321073814882275] },
      { tag: "big seed", seed: 123456789,
        want: [0.6414006161858726, 0.5421892680969495, 0.9931750662832721, 0.8432521366869166] },
      // Past 2^31, where a 32-bit shift would have folded the key to nothing.
      { tag: "past 2^31", seed: 2147483648,
        want: [0.3387958510019964, 0.5050619906087787, 0.8891460738572615, 0.16291786458805446] },
      // Past 2^32, where the key is genuinely two words and the second one
      // only exists if the division is done in floating point.
      { tag: "past 2^32", seed: 12345678901234,
        want: [0.02504137575317178, 0.14532691110186335, 0.42619782335934575] }
    ]
  }
  function test_the_stream_matches_cpython(row) {
    var got = take(row.seed, row.want.length)
    for (var i = 0; i < row.want.length; i++) fuzzyCompare(got[i], row.want[i], 1e-15)
  }

  function test_getrandbits_style_draws_match() {
    // The 32-bit draws underneath, for seed 42.
    var r = R.create(42)
    var want = [2746317213, 478163327, 107420369, 3184935163]
    for (var i = 0; i < want.length; i++) compare(R.genrandInt32(r), want[i])
  }

  function test_two_generators_with_one_seed_agree() {
    compare(take(7, 6).join(","), take(7, 6).join(","))
  }

  function test_every_draw_is_in_range() {
    var r = R.create(99)
    for (var i = 0; i < 500; i++) {
      var v = R.random(r)
      verify(v >= 0 && v < 1)
    }
  }
}

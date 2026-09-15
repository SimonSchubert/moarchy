// The worker thread's program: one search, off the UI thread.
//
// Three things had to be measured to get this file right, and each is a fact
// about Qt 6.11's V4 rather than a preference:
//
//   1. `.import "Ai.js" as Ai` inside a WorkerScript source does nothing. The
//      source is not a QML document, the directive is not processed, and the
//      namespace is simply undefined at the first call.
//   2. `Qt.include()` does work, and runs the file in *this* scope -- so every
//      `var` and `function` in it becomes a global here.
//   3. An included file's own `.import` is not processed either. Ai.js says
//      `.import "Reversi.js" as Reversi` and that stays undefined, which is how
//      the first attempt answered "ReferenceError: Reversi is not defined".
//
// So the namespaces are rebuilt by hand between the includes: define `Bits`
// before including the file that refers to `Bits.*`, and so on. The files
// themselves are unchanged and still work the ordinary way from QML, which is
// what keeps one copy of the rules rather than a worker's own.
Qt.include("Bits.js")

var Bits = {
  make: make, ZERO: ZERO, FULL: FULL, isZero: isZero, equals: equals,
  or: or, and: and, xor: xor, not: not, andNot: andNot,
  shl: shl, shr: shr, bit: bit, test: test, withBit: withBit,
  popcount: popcount, cells: cells, lowest: lowest,
  toHex: toHex, fromHex: fromHex
}

Qt.include("Reversi.js")

var Reversi = {
  SIZE: SIZE, CELLS: CELLS, PASS: PASS, DARK: DARK, LIGHT: LIGHT,
  legalMoves: legalMoves, flips: flips, position: position, OPENING: OPENING,
  own: own, opp: opp, discs: discs, moves: moves, legal: legal,
  isLegal: isLegal, play: play, flippedBy: flippedBy, passed: passed,
  mustPass: mustPass, isOver: isOver, count: count, counts: counts,
  empties: empties, winner: winner, replay: replay, notation: notation
}

Qt.include("Ai.js")

WorkerScript.onMessage = function (msg) {
  var thought
  try {
    // Wall-clock, as ai.py's own deadline is: V4 has no performance.now() in a
    // worker. An NTP step mid-search costs a shallower move and nothing else.
    var clock = function () { return Date.now() / 1000 }
    thought = think(msg.position, levelFor(msg.level), clock, null)
  } catch (e) {
    // A search that dies takes the game with it: this thread is the only thing
    // that will ever move for this side, so it answers with a legal move rather
    // than leaving a board nobody can play on.
    var moves = []
    try { moves = Reversi.legal(msg.position) } catch (inner) { moves = [] }
    thought = { cell: moves.length ? moves[0] : Reversi.PASS, depth: 0, nodes: 0,
                trouble: String(e) }
  }
  thought.generation = msg.generation
  WorkerScript.sendMessage(thought)
}

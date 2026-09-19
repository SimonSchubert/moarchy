// The computer player: alpha-beta over the bitboards, on a clock.
//
// The port of apps/reversi/moarchy_reversi/ai.py, and the clock is why it ports
// straight across: the search already took its deadline as an argument and
// checked it every CHECK_MASK nodes, precisely so a slower machine would get a
// shallower answer rather than a hung one. A phone is that slower machine, and
// V4 is slower again than CPython here -- so the same code simply reaches a
// smaller depth in the same two seconds, which is the behaviour the design
// asked for.
.pragma library
.import "Bits.js" as Bits
.import "Reversi.js" as Reversi

var CELLS = 64

var WEIGHTS = [
  100, -20, 10,  5,  5, 10, -20, 100,
  -20, -50, -2, -2, -2, -2, -50, -20,
   10,  -2, -1, -1, -1, -1,  -2,  10,
    5,  -2, -1, -1, -1, -1,  -2,   5,
    5,  -2, -1, -1, -1, -1,  -2,   5,
   10,  -2, -1, -1, -1, -1,  -2,  10,
  -20, -50, -2, -2, -2, -2, -50, -20,
  100, -20, 10,  5,  5, 10, -20, 100
]

// Scoring a side means summing the weights of the squares it holds, and doing
// that a bit at a time is thousands of operations a second the search does not
// get to spend elsewhere. A rank is one byte, a byte has 256 values, so every
// rank's contribution is a table lookup: eight shifts and eight lookups for a
// whole side.
var RANK_VALUES = (function () {
  var table = []
  for (var rank = 0; rank < 8; rank++) {
    var row = []
    for (var byte = 0; byte < 256; byte++) {
      var sum = 0
      for (var column = 0; column < 8; column++)
        if ((byte >> column) & 1) sum += WEIGHTS[rank * 8 + column]
      row.push(sum)
    }
    table.push(row)
  }
  return table
})()

// Having somewhere to go is worth more than having discs: a side with no moves
// hands its turn back. At eight points a move this is comparable with holding a
// good edge square and well below a corner.
var MOBILITY = 8

// Near the end the count is the thing being played for rather than a proxy.
var COUNTING_FROM = 10
var DISC = 12

// From this many empty squares on, the depth cap gives way for the levels that
// ask, and the search plays the game out exactly -- if the clock allows, which
// is the point of the clock. Only Hard asks: an easy opponent that plays the
// final dozen moves perfectly is an easy opponent right up until the part of
// the game that decides it, which feels like being cheated rather than beaten.
var EXACT_FROM = 12

// A decided game beats any arrangement of discs, and the margin rides along so
// that winning by forty is preferred to winning by two.
var WIN = 100000

// The clock is read once every this many nodes.
var CHECK_MASK = 1023

// Alpha-beta prunes in proportion to how early the best move is tried, and the
// best move is a corner far more often than chance, so the static table is also
// the move order.
// Ties break by square number, ascending. Python's `sorted` is stable, so its
// order among equal weights is the range's own -- and V4's Array.sort is not
// stable, which produced a different table and, three moves later, a different
// game. A total comparator is the fix rather than a hope about the engine.
var SEARCH_ORDER = (function () {
  var cells = []
  for (var i = 0; i < CELLS; i++) cells.push(i)
  cells.sort(function (a, b) {
    return WEIGHTS[b] - WEIGHTS[a] || a - b
  })
  return cells
})()

var RANK = (function () {
  var out = []
  for (var i = 0; i < CELLS; i++) out.push(SEARCH_ORDER.indexOf(i))
  return out
})()

var LEVELS = [
  { key: "easy", name: "Easy", blurb: "Plays quickly, and not always well",
    depth: 1, seconds: 0.15, slack: 45, exact: false },
  { key: "medium", name: "Medium", blurb: "Looks a few moves ahead",
    depth: 3, seconds: 0.7, slack: 8, exact: false },
  { key: "hard", name: "Hard", blurb: "Thinks for a second and plays the endgame out",
    depth: 8, seconds: 2.0, slack: 0, exact: true }
]

var DEFAULT_LEVEL = "medium"

function levelFor(key) {
  for (var i = 0; i < LEVELS.length; i++) if (LEVELS[i].key === key) return LEVELS[i]
  return LEVELS[1]
}

function positional(board) {
  return RANK_VALUES[0][board.lo & 0xFF]
       + RANK_VALUES[1][(board.lo >>> 8) & 0xFF]
       + RANK_VALUES[2][(board.lo >>> 16) & 0xFF]
       + RANK_VALUES[3][(board.lo >>> 24) & 0xFF]
       + RANK_VALUES[4][board.hi & 0xFF]
       + RANK_VALUES[5][(board.hi >>> 8) & 0xFF]
       + RANK_VALUES[6][(board.hi >>> 16) & 0xFF]
       + RANK_VALUES[7][(board.hi >>> 24) & 0xFF]
}

// What a finished game is worth: decided, with the margin riding along.
function terminal(own, opp) {
  var margin = Bits.popcount(own) - Bits.popcount(opp)
  if (margin > 0) return WIN + margin
  if (margin < 0) return -WIN + margin
  return 0
}

function evaluate(own, opp, moves) {
  var mine = Bits.popcount(moves === undefined || moves === null
                           ? Reversi.legalMoves(own, opp) : moves)
  var theirs = Bits.popcount(Reversi.legalMoves(opp, own))
  if (CELLS - Bits.popcount(Bits.or(own, opp)) <= COUNTING_FROM)
    return (Bits.popcount(own) - Bits.popcount(opp)) * DISC + (mine - theirs) * 2
  return positional(own) - positional(opp) + MOBILITY * (mine - theirs)
}

function apply(own, opp, cell) {
  var turned = Reversi.flips(own, opp, cell)
  return { own: Bits.or(Bits.or(own, turned), Bits.bit(cell)),
           opp: Bits.andNot(opp, turned) }
}

// Thrown out of the search when the clock runs out. A sentinel object rather
// than a string so nothing else can be mistaken for it.
var OUT_OF_TIME = { outOfTime: true }

function search(own, opp, depth, alpha, beta, deadline, now, counter) {
  counter.n += 1
  if (!(counter.n & CHECK_MASK) && now() > deadline) throw OUT_OF_TIME
  var moves = Reversi.legalMoves(own, opp)
  if (Bits.isZero(moves)) {
    if (Bits.isZero(Reversi.legalMoves(opp, own))) return terminal(own, opp)
    // A pass costs no depth. It is not a move -- charging it one would make the
    // search shallowest exactly where the position is most forcing.
    return -search(opp, own, depth, -beta, -alpha, deadline, now, counter)
  }
  if (depth <= 0) return evaluate(own, opp, moves)

  var order = Bits.cells(moves)
  order.sort(function (a, b) { return RANK[a] - RANK[b] })
  var best = -WIN * 2
  for (var i = 0; i < order.length; i++) {
    var next = apply(own, opp, order[i])
    var score = -search(next.opp, next.own, depth - 1, -beta, -alpha,
                        deadline, now, counter)
    if (score > best) {
      best = score
      if (best > alpha) {
        alpha = best
        if (alpha >= beta) break  // the opponent would never let us get here
      }
    }
  }
  return best
}

// Score every move from here, best first on return.
//
// `prune` is off for the levels that pick among near-best moves: alpha-beta
// returns bounds rather than values for the moves it refutes, and choosing
// "within eight points of the best" out of a list of bounds would be choosing
// out of numbers that do not mean what they say.
function root(position, order, depth, deadline, now, counter, prune) {
  var alpha = -WIN * 2
  var scored = []
  for (var i = 0; i < order.length; i++) {
    var child = Reversi.play(position, order[i])
    var window = prune ? alpha : -WIN * 2
    var score = -search(Reversi.own(child), Reversi.opp(child), depth - 1,
                        -(WIN * 2), -window, deadline, now, counter)
    scored.push({ cell: order[i], score: score })
    if (score > alpha) alpha = score
  }
  // Equal scores keep the order they were searched in, which is what Python's
  // stable sort does and what makes the iterative deepening loop's re-ordering
  // deterministic.
  for (var k = 0; k < scored.length; k++) scored[k].at = k
  scored.sort(function (a, b) { return b.score - a.score || a.at - b.at })
  return scored
}

// Pick a move for the side to play, inside the level's budget.
//
// `now` and `pick` are arguments for the same reason ai.py takes `clock` and
// `rng`: a test that cannot hold the clock still is a test that fails on a
// loaded machine.
function think(position, level, now, pick) {
  var clock = now || function () { return Date.now() / 1000 }
  var choose = pick || function (list) { return list[Math.floor(Math.random() * list.length)] }

  var legal = Reversi.legal(position)
  if (!legal.length) return { cell: Reversi.PASS, depth: 0, nodes: 0 }
  if (legal.length === 1) {
    // Nothing to think about, and a pause here reads as a computer pretending
    // to consider a move it has no choice about.
    return { cell: legal[0], depth: 0, nodes: 0 }
  }

  var empties = Reversi.empties(position)
  var exact = level.exact && empties <= EXACT_FROM
  var cap = exact ? Math.max(level.depth, empties) : level.depth
  var deadline = clock() + level.seconds
  var counter = { n: 0 }
  var order = legal.slice().sort(function (a, b) { return RANK[a] - RANK[b] })
  var scored = []
  for (var i = 0; i < order.length; i++) scored.push({ cell: order[i], score: 0 })
  var reached = 0

  for (var depth = 1; depth <= cap; depth++) {
    var attempt
    try {
      attempt = root(position, order, depth, deadline, clock, counter, !level.slack)
    } catch (e) {
      if (e === OUT_OF_TIME) break
      throw e
    }
    scored = attempt
    order = []
    for (var j = 0; j < scored.length; j++) order.push(scored[j].cell)
    reached = depth
    // The game is decided from here; deeper says the same thing.
    if (Math.abs(scored[0].score) >= WIN) break
  }

  var top = scored[0].score
  var pool = []
  for (var k = 0; k < scored.length; k++)
    if (top - scored[k].score <= level.slack) pool.push(scored[k].cell)
  return { cell: choose(pool), depth: reached, nodes: counter.n }
}

// Noughts and crosses: the rules, and the game solved.
//
// The port of apps/tictactoe/moarchy_tictactoe/{tictactoe,ai}.py. Nine squares
// fit in a plain number, so unlike Reversi this needs no 64-bit workaround --
// JavaScript's bitwise operators are 32-bit and nine bits is nine bits.
//
// A position is a plain object rather than a frozen class. Python keyed the
// solved table on the position itself, which needs hashability; here the key is
// a string, which is the same idea with the language's own hashable type.
.pragma library

var SIZE = 3
var CELLS = SIZE * SIZE
var FULL = (1 << CELLS) - 1

var CROSS = 0
var NOUGHT = 1
var MARKS = [CROSS, NOUGHT]
var NAMES = { 0: "X", 1: "O" }

function other(mark) { return mark === CROSS ? NOUGHT : CROSS }

function index(row, column) { return row * SIZE + column }
function rowOf(cell) { return Math.floor(cell / SIZE) }
function columnOf(cell) { return cell % SIZE }

function cellsOf(board) {
  var out = []
  for (var i = 0; i < CELLS; i++) if ((board >> i) & 1) out.push(i)
  return out
}

function maskOf(squares) {
  var mask = 0
  for (var i = 0; i < squares.length; i++) mask |= 1 << squares[i]
  return mask
}

// The eight ways to win, each as the mask that tests it and the three squares
// that draw it. The squares travel with the mask rather than being recovered
// from it afterwards, because the line is struck through on screen and a stroke
// needs its two ends in order -- which cellsOf() would give back sorted,
// turning every diagonal into whichever direction the bit order happens to be.
var LINES = (function () {
  var groups = [[0,1,2],[3,4,5],[6,7,8],[0,3,6],[1,4,7],[2,5,8],[0,4,8],[2,4,6]]
  var out = []
  for (var i = 0; i < groups.length; i++)
    out.push({ mask: maskOf(groups[i]), squares: groups[i] })
  return out
})()

var CENTRE = 4
var CORNERS = [0, 2, 6, 8]
var EDGES = [1, 3, 5, 7]

function wonLine(marks) {
  for (var i = 0; i < LINES.length; i++)
    if ((marks & LINES[i].mask) === LINES[i].mask) return LINES[i].squares
  return null
}

function popcount(x) {
  var n = 0
  for (var i = 0; i < CELLS; i++) if ((x >> i) & 1) n += 1
  return n
}

// --- a position --------------------------------------------------------------

function position(x, o, turn) {
  return { x: x || 0, o: o || 0, turn: turn === undefined ? CROSS : turn }
}

var EMPTY = position(0, 0, CROSS)

function own(p) { return p.turn === CROSS ? p.x : p.o }
function opp(p) { return p.turn === CROSS ? p.o : p.x }
function marksOf(p, mark) { return mark === CROSS ? p.x : p.o }
function occupied(p) { return p.x | p.o }
function played(p) { return popcount(occupied(p)) }

// A won board has no legal moves on it even though it has empty squares, and
// saying so here is what stops the rest of the app from having to ask two
// questions where one will do.
function moves(p) {
  if (winner(p) !== null) return 0
  return FULL & ~occupied(p)
}

function legal(p) { return cellsOf(moves(p)) }
function isLegal(p, cell) { return cell >= 0 && cell < CELLS && !!(moves(p) & (1 << cell)) }

function play(p, cell) {
  var placed = own(p) | (1 << cell)
  return p.turn === CROSS ? position(placed, p.o, NOUGHT) : position(p.x, placed, CROSS)
}

// Both sides are tested rather than only the one that just moved: this is asked
// of positions that arrive from a file as well as from a move, and a file is
// not a promise about which side made the last mark.
function winner(p) {
  for (var i = 0; i < MARKS.length; i++)
    if (wonLine(marksOf(p, MARKS[i])) !== null) return MARKS[i]
  return null
}

function winningLine(p) {
  var w = winner(p)
  return w === null ? [] : (wonLine(marksOf(p, w)) || [])
}

function isFull(p) { return occupied(p) === FULL }
function isOver(p) { return winner(p) !== null || isFull(p) }

// The empty squares that would give `mark` three in a row at once.
function winsNow(p, mark) {
  var out = []
  var mine = marksOf(p, mark)
  var empty = FULL & ~occupied(p)
  for (var i = 0; i < CELLS; i++) {
    if (!((empty >> i) & 1)) continue
    if (wonLine(mine | (1 << i)) !== null) out.push(i)
  }
  return out
}

function replay(moveList) {
  var p = EMPTY
  for (var i = 0; i < moveList.length; i++) {
    if (!isLegal(p, moveList[i])) break
    p = play(p, moveList[i])
  }
  return p
}

// --- the game, solved --------------------------------------------------------

var WIN = 10
var DRAW = 0

var LEVELS = [
  { key: "easy", label: "Easy",
    blurb: "Takes a win it is given. Will not see yours coming.",
    careless: 0.80, takesWins: true, blocks: false },
  { key: "fair", label: "Fair",
    blurb: "Blocks what it can see. Misses about one turn in five.",
    careless: 0.22, takesWins: true, blocks: true },
  { key: "perfect", label: "Perfect",
    blurb: "Cannot be beaten. A draw is a result against this one.",
    careless: 0.0, takesWins: true, blocks: true }
]

var LEVEL_KEYS = ["easy", "fair", "perfect"]
var DEFAULT_LEVEL = "fair"

function levelFor(key) {
  for (var i = 0; i < LEVELS.length; i++) if (LEVELS[i].key === key) return LEVELS[i]
  return LEVELS[1]
}

// (x, o, turn) -> value to the side to move. A module global rather than
// per-search state because it describes the rules and not a game: it is correct
// for every game this process plays, and filling it once is the difference
// between a first move that takes a moment and every first move taking one.
var SOLVED = ({})

function key(p) { return p.x + "," + p.o + "," + p.turn }

// What this position is worth to the side about to move, played out.
//
// Exact. There is no horizon and no evaluation: the recursion bottoms out on a
// finished board every time, because the board fills in at most nine plies.
function value(p) {
  var k = key(p)
  var cached = SOLVED[k]
  if (cached !== undefined) return cached

  var result
  var w = winner(p)
  if (w !== null) {
    // Whoever is to move is the one who did not just make three in a row.
    result = -(WIN + CELLS - played(p))
  } else if (isFull(p)) {
    result = DRAW
  } else {
    var options = legal(p)
    result = -Infinity
    for (var i = 0; i < options.length; i++) {
      var score = -value(play(p, options[i]))
      if (score > result) result = score
    }
  }
  SOLVED[k] = result
  return result
}

// Every legal move and what it is worth. The whole opponent, really.
function scored(p) {
  var out = ({})
  var options = legal(p)
  for (var i = 0; i < options.length; i++) out[options[i]] = -value(play(p, options[i]))
  return out
}

// How many replies to this move would lose for the player replying.
//
// The tie-break among equally good moves, and the only thing separating Perfect
// from any other correct player. Between two perfect players this game is drawn
// from the empty board, so a solver with nothing but the result to go on has no
// reason to prefer any drawing move to any other -- and against a person on a
// bus there is every reason to prefer the one with the most ways to go wrong.
function mistakesAllowed(p, cell) {
  var after = scored(play(p, cell))
  var n = 0
  for (var k in after) if (after[k] < DRAW) n += 1
  return n
}

// The optimal moves, in the order a perfect player would prefer them.
function best(p) {
  var values = scored(p)
  var cells = []
  for (var k in values) cells.push(parseInt(k, 10))
  if (!cells.length) return []
  var top = -Infinity
  for (var i = 0; i < cells.length; i++) if (values[cells[i]] > top) top = values[cells[i]]
  var tied = []
  for (var j = 0; j < cells.length; j++) if (values[cells[j]] === top) tied.push(cells[j])
  tied.sort(function (a, b) {
    return (mistakesAllowed(p, b) - mistakesAllowed(p, a)) || (a - b)
  })
  return tied
}

// A move played without thinking about it, to the depth the level allows.
//
// Deliberately not "a random legal move". An opponent that sometimes fails to
// take a win it has been handed does not read as easy, it reads as broken --
// the board says three in a row is there and the app did not take it. Missing
// *your* threat is the thing that reads as not concentrating, and it is the
// only thing Easy is actually allowed to miss.
function careless(p, level, pick) {
  if (level.takesWins) {
    var mine = winsNow(p, p.turn)
    if (mine.length) return pick(mine)
  }
  if (level.blocks) {
    var theirs = winsNow(p, other(p.turn))
    if (theirs.length) return pick(theirs)
  }
  return pick(legal(p))
}

// The computer's move, or -1 on a board with no moves left in it.
//
// `pick` and `chance` are arguments for the same reason ai.py takes an rng: a
// test that cannot hold the dice still is a test that fails one run in five.
function choose(p, level, pick, chance) {
  var options = legal(p)
  if (!options.length) return -1
  if (options.length === 1) {
    // Nobody waits for a move they had no choice about, and on this board that
    // is the ninth square of every drawn game.
    return options[0]
  }
  var roll = chance || Math.random
  var take = pick || function (list) { return list[Math.floor(Math.random() * list.length)] }
  if (level.careless && roll() < level.careless) return careless(p, level, take)
  return best(p)[0]
}

// Solve the game. Returns the number of positions, which is what the Python
// returns for its own tests.
function warm() {
  value(EMPTY)
  var n = 0
  for (var k in SOLVED) n += 1
  return n
}

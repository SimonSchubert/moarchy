// Minesweeper: a portrait board, a latching flag, and a game replayed from a
// seed and a list of taps.
//
// The port of apps/minesweeper/moarchy_minesweeper/minesweeper.py. Nothing
// stores a minefield: the file holds the level, the seed and every tap, and the
// board is rebuilt from them. That is only safe while both halves lay the mines
// identically, which is what Random.js is for.
.pragma library
.import "Random.js" as Rand

var OPEN = 0
var FLAG = 1
var CHORD = 2
var ACTIONS = 3

// Shaped for a phone rather than a desktop. The classic three are 9x9, 16x16
// and 30x16, and the last is twice as wide as a phone screen -- so these are
// taller than they are wide, with the column count chosen so a cell never falls
// below 28px on a 360px screen. The densities are the classic ones: about one
// cell in eight, one in six, one in five.
var LEVELS = [
  { key: "gentle", label: "Gentle", width: 8, height: 10, mines: 10 },
  { key: "standard", label: "Standard", width: 10, height: 13, mines: 22 },
  { key: "hard", label: "Hard", width: 12, height: 16, mines: 40 }
]

var LEVEL_KEYS = ["gentle", "standard", "hard"]
var DEFAULT_LEVEL = "standard"

function levelFor(key) {
  for (var i = 0; i < LEVELS.length; i++) if (LEVELS[i].key === key) return LEVELS[i]
  return LEVELS[1]
}

function cellCount(level) { return level.width * level.height }

function rowOf(cell, width) { return Math.floor(cell / width) }
function columnOf(cell, width) { return cell % width }
function index(row, column, width) { return row * width + column }

// The eight cells touching this one, minus whatever is off the board.
function around(cell, width, height) {
  var row = rowOf(cell, width), column = columnOf(cell, width)
  var out = []
  for (var dr = -1; dr <= 1; dr++) {
    for (var dc = -1; dc <= 1; dc++) {
      if (dr === 0 && dc === 0) continue
      var r = row + dr, c = column + dc
      if (r >= 0 && r < height && c >= 0 && c < width) out.push(index(r, c, width))
    }
  }
  return out
}

// Fisher-Yates on top of random(), and nothing else.
//
// Written out rather than calling a shuffle helper for the reason minesweeper.py
// gives: the saved game is a seed, so a layout has to come back the same in six
// months and on another machine. The stream is promised; a library's shuffle is
// not, in either language.
function shuffled(items, rng) {
  var out = items.slice()
  for (var at = out.length - 1; at > 0; at--) {
    var swap = Math.floor(Rand.random(rng) * (at + 1))
    var tmp = out[at]; out[at] = out[swap]; out[swap] = tmp
  }
  return out
}

// Where the mines go, once the first tap has said where they may not.
//
// The first cell and all eight around it are excluded, so the first tap always
// opens a space and floods outward. On a board where the mines would not fit in
// what is left -- which no shipped level comes near -- the exclusion narrows to
// the tapped cell alone rather than failing.
function place(level, seed, first) {
  var forbidden = ({})
  forbidden[first] = true
  var near = around(first, level.width, level.height)
  for (var i = 0; i < near.length; i++) forbidden[near[i]] = true

  var total = cellCount(level)
  var available = []
  for (var c = 0; c < total; c++) if (!forbidden[c]) available.push(c)
  if (available.length < level.mines) {
    available = []
    for (var d = 0; d < total; d++) if (d !== first) available.push(d)
  }
  var picked = shuffled(available, Rand.create(seed)).slice(0, level.mines)
  var mines = ({})
  for (var m = 0; m < picked.length; m++) mines[picked[m]] = true
  return mines
}

function isMine(game, cell) { return !!(game.mines && game.mines[cell]) }

function neighbourCount(game, cell) {
  var near = around(cell, game.level.width, game.level.height)
  var n = 0
  for (var i = 0; i < near.length; i++) if (isMine(game, near[i])) n += 1
  return n
}

// --- a game ------------------------------------------------------------------

function create(level, seed, moveList) {
  var game = {
    level: level, seed: seed, moves: [],
    mines: null,           // null until the first tap says where they may not be
    opened: ({}), flags: ({}), boom: -1
  }
  var list = moveList || []
  for (var i = 0; i < list.length; i++) applyMove(game, list[i])
  return game
}

function encode(cell, action) { return cell * ACTIONS + action }
function decode(move) {
  return { cell: Math.floor(move / ACTIONS), action: move % ACTIONS }
}

function applyMove(game, move) {
  if (move < 0) return false
  var d = decode(move)
  if (d.cell < 0 || d.cell >= cellCount(game.level)) return false
  if (d.action < 0 || d.action >= ACTIONS) return false
  if (isOver(game)) return false
  var changed = d.action === OPEN ? openCell(game, d.cell)
              : d.action === FLAG ? flagCell(game, d.cell)
              : chord(game, d.cell)
  if (!changed) return false
  game.moves.push(move)
  return true
}

function tap(game, cell) { return applyMove(game, encode(cell, OPEN)) }
function mark(game, cell) { return applyMove(game, encode(cell, FLAG)) }
function clearAround(game, cell) { return applyMove(game, encode(cell, CHORD)) }

function openCell(game, cell) {
  // A flagged cell is not opened by a tap, and that is not a convenience: the
  // flag is there precisely to stop the tap that is about to happen by accident.
  if (game.opened[cell] || game.flags[cell]) return false
  if (game.mines === null) game.mines = place(game.level, game.seed, cell)
  if (isMine(game, cell)) {
    game.opened[cell] = true
    game.boom = cell
    return true
  }
  flood(game, cell)
  return true
}

// Open this cell, and everything an empty one leads to.
//
// Iterative rather than recursive. A first tap on a gentle board opens forty
// cells and on a hard one can open a hundred and fifty, and a recursion that
// deep is a stack nobody needs to spend.
function flood(game, cell) {
  var stack = [cell]
  while (stack.length) {
    var here = stack.pop()
    if (game.opened[here] || game.flags[here]) continue
    game.opened[here] = true
    if (neighbourCount(game, here) === 0) {
      var near = around(here, game.level.width, game.level.height)
      for (var i = 0; i < near.length; i++)
        if (!game.opened[near[i]]) stack.push(near[i])
    }
  }
}

function flagCell(game, cell) {
  if (game.opened[cell]) return false
  if (game.flags[cell]) delete game.flags[cell]
  else game.flags[cell] = true
  return true
}

// Open everything round a number that already has its flags.
//
// The move that makes this game playable at speed, and playable at all on a
// 28px cell. It opens nothing when the flags do not add up -- which is not
// politeness, it is the difference between a move and a gamble, and a gamble
// that ends the game is not something a thumb should be able to do by resting
// on a number.
function chord(game, cell) {
  if (game.mines === null || !game.opened[cell]) return false
  var wanted = neighbourCount(game, cell)
  if (wanted === 0) return false
  var near = around(cell, game.level.width, game.level.height)
  var flagged = 0
  for (var i = 0; i < near.length; i++) if (game.flags[near[i]]) flagged += 1
  if (flagged !== wanted) return false
  var shut = []
  for (var j = 0; j < near.length; j++)
    if (!game.flags[near[j]] && !game.opened[near[j]]) shut.push(near[j])
  if (!shut.length) return false
  for (var k = 0; k < shut.length; k++) {
    if (isMine(game, shut[k])) {
      game.opened[shut[k]] = true
      game.boom = shut[k]
      return true
    }
    flood(game, shut[k])
  }
  return true
}

// --- how it is going ---------------------------------------------------------

function started(game) { return game.mines !== null }
function boomOf(game) { return game.boom }
function lost(game) { return game.boom >= 0 }

function openedCount(game) {
  var n = 0
  for (var k in game.opened) n += 1
  return n
}

function flagCount(game) {
  var n = 0
  for (var k in game.flags) n += 1
  return n
}

function won(game) {
  if (game.mines === null || lost(game)) return false
  return openedCount(game) === cellCount(game.level) - game.level.mines
}

function isOver(game) { return lost(game) || won(game) }

// Mines minus flags. It can go negative, and it is allowed to: clamping it at
// zero would hide the most useful thing it ever says.
function remaining(game) { return game.level.mines - flagCount(game) }

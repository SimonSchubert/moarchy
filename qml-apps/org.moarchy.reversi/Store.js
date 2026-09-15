// The saved game, in the shape apps/reversi/moarchy_reversi/store.py writes.
//
// The board is not stored: the move list is, and the position is replayed from
// it. That is what makes a saved game a handful of small numbers, makes undo a
// subtraction, and makes a file written by either half readable by the other.
.pragma library

var SCHEMA = 1
var DARK = 0
var LIGHT = 1
var LEVEL_KEYS = ["easy", "medium", "hard"]
var DEFAULT_LEVEL = "medium"

function parse(data) {
  var out = {
    mode: "computer", level: DEFAULT_LEVEL, human: DARK,
    finished: false, moves: [], stats: ({})
  }
  if (!data || typeof data !== "object") return out
  var game = data.game
  if (game && typeof game === "object") {
    if (typeof game.mode === "string") out.mode = game.mode
    if (LEVEL_KEYS.indexOf(game.level) >= 0) out.level = game.level
    out.human = game.human === "light" ? LIGHT : DARK
    out.finished = !!game.finished
    var moves = game.moves
    if (moves && moves.constructor === Array) {
      for (var i = 0; i < moves.length; i++) {
        var cell = moves[i]
        // -1 is a pass and is a legal entry; anything off the board is a file
        // that has been edited by hand or truncated, and the game stops there
        // rather than replaying nonsense.
        if (typeof cell !== "number" || cell < -1 || cell > 63) break
        out.moves.push(Math.round(cell))
      }
    }
  }
  if (data.stats && typeof data.stats === "object") out.stats = data.stats
  return out
}

function serialize(game) {
  return JSON.stringify({
    schema: SCHEMA,
    game: {
      mode: game.mode || "computer",
      level: game.level || DEFAULT_LEVEL,
      human: game.human === LIGHT ? "light" : "dark",
      finished: !!game.finished,
      moves: game.moves || []
    },
    stats: game.stats || ({})
  }, null, 1)
}

// Win, loss and draw counts, keyed the way store.py keys them.
function record(stats, outcome) {
  var out = ({})
  for (var k in stats) out[k] = stats[k]
  out[outcome] = (out[outcome] || 0) + 1
  return out
}

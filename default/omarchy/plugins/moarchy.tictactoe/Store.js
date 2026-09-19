// The saved game, in the shape store.py writes: the move list, not the board.
.pragma library

var SCHEMA = 1
var CROSS = 0
var NOUGHT = 1
var LEVEL_KEYS = ["easy", "fair", "perfect"]
var DEFAULT_LEVEL = "fair"

function parse(data) {
  var out = { mode: "solo", level: DEFAULT_LEVEL, mark: CROSS, finished: false,
              recorded: false, moves: [], series: ({}), stats: ({}) }
  if (!data || typeof data !== "object") return out
  var game = data.game
  if (game && typeof game === "object") {
    if (typeof game.mode === "string") out.mode = game.mode
    if (LEVEL_KEYS.indexOf(game.level) >= 0) out.level = game.level
    // `mark` is which side the person plays, and "x"/"o" is how store.py
    // writes it -- not a boolean and not a number, so that a file stays
    // readable by a person.
    out.mark = game.mark === "o" ? NOUGHT : CROSS
    out.finished = !!game.finished
    out.recorded = !!game.recorded
    var moves = game.moves
    if (moves && moves.constructor === Array) {
      for (var i = 0; i < moves.length; i++) {
        var cell = moves[i]
        // A square off the board is a file edited by hand or truncated; the
        // game stops there rather than replaying nonsense.
        if (typeof cell !== "number" || cell < 0 || cell > 8) break
        out.moves.push(Math.round(cell))
      }
    }
  }
  if (data.series && typeof data.series === "object") out.series = data.series
  if (data.stats && typeof data.stats === "object") out.stats = data.stats
  return out
}

function serialize(game) {
  return JSON.stringify({
    schema: SCHEMA,
    game: {
      mode: game.mode || "solo",
      level: game.level || DEFAULT_LEVEL,
      mark: game.mark === NOUGHT ? "o" : "x",
      finished: !!game.finished,
      recorded: !!game.recorded,
      moves: game.moves || []
    },
    series: game.series || ({}),
    stats: game.stats || ({})
  }, null, 1)
}

function record(stats, outcome) {
  var out = ({})
  for (var k in stats) out[k] = stats[k]
  out[outcome] = (out[outcome] || 0) + 1
  return out
}

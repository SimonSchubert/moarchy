// The saved game, in the shape store.py writes: a level, a seed and the taps.
.pragma library

var SCHEMA = 1
var LEVEL_KEYS = ["gentle", "standard", "hard"]
var DEFAULT_LEVEL = "standard"

function parse(data) {
  var out = { level: DEFAULT_LEVEL, seed: 0, seconds: 0, finished: false,
              recorded: false, moves: [], stats: ({}) }
  if (!data || typeof data !== "object") return out
  var game = data.game
  if (game && typeof game === "object") {
    if (LEVEL_KEYS.indexOf(game.level) >= 0) out.level = game.level
    if (typeof game.seed === "number" && isFinite(game.seed)) out.seed = Math.floor(game.seed)
    if (typeof game.seconds === "number" && isFinite(game.seconds))
      out.seconds = Math.max(0, game.seconds)
    out.finished = !!game.finished
    out.recorded = !!game.recorded
    var moves = game.moves
    if (moves && moves.constructor === Array) {
      for (var i = 0; i < moves.length; i++) {
        var move = moves[i]
        // A move out of range is a file edited by hand or truncated; the replay
        // stops there rather than rebuilding a board nobody played.
        if (typeof move !== "number" || move < 0) break
        out.moves.push(Math.round(move))
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
      level: game.level || DEFAULT_LEVEL,
      seed: game.seed || 0,
      seconds: game.seconds || 0,
      finished: !!game.finished,
      recorded: !!game.recorded,
      moves: game.moves || []
    },
    stats: game.stats || ({})
  }, null, 1)
}

function record(stats, key, value) {
  var out = ({})
  for (var k in stats) out[k] = stats[k]
  out[key] = value
  return out
}

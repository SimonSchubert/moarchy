// The sum that was half typed when the phone took the app away.
//
// One small JSON file, and the argument for it is the argument for the app. A
// desktop calculator is a window you leave open; a phone calculator is a thing
// you are holding when somebody rings, and what happens next is that the
// compositor reclaims the app without asking. Coming back to a blank screen is
// what makes a phone calculator annoying, and the fix is not a setting, it is
// a file with two fields in it.
//
// Both are written as text. `0.1` is one thing in decimal and another once JSON
// has been through a double, and the whole point of the arithmetic here is not
// letting that happen.
//
// `answered` is the second field, and it is stored rather than worked out
// because it cannot be: the entry comes back either from `=` -- in which case
// it is an answer, and the next digit starts a new sum -- or from the window
// going away mid-sum, in which case it is a number being typed and the next
// digit belongs on the end of it. Both look like `1428` in a file.
.pragma library

var SCHEMA = 1

function parse(data) {
  var out = { entry: "", answered: false }
  if (!data || typeof data !== "object") return out
  if (typeof data.entry === "string") out.entry = data.entry
  out.answered = !!data.answered
  return out
}

function serialize(state) {
  return JSON.stringify({
    schema: SCHEMA,
    entry: String(state.entry || ""),
    answered: !!state.answered
  }, null, 1)
}

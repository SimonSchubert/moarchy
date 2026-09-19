// How the app talks to moarchy-mail: one process per request, the request on
// stdin and the answer as the last line of stdout.
//
// Through sh, so that a helper which is not installed is still an answer -- an
// exit of 127 -- rather than a Process that never started and a spinner that
// never stops.
.pragma library

function command(helper, verb) {
  return ["sh", "-c", "exec \"$0\" \"$1\"", String(helper), String(verb)]
}

function lastLine(text) {
  var lines = String(text || "").split("\n")
  for (var i = lines.length - 1; i >= 0; i--)
    if (lines[i].trim().length) return lines[i].trim()
  return ""
}

function result(code, stdout, stderr) {
  var line = lastLine(stdout)
  if (line) {
    try {
      var answer = JSON.parse(line)
      if (answer && typeof answer === "object" && typeof answer.ok === "boolean") return answer
    } catch (e) {}
  }
  if (code === 127)
    return { ok: false, kind: "missing", error: "moarchy-mail is not installed, so Mail cannot reach a server." }
  var said = lastLine(stderr)
  return {
    ok: false,
    kind: "bug",
    error: said ? "moarchy-mail failed: " + said : "moarchy-mail stopped without an answer."
  }
}

// Kinds of failure a person could not have done anything about in this
// window, and that a background refresh should not interrupt them with.
function quiet(answer) {
  return !!answer && !answer.ok && (answer.kind === "offline" || answer.kind === "network")
}

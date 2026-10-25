// The one TOML reader the shell has (docs/home.md HM30).
//
//     import "../moarchy.common/Toml.js" as Toml
//
//     var r = Toml.parse(text)       // { ok: true, data: {...} } or
//                                    // { ok: false, data: {...}, line: 7, error: "..." }
//     Toml.get(r.data, "home.opacity", 0.88)
//
// `.pragma library`, so there is one instance, and it reaches nothing: the text
// is handed in, which is what lets `node scripts/toml-test.js` run it without a
// phone (the shape Sheet.js and Edge.js already have).
//
// The subset is what this project's files use, and it is real TOML within it:
// comments, bare and quoted keys, dotted keys, `[table]`, `[a.b]`,
// `[[array of tables]]`, basic and literal strings with escapes, integers,
// floats, booleans, arrays (over several lines, trailing comma allowed) and
// inline tables. Dates and multi-line strings are not, and say so by line.
//
// It stops at the first error and returns what it read up to there as `data`,
// so a caller can choose. Every caller in this tree chooses the same thing --
// keep what was on screen (HM16) -- but a parser that threw the partial read
// away would have made that a choice nobody could make.
.pragma library

function parse(text) {
  var data = {}
  var current = data
  var src = String(text || "")
  var i = 0
  var line = 1

  function fail(msg) {
    var e = new Error(msg)
    e.tomlLine = line
    throw e
  }

  function peek() { return src.charAt(i) }

  function skipSpaces() {
    while (i < src.length && (src[i] === " " || src[i] === "\t")) i++
  }

  // Spaces, newlines and comments: what may sit between the items of an array.
  function skipBlank() {
    for (;;) {
      skipSpaces()
      var c = peek()
      if (c === "#") { while (i < src.length && src[i] !== "\n") i++; continue }
      if (c === "\r") { i++; continue }
      if (c === "\n") { i++; line++; continue }
      return
    }
  }

  function endOfLine() {
    skipSpaces()
    if (peek() === "#") while (i < src.length && src[i] !== "\n") i++
    if (peek() === "\r") i++
    if (i < src.length && peek() !== "\n") fail("expected the end of the line, found '" + peek() + "'")
  }

  function bareKey() {
    var start = i
    while (i < src.length && /[A-Za-z0-9_-]/.test(src[i])) i++
    if (i === start) fail("expected a key")
    return src.slice(start, i)
  }

  function oneKey() {
    var c = peek()
    if (c === "\"") return basicString()
    if (c === "'") return literalString()
    return bareKey()
  }

  // a.b."c d" -> ["a", "b", "c d"]
  function keyPath() {
    var parts = []
    for (;;) {
      skipSpaces()
      parts.push(oneKey())
      skipSpaces()
      if (peek() !== ".") return parts
      i++
    }
  }

  function basicString() {
    i++ // "
    var out = ""
    for (;;) {
      if (i >= src.length || src[i] === "\n") fail("unterminated string")
      var c = src[i++]
      if (c === "\"") return out
      if (c !== "\\") { out += c; continue }
      var e = src[i++]
      if (e === "n") out += "\n"
      else if (e === "t") out += "\t"
      else if (e === "r") out += "\r"
      else if (e === "\"") out += "\""
      else if (e === "\\") out += "\\"
      else if (e === "u" || e === "U") {
        var n = e === "u" ? 4 : 8
        var hex = src.substr(i, n)
        if (!/^[0-9A-Fa-f]+$/.test(hex) || hex.length !== n) fail("bad \\" + e + " escape")
        out += String.fromCodePoint(parseInt(hex, 16))
        i += n
      } else fail("unknown escape \\" + e)
    }
  }

  function literalString() {
    i++ // '
    var start = i
    while (i < src.length && src[i] !== "'" && src[i] !== "\n") i++
    if (src[i] !== "'") fail("unterminated string")
    var s = src.slice(start, i)
    i++
    return s
  }

  function array() {
    i++ // [
    var out = []
    for (;;) {
      skipBlank()
      if (peek() === "]") { i++; return out }
      out.push(value())
      skipBlank()
      if (peek() === ",") { i++; continue }
      if (peek() === "]") { i++; return out }
      fail("expected ',' or ']' in an array")
    }
  }

  function inlineTable() {
    i++ // {
    var out = {}
    skipSpaces()
    if (peek() === "}") { i++; return out }
    for (;;) {
      var path = keyPath()
      skipSpaces()
      if (peek() !== "=") fail("expected '=' after a key")
      i++
      skipSpaces()
      assign(out, path, value())
      skipSpaces()
      if (peek() === ",") { i++; skipSpaces(); continue }
      if (peek() === "}") { i++; return out }
      fail("expected ',' or '}' in an inline table")
    }
  }

  function scalar() {
    var start = i
    while (i < src.length && /[A-Za-z0-9_+.:-]/.test(src[i])) i++
    var word = src.slice(start, i)
    if (word === "true") return true
    if (word === "false") return false
    if (word === "inf" || word === "+inf") return Infinity
    if (word === "-inf") return -Infinity
    if (word === "nan" || word === "+nan" || word === "-nan") return NaN
    var clean = word.replace(/_/g, "")
    if (/^[+-]?(0|[1-9][0-9]*)$/.test(clean)) return parseInt(clean, 10)
    if (/^0x[0-9A-Fa-f]+$/.test(clean)) return parseInt(clean.slice(2), 16)
    if (/^0o[0-7]+$/.test(clean)) return parseInt(clean.slice(2), 8)
    if (/^0b[01]+$/.test(clean)) return parseInt(clean.slice(2), 2)
    if (/^[+-]?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$/.test(clean)) return parseFloat(clean)
    if (word === "") fail("expected a value")
    if (/^\d{4}-\d{2}-\d{2}/.test(word)) fail("dates are not supported here")
    fail("'" + word + "' is not a value (a string needs quotes)")
  }

  function value() {
    var c = peek()
    if (c === "\"") {
      if (src.substr(i, 3) === "\"\"\"") fail("multi-line strings are not supported here")
      return basicString()
    }
    if (c === "'") {
      if (src.substr(i, 3) === "'''") fail("multi-line strings are not supported here")
      return literalString()
    }
    if (c === "[") return array()
    if (c === "{") return inlineTable()
    return scalar()
  }

  function isTable(v) {
    return v !== null && typeof v === "object" && !Array.isArray(v)
  }

  function assign(table, path, v) {
    var t = table
    for (var k = 0; k < path.length - 1; k++) {
      if (t[path[k]] === undefined) t[path[k]] = {}
      else if (!isTable(t[path[k]])) fail("'" + path[k] + "' is already a value")
      t = t[path[k]]
    }
    var last = path[path.length - 1]
    if (t[last] !== undefined) fail("'" + path.join(".") + "' is set twice")
    t[last] = v
  }

  // [a.b] walks into (or creates) tables; through an array of tables it walks
  // into the last element, which is what TOML means by [page.extra] after
  // [[page]].
  function walk(path, upTo) {
    var t = data
    for (var k = 0; k < upTo; k++) {
      var v = t[path[k]]
      if (v === undefined) { v = {}; t[path[k]] = v }
      if (Array.isArray(v)) {
        if (v.length === 0 || !isTable(v[v.length - 1])) fail("'" + path[k] + "' is not a table")
        v = v[v.length - 1]
      } else if (!isTable(v)) fail("'" + path[k] + "' is already a value")
      t = v
    }
    return t
  }

  try {
    for (;;) {
      skipBlank()
      if (i >= src.length) break
      if (peek() === "[") {
        var double = src.charAt(i + 1) === "["
        i += double ? 2 : 1
        var path = keyPath()
        if (double) {
          if (src.substr(i, 2) !== "]]") fail("expected ']]'")
          i += 2
          var parent = walk(path, path.length - 1)
          var name = path[path.length - 1]
          if (parent[name] === undefined) parent[name] = []
          if (!Array.isArray(parent[name])) fail("'" + path.join(".") + "' is not an array of tables")
          var fresh = {}
          parent[name].push(fresh)
          current = fresh
        } else {
          if (peek() !== "]") fail("expected ']'")
          i++
          current = walk(path, path.length)
        }
        endOfLine()
        continue
      }
      var keys = keyPath()
      skipSpaces()
      if (peek() !== "=") fail("expected '=' after '" + keys.join(".") + "'")
      i++
      skipSpaces()
      assign(current, keys, value())
      endOfLine()
    }
  } catch (e) {
    return { ok: false, data: data, line: e.tomlLine || line, error: e.message }
  }
  return { ok: true, data: data, line: 0, error: "" }
}

// The forgiving read every file in this tree had before parse() existed: one
// `key = value` per line, sections tracked, quotes optional. It is what a
// hand-edited `corners = large` -- not TOML, and read happily for a year --
// still means (HM29), so a caller whose strict parse failed can fall back to it
// rather than to the defaults. Arrays and inline tables are not understood
// here; a file that needs them needs parse().
function flat(text) {
  var data = {}
  var current = data
  var lines = String(text || "").split("\n")
  for (var n = 0; n < lines.length; n++) {
    var l = lines[n].replace(/\s+#.*$/, "").trim()
    if (!l || l[0] === "#") continue
    var head = /^\[\s*([A-Za-z0-9_.-]+)\s*\]$/.exec(l)
    if (head) {
      current = data
      var parts = head[1].split(".")
      for (var p = 0; p < parts.length; p++) {
        if (current[parts[p]] === null || typeof current[parts[p]] !== "object") current[parts[p]] = {}
        current = current[parts[p]]
      }
      continue
    }
    var eq = l.indexOf("=")
    if (eq < 1) continue
    var key = l.slice(0, eq).trim()
    var raw = l.slice(eq + 1).trim()
    if ((raw[0] === "\"" && raw[raw.length - 1] === "\"") ||
        (raw[0] === "'" && raw[raw.length - 1] === "'"))
      raw = raw.slice(1, -1)
    current[key] = raw
  }
  return data
}

// A value by dotted path, or `fallback` when any step of it is missing. Never
// throws: a file that has a key where a table was expected is a file that does
// not have the setting.
function get(data, path, fallback) {
  var parts = String(path).split(".")
  var t = data
  for (var k = 0; k < parts.length; k++) {
    if (t === null || typeof t !== "object" || Array.isArray(t)) return fallback
    t = t[parts[k]]
    if (t === undefined) return fallback
  }
  return t
}

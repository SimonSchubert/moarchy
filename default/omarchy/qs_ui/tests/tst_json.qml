// Absent, corrupt and fine are three different things, and only one of them
// may be overwritten without a copy being kept first.
//
// Json.js is the decision; JsonFile.qml is the twenty lines that act on it.
// Keeping them apart is what lets the decision be tested with no compositor,
// no window and no file on disk.
import QtQuick
import QtTest
import "../Json.js" as Json

TestCase {
  name: "Json"

  function test_an_absent_or_blank_file_is_empty_not_corrupt_data() {
    return [
      { tag: "empty string", raw: "" },
      { tag: "whitespace", raw: "   \n\t " },
      { tag: "null", raw: null },
      { tag: "undefined", raw: undefined }
    ]
  }
  function test_an_absent_or_blank_file_is_empty_not_corrupt(row) {
    compare(Json.classify(row.raw).state, Json.EMPTY)
  }

  function test_an_object_parses() {
    var v = Json.classify("{\"schema\":1,\"favourites\":[\"falcon\"]}")
    compare(v.state, Json.OK)
    compare(v.data.favourites.length, 1)
    compare(v.data.favourites[0], "falcon")
  }

  function test_truncated_json_is_corrupt() {
    // What a half-written file looks like, which is the case the quarantine
    // exists for.
    compare(Json.classify("{\"schema\":1,\"favou").state, Json.CORRUPT)
  }

  function test_valid_json_that_is_not_an_object_is_still_corrupt_data() {
    return [
      { tag: "array", raw: "[]" },
      { tag: "number", raw: "12" },
      { tag: "null literal", raw: "null" },
      { tag: "string", raw: "\"notes\"" },
      { tag: "bool", raw: "true" }
    ]
  }
  function test_valid_json_that_is_not_an_object_is_still_corrupt(row) {
    // Every store here writes an object at the top level, so a bare array or
    // number is a file that is not ours -- overwriting it is the thing to
    // avoid.
    compare(Json.classify(row.raw).state, Json.CORRUPT)
  }

  function test_the_quarantine_name_is_pythons_with_suffix() {
    compare(Json.brokenPath("/home/moarchy/.local/share/moarchy-keep/notes.json", 1757930000),
            "/home/moarchy/.local/share/moarchy-keep/notes.broken-1757930000.json")
  }

  function test_a_fractional_clock_still_names_an_integer_second() {
    // Date.now()/1000 is fractional; Python's int(time.time()) is not.
    compare(Json.brokenPath("/x/notes.json", 1757930000.9137), "/x/notes.broken-1757930000.json")
  }

  function test_a_dot_in_a_directory_name_is_not_a_suffix() {
    // moarchy.keep is a plugin id and appears in paths; chopping at the
    // last dot of the whole string would mangle a file with no extension.
    compare(Json.brokenPath("/usr/share/moarchy/plugins/moarchy.keep/state", 5),
            "/usr/share/moarchy/plugins/moarchy.keep/state.broken-5.json")
  }
}

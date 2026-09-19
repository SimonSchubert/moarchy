// The file, which is about the view and never about anybody's files.
import QtQuick
import QtTest
import "../Store.js" as Store

TestCase {
  name: "Store"

  function test_a_view_goes_out_and_comes_back() {
    var back = Store.parse(JSON.parse(
      Store.serialize("modified", true, "/home/simon/Pictures")))
    compare(back.sort, "modified")
    compare(back.hidden, true)
    compare(back.path, "/home/simon/Pictures")
    compare(JSON.parse(Store.serialize("name", false, "")).schema, Store.SCHEMA)
  }

  function test_a_file_from_somewhere_else_does_not_decide_the_sort() {
    compare(Store.parse({ sort: "colour" }).sort, "name")
    compare(Store.parse({ sort: 7 }).sort, "name")
    compare(Store.parse({ hidden: "yes" }).hidden, false)
    compare(Store.parse(null).sort, "name")
    compare(Store.parse({}).path, "")
  }

  function test_a_folder_is_only_remembered_when_it_is_one() {
    // The empty string would come back as a folder called "" and send the app
    // to the root on the next start.
    compare(JSON.parse(Store.serialize("name", false, "")).path, undefined)
    compare(JSON.parse(Store.serialize("name", false, "Pictures")).path, undefined)
    compare(Store.parse({ path: "Pictures" }).path, "")
    compare(Store.parse({ path: "/home/simon//Pictures/" }).path,
            "/home/simon/Pictures")
  }
}

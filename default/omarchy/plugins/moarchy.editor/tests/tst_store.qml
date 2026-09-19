import QtQuick
import QtTest
import "../Store.js" as Store

TestCase {
  name: "Store"

  function test_nothing_on_disk_is_a_first_run() {
    compare(Store.parse(null).recent.length, 0)
    compare(Store.parse(null).wrap, true)
    compare(Store.parse({ recent: "nonsense" }).recent.length, 0)
  }

  function test_the_list_goes_out_and_comes_back() {
    var s = { recent: Store.touch([], "/home/m/a.txt", 100), wrap: false }
    var back = Store.parse(JSON.parse(Store.serialize(s)))
    compare(back.wrap, false)
    compare(back.recent.length, 1)
    compare(back.recent[0].path, "/home/m/a.txt")
    compare(back.recent[0].opened, 100)
  }

  function test_opening_again_moves_a_file_to_the_top() {
    var list = Store.touch([], "/a", 1)
    list = Store.touch(list, "/b", 2)
    list = Store.touch(list, "/a", 3)
    compare(list.length, 2)
    compare(list[0].path, "/a")
    compare(list[0].opened, 3)
    compare(list[1].path, "/b")
  }

  function test_the_list_is_capped() {
    var list = []
    for (var i = 0; i < Store.MAX + 5; i++) list = Store.touch(list, "/f" + i, i)
    compare(list.length, Store.MAX)
    compare(list[0].path, "/f" + (Store.MAX + 4))
  }

  function test_forgetting_is_off_the_list_only() {
    var list = Store.touch(Store.touch([], "/a", 1), "/b", 2)
    list = Store.forget(list, "/a")
    compare(list.length, 1)
    compare(list[0].path, "/b")
  }

  function test_rows_that_are_not_absolute_paths_are_dropped() {
    var s = Store.parse({ recent: [{ path: "relative" }, { path: "/ok", opened: "x" },
                                   { path: "/ok" }, null, { nope: 1 }] })
    compare(s.recent.length, 1)
    compare(s.recent[0].path, "/ok")
    compare(s.recent[0].opened, 0)
  }
}

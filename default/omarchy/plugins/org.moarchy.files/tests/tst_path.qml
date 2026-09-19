// Going up, going down, and the one comparison that decides whether a folder
// may be copied into itself.
import QtQuick
import QtTest
import "../Path.js" as Path

TestCase {
  name: "Path"

  function test_a_path_is_tidied_before_it_is_used() {
    compare(Path.clean("/home//simon/"), "/home/simon")
    compare(Path.clean("/"), "/")
    compare(Path.clean("//"), "/")
    compare(Path.clean(""), "/")
    compare(Path.clean(null), "/")
  }

  function test_up_from_the_root_is_the_root() {
    compare(Path.parent("/home/simon/Pictures"), "/home/simon")
    compare(Path.parent("/home"), "/")
    compare(Path.parent("/"), "/")
    verify(Path.isRoot("/"))
    verify(!Path.isRoot("/home"))
  }

  function test_a_name_comes_off_the_end() {
    compare(Path.base("/home/simon/todo.txt"), "todo.txt")
    compare(Path.base("/home/simon/"), "simon")
    compare(Path.base("/"), "/")
  }

  function test_joining_the_root_does_not_double_the_slash() {
    compare(Path.join("/", "etc"), "/etc")
    compare(Path.join("/home/simon", "Pictures"), "/home/simon/Pictures")
    compare(Path.join("/home/simon", ""), "/home/simon")
  }

  function test_a_neighbour_is_not_inside_a_folder() {
    // The whole reason this function exists: "/home/simon-old" starts with
    // "/home/simon" and copying into it is not copying into itself.
    verify(!Path.isUnder("/home/simon-old", "/home/simon"))
    verify(Path.isUnder("/home/simon/Pictures", "/home/simon"))
    verify(Path.isUnder("/home/simon", "/home/simon"))
    verify(!Path.isUnder("/home", "/home/simon"))
    // Everything is inside the root, including the root.
    verify(Path.isUnder("/etc", "/"))
    verify(Path.isUnder("/", "/"))
  }

  function test_home_is_written_the_way_people_write_it() {
    compare(Path.pretty("/home/simon", "/home/simon"), "~")
    compare(Path.pretty("/home/simon/Pictures", "/home/simon"), "~/Pictures")
    compare(Path.pretty("/etc/fstab", "/home/simon"), "/etc/fstab")
    // A home of "/" would turn every path into a tilde, so it is ignored.
    compare(Path.pretty("/etc", "/"), "/etc")
  }

  function test_the_crumbs_start_at_home_when_we_are_in_it() {
    var crumbs = Path.crumbs("/home/simon/Pictures/Camera", "/home/simon")
    compare(crumbs.length, 3)
    compare(crumbs[0].label, "Home")
    compare(crumbs[0].path, "/home/simon")
    compare(crumbs[1].label, "Pictures")
    compare(crumbs[1].path, "/home/simon/Pictures")
    compare(crumbs[2].label, "Camera")
    compare(crumbs[2].path, "/home/simon/Pictures/Camera")
  }

  function test_the_crumbs_start_at_the_root_when_we_are_not() {
    var crumbs = Path.crumbs("/etc/systemd", "/home/simon")
    compare(crumbs.length, 3)
    compare(crumbs[0].label, "/")
    compare(crumbs[0].path, "/")
    compare(crumbs[2].path, "/etc/systemd")

    compare(Path.crumbs("/", "/home/simon").length, 1)
    compare(Path.crumbs("/home/simon", "/home/simon").length, 1)
  }

  function test_depth_counts_from_the_root() {
    compare(Path.depth("/"), 0)
    compare(Path.depth("/home"), 1)
    compare(Path.depth("/home/simon/Pictures"), 3)
  }
}

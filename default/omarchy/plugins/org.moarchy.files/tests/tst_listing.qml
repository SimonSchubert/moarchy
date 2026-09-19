// What find said, and what the list makes of it.
import QtQuick
import QtTest
import "../Listing.js" as Listing

TestCase {
  name: "Listing"

  readonly property string rs: String.fromCharCode(30)
  readonly property string us: String.fromCharCode(31)

  function record(kind, target, size, when, name) {
    return [kind, target, size, when, name].join(us) + rs
  }

  function test_a_directory_comes_back_as_rows() {
    var blob = record("d", "d", 4096, 1789400000, "Pictures")
             + record("f", "f", 1234, 1789400001, "todo.txt")
    var rows = Listing.parse(blob)
    compare(rows.length, 2)
    compare(rows[0].name, "Pictures")
    verify(rows[0].folder)
    compare(rows[1].name, "todo.txt")
    verify(!rows[1].folder)
    compare(rows[1].size, 1234)
    compare(rows[1].modified, 1789400001)
  }

  function test_a_name_with_a_space_or_a_newline_in_it_survives() {
    var blob = record("f", "f", 10, 1, "Bahn ticket.pdf")
             + record("f", "f", 10, 1, "two\nlines")
    var rows = Listing.parse(blob)
    compare(rows.length, 2)
    compare(rows[0].name, "Bahn ticket.pdf")
    compare(rows[1].name, "two\nlines")
  }

  function test_a_link_is_what_it_points_at() {
    var blob = record("l", "d", 8, 1, "shortcut")
             + record("l", "N", 8, 1, "dangling")
             + record("l", "L", 8, 1, "loop")
    var rows = Listing.parse(blob)
    // A link to a directory sorts and opens as a directory.
    verify(rows[0].folder)
    verify(rows[0].link)
    verify(!rows[0].broken)
    // A link to nothing is shown rather than hidden: it is a thing on the
    // disk, and hiding it makes a directory impossible to tidy.
    verify(rows[1].broken)
    verify(rows[2].broken)
    compare(Listing.note(rows[1], 0), "Link to nothing")
  }

  function test_rubbish_in_the_middle_does_not_lose_the_rest() {
    var blob = record("f", "f", 10, 1, "first") + "half a record" + rs
             + record("f", "f", 10, 1, "last")
    var rows = Listing.parse(blob)
    compare(rows.length, 2)
    compare(rows[1].name, "last")
    compare(Listing.parse("").length, 0)
    compare(Listing.parse(null).length, 0)
  }

  function entry(name, folder, size, when) {
    return { name: name, folder: !!folder, link: false, broken: false,
             size: size || 0, modified: when || 0 }
  }

  function names(rows) {
    var out = []
    for (var i = 0; i < rows.length; i++) out.push(rows[i].name)
    return out
  }

  function test_folders_come_first_whatever_the_sort() {
    var rows = [entry("zebra.txt", false, 10, 500), entry("Apps", true, 0, 1),
                entry("apple.txt", false, 9000, 900)]
    compare(names(Listing.arrange(rows, "name", false, "")),
            ["Apps", "apple.txt", "zebra.txt"])
    compare(names(Listing.arrange(rows, "size", false, ""))[0], "Apps")
    compare(names(Listing.arrange(rows, "modified", false, ""))[0], "Apps")
  }

  function test_the_big_and_the_recent_come_first() {
    var rows = [entry("small.txt", false, 10, 500), entry("big.txt", false, 9000, 100)]
    compare(names(Listing.arrange(rows, "size", false, "")), ["big.txt", "small.txt"])
    compare(names(Listing.arrange(rows, "modified", false, "")), ["small.txt", "big.txt"])
  }

  function test_a_camera_roll_is_in_the_order_the_camera_wrote_it() {
    var rows = [entry("IMG_10.jpg"), entry("IMG_9.jpg"), entry("IMG_2.jpg")]
    compare(names(Listing.arrange(rows, "name", false, "")),
            ["IMG_2.jpg", "IMG_9.jpg", "IMG_10.jpg"])
  }

  function test_hidden_files_are_hidden_until_they_are_not() {
    var rows = [entry(".bashrc"), entry("todo.txt")]
    compare(names(Listing.arrange(rows, "name", false, "")), ["todo.txt"])
    compare(Listing.arrange(rows, "name", true, "").length, 2)
  }

  function test_the_search_looks_at_this_folder_and_no_further() {
    var rows = [entry("Bahn ticket.pdf"), entry("todo.txt")]
    compare(names(Listing.arrange(rows, "name", false, "TICKET")), ["Bahn ticket.pdf"])
    compare(Listing.arrange(rows, "name", false, "nothing").length, 0)
  }

  function test_a_size_is_read_at_a_glance_or_not_at_all() {
    compare(Listing.human(0), "0 B")
    compare(Listing.human(840), "840 B")
    compare(Listing.human(1234), "1.2 kB")
    compare(Listing.human(18900000), "19 MB")
    compare(Listing.human(1430000000), "1.4 GB")
  }

  function test_a_date_gets_shorter_as_it_gets_closer() {
    // Tuesday 15 September 2026, 14:32 UTC, which is what the pictures are
    // taken against.
    var now = 1789482720 * 1000
    compare(Listing.when(1789482720 - 2 * 3600, now), "12:32")
    compare(Listing.when(1789482720 - 26 * 3600, now), "Yesterday")
    compare(Listing.when(1789482720 - 4 * 86400, now), "Fri")
    compare(Listing.when(1789482720 - 47 * 86400, now), "30 Jul")
    compare(Listing.when(1789482720 - 400 * 86400, now), "11 Aug 2025")
    compare(Listing.when(0, now), "")
  }

  function test_a_folder_says_what_is_in_it() {
    compare(Listing.summary([]), "Empty")
    compare(Listing.summary([entry("a", true)]), "1 folder")
    compare(Listing.summary([entry("a", true), entry("b", true), entry("c")]),
            "2 folders · 1 file")
  }

  function test_an_extension_picks_the_picture() {
    compare(Listing.glyphs(entry("Pictures", true))[0], "folder-symbolic")
    compare(Listing.glyphs(entry("IMG_2.jpg"))[0], "image-x-generic-symbolic")
    compare(Listing.glyphs(entry("song.FLAC"))[0], "audio-x-generic-symbolic")
    compare(Listing.glyphs(entry("clip.mp4"))[0], "video-x-generic-symbolic")
    compare(Listing.glyphs(entry("firmware.tar.gz"))[0], "package-x-generic-symbolic")
    // Not an extension: a leading dot is a hidden file, and a file with no
    // dot at all is not a file of type "README".
    compare(Listing.extension(".bashrc"), "")
    compare(Listing.extension("README"), "")
    compare(Listing.glyphs(entry("README"))[0], "text-x-generic-symbolic")
    // Every row ends with something Adwaita has, so no row is ever blank.
    compare(Listing.glyphs(entry("thing.wat")).length, 1)
  }

  function test_every_failure_has_a_sentence() {
    verify(Listing.trouble(Listing.MISSING).length > 0)
    verify(Listing.trouble(Listing.UNREADABLE).indexOf("read") > 0)
    verify(Listing.trouble(Listing.NOT_A_DIRECTORY).length > 0)
    verify(Listing.trouble(99).length > 0)
  }

  function test_the_directory_is_an_argument_and_never_quoted() {
    var argv = Listing.command("/home/simon/Bahn ticket")
    compare(argv[0], "sh")
    compare(argv[1], "-c")
    compare(argv[4], "/home/simon/Bahn ticket")
  }
}

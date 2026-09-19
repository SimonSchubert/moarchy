// The three ways a file manager loses somebody's afternoon, held still.
import QtQuick
import QtTest
import "../Ops.js" as Ops

TestCase {
  name: "Ops"

  // --- names ------------------------------------------------------------

  function test_a_name_has_to_be_one() {
    verify(Ops.nameProblem("").length > 0)
    verify(Ops.nameProblem(".").length > 0)
    verify(Ops.nameProblem("..").length > 0)
    verify(Ops.nameProblem("holiday/2026").length > 0)
    compare(Ops.nameProblem("Bahn ticket.pdf"), "")
    // A leading dot is a hidden file, which is a thing somebody may want to
    // make on purpose.
    compare(Ops.nameProblem(".bashrc"), "")
  }

  function test_the_limit_is_bytes_and_not_letters() {
    var ascii = ""
    for (var i = 0; i < 255; i++) ascii += "a"
    compare(Ops.nameProblem(ascii), "")
    verify(Ops.nameProblem(ascii + "a").length > 0)

    // "ü" is two bytes, so 128 of them is 256 and over the limit even though
    // it is one letter short of the ASCII name that fits.
    var umlauts = ""
    for (var k = 0; k < 128; k++) umlauts += "ü"
    compare(umlauts.length, 128)
    compare(Ops.utf8Length(umlauts), 256)
    verify(Ops.nameProblem(umlauts).length > 0)
  }

  // --- pasting ----------------------------------------------------------

  function test_a_folder_cannot_be_put_inside_itself() {
    verify(Ops.pasteProblem("copy", "/home/simon/Pictures",
                            "/home/simon/Pictures/Camera").length > 0)
    verify(Ops.pasteProblem("copy", "/home/simon/Pictures",
                            "/home/simon/Pictures").length > 0)
    verify(Ops.pasteProblem("move", "/home/simon/Pictures",
                            "/home/simon/Pictures/Camera").length > 0)
  }

  function test_a_neighbouring_folder_is_not_inside_it() {
    // The string compare this rests on is against "/home/simon/" and not
    // against "/home/simon", or this would be refused.
    compare(Ops.pasteProblem("copy", "/home/simon", "/home/simon-old"), "")
  }

  function test_moving_something_where_it_already_is_says_so() {
    compare(Ops.pasteProblem("move", "/home/simon/todo.txt", "/home/simon"),
            "It is already here.")
    // Copying is not the same question: a copy beside the original is a copy,
    // and it lands as "todo (2).txt".
    compare(Ops.pasteProblem("copy", "/home/simon/todo.txt", "/home/simon"), "")
  }

  function test_the_whole_filesystem_is_not_a_thing_to_copy() {
    verify(Ops.pasteProblem("copy", "/", "/home/simon").length > 0)
  }

  // --- deleting ----------------------------------------------------------

  function test_home_and_everything_above_it_is_refused() {
    verify(Ops.trashProblem("/", "/home/simon").length > 0)
    verify(Ops.trashProblem("/home/simon", "/home/simon").length > 0)
    // Not the home folder, but it has the home folder in it, which is the
    // same loss with one more step.
    verify(Ops.trashProblem("/home", "/home/simon").length > 0)
    compare(Ops.trashProblem("/home/simon/todo.txt", "/home/simon"), "")
  }

  function test_the_trash_on_this_volume_is_the_one_in_home() {
    var plan = Ops.trashPlan("/home/simon/todo.txt", "/home/simon", "",
                             { top: "/", homeTop: "/", uid: "1000" })
    compare(plan.dir, "/home/simon/.local/share/Trash")
    // Absolute, as the specification asks for the home trash.
    compare(plan.line, "/home/simon/todo.txt")
  }

  function test_xdg_data_home_is_followed_when_it_is_set() {
    var plan = Ops.trashPlan("/home/simon/todo.txt", "/home/simon",
                             "/data/simon", { top: "/", homeTop: "/", uid: "1000" })
    compare(plan.dir, "/data/simon/Trash")
  }

  function test_a_card_gets_its_own_trash_and_a_relative_path() {
    // The alternative is copying a 1.4 GB video across a card reader in order
    // to delete it, which is what a plain move to the home trash would do.
    var plan = Ops.trashPlan("/run/media/simon/SD/DCIM/IMG_2.jpg", "/home/simon", "",
                             { top: "/run/media/simon/SD", homeTop: "/", uid: "1000" })
    compare(plan.dir, "/run/media/simon/SD/.Trash-1000")
    // Relative to the top of that volume, so the trash still reads after the
    // card has been moved to another machine and mounted somewhere else.
    compare(plan.line, "DCIM/IMG_2.jpg")
  }

  function test_a_path_is_encoded_the_way_the_specification_asks() {
    compare(Ops.encodePath("/home/simon/Bahn ticket.pdf"),
            "/home/simon/Bahn%20ticket.pdf")
    // The separators stay separators; everything between them is encoded.
    compare(Ops.encodePath("/a/100%/c"), "/a/100%25/c")
    compare(Ops.encodePath("/München/Straße.txt"),
            "/M%C3%BCnchen/Stra%C3%9Fe.txt")
  }

  function test_a_volume_nobody_could_name_is_refused_rather_than_guessed() {
    var plan = Ops.trashPlan("/x", "/home/simon", "", { top: "", homeTop: "/", uid: "1000" })
    verify(plan.problem.length > 0)
    verify(!plan.dir)
    var noUid = Ops.trashPlan("/mnt/x/y", "/home/simon", "",
                              { top: "/mnt/x", homeTop: "/", uid: "" })
    verify(noUid.problem.length > 0)
  }

  function test_df_is_read_off_the_bottom_line() {
    // `df --output=target | tail -n1` is what the script runs, so each line
    // is already the answer: the volume the file is on, the volume home is
    // on, and who we are.
    var card = Ops.parseTops("/run/media/simon/SD\n/\n1000\n")
    compare(card.top, "/run/media/simon/SD")
    compare(card.homeTop, "/")
    compare(card.uid, "1000")

    // df printing nothing but its own header is what a path that has gone
    // looks like, and it must not be mistaken for a mount point called
    // "Mounted on".
    compare(Ops.parseTops("Mounted on\n/\n1000").top, "")
    compare(Ops.parseTops("").top, "")
  }

  // --- the one that really deletes ---------------------------------------

  function test_only_a_direct_child_of_the_trash_is_a_trashed_thing() {
    var trash = "/home/simon/.local/share/Trash"
    compare(Ops.trashedName(trash + "/files/todo.txt", trash), "todo.txt")
    // Something inside a trashed folder is part of that folder, not a trashed
    // thing with an info file of its own.
    compare(Ops.trashedName(trash + "/files/Pictures/IMG_2.jpg", trash), "")
    compare(Ops.trashedName(trash + "/files", trash), "")
    compare(Ops.trashedName("/home/simon/todo.txt", trash), "")
  }

  // --- the scripts --------------------------------------------------------

  function test_every_path_is_an_argument_and_never_text_in_a_script() {
    // The property that makes a file called "; rm -rf ~" a file called
    // "; rm -rf ~". If a path ever reaches the script body, this fails.
    var nasty = "/home/simon/; rm -rf ~"
    var argv = Ops.place("copy", nasty, "/tmp")
    compare(argv[0], "sh")
    compare(argv[1], "-c")
    verify(argv[2].indexOf("rm -rf") < 0)
    compare(argv[4], nasty)
    compare(argv[5], "/tmp")

    var made = Ops.makeDir("/tmp", nasty)
    verify(made[2].indexOf("rm -rf") < 0)
    compare(made[5], nasty)

    var renamed = Ops.rename("/tmp", "a", nasty)
    verify(renamed[2].indexOf("rm -rf") < 0)
    compare(renamed[6], nasty)

    var trashed = Ops.trashCommand("/t", nasty, "/encoded")
    verify(trashed[2].indexOf("rm -rf") < 0)
    compare(trashed[5], nasty)
  }

  function test_a_move_is_a_move_and_a_copy_is_a_copy() {
    verify(Ops.place("move", "/a", "/b")[2].indexOf("mv -- ") > 0)
    verify(Ops.place("copy", "/a", "/b")[2].indexOf("cp -a -- ") > 0)
    // An archive copy, so a camera roll is still in date order afterwards.
    verify(Ops.place("copy", "/a", "/b")[2].indexOf("cp -r") < 0)
  }

  function test_every_failure_has_a_sentence() {
    verify(Ops.why(Ops.IN_THE_WAY).indexOf("already") > 0)
    verify(Ops.why(Ops.GONE).length > 0)
    verify(Ops.why(Ops.NO_FREE_NAME).length > 0)
    verify(Ops.why(1, "The rename").indexOf("The rename") === 0)
    verify(Ops.openTrouble(3).indexOf("Nothing") === 0)
    verify(Ops.trashTrouble(9).length > 0)
  }
}

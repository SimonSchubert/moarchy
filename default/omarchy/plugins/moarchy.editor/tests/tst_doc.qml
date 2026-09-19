import QtQuick
import QtTest
import "../Doc.js" as Doc

TestCase {
  name: "Doc"

  // --- what the shell hands over ---

  function test_json_payload_names_a_path_and_a_marker() {
    var p = Doc.parsePayload('{"path": "/home/moarchy/notes.md", "wait": "/run/user/1000/moarchy-editor-abc"}')
    compare(p.path, "/home/moarchy/notes.md")
    compare(p.wait, "/run/user/1000/moarchy-editor-abc")
    compare(p.refused, false)
  }

  function test_xdg_open_hands_over_a_bare_path() {
    compare(Doc.parsePayload("/home/moarchy/a file.txt").path, "/home/moarchy/a file.txt")
  }

  function test_a_file_uri_is_a_path() {
    compare(Doc.parsePayload("file:///home/moarchy/a%20file.txt").path, "/home/moarchy/a file.txt")
    compare(Doc.parsePayload("file://localhost/etc/hostname").path, "/etc/hostname")
  }

  function test_an_empty_payload_asks_for_nothing() {
    var p = Doc.parsePayload("{}")
    compare(p.path, "")
    compare(p.refused, false)
    compare(Doc.parsePayload("").refused, false)
    compare(Doc.parsePayload(undefined).path, "")
  }

  // The shell's working directory is not the caller's, so a relative path
  // names some other file. It is refused and said, not guessed at.
  function test_a_relative_path_is_refused() {
    compare(Doc.parsePayload("notes.md").path, "")
    compare(Doc.parsePayload("notes.md").refused, true)
    compare(Doc.parsePayload('{"path": "notes.md"}').refused, true)
  }

  function test_broken_json_is_not_a_path() {
    var p = Doc.parsePayload("{not json")
    compare(p.path, "")
    compare(p.refused, false)
  }

  function test_only_our_markers_are_touched() {
    verify(Doc.markerOk("/run/user/1000/moarchy-editor-x1y2"))
    verify(!Doc.markerOk("/home/moarchy/.bashrc"))
    verify(!Doc.markerOk("moarchy-editor-relative"))
    verify(!Doc.markerOk(""))
    verify(!Doc.markerOk(undefined))
  }

  // --- paths ---

  function test_basename_and_dirname() {
    compare(Doc.basename("/a/b/c.txt"), "c.txt")
    compare(Doc.basename("/a/b/"), "b")
    compare(Doc.dirname("/a/b/c.txt"), "/a/b")
    compare(Doc.dirname("/c.txt"), "/")
  }

  function test_home_reads_as_a_tilde_and_back() {
    compare(Doc.tilde("/home/m/Documents/x.txt", "/home/m"), "~/Documents/x.txt")
    compare(Doc.tilde("/home/mo/x.txt", "/home/m"), "/home/mo/x.txt")
    compare(Doc.tilde("/home/m", "/home/m"), "~")
    compare(Doc.expand("~/Documents/x.txt", "/home/m"), "/home/m/Documents/x.txt")
    compare(Doc.expand("  /etc/x  ", "/home/m"), "/etc/x")
  }

  function test_a_save_path_needs_a_name() {
    compare(Doc.saveAsProblem("~/Documents/x.txt", "/home/m"), "")
    verify(Doc.saveAsProblem("", "/home/m").length > 0)
    verify(Doc.saveAsProblem("x.txt", "/home/m").length > 0)
    verify(Doc.saveAsProblem("~/Documents/", "/home/m").length > 0)
    verify(Doc.saveAsProblem("/tmp/..", "/home/m").length > 0)
  }

  // --- the probe ---

  function test_the_probe_is_one_shell_with_the_path_as_an_argument() {
    var cmd = Doc.probeCommand("/tmp/it's \"quoted\".txt")
    compare(cmd[0], "sh")
    compare(cmd[cmd.length - 1], "/tmp/it's \"quoted\".txt")
    verify(cmd[2].indexOf("it's") < 0)
  }

  function test_probe_output_is_read() {
    compare(Doc.parseProbe("file 1234 w\n").kind, "file")
    compare(Doc.parseProbe("file 1234 w\n").size, 1234)
    compare(Doc.parseProbe("file 1234 w\n").writable, true)
    compare(Doc.parseProbe("file 9 ro").writable, false)
    compare(Doc.parseProbe("missing w").writable, true)
    compare(Doc.parseProbe("missing ro").writable, false)
    compare(Doc.parseProbe("dir").kind, "dir")
    compare(Doc.parseProbe("garbage").kind, "")
  }

  function test_what_is_refused_before_it_is_read() {
    compare(Doc.probeTrouble(Doc.parseProbe("file 10 w")), "")
    compare(Doc.probeTrouble(Doc.parseProbe("file 10 ro")), "")
    compare(Doc.probeTrouble(Doc.parseProbe("missing w")), "")
    verify(Doc.probeTrouble(Doc.parseProbe("missing ro")).length > 0)
    verify(Doc.probeTrouble(Doc.parseProbe("dir")).length > 0)
    verify(Doc.probeTrouble(Doc.parseProbe("unreadable")).length > 0)
    verify(Doc.probeTrouble(Doc.parseProbe("file " + (Doc.LIMIT + 1) + " w")).indexOf("256 KB") > 0)
    verify(Doc.probeTrouble(null).length > 0)
  }

  // --- the text ---

  function test_line_endings() {
    compare(Doc.endings("a\nb\n"), "lf")
    compare(Doc.endings("no break"), "lf")
    compare(Doc.endings("a\r\nb\r\n"), "crlf")
    compare(Doc.endings("a\r\nb\n"), "mixed")
    compare(Doc.endings("a\rb"), "mixed")
  }

  // Each of these is a character the phone's Qt text control was measured
  // changing on the way back out. Writing one of these files would change it.
  function test_files_that_cannot_be_written_back_exactly() {
    compare(Doc.problem("plain\ttext\n"), "")
    compare(Doc.problem("x" + String.fromCharCode(0) + "y"), "binary")
    compare(Doc.problem("caf" + String.fromCharCode(0xfffd)), "encoding")
    compare(Doc.problem("a" + String.fromCharCode(0xa0) + "b"), "spaces")
    compare(Doc.problem("a" + String.fromCharCode(0x2028) + "b"), "spaces")
    compare(Doc.problem("a" + String.fromCharCode(0x2029) + "b"), "spaces")
    compare(Doc.problem("a\r\nb\n"), "endings")
    verify(Doc.problemText("spaces").length > 0)
    compare(Doc.problemText(""), "")
  }

  function test_crlf_goes_back_out_as_it_came_in() {
    var raw = "one\r\ntwo\r\n"
    var held = Doc.forEditing(raw)
    compare(held.text, "one\ntwo\n")
    compare(held.endings, "crlf")
    compare(held.problem, "")
    compare(Doc.forDisk(held.text + "three\n", held.endings), "one\r\ntwo\r\nthree\r\n")
  }

  function test_lf_is_left_alone() {
    var held = Doc.forEditing("one\ntwo")
    compare(held.text, "one\ntwo")
    compare(Doc.forDisk(held.text, held.endings), "one\ntwo")
  }

  function test_a_file_with_a_problem_is_not_folded() {
    var raw = "a" + String.fromCharCode(0xa0) + "b\r\nc\r\n"
    var held = Doc.forEditing(raw)
    compare(held.problem, "spaces")
    compare(held.text, raw)
  }

  function test_sizes_and_times_read_as_words() {
    compare(Doc.sizeLabel(512), "512 bytes")
    compare(Doc.sizeLabel(256 * 1024), "256 KB")
    compare(Doc.sizeLabel(3.5 * 1024 * 1024), "3.5 MB")
    compare(Doc.ago(1000, 1030), "just now")
    compare(Doc.ago(1000, 1000 + 7200), "2 h ago")
    compare(Doc.ago(1000, 1000 + 86400 + 5), "yesterday")
    compare(Doc.ago(0, 5000), "")
  }
}

import QtQuick
import QtTest
import "../Mailbox.js" as Mailbox

TestCase {
  name: "Mailbox"

  function row(uid, at, flags) {
    return { uid: uid, at: at, flags: flags || [], from: { name: "A", email: "a@example.org" },
             to: [], subject: "s" + uid, preview: "", attachment: false, size: 1 }
  }

  function answer(folder, validity, present, rows, extra) {
    var r = { folder: folder, uidvalidity: validity, uidnext: 100, exists: present.length,
              unseen: 0, reset: false, present: present, rows: rows, more: false }
    for (var k in (extra || {})) r[k] = extra[k]
    return r
  }

  function test_the_first_answer_fills_an_empty_folder_newest_first() {
    var box = Mailbox.merge(Mailbox.empty("INBOX"),
                            answer("INBOX", 7, [[1, []], [2, ["\\Seen"]]], [row(1, 1000), row(2, 2000)],
                                   { reset: true }), 5)
    compare(box.rows.map(function (r) { return r.uid }), [2, 1])
    compare(box.rows[0].flags, ["\\Seen"])
    compare(box.uidvalidity, 7)
    compare(box.at, 5)
  }

  function test_flags_come_from_present_and_expunged_rows_go() {
    var box = Mailbox.merge(Mailbox.empty("INBOX"),
                            answer("INBOX", 7, [[1, []], [2, []], [3, []]], [row(1, 1), row(2, 2), row(3, 3)]), 1)
    var next = Mailbox.merge(box, answer("INBOX", 7, [[1, ["\\Seen"]], [3, ["\\Flagged"]]], []), 2)
    compare(next.rows.map(function (r) { return r.uid }), [3, 1])
    compare(next.rows[1].flags, ["\\Seen"])
    compare(next.rows[0].flags, ["\\Flagged"])
  }

  function test_a_new_uidvalidity_throws_everything_away() {
    var box = Mailbox.merge(Mailbox.empty("INBOX"), answer("INBOX", 7, [[1, []]], [row(1, 1)]), 1)
    var next = Mailbox.merge(box, answer("INBOX", 8, [[1, []]], [row(1, 50)]), 2)
    compare(next.rows.length, 1)
    compare(next.rows[0].at, 50)
  }

  function test_an_answer_for_another_folder_changes_nothing() {
    var box = Mailbox.empty("INBOX")
    compare(Mailbox.merge(box, answer("Sent", 1, [[1, []]], [row(1, 1)]), 1), box)
  }

  function test_the_file_round_trips_and_drops_what_it_cannot_read() {
    var box = Mailbox.merge(Mailbox.empty("Sent"), answer("Sent", 3, [[4, []]], [row(4, 9)]), 1)
    var data = JSON.parse(Mailbox.serialize(box))
    data.rows.push({ uid: "nope" }, null)
    var back = Mailbox.parse(data, "Sent")
    compare(back.rows.length, 1)
    compare(back.uidvalidity, 3)
    compare(Mailbox.parse(data, "INBOX").rows.length, 0)
  }

  function test_pending_changes_are_drawn_until_their_own_answer() {
    var box = Mailbox.merge(Mailbox.empty("INBOX"),
                            answer("INBOX", 1, [[1, []], [2, []]], [row(1, 1), row(2, 2)], { unseen: 2 }), 1)
    var pending = Mailbox.withPending({}, "INBOX", [1], "seen", true, 1)
    compare(Mailbox.unseen(box, pending), 1)
    compare(Mailbox.view(box, pending)[1].flags, ["\\Seen"])
    // Tapped again before the first answer came back.
    pending = Mailbox.withPending(pending, "INBOX", [1], "seen", false, 2)
    pending = Mailbox.clearPending(pending, "INBOX", [1], "seen", 1)
    compare(Mailbox.view(box, pending)[1].flags, [])
    pending = Mailbox.clearPending(pending, "INBOX", [1], "seen", 2)
    compare(Object.keys(pending).length, 0)
  }

  function test_a_row_moved_away_is_not_drawn() {
    var box = Mailbox.merge(Mailbox.empty("INBOX"), answer("INBOX", 1, [[1, []], [2, []]], [row(1, 1), row(2, 2)],
                                                         { unseen: 2 }), 1)
    var pending = Mailbox.withPending({}, "INBOX", [2], "gone", true, 1)
    compare(Mailbox.view(box, pending).map(function (r) { return r.uid }), [1])
    compare(Mailbox.unseen(box, pending), 1)
    var after = Mailbox.without(box, [2])
    compare(after.unseen, 1)
    compare(after.exists, 1)
  }

  function test_with_flag_keeps_the_count_honest() {
    var box = Mailbox.merge(Mailbox.empty("INBOX"), answer("INBOX", 1, [[1, []]], [row(1, 1)], { unseen: 1 }), 1)
    var read = Mailbox.withFlag(box, [1], Mailbox.SEEN, true)
    compare(read.unseen, 0)
    compare(Mailbox.withFlag(read, [1], Mailbox.SEEN, true).unseen, 0)
    compare(Mailbox.withFlag(read, [1], Mailbox.SEEN, false).unseen, 1)
  }

  function test_when() {
    var now = new Date(2026, 8, 16, 15, 0).getTime()
    compare(Mailbox.when(new Date(2026, 8, 16, 9, 5).getTime(), now), "09:05")
    compare(Mailbox.when(new Date(2026, 8, 15, 23, 0).getTime(), now), "Yesterday")
    compare(Mailbox.when(new Date(2026, 8, 3).getTime(), now), "3 Sep")
    compare(Mailbox.when(new Date(2025, 11, 30).getTime(), now), "30 Dec 2025")
    compare(Mailbox.stamp(new Date(2026, 8, 16, 9, 5).getTime(), now), "09:05")
    compare(Mailbox.stamp(new Date(2026, 8, 3, 18, 40).getTime(), now), "3 Sep, 18:40")
    compare(Mailbox.size(182100), "182 KB")
    compare(Mailbox.size(2500000), "2.5 MB")
  }
}

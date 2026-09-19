import QtQuick
import QtTest
import "../Threads.js" as Threads
import "../Store.js" as Store

TestCase {
  name: "Threads"

  function sms(path, state, pduType, number, text, time) {
    return { path: path, state: state, pduType: pduType, number: number, text: text, time: time }
  }

  function test_a_received_text_is_kept_then_deleted() {
    var r = Threads.sweep([sms("/s/1", "received", "deliver", "+447700900412", "hi", 5000)], [], 9000)
    compare(r.add.length, 1)
    compare(r.add[0].dir, "in")
    compare(r.add[0].at, 5000)
    compare(r.add[0].read, false)
    compare(r.remove, ["/s/1"])
  }

  function test_a_text_still_arriving_is_left_alone() {
    var r = Threads.sweep([sms("/s/1", "receiving", "deliver", "+447700900412", "", 0)], [], 9000)
    compare(r.add.length, 0)
    compare(r.remove.length, 0)
  }

  function test_a_text_already_kept_is_only_deleted() {
    var first = Threads.sweep([sms("/s/1", "received", "deliver", "+44", "hi", 5000)], [], 9000)
    var again = Threads.sweep([sms("/s/1", "received", "deliver", "+44", "hi", 5000)], first.add, 9500)
    compare(again.add.length, 0)
    compare(again.remove, ["/s/1"])
  }

  function test_the_same_text_twice_on_the_modem_is_kept_once() {
    var r = Threads.sweep([sms("/s/1", "received", "deliver", "+44", "hi", 5000),
                           sms("/s/2", "received", "deliver", "+44", "hi", 5000)], [], 9000)
    compare(r.add.length, 1)
    compare(r.remove.length, 2)
  }

  function test_reports_are_deleted_and_our_own_texts_are_not_touched() {
    var r = Threads.sweep([sms("/s/1", "received", "status-report", "+44", "", 5000),
                           sms("/s/2", "sent", "submit", "+44", "hello", 0),
                           sms("/s/3", "", "submit", "+44", "hello", 0)], [], 9000)
    compare(r.add.length, 0)
    compare(r.remove, ["/s/1"])
  }

  function test_a_text_with_no_timestamp_is_dated_when_it_was_found() {
    var r = Threads.sweep([sms("/s/1", "received", "cdma-deliver", "+44", "hi", 0)], [], 9000)
    compare(r.add[0].at, 9000)
    compare(r.add[0].stamp, 0)
  }

  function test_conversations_group_by_number_newest_first() {
    var list = [
      { id: "1", number: "+447700900412", dir: "in", text: "a", at: 100, read: true, status: "received" },
      { id: "2", number: "+4930555", dir: "in", text: "b", at: 200, read: false, status: "received" },
      { id: "3", number: "07700900412", dir: "out", text: "c", at: 300, read: true, status: "sent" },
      { id: "4", number: "+447700900412", dir: "in", text: "d", at: 400, read: false, status: "received" }
    ]
    var threads = Threads.threads(list)
    compare(threads.length, 2)
    compare(threads[0].last.id, "4")
    compare(threads[0].count, 3)
    compare(threads[0].unread, 1)
    compare(threads[1].unread, 1)
    compare(Threads.unread(list), 2)

    var convo = Threads.conversation(list, "07700 900412")
    compare(convo.length, 3)
    compare(convo[0].id, "4")

    var read = Threads.markRead(list, "+447700900412")
    compare(Threads.unread(read), 1)
    verify(Threads.markRead(read, "+447700900412") === read)
    compare(Threads.withoutThread(list, "+447700900412").length, 1)
  }

  function test_a_retry_moves_to_the_bottom() {
    var list = [
      { id: "1", number: "+44", dir: "out", text: "a", at: 100, status: "failed", read: true },
      { id: "2", number: "+44", dir: "in", text: "b", at: 200, status: "received", read: true }
    ]
    var out = Threads.withStatus(list, "1", "sending", 300)
    compare(out[1].id, "1")
    compare(out[1].status, "sending")
    compare(list[0].status, "failed")
  }

  function test_previews() {
    compare(Threads.preview({ dir: "in", text: "one\ntwo   three" }), "one two three")
    compare(Threads.preview({ dir: "out", text: "hi", status: "sent" }), "You: hi")
    compare(Threads.preview({ dir: "out", text: "hi", status: "failed" }), "Not sent: hi")
  }

  function test_times() {
    var now = new Date(2026, 8, 16, 12, 0).getTime()
    compare(Threads.stamp(new Date(2026, 8, 16, 9, 5).getTime(), now), "09:05")
    compare(Threads.stamp(new Date(2026, 8, 15, 21, 30).getTime(), now), "Yesterday 21:30")
    compare(Threads.when(new Date(2026, 2, 3, 10, 0).getTime(), now), "3 Mar")
  }

  function test_the_file_goes_out_and_comes_back() {
    var text = "it's \"quoted\"\nand " + String.fromCharCode(0x2713)
    var list = [
      { id: "1", number: "+44", dir: "in", text: text, at: 100, stamp: 100, status: "received", read: false },
      { id: "2", number: "+44", dir: "out", text: "b", at: 200, stamp: 0, status: "sending", read: true }
    ]
    var back = Store.parse(JSON.parse(Store.serialize(list, [{ odd: 1 }])))
    compare(back.messages.length, 2)
    compare(back.messages[0].text, text)
    compare(back.messages[0].read, false)
    compare(back.messages[0].stamp, 100)
    // It was on its way out when the file was written. Nobody knows if it went.
    compare(back.messages[1].status, "failed")
    compare(back.strays.length, 1)
    compare(Store.parse({ messages: [{ dir: "in", text: 5, number: "+44", at: 1 }] }).strays.length, 1)
  }
}

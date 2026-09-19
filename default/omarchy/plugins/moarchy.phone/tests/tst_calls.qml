import QtQuick
import QtTest
import "../Calls.js" as Calls
import "../Store.js" as Store

TestCase {
  name: "Calls"

  function call(path, state, direction, number) {
    return { path: path, state: state, direction: direction || "incoming", number: number || "+4930123", reason: "" }
  }

  function test_which_call_the_screen_is_about() {
    var ringing = call("/c/2", "waiting")
    var active = call("/c/1", "active")
    compare(Calls.primary([ringing, active]).path, "/c/1")
    compare(Calls.waiting([ringing, active]).path, "/c/2")
    compare(Calls.ringing([ringing, active]), null)
    compare(Calls.primary([call("/c/1", "terminated")]), null)
  }

  function test_only_a_call_alone_rings_out_loud() {
    compare(Calls.ringing([call("/c/1", "ringing-in")]).path, "/c/1")
    compare(Calls.ringing([call("/c/1", "ringing-in"), call("/c/0", "terminated")]).path, "/c/1")
    compare(Calls.waiting([call("/c/1", "ringing-in")]), null)
  }

  function test_audio_follows_the_call_but_not_the_ring() {
    verify(!Calls.audioWanted([call("/c/1", "ringing-in")]))
    verify(Calls.audioWanted([call("/c/1", "dialing", "outgoing")]))
    verify(Calls.audioWanted([call("/c/1", "active")]))
    verify(!Calls.audioWanted([call("/c/1", "terminated")]))
    verify(!Calls.audioWanted([]))
  }

  function test_an_answered_call_is_logged_with_its_length() {
    var r = Calls.follow({}, [call("/c/1", "ringing-in")], 1000)
    compare(r.ended.length, 0)
    r = Calls.follow(r.seen, [call("/c/1", "active")], 5000)
    r = Calls.follow(r.seen, [call("/c/1", "terminated")], 65000)
    compare(r.ended.length, 1)
    var e = r.ended[0]
    compare(e.dir, "in")
    verify(e.answered)
    verify(!e.missed)
    compare(e.at, 1000)
    compare(e.seconds, 60)
    compare(r.finished, ["/c/1"])

    // Read again before the delete lands: logged once, deleted again.
    r = Calls.follow(r.seen, [call("/c/1", "terminated")], 66000)
    compare(r.ended.length, 0)
    compare(r.finished, ["/c/1"])
    r = Calls.follow(r.seen, [], 67000)
    compare(r.ended.length, 0)
  }

  function test_an_incoming_call_nobody_answered_is_missed() {
    var r = Calls.follow({}, [call("/c/1", "ringing-in")], 1000)
    r = Calls.follow(r.seen, [call("/c/1", "terminated")], 20000)
    verify(r.ended[0].missed)
    compare(r.ended[0].seconds, 0)
  }

  function test_a_declined_call_is_not_missed() {
    var r = Calls.follow({}, [call("/c/1", "ringing-in")], 1000)
    var seen = Calls.decline(r.seen, "/c/1")
    r = Calls.follow(seen, [call("/c/1", "terminated")], 3000)
    verify(!r.ended[0].missed)
    verify(!r.ended[0].answered)
    compare(Calls.describe(r.ended[0]), "Declined")
  }

  function test_the_number_arriving_late_is_kept() {
    var r = Calls.follow({}, [call("/c/1", "ringing-in", "incoming", "")], 1000)
    r = Calls.follow(r.seen, [call("/c/1", "ringing-in", "incoming", "+447700900412")], 1500)
    r = Calls.follow(r.seen, [{ path: "/c/1", state: "terminated", direction: "", number: "" }], 9000)
    compare(r.ended[0].number, "+447700900412")
    compare(r.ended[0].dir, "in")
  }

  function test_a_call_that_vanished_still_happened() {
    var r = Calls.follow({}, [call("/c/1", "active", "outgoing")], 1000)
    r = Calls.follow(r.seen, [], 31000)
    compare(r.ended.length, 1)
    compare(r.ended[0].dir, "out")
    compare(r.ended[0].seconds, 30)
  }

  function test_a_call_already_over_when_first_seen_is_only_deleted() {
    var r = Calls.follow({}, [call("/c/9", "terminated")], 1000)
    compare(r.ended.length, 0)
    compare(r.finished, ["/c/9"])
  }

  function test_the_log_is_capped_and_newest_first() {
    var log = []
    for (var i = 0; i < Calls.MAX + 5; i++)
      log = Calls.withEntry(log, { id: "k" + i, number: "1", dir: "in", at: i + 1, seconds: 0 })
    compare(log.length, Calls.MAX)
    compare(log[0].id, "k" + (Calls.MAX + 4))
    compare(Calls.without(log, "k" + (Calls.MAX + 4)).length, Calls.MAX - 1)
  }

  function test_missed_calls_since_they_were_last_looked_at() {
    var log = [{ id: "a", missed: true, at: 300 }, { id: "b", missed: false, at: 200 },
               { id: "c", missed: true, at: 100 }]
    compare(Calls.unseenMissed(log, 0), 2)
    compare(Calls.unseenMissed(log, 150), 1)
    compare(Calls.unseenMissed(log, 300), 0)
  }

  function test_durations_and_dates() {
    compare(Calls.duration(0), "0:00")
    compare(Calls.duration(62), "1:02")
    compare(Calls.duration(3723), "1:02:03")
    var now = new Date(2026, 8, 16, 12, 0).getTime()
    compare(Calls.when(new Date(2026, 8, 16, 9, 5).getTime(), now), "09:05")
    compare(Calls.when(new Date(2026, 8, 15, 23, 59).getTime(), now), "Yesterday")
    compare(Calls.when(new Date(2026, 8, 12, 10, 0).getTime(), now), "Sat")
    compare(Calls.when(new Date(2026, 2, 3, 10, 0).getTime(), now), "3 Mar")
    compare(Calls.when(new Date(2025, 11, 31, 10, 0).getTime(), now), "31 Dec 2025")
  }

  function test_the_file_goes_out_and_comes_back() {
    var log = [{ id: "a", number: "+4930123", dir: "out", answered: true, missed: false, at: 2000, seconds: 61 },
               { id: "b", number: "", dir: "in", answered: false, missed: true, at: 1000, seconds: 0 }]
    var stray = { at: "whenever" }
    var back = Store.parse(JSON.parse(Store.serialize(log, [stray], 1500)))
    compare(back.log.length, 2)
    compare(back.log[0].seconds, 61)
    verify(back.log[0].answered)
    verify(back.log[1].missed)
    compare(back.log[1].number, "")
    compare(back.strays.length, 1)
    compare(back.seen, 1500)
    compare(Store.parse(null).log.length, 0)
  }
}

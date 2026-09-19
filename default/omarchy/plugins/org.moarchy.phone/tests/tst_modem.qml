import QtQuick
import QtTest
import "../Modem.js" as Modem

TestCase {
  name: "Modem"

  readonly property string bus: "org.freedesktop.ModemManager1"

  function test_gdbus_lines_about_calls() {
    compare(Modem.classify("/org/freedesktop/ModemManager1/Modem/0: " + bus
                           + ".Modem.Voice.CallAdded (objectpath '/org/freedesktop/ModemManager1/Call/1',)", "calls"),
            Modem.REFRESH)
    compare(Modem.classify("/org/freedesktop/ModemManager1/Call/1: " + bus
                           + ".Call.StateChanged (3, 4, uint32 3)", "calls"),
            Modem.REFRESH)
    compare(Modem.classify("/org/freedesktop/ModemManager1/Call/1: org.freedesktop.DBus.Properties.PropertiesChanged ('"
                           + bus + ".Call', {'Number': <'+4930123456'>}, @as [])", "calls"),
            Modem.REFRESH)
  }

  function test_gdbus_lines_about_texts() {
    compare(Modem.classify("/org/freedesktop/ModemManager1/Modem/0: " + bus
                           + ".Modem.Messaging.Added (objectpath '/org/freedesktop/ModemManager1/SMS/4', true)", "messages"),
            Modem.REFRESH)
    compare(Modem.classify("/org/freedesktop/ModemManager1/SMS/4: org.freedesktop.DBus.Properties.PropertiesChanged ('"
                           + bus + ".Sms', {'State': <uint32 3>}, @as [])", "messages"),
            Modem.REFRESH)
    // A call is not a text, and the other way round.
    compare(Modem.classify("/org/freedesktop/ModemManager1/Modem/0: " + bus
                           + ".Modem.Messaging.Added (objectpath '/org/freedesktop/ModemManager1/SMS/4', true)", "calls"),
            Modem.IGNORE)
    compare(Modem.classify("/org/freedesktop/ModemManager1/Call/1: " + bus
                           + ".Call.StateChanged (3, 4, uint32 3)", "messages"),
            Modem.IGNORE)
  }

  function test_the_noise_is_ignored() {
    compare(Modem.classify("/org/freedesktop/ModemManager1/Modem/0: org.freedesktop.DBus.Properties.PropertiesChanged ('"
                           + bus + ".Modem', {'SignalQuality': <(uint32 61, true)>}, @as [])", "calls"),
            Modem.IGNORE)
    compare(Modem.classify("Monitoring signals from all objects owned by " + bus, "calls"), Modem.IGNORE)
    compare(Modem.classify("", "calls"), Modem.IGNORE)
  }

  function test_modemmanager_coming_and_going_is_a_resync() {
    compare(Modem.classify("The name " + bus + " is owned by :1.12", "calls"), Modem.RESYNC)
    compare(Modem.classify("The name " + bus + " does not have an owner", "messages"), Modem.RESYNC)
    compare(Modem.classify("/org/freedesktop/ModemManager1: org.freedesktop.DBus.ObjectManager.InterfacesAdded (objectpath '/org/freedesktop/ModemManager1/Modem/1', {})", "calls"),
            Modem.REFRESH)
  }

  function test_a_call_as_json() {
    var c = Modem.parseCall('{"call":{"audio-format":{"encoding":"--","rate":"--","resolution":"--"},'
                            + '"dbus-path":"/org/freedesktop/ModemManager1/Call/3",'
                            + '"properties":{"audio-port":"--","direction":"incoming","multiparty":"no",'
                            + '"number":"+4930123456","state":"ringing-in","state-reason":"incoming-new"}}}')
    compare(c.path, "/org/freedesktop/ModemManager1/Call/3")
    compare(c.number, "+4930123456")
    compare(c.direction, "incoming")
    compare(c.state, "ringing-in")
    compare(c.reason, "incoming-new")
  }

  function test_dashes_are_nothing() {
    var c = Modem.parseCall('{"call":{"dbus-path":"/org/freedesktop/ModemManager1/Call/1",'
                            + '"properties":{"direction":"outgoing","number":"--","state":"--"}}}')
    compare(c.number, "")
    compare(c.state, "")
    compare(Modem.parseCall("error: couldn't find call"), null)
    compare(Modem.parseCall('{"call":{}}'), null)
  }

  function test_a_text_as_json() {
    var umlaut = String.fromCharCode(0xe4)
    var s = Modem.parseSms('{"sms":{"content":{"data":"--","number":"+447700900412","text":"Gr'
                           + umlaut + 'ße\\n\\"quoted\\""},'
                           + '"dbus-path":"/org/freedesktop/ModemManager1/SMS/4",'
                           + '"properties":{"class":"--","pdu-type":"deliver","state":"received",'
                           + '"storage":"me","timestamp":"2025-03-14T09:26:53+01"}}}')
    compare(s.path, "/org/freedesktop/ModemManager1/SMS/4")
    compare(s.number, "+447700900412")
    compare(s.text, "Gr" + umlaut + "ße\n\"quoted\"")
    compare(s.state, "received")
    compare(s.pduType, "deliver")
    compare(s.time, Date.UTC(2025, 2, 14, 8, 26, 53))
  }

  function test_timestamps_in_every_shape_modemmanager_prints() {
    compare(Modem.timestamp("2025-03-14T09:26:53Z"), Date.UTC(2025, 2, 14, 9, 26, 53))
    compare(Modem.timestamp("2025-03-14T09:26:53+05:30"), Date.UTC(2025, 2, 14, 3, 56, 53))
    compare(Modem.timestamp("2025-03-14T09:26:53-03"), Date.UTC(2025, 2, 14, 12, 26, 53))
    compare(Modem.timestamp("--"), 0)
    compare(Modem.timestamp("yesterday"), 0)
  }

  function test_the_collector_output_is_read_line_by_line() {
    var text = '{"call":{"dbus-path":"/org/freedesktop/ModemManager1/Call/1","properties":{"state":"active"}}}\n'
             + "\n"
             + "error: couldn't find call\n"
             + '{"call":{"dbus-path":"/org/freedesktop/ModemManager1/Call/2","properties":{"state":"waiting"}}}\n'
    var calls = Modem.parseLines(text, Modem.parseCall)
    compare(calls.length, 2)
    compare(calls[1].state, "waiting")
  }

  function test_every_command_goes_through_a_shell() {
    var cmds = [Modem.monitorCommand(), Modem.collectCommand("calls"), Modem.collectCommand("messages"),
                Modem.dialCommand("+4930123"), Modem.acceptCommand("/p"), Modem.hangupCommand("/p"),
                Modem.hangupAndAcceptCommand(), Modem.dtmfCommand("/p", "5"),
                Modem.deleteCallsCommand(["/p"]), Modem.deleteSmsCommand(["/p"]),
                Modem.sendCommand("+4930123", "hi"), Modem.feedbackCommand("phone-incoming-call", true, false),
                Modem.callAudioCommand("SelectMode", "u", 1), Modem.wakeCommand(), Modem.lockCommand(),
                Modem.notifyCommand("Mum", "hi")]
    for (var i = 0; i < cmds.length; i++) {
      compare(cmds[i][0], "sh")
      compare(cmds[i][1], "-c")
    }
  }

  function test_arguments_are_never_pasted_into_a_script() {
    var text = "it's \"quoted\" $(reboot) `id` " + String.fromCharCode(0x2713)
    var send = Modem.sendCommand("+4930123", text)
    compare(send[3], "sh")
    compare(send[4], text)
    compare(send[5], "+4930123")
    verify(send[2].indexOf("reboot") < 0)

    var dial = Modem.dialCommand("+4930123")
    compare(dial[4], "+4930123")

    var accept = Modem.acceptCommand("/org/freedesktop/ModemManager1/Call/1")
    compare(accept.slice(3), ["mmcli", "-o", "/org/freedesktop/ModemManager1/Call/1", "--accept"])
  }

  function test_the_monitor_dies_with_the_shell() {
    var monitor = Modem.monitorCommand()
    verify(monitor[2].indexOf("exec setpriv --pdeathsig TERM gdbus monitor") >= 0)
    // And still starts where setpriv cannot do that.
    verify(monitor[2].indexOf("\nexec gdbus monitor --system") >= 0)
    compare(monitor[3], "org.freedesktop.ModemManager1")
  }

  function test_only_real_keys_are_sent_as_tones() {
    compare(Modem.dtmfCommand("/p", "#").slice(4), ["-o", "/p", "--send-dtmf=#"])
    compare(Modem.dtmfCommand("/p", "12").length, 0)
    compare(Modem.dtmfCommand("/p", "x").length, 0)
  }

  function test_a_ring_loops_and_a_ping_does_not() {
    var ring = Modem.feedbackCommand("phone-incoming-call", true, false)
    compare(ring.slice(4), ["-E", "phone-incoming-call", "-t", "0", "-w", "3600"])
    var quiet = Modem.feedbackCommand("phone-incoming-call", true, true)
    compare(quiet.slice(quiet.length - 2), ["-P", "quiet"])
    var ping = Modem.feedbackCommand("message-new-sms", false, false)
    compare(ping.slice(4), ["-E", "message-new-sms", "-t", "-1", "-w", "30"])
  }

  function test_what_mmcli_says_when_it_fails() {
    compare(Modem.trouble("error: couldn't create new call: 'GDBus.Error:org.freedesktop.ModemManager1.Error.Core.WrongState: modem not enabled'", "x"),
            "Modem not enabled")
    compare(Modem.trouble("error: couldn't send the SMS: 'GDBus.Error:org.freedesktop.ModemManager1.Error.Core.Unauthorized: PolicyKit authorization failed: not authorized for 'org.freedesktop.ModemManager1.Messaging''", "x"),
            "The modem refused: not allowed from here.")
    compare(Modem.trouble("error: no modems were found", "x"), "No modem.")
    compare(Modem.trouble("", "Could not call."), "Could not call.")
  }
}

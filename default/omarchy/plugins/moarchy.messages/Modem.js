// The modem, as mmcli and gdbus print it.
//
// Quickshell has no D-Bus module, so ModemManager is reached the way the bar
// and moarchy-sim already reach it: through processes. Three kinds of them.
//
//   gdbus monitor   one, for as long as the app is loaded. It sleeps on the
//                   bus socket and prints a line per signal, which is how a
//                   call that starts ringing is heard without polling for it.
//   a collector     one `sh -c` per change: list the calls or the texts, then
//                   print each one as JSON on a line of its own.
//   an action       mmcli with arguments, one per tap.
//
// JSON rather than mmcli's key-value output, because `-K` escapes every byte
// outside ASCII as octal -- a text in German comes back as \303\244 -- while
// `-J` passes UTF-8 through to JSON.parse. Both print `--` for a value that is
// missing, empty, unknown or none, and `value()` below is the one place that
// is undone.
//
// `-m any` everywhere and never an index: ModemManager renumbers the modem when
// it re-enumerates (bin/moarchy-sim says so, and measured it). Every command is
// `sh -c` rather than the binary itself, because a Process handed a binary
// that is not installed never emits `exited` (Clock.qml measured that) -- a
// shell always starts, and a missing mmcli is an ordinary exit code 127.
//
// This file is identical in moarchy.phone and moarchy.messages.
.pragma library

var BUS = "org.freedesktop.ModemManager1"

// --- what gdbus says -----------------------------------------------------

var IGNORE = 0
var REFRESH = 1
// ModemManager went away or came back. Call and SMS paths come from a counter
// in the ModemManager process, so everything remembered by path is stale.
var RESYNC = 2

var WANTED = {
  calls: ["Modem.Voice", "Call"],
  messages: ["Modem.Messaging", "Sms"]
}

// One line of `gdbus monitor --system --dest org.freedesktop.ModemManager1`:
//
//   /org/freedesktop/ModemManager1/Modem/0: org.freedesktop.ModemManager1.Modem.Voice.CallAdded (objectpath '...',)
//   /org/freedesktop/ModemManager1/Call/1: org.freedesktop.DBus.Properties.PropertiesChanged ('org.freedesktop.ModemManager1.Call', {...}, @as [])
//   The name org.freedesktop.ModemManager1 is owned by :1.12
//
// The modem's own property changes -- signal quality, every few seconds -- are
// the lines this exists to throw away cheaply.
function classify(line, kind) {
  var t = String(line || "")
  if (t.indexOf("The name " + BUS + " ") === 0) return RESYNC
  var m = /^(\/org\/freedesktop\/ModemManager1\S*): (\S+) ?(.*)$/.exec(t)
  if (!m) return IGNORE
  var member = m[2]
  var args = m[3]
  if (member.indexOf("org.freedesktop.DBus.ObjectManager.Interfaces") === 0) return REFRESH
  var wanted = WANTED[kind] || []
  var i
  if (member === "org.freedesktop.DBus.Properties.PropertiesChanged") {
    for (i = 0; i < wanted.length; i++)
      if (args.indexOf("('" + BUS + "." + wanted[i] + "'") === 0) return REFRESH
    return IGNORE
  }
  for (i = 0; i < wanted.length; i++)
    if (member.indexOf(BUS + "." + wanted[i] + ".") === 0) return REFRESH
  return IGNORE
}

// --- what mmcli says -----------------------------------------------------

function value(v) {
  if (v === undefined || v === null) return ""
  var s = String(v)
  return s === "--" ? "" : s
}

// `mmcli -o <path> -J`
function parseCall(line) {
  var data
  try { data = JSON.parse(String(line || "")) } catch (e) { return null }
  var call = data && data.call
  if (!call || typeof call !== "object") return null
  var props = call.properties || {}
  var path = value(call["dbus-path"])
  if (!path) return null
  return {
    path: path,
    number: value(props.number),
    direction: value(props.direction),
    state: value(props.state),
    reason: value(props["state-reason"])
  }
}

// ModemManager prints a timestamp with the minutes of its offset dropped when
// they are zero -- 2025-03-14T09:26:53+01 -- which is ISO 8601 and which
// Date.parse does not accept.
function timestamp(text) {
  var t = value(text).trim()
  if (!t) return 0
  if (/[+-]\d\d$/.test(t)) t += ":00"
  else if (/[+-]\d\d\d\d$/.test(t)) t = t.slice(0, t.length - 2) + ":" + t.slice(t.length - 2)
  var ms = Date.parse(t)
  return isFinite(ms) ? ms : 0
}

// `mmcli -s <path> -J`
function parseSms(line) {
  var data
  try { data = JSON.parse(String(line || "")) } catch (e) { return null }
  var sms = data && data.sms
  if (!sms || typeof sms !== "object") return null
  var content = sms.content || {}
  var props = sms.properties || {}
  var path = value(sms["dbus-path"])
  if (!path) return null
  return {
    path: path,
    number: value(content.number),
    // A text that is literally "--" comes back empty. That is mmcli's doing
    // and there is no way to tell the two apart from out here.
    text: value(content.text),
    state: value(props.state),
    pduType: value(props["pdu-type"]),
    time: timestamp(props.timestamp)
  }
}

// The collector's output: one JSON document per line, anything else skipped.
function parseLines(text, parse) {
  var out = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var item = parse(line)
    if (item) out.push(item)
  }
  return out
}

// --- commands ------------------------------------------------------------

function mmcli(args) {
  return ["sh", "-c", "exec mmcli \"$@\"", "mmcli"].concat(args)
}

// With a parent-death signal. A shell that is restarted does not take its
// children with it, and gdbus has nothing to notice that it is gone: it sleeps
// on the bus and only finds its stdout closed the next time ModemManager says
// something. Measured on the Pixel with a locked SIM, where that is never --
// three restarts left six orphaned monitors behind. `setpriv --pdeathsig`
// makes the kernel send TERM when the shell goes; where util-linux is too old
// to have it, the monitor is started plainly.
function monitorCommand() {
  var script =
    "if setpriv --pdeathsig TERM true 2>/dev/null; then\n" +
    "  exec setpriv --pdeathsig TERM gdbus monitor --system --dest \"$0\"\n" +
    "fi\n" +
    "exec gdbus monitor --system --dest \"$0\"\n"
  return ["sh", "-c", script, BUS]
}

// Exit 3 when the list itself failed -- no modem, ModemManager restarting --
// so the caller can tell "there are no calls" from "nobody could say".
function collectCommand(kind) {
  var calls = kind === "calls"
  var list = calls ? "--voice-list-calls" : "--messaging-list-sms"
  var noun = calls ? "Call" : "SMS"
  var show = calls ? "-o" : "-s"
  var script =
    "list=$(mmcli -m any -K " + list + " 2>/dev/null) || exit 3\n" +
    "for p in $(echo \"$list\" | grep -o '/org/freedesktop/ModemManager1/" + noun + "/[0-9]*'); do\n" +
    "  mmcli " + show + " \"$p\" -J 2>/dev/null\n" +
    "  echo\n" +
    "done\n" +
    "exit 0\n"
  return ["sh", "-c", script]
}

// Create, then start. Two steps because that is ModemManager's API and what
// gnome-calls does; the start waits for the network (the modem allows 90
// seconds for the dial), which is why the timeout is longer than mmcli's 30.
function dialCommand(number) {
  var script =
    "out=$(mmcli -m any -K --voice-create-call=\"number=$1\" 2>&1) || { echo \"$out\" >&2; exit 1; }\n" +
    "path=$(echo \"$out\" | grep -o '/org/freedesktop/ModemManager1/Call/[0-9]*' | head -n 1)\n" +
    "[ -n \"$path\" ] || { echo \"$out\" >&2; exit 1; }\n" +
    "exec mmcli -o \"$path\" --start --timeout=100\n"
  return ["sh", "-c", script, "sh", number]
}

function acceptCommand(path) { return mmcli(["-o", path, "--accept"]) }
function hangupCommand(path) { return mmcli(["-o", path, "--hangup"]) }
function hangupAllCommand() { return mmcli(["-m", "any", "--voice-hangup-all"]) }
function hangupAndAcceptCommand() { return mmcli(["-m", "any", "--voice-hangup-and-accept"]) }

function dtmfCommand(path, key) {
  if (!/^[0-9*#A-D]$/.test(String(key))) return []
  return mmcli(["-o", path, "--send-dtmf=" + key])
}

// ModemManager keeps a call until somebody deletes it. gnome-calls deletes one
// as soon as it ends, and so does this.
function deleteCallsCommand(paths) {
  return ["sh", "-c", "for p in \"$@\"; do mmcli -m any --voice-delete-call=\"$p\" >/dev/null 2>&1; done; exit 0", "sh"]
    .concat(paths || [])
}

function deleteSmsCommand(paths) {
  return ["sh", "-c", "for p in \"$@\"; do mmcli -m any --messaging-delete-sms=\"$p\" >/dev/null 2>&1; done; exit 0", "sh"]
    .concat(paths || [])
}

// The text goes in on stdin, which is the whole reason this is safe:
// `--messaging-create-sms="text='...'"` is mmcli's key=value parser, which has
// no escaping, so a text with both kinds of quote in it cannot be said that
// way at all. `--messaging-create-sms-with-text` reads a file, and a pipe is a
// file. ModemManager picks GSM 7 or UCS-2 and splits long texts itself.
//
// Sent, the SMS object is deleted: the app has its own copy, and a modem
// that keeps every text it ever sent is a SIM that fills up. A failed send is
// only a non-zero exit and a sentence on stderr -- ModemManager has no failed
// state for an SMS -- so that sentence is what the app shows.
function sendCommand(number, text) {
  var script =
    "out=$(printf %s \"$1\" | mmcli -m any -K --messaging-create-sms=\"number=$2\" --messaging-create-sms-with-text=/dev/stdin 2>&1) || { echo \"$out\" >&2; exit 2; }\n" +
    "path=$(echo \"$out\" | grep -o '/org/freedesktop/ModemManager1/SMS/[0-9]*' | head -n 1)\n" +
    "[ -n \"$path\" ] || { echo \"$out\" >&2; exit 2; }\n" +
    "err=$(mmcli -s \"$path\" --send --timeout=600 2>&1 >/dev/null)\n" +
    "code=$?\n" +
    "mmcli -m any --messaging-delete-sms=\"$path\" >/dev/null 2>&1\n" +
    "[ $code -eq 0 ] || { echo \"$err\" >&2; exit 1; }\n" +
    "exit 0\n"
  return ["sh", "-c", script, "sh", String(text), String(number)]
}

// mmcli's errors are `error: couldn't start call: 'GDBus.Error:...: reason'`.
// The part a person can read is the last quoted reason, if there is one.
function trouble(stderr, fallback) {
  var t = String(stderr || "").trim()
  if (!t) return fallback
  var lines = t.split("\n")
  var last = lines[lines.length - 1]
  var m = /:\s*([^:']+)'?\s*$/.exec(last)
  var reason = m ? m[1].trim() : last
  if (/not authorized|challenge needed/i.test(t)) return "The modem refused: not allowed from here."
  if (/no modems were found|couldn't find modem/i.test(t)) return "No modem."
  if (!reason) return fallback
  return reason.charAt(0).toUpperCase() + reason.slice(1)
}

// --- feedback and audio --------------------------------------------------

// feedbackd, so a ring follows the phone's own profile: a tone, a buzz, or
// nothing. fbcli ends the feedback on the first readable byte of its stdin --
// /dev/null is always readable -- so the Process that runs this has to keep a
// pipe open (`stdinEnabled`). `-w` is how long it waits for the feedback to
// end, 30 seconds unless told otherwise.
function feedbackCommand(event, loop, quiet) {
  var args = ["-E", event, "-t", loop ? "0" : "-1", "-w", loop ? "3600" : "30"]
  if (quiet) args = args.concat(["-P", "quiet"])
  return ["sh", "-c", "exec fbcli \"$@\"", "fbcli"].concat(args)
}

// The screen, for a call that arrives while the phone is in a pocket.
//
// moarchy-screen's `wake` refuses while the lock flag is set -- that is its
// whole point -- and a locked phone also has its touchscreen switched off, so
// a ringing call on a locked phone has to `unlock`. It says "locked" first
// when it did, so the app can put the lock back when the call is over. Off
// moarchy there is no such tool and nothing to do.
var SCREEN = "/usr/lib/moarchy/bin/moarchy-screen"

function wakeCommand() {
  var script =
    "t=\"$1\"\n" +
    "[ -x \"$t\" ] || exit 0\n" +
    "if [ -e \"${XDG_STATE_HOME:-$HOME/.local/state}/moarchy/screen-locked\" ]; then\n" +
    "  echo locked\n" +
    "  exec \"$t\" unlock\n" +
    "fi\n" +
    "exec \"$t\" wake\n"
  return ["sh", "-c", script, "sh", SCREEN]
}

function lockCommand() {
  return ["sh", "-c", "[ -x \"$1\" ] && exec \"$1\" lock; exit 0", "sh", SCREEN]
}

// A line in the shade's notification list. Nothing on this phone pops up --
// moarchy.bar turns popups off -- so this is where a text that arrived while
// the phone was in a pocket is found. `omarchy-notification-send` because the
// image has no libnotify; off moarchy, nothing.
function notifyCommand(title, body) {
  return ["sh", "-c",
          "command -v omarchy-notification-send >/dev/null 2>&1 || exit 0\n" +
          "exec omarchy-notification-send \"$1\" \"$2\" >/dev/null 2>&1",
          "sh", String(title), String(body)]
}

// callaudiod: the earpiece and the call profile while a call is up, back to
// ordinary audio when the last one ends. D-Bus activated on the session bus.
function callAudioCommand(method, type, arg) {
  return ["sh", "-c",
          "exec busctl --user call org.mobian_project.CallAudio /org/mobian_project/CallAudio org.mobian_project.CallAudio \"$@\" >/dev/null 2>&1",
          "sh", method, type, String(arg)]
}

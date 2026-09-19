// A clock for a phone: the time, an alarm, a stopwatch and a timer.
//
// Three tabs and no fourth. Android's clock has a world-clock page and this
// does not, because the one thing a world clock needs is a list of somewhere
// else -- and the page that would carry it is the page a phone already has a
// clock on, in its own status bar. What is left is the three things a phone is
// actually picked up to do with time, and the first screen of the three is a
// dial, because an app called Clock whose first screen is a list is an app
// that has hidden the thing it is named after.
//
// It was written for the shell first, and for this app that is not a
// convenience -- it is the only arrangement in which an alarm works at all.
// `keepLoaded` means this Item exists from the moment the shell starts, so the
// timer that watches for an alarm is running while the window is nowhere on
// screen. A GTK app in `apps/` could not do this without a second package
// holding a systemd service, and then the alarm would live somewhere the app
// could not see.
//
// What it still cannot do is wake a phone that is asleep. Nothing a user
// process can do will: `WakeSystem=true` on a systemd timer is root's, and so
// is `rtcwake`. So the honest behaviour is the one implemented here -- an
// alarm that came due while the phone was off rings when it comes back, and
// says how late it is, up to an hour. Past that it is recorded as missed and
// said out loud, because a phone that rings at ten for a seven o'clock alarm
// is worse than one that admits it slept through.
//
// Bound because every list on these three screens is a Repeater or a ListView
// whose delegate reads the palette, the clock and the units off `root`.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Alarms.js" as Alarms
import "Watch.js" as Watch
import "Store.js" as Store

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "moarchy.clock"
  readonly property bool opened: clockWindow.visible
  readonly property var appWindow: clockWindow

  property string returnTo: ""
  // `colours` and not `palette`: QQuickItem already has a `palette`, and
  // shadowing it makes a binding resolve to whichever the compiler picked.
  readonly property var colours: themeFile.colours
  property int bodySize: Metrics.BODY

  Component.onCompleted: {
    root.bodySize = Metrics.shellBody(root)
    root.applyHarness()
    // Read the file now, before any window exists. `keepLoaded` puts this Item
    // on the screen's behalf at shell start and the whole alarm depends on it:
    // waiting for the first `open()` would mean no alarm worked until somebody
    // had opened the app once since the shell came up, which is the failure
    // nobody would notice until a morning.
    Qt.callLater(root.ensureLoaded)
  }

  // --- what is known --------------------------------------------------------

  property var alarms: []
  // Rows of the file this app cannot read, kept so that saving does not
  // destroy them. Store.js says why at length.
  property var strays: []
  property var watch: Watch.blankWatch()
  property var timer: Watch.blankTimer()
  property var settings: Store.defaults()

  property bool loaded: false
  property bool dirty: false

  // The clock, in milliseconds, sampled rather than counted. Everything on
  // every screen is drawn from this one number, which is what lets the
  // screenshot harness pin it.
  property double now: Date.now()
  // Zero except under the harness. Pinned for the reason the GTK apps pin
  // theirs: two pictures of a clock taken a second apart are two different
  // pictures, for reasons that have nothing to do with the app.
  property double pinnedNow: 0
  readonly property bool pinned: root.pinnedNow > 0

  // 0 alarm, 1 stopwatch, 2 timer.
  property int page: 0

  // The alarm being edited, or null. A copy, always: nothing in `alarms`
  // changes until Save is pressed, which is what makes Back a cancel.
  property var draft: null
  property bool draftIsNew: false
  // The bin asks twice. There is no undo in a file with one version of
  // itself, so the second tap is the undo.
  property bool armed: false

  // The one thing this app has to say that a toast is too small for: an alarm
  // that did not ring. It stays on the screen until it is dismissed, because
  // the whole of what this app can honestly promise about a sleeping phone is
  // that it will tell you afterwards -- and telling you for three seconds,
  // while the window was not up, is not telling you.
  //
  // Not written to the file. The shell restarting means this Item was built
  // again, and a note about an alarm from before that is a note about a
  // different session.
  property string missedNote: ""

  // What is going off, or null:
  //   { kind: "alarm" | "timer", id, at, since, label, time }
  property var ringing: null
  property bool menuOpen: false

  // The timer's keypad, as digits pushed in from the right.
  property var digits: []

  // The harness's overrides.
  property string harnessPage: ""
  property string harnessTyped: ""
  property bool quiet: false

  readonly property string dataDir: Plugin.dataDir(
    "clock", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_CLOCK_DIR"))

  // A ring nobody answers gives up rather than going on for ever, and says so
  // afterwards. Five minutes is roughly what a bedside clock radio managed
  // before its own timer cut it.
  readonly property int ringSeconds: 300

  // --- derived --------------------------------------------------------------

  // Twelve or twenty-four hours. Nobody's choice until somebody makes one, and
  // until then it is the phone's: Qt's own short time format for the locale
  // either has an AM/PM field in it or does not, which is the same question
  // asked of the same place GTK asks it.
  readonly property bool localeHour24:
    String(Qt.locale().timeFormat(Locale.ShortFormat)).toLowerCase().indexOf("a") < 0

  readonly property bool hour24: typeof root.settings.hour24 === "boolean"
                                 ? root.settings.hour24 : root.localeHour24

  readonly property var ordered: Store.sorted(root.alarms)
  readonly property var next: Alarms.soonest(root.alarms, root.now)

  readonly property double elapsed: Watch.elapsed(root.watch, root.now)
  readonly property var laps: Watch.lapRows(root.watch, root.now)
  readonly property double remaining: Watch.timerLeft(root.timer, root.now)
  readonly property double typed: Watch.keypadMs(root.digits)

  readonly property bool editing: root.draft !== null

  // The clock's own hands, as three fractions. Read off `now` so that a pinned
  // clock has pinned hands.
  readonly property var face: {
    var d = new Date(root.now)
    return {
      hours: d.getHours() % 12,
      minutes: d.getMinutes(),
      seconds: d.getSeconds() + d.getMilliseconds() / 1000
    }
  }

  // --- colour ---------------------------------------------------------------

  readonly property color background: root.colours.background
  readonly property color ink: root.colours.foreground
  readonly property color dim: root.colours.dim
  readonly property color accent: root.colours.accent

  function hue(name: string): color {
    var hues = root.colours.hues || {}
    return hues[name] || root.colours.accent
  }

  readonly property color danger: root.hue("red")
  readonly property color good: root.hue("green")

  // How bright a colour is, on the crude weighting that has been good enough
  // for choosing black-or-white text since the nineteen-fifties.
  function shade(colour): real {
    var c = Theme.rgb(String(colour))
    return (c[0] * 299 + c[1] * 587 + c[2] * 114) / 255000.0
  }

  // What can be read on a solid accent fill. Not always the background: on a
  // light theme that is white, and white on a pale yellow accent is a Start
  // button nobody can find. Calculator's rule, and its reason.
  readonly property color accentInk: {
    var level = root.shade(root.colours.accent)
    return Math.abs(level - root.shade(root.colours.background))
         > Math.abs(level - root.shade(root.colours.foreground))
      ? root.colours.background : root.colours.foreground
  }

  // A step up from the window, mixed from the theme's *foreground* rather than
  // from its surface. Minesweeper's rule and its reason: on a light theme the
  // surface colour is nearly the window colour, so anything mixed from it
  // comes out invisible.
  readonly property color card: Theme.mix(root.colours.foreground, root.colours.background, 0.07)
  readonly property color sunk: Theme.mix(root.colours.foreground, root.colours.background, 0.12)

  function wash(colour, amount: real): color {
    return Theme.mix(colour, root.colours.background, amount)
  }

  // --- the clock ------------------------------------------------------------

  function clockNow(): double {
    return root.pinned ? root.pinnedNow : Date.now()
  }

  // Re-read the clock and hand it back, for anything a thumb just did. The
  // beat below is a second wide and a stopwatch started on a second-old
  // reading of the clock is a stopwatch that is wrong by up to a second, which
  // is the one number in this app nobody would forgive.
  function stamp(): double {
    root.now = root.clockNow()
    return root.now
  }

  // A sentence for the toast -- or kept until there is a screen to put it on.
  //
  // Most of what this app has to say, it has to say while the window is
  // nowhere: an alarm that went by, a row of the file it could not read, a ring
  // that nobody answered. A Toast in a window that is not mapped runs its three
  // seconds out against nobody.
  property string pending: ""

  function say(text: string): void {
    if (clockWindow.visible) { toast.show(text); return }
    root.pending = String(text || "")
  }

  // --- the harness ----------------------------------------------------------

  function applyHarness(): void {
    var at = parseInt(Quickshell.env("MOARCHY_CLOCK_NOW") || "0", 10)
    root.pinnedNow = at > 0 ? at * 1000 : 0
    root.now = root.clockNow()
    root.harnessPage = String(Quickshell.env("MOARCHY_CLOCK_PAGE") || "")
    root.harnessTyped = String(Quickshell.env("MOARCHY_CLOCK_TYPED") || "")
    // _OFFLINE is what both harnesses set, and for a clock it has one useful
    // meaning: do not put a sound on a machine that is taking photographs.
    root.quiet = (Quickshell.env("MOARCHY_CLOCK_OFFLINE") || "") !== ""
  }

  function applyHarnessPage(): void {
    if (root.harnessTyped.length) {
      root.timer = Watch.blankTimer()
      var keys = []
      for (var i = 0; i < root.harnessTyped.length; i++) {
        var d = parseInt(root.harnessTyped.charAt(i), 10)
        if (isFinite(d)) keys = Watch.push(keys, d)
      }
      root.digits = keys
    }
    var want = root.harnessPage
    if (!want.length) return
    if (want === "stopwatch") root.page = 1
    else if (want === "timer" || want === "keypad") root.page = 2
    else root.page = 0
    if (want === "editor" && root.ordered.length) root.edit(root.ordered[0].id)
    if (want === "ring") {
      // Four minutes ago, and an alarm set for then -- rather than whichever
      // alarm is in the fixture, whose last occurrence may be hours back. The
      // app would never ring an alarm that late; it would record it as missed.
      // A photograph of a screen the app cannot reach is a photograph that
      // lies, which is the one thing a screenshot in a README must not do.
      var when = root.now - 4 * 60000
      var clock = new Date(when)
      var probe = Alarms.blank(clock.getHours(), clock.getMinutes())
      probe.label = root.ordered.length ? root.ordered[0].label : ""
      root.ring("alarm", probe, when)
    }
  }

  // --- the shell's plugin contract ------------------------------------------

  function open(payloadJson: string): void {
    Plugin.hideOverlays(root.shell)
    root.returnTo = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload.returnTo) root.returnTo = String(payload.returnTo)
      if (payload.page === "stopwatch") root.page = 1
      else if (payload.page === "timer") root.page = 2
      else if (payload.page === "alarm") root.page = 0
    } catch (e) {}
    clockWindow.show()
    Qt.callLater(root.ensureLoaded)
  }

  // `close()` has to actually take the window down.
  //
  // This is the host's contract and it is not guessable from the name: read
  // /usr/share/omarchy/shell/shell.qml, and `hide(pluginId)` does
  // `invokeIfLoaded(id, "close", null)` while `isPluginOpen(pluginId)` reads
  // the plugin's own `opened`. `toggle()` is then
  // `isPluginOpen(id) ? hide(id) : summon(id, ...)`.
  //
  // So a `close()` that only reset page state -- which is what this was, and
  // what its siblings in this repository still are -- leaves `opened` true for
  // ever: the first tap on the app drawer icon opens the app and no tap ever
  // closes it again. Measured on the phone, on this plugin and on two others.
  //
  // A ring is the one exception. Nothing that can happen by accident should be
  // able to lose an alarm that is going off, and a tap on a app drawer icon is the
  // definition of something that happens by accident.
  function close(): void {
    root.draft = null
    root.armed = false
    root.menuOpen = false
    if (root.ringing) return
    root.saveIfDirty()
    clockWindow.hide()
  }

  function dismiss(): void {
    if (root.ringing) return
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
    var back = root.returnTo
    root.returnTo = ""
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, "{}")
  }

  function ensureLoaded(): void {
    if (root.loaded) return
    root.loaded = true
    ensureDir.running = true
    storeFile.reload()
  }

  // Bring the window up for something the app decided, rather than for
  // something a thumb did.
  function raise(): void {
    if (root.shell && typeof root.shell.summon === "function") {
      root.shell.summon(root.pluginId, "{}")
      return
    }
    clockWindow.show()
  }

  // --- the file -------------------------------------------------------------

  function stateOut(): var {
    return {
      alarms: root.alarms, strays: root.strays,
      watch: root.watch, timer: root.timer, settings: root.settings
    }
  }

  function save(): void {
    storeFile.setText(Store.serialize(root.stateOut()))
    root.dirty = false
  }

  function saveIfDirty(): void {
    if (root.dirty) root.save()
  }

  // An alarm somebody set, a lap somebody took, a stopwatch somebody started:
  // all of them are written at once, because every one of them is rare and
  // every one of them is the thing that would be missed. What is never written
  // per change is the clock -- there is no tick in this app that touches the
  // disk.
  function commit(): void {
    root.dirty = true
    root.save()
  }

  function setSetting(key: string, value): void {
    var next = { hour24: root.settings.hour24, silent: root.settings.silent }
    next[key] = value
    root.settings = next
    root.commit()
  }

  // --- the alarms -----------------------------------------------------------

  function startNew(): void {
    var d = new Date(root.now)
    // Seven in the morning, which is the alarm most people are setting, unless
    // there is already one at seven -- then the hour they are looking at, so a
    // second alarm is not a fight with the wheel.
    var hour = 7
    if (Alarms.soonest(root.alarms, root.now)) hour = (d.getHours() + 1) % 24
    root.draft = Alarms.blank(hour, 0)
    root.draftIsNew = true
    root.armed = false
    labelField.text = ""
  }

  function edit(id: string): void {
    var alarm = Alarms.find(root.alarms, id)
    if (!alarm) return
    root.draft = Alarms.clone(alarm)
    root.draftIsNew = false
    root.armed = false
    labelField.text = alarm.label
  }

  function change(key: string, value): void {
    if (!root.draft) return
    // A write that changes nothing changes nothing. Without this the wheels
    // are a binding loop: each one's `value` is read off the draft, picking a
    // number writes the draft, a new draft re-evaluates both `value` bindings,
    // and each of those pushes its view's index back -- which emits `picked`
    // again. Qt detects it and says so; stopping the echo at the first hop is
    // the fix, and it is also just correct.
    if (root.draft[key] === value) return
    var next = Alarms.clone(root.draft)
    next[key] = value
    root.draft = next
  }

  function toggleDay(day: int): void {
    if (!root.draft) return
    var days = root.draft.days.slice()
    var at = days.indexOf(day)
    if (at >= 0) days.splice(at, 1)
    else days.push(day)
    days.sort(function (a, b) { return a - b })
    root.change("days", days)
  }

  function setRepeat(days): void {
    root.change("days", days.slice())
  }

  function saveDraft(): void {
    if (!root.draft) return
    if (root.draftIsNew && root.alarms.length >= Alarms.MAX) {
      root.say(Alarms.MAX + " alarms is as many as this app keeps.")
      return
    }
    var next = Alarms.clone(root.draft)
    if (!next.id.length) next.id = Alarms.newId(root.alarms.length + 1)
    next.enabled = true
    // Armed from now, not from zero. `fired` records the last occurrence that
    // has been dealt with, and an alarm just set has dealt with all of them --
    // everything before this instant already happened, whatever the hands say.
    //
    // Zero here was a bug, and the ordinary case was the worst of it: at 10:09,
    // an alarm set for 10:15 has a most recent occurrence of *yesterday* at
    // 10:15, which is unrung and more than an hour ago, so the app announced a
    // brand new alarm as one it had slept through. An alarm set for 10:00 was
    // worse still and simply went off.
    next.fired = root.stamp()
    next.snoozed = 0
    root.alarms = Store.put(root.alarms, next)
    root.commit()
    root.draft = null
    var at = Alarms.nextFire(next, root.now)
    root.say(Alarms.timeText(next.hour, next.minute, root.hour24)
             + (root.hour24 ? "" : " " + Alarms.meridiem(next.hour))
             + " · " + (at ? Alarms.untilLabel(at - root.now) : "off"))
  }

  function deleteDraft(): void {
    if (!root.draft) return
    if (!root.armed) { root.armed = true; return }
    root.alarms = Store.drop(root.alarms, root.draft.id)
    root.commit()
    root.draft = null
    root.armed = false
    root.say("Alarm deleted.")
  }

  function toggleAlarm(id: string): void {
    var alarm = Alarms.find(root.alarms, id)
    if (!alarm) return
    var next = Alarms.clone(alarm)
    next.enabled = !next.enabled
    next.snoozed = 0
    // Switching an alarm on is a decision about the future, so what it did in
    // the past stops counting -- an alarm switched on at 07:05 must not fire
    // immediately for the seven o'clock it was off for.
    if (next.enabled) next.fired = root.stamp()
    root.alarms = Store.put(root.alarms, next)
    root.commit()
    if (next.enabled) {
      var at = Alarms.nextFire(next, root.now)
      if (at) root.say(Alarms.untilLabel(at - root.now))
    }
  }

  // --- what goes off, and when ----------------------------------------------

  function ring(kind: string, subject, at: double): void {
    root.ringing = {
      kind: kind,
      id: kind === "alarm" ? subject.id : "timer",
      at: at,
      since: root.now,
      label: kind === "alarm"
        ? (subject.label.length ? subject.label : "Alarm")
        : (Watch.spanLabel(root.timer.total) + " timer"),
      time: kind === "alarm"
        ? Alarms.timeText(subject.hour, subject.minute, root.hour24)
        : Watch.timerText(0)
    }
    root.startSound()
  }

  // Everything that has to happen because the clock moved. Called by every
  // timer in the file and by nothing else, so there is one place where an
  // alarm can go off.
  function settle(): void {
    if (root.ringing) {
      // A ring that has gone unanswered for long enough stops, and the alarm
      // is left switched off rather than armed -- it has had its turn.
      if (root.now - root.ringing.since > root.ringSeconds * 1000) {
        var what = root.ringing.label
        root.stopSound()
        if (root.ringing.kind === "timer") root.timer = Watch.blankTimer()
        root.ringing = null
        root.commit()
        root.say(what + " rang for " + Math.round(root.ringSeconds / 60)
                 + " minutes with nobody listening.")
      }
      return
    }

    for (var i = 0; i < root.alarms.length; i++) {
      var alarm = root.alarms[i]
      var at = Alarms.due(alarm, root.now)
      if (at) {
        root.alarms = Store.put(root.alarms, Alarms.rang(alarm, at))
        root.commit()
        root.ring("alarm", alarm, at)
        root.raise()
        return
      }
      var lost = Alarms.missed(alarm, root.now)
      if (lost) {
        root.alarms = Store.put(root.alarms, Alarms.rang(alarm, lost))
        root.commit()
        root.missedNote = Alarms.timeText(alarm.hour, alarm.minute, root.hour24)
          + (alarm.label.length ? " · " + alarm.label : "")
          + " went by " + Alarms.whichDay(lost, root.now)
          + " while the phone was off."
      }
    }

    var over = Watch.timerDue(root.timer, root.now)
    if (over) {
      root.ring("timer", null, over)
      root.raise()
      return
    }
    var gone = Watch.timerMissed(root.timer, root.now)
    if (gone) {
      var span = Watch.spanLabel(root.timer.total)
      root.timer = Watch.blankTimer()
      root.commit()
      root.missedNote = "The " + span + " timer ended while the phone was off."
    }
  }

  function snoozeRing(): void {
    if (!root.ringing || root.ringing.kind !== "alarm") return
    var alarm = Alarms.find(root.alarms, root.ringing.id)
    root.stopSound()
    root.ringing = null
    if (!alarm) return
    var next = Alarms.snooze(alarm, root.stamp())
    root.alarms = Store.put(root.alarms, next)
    root.commit()
    root.say("Again " + Alarms.untilLabel(next.snoozed - root.now) + ".")
  }

  function stopRing(): void {
    if (!root.ringing) return
    var wasTimer = root.ringing.kind === "timer"
    root.stopSound()
    root.ringing = null
    if (wasTimer) {
      root.timer = Watch.blankTimer()
      root.page = 2
    }
    root.commit()
  }

  // --- the sound ------------------------------------------------------------
  //
  // Nothing here ships a tone. The one an alarm should make is already on the
  // phone -- `alarm-clock-elapsed` in the freedesktop sound theme, which is
  // what every GNOME alarm has used for fifteen years -- and the players are
  // whichever of pipewire's, pulse's or libcanberra's happens to be installed.
  //
  // Which one that is, is not asked. It is found the way the kit finds an
  // icon: try the first, and treat a non-zero exit as the answer. When the
  // list runs out, the ring is silent and the screen says so, because an alarm
  // that is quietly mute is the worst failure this app has.
  //
  // Every candidate goes through `sh -c`, and that is not decoration. Measured:
  // handed a binary that is not installed, Quickshell's Process does not emit
  // `exited` at all -- it logs "Process failed to start, likely because the
  // binary could not be found" and puts `running` back to false. So the walk
  // below stopped dead at the first missing player, the list after it was never
  // tried, `mute` was never set, and the screen said nothing. An alarm that is
  // quietly mute, in other words, which is the one thing this was written not
  // to be.
  //
  // `sh` is always there, so with the wrapper the process always starts and a
  // missing player is an ordinary exit code 127 -- which is what the walk was
  // written to read. The arguments are passed as positional parameters rather
  // than pasted into the script, so nothing here depends on a path not
  // containing a space.

  readonly property var players: [
    ["pw-play", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"],
    ["paplay", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"],
    ["canberra-gtk-play", "-i", "alarm-clock-elapsed"],
    ["pw-play", "/usr/share/sounds/freedesktop/stereo/complete.oga"],
    ["paplay", "/usr/share/sounds/freedesktop/stereo/complete.oga"]
  ]

  // ["pw-play", "/a/b.oga"] becomes
  // ["sh", "-c", "exec \"$0\" \"$1\"", "pw-play", "/a/b.oga"].
  function playCommand(spec): var {
    var line = "exec \"$0\""
    for (var i = 1; i < spec.length; i++) line += " \"$" + i + "\""
    return ["sh", "-c", line].concat(spec)
  }

  property int player: 0
  // Nothing on this machine could play it. Said on the ringing screen rather
  // than in a log, and it stays set for as long as the shell runs -- so the
  // walk costs five processes once, not five every time something goes off.
  property bool mute: false

  readonly property bool silent: root.quiet || !!root.settings.silent

  function startSound(): void {
    if (root.silent || root.mute) return
    root.player = 0
    root.playOnce()
  }

  function playOnce(): void {
    if (!root.ringing || root.silent || root.mute) return
    if (root.player >= root.players.length) { root.mute = true; return }
    tone.command = root.playCommand(root.players[root.player])
    tone.running = true
  }

  function stopSound(): void {
    gap.stop()
    tone.running = false
  }

  function toneEnded(code: int): void {
    if (!root.ringing) return
    if (code !== 0) {
      // 127 for a player that is not installed, something else for one that
      // cannot read that file. Either way: next.
      root.player += 1
      root.playOnce()
      return
    }
    // A tone on a loop with no space in it is a siren. The gap is what makes
    // it an alarm clock.
    gap.restart()
  }

  // --- the stopwatch --------------------------------------------------------

  function watchStart(): void {
    root.watch = Watch.startWatch(root.watch, root.stamp())
    root.commit()
  }

  function watchStop(): void {
    root.watch = Watch.stopWatch(root.watch, root.stamp())
    root.commit()
  }

  function watchLap(): void {
    var before = root.watch.laps.length
    root.watch = Watch.lapWatch(root.watch, root.stamp())
    if (root.watch.laps.length === before && before >= Watch.MAX_LAPS)
      root.say(Watch.MAX_LAPS + " laps is as many as this keeps.")
    else root.commit()
  }

  function watchReset(): void {
    root.watch = Watch.blankWatch()
    root.commit()
  }

  // --- the timer ------------------------------------------------------------

  function keyDigit(digit: int): void {
    root.digits = Watch.push(root.digits, digit)
  }

  function keyBack(): void {
    root.digits = Watch.pop(root.digits)
  }

  function keyClear(): void {
    root.digits = []
  }

  function keyPreset(seconds: int): void {
    root.digits = Watch.digitsFor(seconds * 1000)
  }

  function timerStart(): void {
    var ms = Watch.keypadMs(root.digits)
    if (ms <= 0) return
    root.timer = Watch.startTimer(ms, root.stamp())
    root.digits = []
    root.commit()
  }

  function timerPause(): void {
    root.timer = Watch.pauseTimer(root.timer, root.stamp())
    root.commit()
  }

  function timerResume(): void {
    root.timer = Watch.resumeTimer(root.timer, root.stamp())
    root.commit()
  }

  function timerAdd(): void {
    root.timer = Watch.extendTimer(root.timer, root.stamp(), 60000)
    root.commit()
  }

  function timerCancel(): void {
    root.timer = Watch.blankTimer()
    root.commit()
  }

  // --- plumbing -------------------------------------------------------------

  // The beat, while the window is on screen. One second, re-aimed at the next
  // whole one every time it fires: a QML Timer goes off on the first frame
  // after its interval, which is up to 16ms late, and that error accumulates
  // until the digital clock skips a minute-boundary by a beat. Reassigning the
  // interval restarts it, which is what pulls the phase back.
  Timer {
    id: beat
    interval: 1000
    repeat: true
    running: clockWindow.visible && !root.pinned
    onTriggered: {
      root.now = root.clockNow()
      beat.interval = Math.max(120, 1000 - (root.now % 1000))
      root.settle()
    }
  }

  // The one screen that needs more than a second, while it is the screen on
  // screen. Ten a second for the stopwatch's tenths; four for a countdown,
  // which only has to catch the second it changes on.
  Timer {
    id: fast
    interval: root.page === 1 ? 100 : 250
    repeat: true
    running: clockWindow.visible && !root.pinned && !root.editing
             && ((root.page === 1 && root.watch.running)
                 || (root.page === 2 && root.timer.running))
    onTriggered: root.now = root.clockNow()
  }

  // The alarm's own clock, for when there is no window at all.
  //
  // Its interval is the time until the next thing that has to happen, capped
  // at a minute, so a phone with an alarm eight hours away is woken sixty
  // times an hour rather than three thousand six hundred -- and one second
  // before the alarm, it is woken once. Only while the window is down, because
  // the beat above already does this while it is up; `interval` follows `now`,
  // and two timers both moving `now` would restart each other for ever.
  readonly property int wakeIn: {
    var at = 0
    if (root.ringing) {
      // The only deadline left is giving up on it. Without this branch the
      // next line below would keep handing back a timer whose end is already
      // in the past -- the one that is ringing -- and the floor would then run
      // this timer at its fastest for the whole five minutes, doing nothing.
      at = root.ringing.since + root.ringSeconds * 1000
    } else {
      if (root.next) at = root.next.at
      // `> root.now` and not `> 0`: a finished timer is cleared by settle() on
      // the same turn, and until it is, its end is in the past.
      if (root.timer.running && root.timer.endsAt > root.now)
        at = at ? Math.min(at, root.timer.endsAt) : root.timer.endsAt
    }
    if (!at) return 60000
    // A second is the floor rather than a quarter of one. Anything in the past
    // that settle() has not cleared yet is then a wakeup a second, not four,
    // and an alarm is never more than a second late on account of it -- which
    // this app measures in minutes anyway.
    return Math.max(1000, Math.min(60000, at - root.now))
  }

  Timer {
    id: wake
    interval: root.wakeIn
    repeat: true
    running: !clockWindow.visible && !root.pinned
    onTriggered: {
      root.now = root.clockNow()
      root.settle()
    }
    // Explicit, because whether assigning `interval` restarts a running timer
    // is not something to leave to a version of Qt.
    onIntervalChanged: if (wake.running) wake.restart()
  }

  Timer {
    id: gap
    interval: 900
    onTriggered: root.playOnce()
  }

  Process {
    id: ensureDir
    running: false
    command: ["mkdir", "-p", root.dataDir]
  }

  Process {
    id: tone
    running: false
    // The disable is Quickshell's gap, not ours: `exited` carries a
    // QProcess::ExitStatus, and that enum is not in the type information the
    // module ships, so the linter cannot resolve a parameter this handler does
    // not even read.
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.toneEnded(code) }
    // qmllint enable signal-handler-parameters
  }

  Chrome.JsonFile {
    id: storeFile
    path: root.dataDir + "/clock.json"

    onParsed: function (data) {
      var state = Store.parse(data)
      // An enabled alarm with no `fired` on it came from a text editor, not
      // from here: this app records the occurrence it has dealt with every time
      // it writes. Arming it from now is the same rule the editor uses -- and
      // without it, a line somebody typed at nine in the morning would be
      // announced as an alarm that had been slept through at seven.
      for (var i = 0; i < state.alarms.length; i++) {
        if (state.alarms[i].enabled && !state.alarms[i].fired)
          state.alarms[i].fired = root.clockNow()
      }
      root.alarms = state.alarms
      root.strays = state.strays
      root.watch = state.watch
      root.timer = state.timer
      root.settings = state.settings
      root.now = root.clockNow()
      root.applyHarnessPage()
      // After the state is in, never before: an alarm that came due while the
      // phone was off is only knowable once the file has been read.
      Qt.callLater(root.settle)
      if (state.strays.length)
        root.say(state.strays.length + " row" + (state.strays.length === 1 ? "" : "s")
                 + " in the file could not be read, and were left alone.")
    }

    onQuarantined: function (to) {
      root.say("The clock file was unreadable and was kept aside.")
    }
  }

  Chrome.ThemeFile { id: themeFile }

  IpcHandler {
    target: "clock"
    function state(): string { return root.opened ? "open" : "closed" }
    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      return "ok"
    }
    function close(): string { root.dismiss(); return "ok" }
    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }
    // The three questions a status bar or a script would ask.
    function next(): string {
      if (!root.next) return ""
      return Alarms.timeText(root.next.alarm.hour, root.next.alarm.minute, root.hour24)
             + " " + Alarms.untilLabel(root.next.at - root.now)
    }
    function elapsed(): string {
      return root.watch.running || root.elapsed > 0 ? Watch.watchText(root.elapsed) : ""
    }
    function remaining(): string {
      return root.timer.total > 0 ? Watch.timerText(root.remaining) : ""
    }
    // And the two a button on a headset would.
    function snooze(): string {
      if (!root.ringing) return "nothing is ringing"
      root.snoozeRing()
      return "ok"
    }
    function stop(): string {
      if (!root.ringing) return "nothing is ringing"
      root.stopRing()
      return "ok"
    }
  }


  // The days, in the order this phone's week runs. Qt numbers Sunday 0, which
  // is also how `Date.getDay()` numbers it, so the two agree without a map.
  readonly property var weekOrder: {
    var first = Qt.locale().firstDayOfWeek
    var out = []
    for (var i = 0; i < 7; i++) out.push((first + i) % 7)
    return out
  }

  readonly property var keypad: [
    { text: "1", key: 1 }, { text: "2", key: 2 }, { text: "3", key: 3 },
    { text: "4", key: 4 }, { text: "5", key: 5 }, { text: "6", key: 6 },
    { text: "7", key: 7 }, { text: "8", key: 8 }, { text: "9", key: 9 },
    // "00" is two taps in one, because a duration typed on this keypad is
    // almost always a round number of minutes.
    { text: "00", key: -2 }, { text: "0", key: 0 }, { text: "", key: -1 }
  ]

  function keyPress(key: int): void {
    if (key === -1) { root.keyBack(); return }
    if (key === -2) { root.keyDigit(0); root.keyDigit(0); return }
    root.keyDigit(key)
  }

  // --- the window -----------------------------------------------------------

  Chrome.AppWindow {
    id: clockWindow
    shell: root.shell
    appName: "Clock"
    pageTitle: root.ringing ? "Ringing"
             : root.editing ? (root.draftIsNew ? "New alarm" : "Alarm")
             : (root.page === 1 ? "Stopwatch" : (root.page === 2 ? "Timer" : "Alarm"))
    pluginId: root.pluginId
    color: root.background

    onMapped: {
      root.now = root.clockNow()
      // The hands are put where the clock is and the sweep starts again from
      // there. Without this a window reopened after an hour would animate the
      // seconds hand from wherever it was parked.
      dial.lock()
      Qt.callLater(root.ensureLoaded)
      Qt.callLater(root.settle)
      if (root.pending.length) {
        toast.show(root.pending)
        root.pending = ""
      }
    }

    // Written when the window leaves the screen, which on this phone is the
    // event immediately before the app is reclaimed. Everything a thumb does
    // is already saved as it happens; this is for the clock having moved since.
    onUnmapped: root.saveIfDirty()

    Rectangle {
      anchors.fill: parent
      color: root.background
      focus: true

      Keys.onEscapePressed: {
        if (root.ringing) { root.stopRing(); return }
        if (root.menuOpen) { root.menuOpen = false; return }
        if (root.editing) { root.draft = null; root.armed = false; return }
        root.dismiss()
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- the title ---------------------------------------------------

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 12

          // The window's own background, the same colour as the status bar
          // above it. This used to be the top of a band washed in a hue that
          // followed the hour, and the shell does not draw an app under the
          // status bar -- so the wash stopped at its bottom edge in a hard
          // line across the top of the screen.
          Rectangle {
            anchors.fill: parent
            color: root.background
          }

          Chrome.AppBar {
            anchors.fill: parent
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize
            title: root.editing
              ? (root.draftIsNew ? "New alarm" : "Alarm")
              : (root.page === 1 ? "Stopwatch" : (root.page === 2 ? "Timer" : "Alarm"))
            subtitle: root.editing ? "" : root.subtitleText()

            leading: Chrome.BackButton {
              colours: root.colours
              visible: root.editing
              color: root.ink
              onClicked: { root.draft = null; root.armed = false }
            }

            trailing: [
              // The bin is in the editor's own bar rather than on the row,
              // where it would be a 44px target next to a switch.
              Chrome.IconButton {
                colours: root.colours
                visible: root.editing && !root.draftIsNew
                names: ["user-trash-symbolic", "edit-delete-symbolic"]
                color: root.armed ? root.danger : root.ink
                tooltip: root.armed ? "Tap again to delete" : "Delete this alarm"
                onClicked: root.deleteDraft()
              },
              Chrome.IconButton {
                colours: root.colours
                visible: root.editing
                names: ["object-select-symbolic"]
                color: root.accent
                tooltip: "Save this alarm"
                onClicked: root.saveDraft()
              },
              Chrome.IconButton {
                colours: root.colours
                visible: !root.editing
                names: ["view-more-symbolic", "open-menu-symbolic"]
                color: root.ink
                tooltip: "More"
                onClicked: root.menuOpen = !root.menuOpen
              }
            ]
          }
        }

        // --- the three screens --------------------------------------------

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          // === the alarms ================================================

          Flickable {
            id: alarmPage
            anchors.fill: parent
            visible: root.page === 0 && !root.editing
            clip: true
            contentWidth: width
            contentHeight: alarmCol.height
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: alarmCol
              width: alarmPage.width

              // --- the hero ---
              Rectangle {
                width: parent.width
                // 236 is the natural height; anything the rest of the page does
                // not need is added to it, and the dial block is centred in
                // whatever that comes to. No loop: `rest` measures its own
                // children and the Flickable's height is the viewport, which
                // does not depend on what is in it.
                //
                // `heroBlock.height` is the third term and it is the one that
                // matters on a short screen. With no alarms `rest` is nothing,
                // so the band took the viewport exactly -- and the column
                // centred in it, which is then dial plus clock plus an
                // EmptyState, was taller than that and hung out of both ends
                // with nothing to scroll to, because the content was exactly
                // as tall as the viewport. Found on the phone, where the
                // keyboard leaves an app 494px rather than 714.
                height: Math.max(236, heroBlock.height + 24,
                                 alarmPage.height - rest.height)
                color: root.background

                Column {
                  id: heroBlock
                  anchors.centerIn: parent
                  width: parent.width
                  spacing: 6

                  Face {
                    id: dial
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 132
                    height: 132
                    hours: root.face.hours
                    minutes: root.face.minutes
                    seconds: root.face.seconds
                    ink: root.ink
                    dim: root.dim
                    accent: root.accent
                    behind: root.background
                    sweeping: !root.pinned && clockWindow.visible
                              && root.page === 0 && !root.editing
                  }

                  Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 5

                    Digits {
                      anchors.verticalCenter: parent.verticalCenter
                      text: Alarms.timeText(new Date(root.now).getHours(),
                                            new Date(root.now).getMinutes(), root.hour24)
                      pixelSize: Math.round(root.bodySize * 2.6)
                      weight: Font.Light
                      color: root.ink
                    }

                    Chrome.TypedText {
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: 8
                      visible: !root.hour24
                      role: "caption"
                      text: Alarms.meridiem(new Date(root.now).getHours())
                      color: root.dim
                      bodySize: root.bodySize
                    }
                  }

                  Chrome.TypedText {
                    width: parent.width
                    role: "caption"
                    text: Qt.formatDate(new Date(root.now), "dddd d MMMM")
                    color: root.dim
                    bodySize: root.bodySize
                    horizontalAlignment: Text.AlignHCenter
                  }

                }
              }

              // Everything under the dial, in one item, so the band above
              // can be told how much room is left over. With four alarms on
              // the list that is none and the band is its natural 236; with
              // one, or none at all, the band takes the slack and the clock
              // ends up in the middle of the screen instead of at the top of
              // it with a screenful of nothing underneath.
              Column {
                id: rest
                width: alarmCol.width

                // --- nothing on the list ---
                //
                // Below the dial rather than inside it. It used to be the last
                // item in the hero's own centred column, on the argument that
                // with an empty list the band owns the page and the dial and
                // the sentence should sit either side of its middle. That is
                // true at 714px and false at 494 -- which is what an app
                // actually gets on the phone with the keyboard up, and there
                // the dial, the clock and a box of text came to more than the
                // viewport and the box was cut off by the tab bar. Down here it
                // is measured as part of `rest`, so the band gives up exactly
                // the room it needs.
                Item {
                  width: parent.width
                  height: blank.height + 20
                  visible: !root.ordered.length

                  Chrome.EmptyState {
                    id: blank
                    x: Metrics.GUTTER
                    y: 4
                    width: parent.width - Metrics.GUTTER * 2
                    colours: root.colours
                    bodySize: root.bodySize
                    names: [Qt.resolvedUrl("glyph-alarm.svg"), "alarm-symbolic"]
                    title: "No alarms"
                    detail: "This one cannot wake a sleeping phone — it rings when "
                            + "the phone is awake, and says how late it is."
                  }
                }

                // --- an alarm that did not ring ---
                Item {
                  width: parent.width
                  height: root.missedNote.length ? note.height + 12 : 0
                  visible: root.missedNote.length > 0

                  Rectangle {
                    id: note
                    x: 12
                    width: parent.width - 24
                    height: Math.max(Metrics.TARGET, noteText.implicitHeight + 20)
                    radius: Metrics.radius(root.colours, Metrics.CARD_RADIUS)
                    color: root.wash(root.hue("orange"), 0.16)

                    Chrome.TypedText {
                      id: noteText
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.left: parent.left
                      anchors.leftMargin: 14
                      anchors.right: parent.right
                      anchors.rightMargin: Metrics.TARGET
                      role: "caption"
                      text: root.missedNote
                      color: root.hue("orange")
                      bodySize: root.bodySize
                    }

                    Chrome.IconButton {
                      colours: root.colours
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.right: parent.right
                      names: ["window-close-symbolic"]
                      color: root.hue("orange")
                      tooltip: "Dismiss"
                      onClicked: root.missedNote = ""
                    }
                  }
                }

                // --- the rows ---
                Repeater {
                  model: root.ordered

                  Item {
                    id: alarmRow
                    required property var modelData

                    width: alarmCol.width
                    height: 88

                    readonly property double fires: Alarms.nextFire(alarmRow.modelData, root.now)

                    Rectangle {
                      anchors.fill: parent
                      anchors.leftMargin: 12
                      anchors.rightMargin: 12
                      anchors.topMargin: 4
                      anchors.bottomMargin: 4
                      radius: Metrics.radius(root.colours, Metrics.CARD_RADIUS)
                      // An alarm that is off is drawn on a fainter card as well
                      // as with a switch to the left. One signal is a switch
                      // somebody has to look for.
                      color: alarmRow.modelData.enabled ? root.card : root.wash(root.dim, 0.05)

                      Row {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 6
                        spacing: 4

                        Column {
                          anchors.verticalCenter: parent.verticalCenter
                          width: parent.width - 58
                          spacing: 1

                          Row {
                            spacing: 4

                            Digits {
                              anchors.verticalCenter: parent.verticalCenter
                              text: Alarms.timeText(alarmRow.modelData.hour,
                                                    alarmRow.modelData.minute, root.hour24)
                              pixelSize: Math.round(root.bodySize * 1.7)
                              weight: Font.Normal
                              color: alarmRow.modelData.enabled ? root.ink : root.dim
                            }

                            Chrome.TypedText {
                              anchors.bottom: parent.bottom
                              anchors.bottomMargin: 3
                              visible: !root.hour24
                              role: "caption"
                              text: Alarms.meridiem(alarmRow.modelData.hour)
                              color: root.dim
                              bodySize: root.bodySize
                            }

                            Chrome.Icon {
                              anchors.verticalCenter: parent.verticalCenter
                              visible: alarmRow.modelData.snoozed > root.now
                              slot: 18
                              size: 13
                              color: root.accent
                              names: ["media-playback-pause-symbolic"]
                            }
                          }

                          Chrome.TypedText {
                            width: parent.width
                            role: "caption"
                            text: {
                              var repeat = Alarms.repeatLabel(alarmRow.modelData.days)
                              var label = alarmRow.modelData.label
                              return label.length ? label + " · " + repeat : repeat
                            }
                            color: alarmRow.modelData.enabled ? root.dim
                                                              : Theme.alpha(root.dim, 0.6)
                            bodySize: root.bodySize
                            elide: Text.ElideRight
                            maximumLineCount: 1
                          }

                          Chrome.TypedText {
                            width: parent.width
                            role: "caption"
                            text: {
                              if (!alarmRow.modelData.enabled) return "Off"
                              if (alarmRow.modelData.snoozed > root.now)
                                return "Snoozed, again "
                                       + Alarms.untilLabel(alarmRow.fires - root.now)
                              return Alarms.whichDay(alarmRow.fires, root.now) + ", "
                                     + Alarms.untilLabel(alarmRow.fires - root.now)
                            }
                            color: alarmRow.modelData.enabled ? root.accent
                                                              : Theme.alpha(root.dim, 0.6)
                            bodySize: root.bodySize
                            elide: Text.ElideRight
                            maximumLineCount: 1
                          }
                        }

                        Toggle {
                          colours: root.colours
                          anchors.verticalCenter: parent.verticalCenter
                          checked: alarmRow.modelData.enabled
                          accent: root.accent
                          knobInk: root.accentInk
                          dim: root.dim
                          onToggled: root.toggleAlarm(alarmRow.modelData.id)
                        }
                      }

                      Chrome.PressVeil {
                        anchors.fill: parent
                        anchors.rightMargin: 58
                        radius: parent.radius
                        ink: root.ink
                        on: rowTap.pressed
                      }

                      // The card opens the editor; the switch is its own target
                      // and sits on top of this one.
                      MouseArea {
                        id: rowTap
                        anchors.fill: parent
                        anchors.rightMargin: 58
                        onClicked: root.edit(alarmRow.modelData.id)
                      }
                    }
                  }
                }

                // Room for the FAB, the tab bar and whatever the shell keeps.
                // Enough to scroll the last row out from under the FAB, and no
                // more. The tab bar and the shell's own strip are outside this
                // Flickable already, so counting them here would have left a
                // screenful of nothing under the last alarm.
                //
                // Unconditional, though it used to be only when there were
                // alarms to clear. The empty state is the last thing on the
                // page too, and without this the plus sat on the middle of the
                // sentence explaining what the alarm cannot do -- which is the
                // one sentence on that screen somebody needs to read.
                Item {
                  width: 1
                  height: 24 + Metrics.FAB
                }
              }
            }
          }

          // === one alarm, being set ======================================

          Flickable {
            id: editorPage
            anchors.fill: parent
            visible: root.editing
            clip: true
            contentWidth: width
            contentHeight: editorCol.height
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: editorCol
              width: editorPage.width
              spacing: 14

              Item { width: 1; height: 4 }

              // --- the time ---
              //
              // The wheels and the sentence under them are one box, because
              // the sentence is what the wheels *mean*. A caption floating on
              // the window under a control is the loose text this phone does
              // not have any more.
              Chrome.Card {
                x: Metrics.GUTTER
                width: editorCol.width - Metrics.GUTTER * 2
                colours: root.colours
                spacing: 6

              Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 2

                Wheel {
                  colours: root.colours
                  anchors.verticalCenter: parent.verticalCenter
                  count: root.hour24 ? 24 : 12
                  from: root.hour24 ? 0 : 1
                  pad: root.hour24
                  value: root.hour24
                    ? (root.draft ? root.draft.hour : 0)
                    : (root.draft ? ((root.draft.hour % 12) || 12) : 12)
                  ink: root.ink
                  dim: Theme.alpha(root.dim, 0.75)
                  bodySize: Math.round(root.bodySize * 1.5)
                  rowHeight: 52
                  onPicked: function (n) {
                    if (!root.draft) return
                    if (root.hour24) { root.change("hour", n); return }
                    var pm = root.draft.hour >= 12
                    root.change("hour", (n % 12) + (pm ? 12 : 0))
                  }
                }

                Chrome.TypedText {
                  anchors.verticalCenter: parent.verticalCenter
                  role: "title"
                  text: ":"
                  color: root.dim
                  bodySize: Math.round(root.bodySize * 1.5)
                }

                Wheel {
                  colours: root.colours
                  anchors.verticalCenter: parent.verticalCenter
                  count: 60
                  value: root.draft ? root.draft.minute : 0
                  ink: root.ink
                  dim: Theme.alpha(root.dim, 0.75)
                  bodySize: Math.round(root.bodySize * 1.5)
                  rowHeight: 52
                  onPicked: function (n) { root.change("minute", n) }
                }

                // AM and PM are two words, not a wheel of two numbers, and a
                // wheel with two rows in it is a wheel that looks broken.
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !root.hour24
                  spacing: 4

                  Repeater {
                    model: ["AM", "PM"]

                    Rectangle {
                      id: half
                      required property string modelData
                      required property int index

                      readonly property bool on:
                        root.draft ? ((root.draft.hour >= 12) === (half.index === 1)) : false

                      width: 50
                      height: 40
                      radius: Metrics.radius(root.colours, Metrics.RADIUS_SM)
                      color: half.on ? root.accent : "transparent"

                      Chrome.TypedText {
                        anchors.centerIn: parent
                        role: "caption"
                        text: half.modelData
                        color: half.on ? root.accentInk : root.dim
                        bodySize: root.bodySize
                      }

                      MouseArea {
                        anchors.fill: parent
                        onClicked: {
                          if (!root.draft) return
                          root.change("hour", (root.draft.hour % 12) + (half.index ? 12 : 0))
                        }
                      }
                    }
                  }
                }
              }

              // What setting it will actually do, said before it is saved. The
              // wheel says 06:30 and this says "tomorrow, in 9 h 20 min",
              // which is the question somebody setting an alarm at midnight
              // actually has.
              Chrome.TypedText {
                Layout.fillWidth: true
                role: "caption"
                // Always a sentence, never an empty one. An alarm that is on
                // always has a next time -- Alarms.normalise() is what
                // guarantees it, by turning a day list that nothing can fall
                // on into a one-off, and tst_alarms.qml asserts it over every
                // shape a day list can take.
                text: {
                  var at = root.previewFire()
                  return Alarms.whichDay(at, root.now) + ", "
                         + Alarms.untilLabel(at - root.now)
                }
                color: root.accent
                bodySize: root.bodySize
                horizontalAlignment: Text.AlignHCenter
              }
              }

              // --- how often ---
              // A Flow and not a Row: at the default text size the four fit
              // on one line, and on a phone whose Settings have been turned up
              // they wrap rather than run off the edge.
              Chrome.Section {
                x: Metrics.GUTTER
                width: editorCol.width - Metrics.GUTTER * 2
                colours: root.colours
                bodySize: root.bodySize
                title: "Repeats"
                cardSpacing: 10

              Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                  model: [
                    { text: "Once", days: [] },
                    { text: "Every day", days: [0, 1, 2, 3, 4, 5, 6] },
                    { text: "Weekdays", days: [1, 2, 3, 4, 5] },
                    { text: "Weekends", days: [0, 6] }
                  ]

                  Chrome.Chip {
                    id: preset
                    required property var modelData

                    colours: root.colours
                    text: preset.modelData.text
                    pad: 11
                    implicitHeight: 38
                    on: root.draft
                        ? Alarms.sameDays(root.draft.days, preset.modelData.days) : false
                    bodySize: root.bodySize
                    onClicked: root.setRepeat(preset.modelData.days)
                  }
                }
              }

              // --- which days ---
              Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4

                Repeater {
                  model: root.weekOrder

                  Rectangle {
                    id: chip
                    required property int modelData

                    readonly property bool on:
                      root.draft ? root.draft.days.indexOf(chip.modelData) >= 0 : false

                    width: 38
                    height: 38
                    radius: Metrics.round(root.colours, width)
                    // A step above the card they sit in, not the same colour
                    // as it: inside the Repeats box, `card` was a circle you
                    // could not see until it was chosen.
                    color: chip.on ? root.accent : Theme.surface(root.colours, "raised")

                    Accessible.role: Accessible.CheckBox
                    Accessible.name: Alarms.DAY_SHORT[chip.modelData]
                    Accessible.checkable: true
                    Accessible.checked: chip.on
                    Accessible.onPressAction: root.toggleDay(chip.modelData)

                    Chrome.TypedText {
                      anchors.centerIn: parent
                      role: "caption"
                      // Sunday and Saturday are both S and Tuesday and
                      // Thursday are both T. The position in the row is what
                      // tells them apart, which is what every paper diary has
                      // always relied on.
                      text: Alarms.DAY_INITIAL[chip.modelData]
                      color: chip.on ? root.accentInk : root.dim
                      bodySize: root.bodySize
                    }

                    Chrome.PressVeil {
                      anchors.fill: parent
                      radius: parent.radius
                      ink: chip.on ? root.accentInk : root.ink
                      on: chipTap.pressed
                    }

                    MouseArea {
                      id: chipTap
                      anchors.fill: parent
                      onClicked: root.toggleDay(chip.modelData)
                    }
                  }
                }
              }

              }

              // --- what it is for ---
              Chrome.Card {
                x: Metrics.GUTTER
                width: editorCol.width - Metrics.GUTTER * 2
                colours: root.colours
                spacing: 6

              Chrome.TextField {
                id: labelField
                Layout.fillWidth: true
                // Not bound to the draft. Typing writes `text`, and a write
                // breaks a binding -- so a field bound to the draft would go
                // dead the moment somebody used it, and the next alarm opened
                // would show the last one's label. Pushed in by edit() and
                // startNew() instead, which is what Calendar's editor does.
                placeholderText: "Label — work, pills, the bread"
                foreground: root.ink
                accent: root.accent
                iconColor: root.dim
                placeholderColor: root.dim
                bodySize: root.bodySize
                colours: root.colours
                leadingNames: ["document-edit-symbolic", "edit-find-symbolic"]
                onTextChanged: if (root.draft && labelField.text !== root.draft.label)
                                 root.change("label", labelField.text)
                onAccepted: root.saveDraft()
              }

              Chrome.TypedText {
                Layout.fillWidth: true
                visible: root.armed
                role: "caption"
                text: "Tap the bin again to delete this alarm."
                color: root.danger
                bodySize: root.bodySize
                wrapMode: Text.WordWrap
              }
              }

              Item { width: 1; height: 16 + root.shellFurniture }
            }
          }

          // === the stopwatch =============================================

          ColumnLayout {
            anchors.fill: parent
            visible: root.page === 1 && !root.editing
            spacing: 0

            // With laps on the list, the list takes the room below and the ring
            // sits at the top. With none -- which is every stopwatch before
            // somebody taps Lap -- these two split it instead, and the ring is
            // in the middle of the screen rather than pinned to the top of a
            // page that is two thirds empty.
            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.preferredHeight: 0
              visible: !root.watch.laps.length
            }

            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: 236

              Ring {
                anchors.centerIn: parent
                width: 210
                height: 210
                thickness: 7
                // The minute, not the hour: a ring that has to show an hour
                // moves a degree a minute and reads as broken. What this shows
                // is the seconds hand of the thing being timed.
                progress: Watch.watchSweep(root.elapsed)
                ink: root.watch.running ? root.accent : root.dim
                track: root.ink
              }

              Column {
                anchors.centerIn: parent
                spacing: 0

                Digits {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: Watch.watchText(root.elapsed).slice(0, -2)
                  tail: Watch.watchText(root.elapsed).slice(-2)
                  pixelSize: Math.round(root.bodySize * 2.7)
                  weight: Font.Light
                  color: root.ink
                  tailColor: root.watch.running ? root.accent : root.dim
                }

                Chrome.TypedText {
                  anchors.horizontalCenter: parent.horizontalCenter
                  role: "overline"
                  text: root.watch.laps.length
                    ? "LAP " + (root.watch.laps.length + (root.watch.running ? 1 : 0))
                    : (root.watch.running ? "RUNNING" : (root.elapsed > 0 ? "STOPPED" : "READY"))
                  color: root.dim
                  bodySize: root.bodySize
                }
              }
            }

            Row {
              Layout.alignment: Qt.AlignHCenter
              Layout.bottomMargin: 10
              spacing: 12

              Chrome.Button {
                // Lap while it runs, Reset once it has stopped: the same key,
                // because the two are never wanted at the same moment and a
                // third button would be one nobody could find in a hurry.
                colours: root.colours
                kind: "tonal"
                text: root.watch.running ? "Lap" : "Reset"
                enabled: root.watch.running || root.elapsed > 0
                bodySize: root.bodySize
                pad: 24
                onClicked: root.watch.running ? root.watchLap() : root.watchReset()
              }

              Chrome.Button {
                colours: root.colours
                kind: "filled"
                destructive: root.watch.running
                text: root.watch.running ? "Stop" : (root.elapsed > 0 ? "Resume" : "Start")
                bodySize: root.bodySize
                pad: 28
                onClicked: root.watch.running ? root.watchStop() : root.watchStart()
              }
            }

            // A gap, not a rule. The laps below are their own box; the
            // stopwatch above them does not need a line drawn under it to be
            // a different thing.
            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: root.watch.laps.length ? Metrics.GAP : 0
            }

            Chrome.ListFrame {
              id: lapFrame
              Layout.fillWidth: true
              Layout.leftMargin: Metrics.GUTTER
              Layout.rightMargin: Metrics.GUTTER
              Layout.bottomMargin: root.watch.laps.length ? Metrics.GAP : 0
              // Only when there is something in it. An empty ListView that
              // fills would take the slack the two spacers are there to share.
              Layout.fillHeight: root.watch.laps.length > 0
              Layout.preferredHeight: 0
              visible: root.watch.laps.length > 0
              colours: root.colours

            ListView {
              id: lapList
              anchors.fill: parent
              clip: true
              model: root.laps
              boundsBehavior: Flickable.StopAtBounds
              // The newest lap is at the top, which is where the eye already
              // is; nothing scrolls under a thumb that is about to tap Lap.
              footer: Item { width: 1; height: 8 }

              delegate: Item {
                id: lapRow
                required property var modelData

                width: lapList.width
                height: 36

                readonly property color mark: lapRow.modelData.best ? root.good
                  : (lapRow.modelData.worst ? root.danger : root.ink)

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Metrics.GAP
                  anchors.rightMargin: Metrics.GAP

                  Chrome.TypedText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 46
                    role: "caption"
                    text: "#" + lapRow.modelData.index
                    color: lapRow.modelData.running ? root.accent : root.dim
                    bodySize: root.bodySize
                  }

                  // The lap, which is the number somebody took the lap for,
                  // and then the total, which is the one they will read
                  // afterwards. Best and worst are marked in the theme's own
                  // green and red -- and in bold as well, because a colour on
                  // its own is not a signal everybody gets.
                  Digits {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 104
                    text: Watch.watchText(lapRow.modelData.lap).slice(0, -2)
                    tail: Watch.watchText(lapRow.modelData.lap).slice(-2)
                    pixelSize: root.bodySize
                    weight: lapRow.modelData.best || lapRow.modelData.worst
                            ? Font.DemiBold : Font.Normal
                    color: lapRow.mark
                    tailColor: Theme.alpha(lapRow.mark, 0.7)
                  }

                  Item { width: 8; height: 1 }

                  Digits {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Watch.watchText(lapRow.modelData.at).slice(0, -2)
                    tail: Watch.watchText(lapRow.modelData.at).slice(-2)
                    pixelSize: root.bodySize
                    color: root.dim
                    tailColor: Theme.alpha(root.dim, 0.7)
                  }
                }
              }
            }
            }

            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.preferredHeight: 0
              visible: !root.watch.laps.length
            }
          }

          // === the timer =================================================

          ColumnLayout {
            anchors.fill: parent
            visible: root.page === 2 && !root.editing
            spacing: 0

            // --- one is running, or paused ---
            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true
              visible: root.timer.total > 0

              Column {
                anchors.centerIn: parent
                width: parent.width
                spacing: 24

                Item {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: 232
                  height: 232

                  Ring {
                    anchors.fill: parent
                    thickness: 8
                    progress: Watch.timerProgress(root.timer, root.now)
                    // Anticlockwise, so the arc that is left is the arc that
                    // is left: a countdown drawn forwards looks like something
                    // filling up.
                    reverse: true
                    ink: root.timer.running ? root.accent : root.dim
                    track: root.ink
                  }

                  Column {
                    anchors.centerIn: parent
                    spacing: 2

                    Digits {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: Watch.timerText(root.remaining)
                      pixelSize: Math.round(root.bodySize * 2.9)
                      weight: Font.Light
                      color: root.ink
                    }

                    Chrome.TypedText {
                      anchors.horizontalCenter: parent.horizontalCenter
                      role: "caption"
                      text: root.timer.running
                        ? "of " + Watch.spanLabel(root.timer.total)
                        : "paused, of " + Watch.spanLabel(root.timer.total)
                      color: root.dim
                      bodySize: root.bodySize
                    }
                  }
                }

                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: 10

                  Chrome.Button {
                    colours: root.colours
                    kind: "tonal"
                    text: "+1 min"
                    bodySize: root.bodySize
                    pad: 16
                    onClicked: root.timerAdd()
                  }

                  Chrome.Button {
                    colours: root.colours
                    kind: "filled"
                    text: root.timer.running ? "Pause" : "Resume"
                    bodySize: root.bodySize
                    pad: 20
                    onClicked: root.timer.running ? root.timerPause() : root.timerResume()
                  }

                  Chrome.Button {
                    colours: root.colours
                    kind: "tonal"
                    destructive: true
                    text: "Cancel"
                    bodySize: root.bodySize
                    pad: 16
                    onClicked: root.timerCancel()
                  }
                }
              }
            }

            // --- setting one ---
            ColumnLayout {
              Layout.fillWidth: true
              Layout.fillHeight: true
              visible: root.timer.total <= 0
              spacing: 0

              Item { Layout.fillHeight: true; Layout.preferredHeight: 4 }

              // Leading zeros dim, the typed digits lit. It is the one thing
              // that makes 00:05:00 read as five minutes rather than as a
              // number somebody has to parse.
              Digits {
                Layout.alignment: Qt.AlignHCenter
                text: Watch.keypadClock(root.digits)
                litFrom: Watch.keypadLit(root.digits)
                pixelSize: Math.round(root.bodySize * 2.5)
                weight: Font.Light
                color: root.ink
                dimColor: Theme.alpha(root.dim, 0.45)
              }

              Chrome.TypedText {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 12
                role: "caption"
                // What will actually run, in words, which is where 0:90
                // becomes a minute and a half before anybody presses Start.
                text: root.typed > 0 ? Watch.spanLabel(root.typed) : "Hours, minutes, seconds"
                color: root.typed > 0 ? root.accent : root.dim
                bodySize: root.bodySize
              }

              Row {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 14
                spacing: 6

                Repeater {
                  model: Watch.PRESETS

                  Chrome.Chip {
                    id: chipPreset
                    required property int modelData

                    colours: root.colours
                    text: Watch.spanLabel(chipPreset.modelData * 1000)
                    pad: 13
                    bodySize: root.bodySize
                    onClicked: root.keyPreset(chipPreset.modelData)
                  }
                }
              }

              // The Grid is inside an Item rather than aligned in the layout
              // directly: a Grid reports no implicitWidth until it has laid its
              // children out, so Layout.AlignHCenter had nothing to centre and
              // the keypad sat against the left edge.
              Item {
                Layout.fillWidth: true
                Layout.preferredHeight: keys.height

                Grid {
                  id: keys
                  anchors.horizontalCenter: parent.horizontalCenter
                  columns: 3
                  spacing: 8

                  Repeater {
                    model: root.keypad

                    Rectangle {
                      id: key
                      required property var modelData

                      // 100 by 58, which is above the 44 thumb floor in both
                      // directions and close to Calculator's 62 -- a duration is
                      // typed in the same hurry a sum is.
                      width: 100
                      height: 58
                      radius: Metrics.radius(root.colours, Metrics.RADIUS_MD)
                      color: key.modelData.key < 0
                        ? root.wash(root.dim, 0.1)
                        : Theme.mix(root.colours.foreground, root.colours.background,
                                    keyTap.pressed ? 0.17 : 0.09)

                      Accessible.role: Accessible.Button
                      Accessible.name: key.modelData.key === -1
                        ? "Backspace" : key.modelData.text
                      Accessible.onPressAction: root.keyPress(key.modelData.key)

                      Chrome.TypedText {
                        anchors.centerIn: parent
                        visible: key.modelData.text.length > 0
                        role: "title"
                        text: key.modelData.text
                        color: root.ink
                        bodySize: root.bodySize
                      }

                      Chrome.Icon {
                        anchors.centerIn: parent
                        visible: key.modelData.key === -1
                        slot: 28
                        size: 20
                        color: root.ink
                        names: ["edit-clear-symbolic", "list-remove-symbolic"]
                      }

                      Chrome.PressVeil {
                        anchors.fill: parent
                        radius: parent.radius
                        ink: root.ink
                        on: keyTap.pressed
                      }

                      MouseArea {
                        id: keyTap
                        anchors.fill: parent
                        onClicked: root.keyPress(key.modelData.key)
                        // Held down, backspace empties the whole entry. A
                        // six-digit mistake is six taps otherwise.
                        onPressAndHold: if (key.modelData.key === -1) root.keyClear()
                      }
                    }
                  }
                }
              }

              Chrome.Button {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 14
                colours: root.colours
                kind: "filled"
                text: "Start"
                enabled: root.typed > 0
                bodySize: root.bodySize
                pad: 46
                onClicked: root.timerStart()
              }

              Item { Layout.fillHeight: true; Layout.preferredHeight: 4 }
            }
          }
        }

        // --- the three screens, along the bottom ---------------------------

        // The tab bar, flush with the bottom of the window as it is in every
        // other app here with one.
        //
        // It used to be the top 56px of a taller bar whose background ran on
        // for another 60 underneath, kept clear for the gesture bar and
        // moarchy-keyboard's toggle -- layer surfaces that draw over an app
        // and take the taps that land on them. On the phone that read as a
        // band of nothing under the tabs, in two apps out of seven. The toggle
        // does sit over part of the Timer tab now, as it already did over the
        // right-hand tab in Files, Coins, Launches and Vitals; that is the
        // shell's to fix with an exclusive zone, once.
        Chrome.BottomNav {
          id: bottomNav
          Layout.fillWidth: true
          Layout.preferredHeight: root.editing ? 0 : Metrics.BOTTOM_NAV
          visible: !root.editing
          color: root.background
          dim: root.dim
          accent: root.accent
          bodySize: root.bodySize
          currentIndex: root.page
          onActivated: function (i) { root.page = i }

          Chrome.BottomNavItem {
            text: "Alarm"
            names: [Qt.resolvedUrl("glyph-alarm.svg"), "alarm-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }

          Chrome.BottomNavItem {
            text: "Stopwatch"
            names: [Qt.resolvedUrl("glyph-stopwatch.svg"), "preferences-system-time-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }

          Chrome.BottomNavItem {
            text: "Timer"
            names: [Qt.resolvedUrl("glyph-hourglass.svg"), "alarm-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }
        }
      }

      Chrome.Fab {
        colours: root.colours
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 16
        anchors.bottomMargin: 16 + Metrics.BOTTOM_NAV
        visible: root.page === 0 && !root.editing && !root.ringing
        accent: root.accent
        foreground: root.accentInk
        names: ["list-add-symbolic"]
        tooltip: "A new alarm"
        onClicked: root.startNew()
      }

      Chrome.Toast {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        // Above the tab bar where there is one. The editor has none, so there
        // the toast clears the shell's furniture instead.
        anchors.bottomMargin: 12 + (root.editing
                                    ? root.shellFurniture : Metrics.BOTTOM_NAV)
        colours: root.colours
        bodySize: root.bodySize
      }

      Chrome.ContextMenu {
        open: root.menuOpen
        colours: root.colours
        background: root.background
        foreground: root.ink
        danger: root.danger
        bodySize: root.bodySize
        onDismissed: root.menuOpen = false

        Chrome.MenuItem {
          colours: root.colours
          text: "24-hour clock"
          names: root.hour24 ? ["object-select-symbolic"] : []
          foreground: root.ink
          bodySize: root.bodySize
          onClicked: { root.setSetting("hour24", !root.hour24); root.menuOpen = false }
        }

        Chrome.MenuItem {
          colours: root.colours
          text: "Silent ring"
          names: root.settings.silent ? ["object-select-symbolic"] : []
          foreground: root.ink
          bodySize: root.bodySize
          onClicked: {
            root.setSetting("silent", !root.settings.silent)
            root.menuOpen = false
            root.say(root.settings.silent
                     ? "Alarms will ring on the screen only."
                     : "Alarms will make a sound.")
          }
        }
      }

      // --- something is going off ------------------------------------------
      //
      // Over everything, including the tab bar, and it does not take a back
      // swipe: `dismiss()` refuses while this is up. An alarm a gesture can
      // lose by accident is an alarm.

      Rectangle {
        id: ringScreen
        anchors.fill: parent
        visible: !!root.ringing
        z: 200

        readonly property color ringHue: root.ringing && root.ringing.kind === "timer"
          ? root.hue("green") : root.accent

        // The window's background, not a wash of the ring's hue fading down
        // from the top: the status bar above is that background, and a hue
        // that starts at the top of the window starts in a hard line under it.
        // The hue is in the ring and the glyph, which are what is looked at.
        color: root.background

        // Under the content, so that nothing behind this screen can be
        // pressed through it.
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onClicked: {}
        }

        Column {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: Math.round(parent.height * 0.13)
          width: parent.width
          spacing: 10

          Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 108
            height: 108

            // One ring, breathing. Not a shaking bell: a phone that is ringing
            // is already making a noise and moving in somebody's hand, and an
            // animation that costs a repaint per frame on a Mali-400 is one
            // the compositor pays for.
            Rectangle {
              id: pulse
              anchors.centerIn: parent
              width: 88
              height: 88
              radius: width / 2
              color: "transparent"
              border.width: 2
              border.color: ringScreen.ringHue

              SequentialAnimation {
                running: !!root.ringing && !root.pinned
                loops: Animation.Infinite

                ParallelAnimation {
                  NumberAnimation { target: pulse; property: "scale"; from: 0.82; to: 1.2; duration: 1100; easing.type: Easing.OutQuad }
                  NumberAnimation { target: pulse; property: "opacity"; from: 0.9; to: 0; duration: 1100 }
                }
              }
            }

            Rectangle {
              anchors.centerIn: parent
              width: 74
              height: 74
              radius: width / 2
              color: Theme.mix(ringScreen.ringHue, root.background, 0.9)

              Chrome.Icon {
                anchors.centerIn: parent
                slot: 44
                size: 32
                color: root.background
                names: root.ringing && root.ringing.kind === "timer"
                  ? [Qt.resolvedUrl("glyph-hourglass.svg"), "alarm-symbolic"]
                  : [Qt.resolvedUrl("glyph-alarm.svg"), "alarm-symbolic"]
              }
            }
          }

          Chrome.TypedText {
            width: parent.width
            role: "subtitle"
            text: root.ringing ? root.ringing.label : ""
            color: root.ink
            bodySize: root.bodySize
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 5

            Digits {
              anchors.verticalCenter: parent.verticalCenter
              text: root.ringing ? root.ringing.time : ""
              pixelSize: Math.round(root.bodySize * 3.4)
              weight: Font.Light
              color: root.ink
            }

            Chrome.TypedText {
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 10
              visible: !root.hour24 && !!root.ringing && root.ringing.kind === "alarm"
              role: "caption"
              text: root.ringing ? Alarms.meridiem(new Date(root.ringing.at).getHours()) : ""
              color: root.dim
              bodySize: root.bodySize
            }
          }

          // The two sentences this screen owes somebody. How late it is, which
          // is the whole of what this app can honestly do about a phone that
          // was asleep -- and that it is not making a sound, if it is not,
          // because an alarm that is silently mute is this app's worst failure
          // and it is not going to be silent about it as well.
          Chrome.TypedText {
            width: parent.width
            visible: root.ringLate().length > 0
            role: "caption"
            text: root.ringLate()
            color: root.hue("orange")
            bodySize: root.bodySize
            horizontalAlignment: Text.AlignHCenter
          }

          Chrome.TypedText {
            width: parent.width - 48
            x: 24
            visible: root.mute || !!root.settings.silent
            role: "caption"
            // Only the two a person can do something about. `quiet` is the
            // screenshot harness's, and a picture captioned with the reason it
            // is a picture would be a caption about the wrong thing.
            text: root.settings.silent
              ? "Set to ring on the screen only."
              : "Nothing on this phone could play the alarm tone."
            color: root.dim
            bodySize: root.bodySize
            horizontalAlignment: Text.AlignHCenter
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 40 + root.shellFurniture
          spacing: 14

          Chrome.Button {
            visible: !!root.ringing && root.ringing.kind === "alarm"
            colours: root.colours
            kind: "tonal"
            text: "Snooze " + Alarms.SNOOZE_MINUTES + " min"
            implicitHeight: 62
            pad: 20
            bodySize: root.bodySize
            role: "subtitle"
            onClicked: root.snoozeRing()
          }

          Chrome.Button {
            colours: root.colours
            kind: "filled"
            hue: ringScreen.ringHue
            text: "Stop"
            implicitHeight: 62
            pad: root.ringing && root.ringing.kind === "timer" ? 72 : 30
            bodySize: root.bodySize
            role: "subtitle"
            onClicked: root.stopRing()
          }
        }
      }
    }
  }

  // --- the last few things the screens above ask for ------------------------

  // The strip the shell keeps along the bottom of the screen for the gesture
  // bar and moarchy-keyboard's toggle. Only the screens with no tab bar under
  // them still clear it -- the alarm editor and the ringing screen, whose last
  // controls are otherwise under a layer surface that takes their taps.
  readonly property int shellFurniture: root.shell ? 60 : 0

  // What the title bar says under the page name. The alarm page's is the one
  // that earns its line: it is the answer to the question the app is opened
  // for, on the screen before anybody scrolls.
  function subtitleText(): string {
    if (root.page === 1) return ""
    if (root.page === 2) {
      if (root.timer.total <= 0) return ""
      if (!root.timer.running) return "Paused"
      return "Ends " + Qt.formatTime(new Date(root.timer.endsAt),
                                     root.hour24 ? "HH:mm" : "h:mm AP")
    }
    if (!root.alarms.length) return ""
    if (!root.next) return "All off"
    var alarm = root.next.alarm
    var when = Alarms.untilLabel(root.next.at - root.now)
    return alarm.label.length ? alarm.label + " · " + when : when
  }

  // When the alarm on the wheels would actually go off. The draft may be a
  // copy of an alarm that is switched off or snoozed, and neither is what the
  // editor is asking about.
  function previewFire(): double {
    if (!root.draft) return 0
    var probe = Alarms.clone(root.draft)
    probe.enabled = true
    probe.snoozed = 0
    probe.fired = 0
    return Alarms.nextFire(probe, root.now)
  }

  function ringLate(): string {
    if (!root.ringing) return ""
    return Alarms.lateLabel(root.now - root.ringing.at)
  }
}

// The stopwatch and the timer: elapsed, remaining, and the digits for both.
//
// Neither keeps a running total in a variable that a tick increments. Both are
// two numbers and a subtraction -- the stopwatch is *when it started* plus
// what it had accrued before the last pause, and the timer is *when it ends* --
// so a tick that arrives late, or does not arrive at all because the phone
// suspended for twenty minutes, cannot make either of them wrong. A stopwatch
// driven by `+= interval` loses exactly the time the phone spent asleep, which
// is the time somebody was most likely measuring.
//
// Milliseconds throughout, as in Alarms.js, and for the reason given there.
.pragma library

// Ninety-nine, which is what the lap number fits in two digits.
var MAX_LAPS = 99

// A day and a bit less than four days, which is what six typed digits can
// hold: 99:59:59.
var TIMER_MAX = (99 * 3600 + 59 * 60 + 59) * 1000

// How late a finished timer may be and still ring, in seconds. Same number and
// same argument as the alarm's, and the same README section covers both.
var LATE_LIMIT = 3600

// The countdowns a phone is actually asked for: an egg, a tea, a five, a
// quarter of an hour, a half.
var PRESETS = [60, 180, 300, 900, 1800]

function pad(n) {
  return n < 10 ? "0" + n : String(n)
}

// --- the stopwatch --------------------------------------------------------

function blankWatch() {
  return { running: false, since: 0, accrued: 0, laps: [] }
}

function elapsed(watch, now) {
  if (!watch.running) return Math.max(0, watch.accrued)
  return Math.max(0, watch.accrued + Math.max(0, now - watch.since))
}

function startWatch(watch, now) {
  if (watch.running) return watch
  return { running: true, since: now, accrued: watch.accrued, laps: watch.laps.slice() }
}

function stopWatch(watch, now) {
  if (!watch.running) return watch
  return { running: false, since: 0, accrued: elapsed(watch, now), laps: watch.laps.slice() }
}

// A lap is a mark on the elapsed time rather than a duration, so that a list
// of them can be read forwards -- and so that deleting the arithmetic from the
// file leaves the marks intact.
function lapWatch(watch, now) {
  if (!watch.running || watch.laps.length >= MAX_LAPS) return watch
  var at = elapsed(watch, now)
  var laps = watch.laps.slice()
  // A second tap in the same millisecond is a slip, not a lap of zero.
  if (laps.length && at <= laps[laps.length - 1]) return watch
  laps.push(at)
  return { running: true, since: watch.since, accrued: watch.accrued, laps: laps }
}

// Newest first, because that is the end being watched, with the lap in
// progress at the top of the list while the watch runs.
//
// Best and worst are marked over the finished laps only, and only once there
// are two of them that differ -- a single lap is not a personal best, and
// neither is a lap still being run.
function lapRows(watch, now) {
  var marks = watch.laps
  var rows = []
  var previous = 0
  for (var i = 0; i < marks.length; i++) {
    rows.push({ index: i + 1, at: marks[i], lap: marks[i] - previous,
                best: false, worst: false, running: false })
    previous = marks[i]
  }
  if (rows.length >= 2) {
    var best = 0
    var worst = 0
    for (var j = 1; j < rows.length; j++) {
      if (rows[j].lap < rows[best].lap) best = j
      if (rows[j].lap > rows[worst].lap) worst = j
    }
    if (rows[best].lap !== rows[worst].lap) {
      rows[best].best = true
      rows[worst].worst = true
    }
  }
  rows.reverse()
  if (watch.running && marks.length) {
    var at = elapsed(watch, now)
    rows.unshift({ index: marks.length + 1, at: at, lap: at - previous,
                   best: false, worst: false, running: true })
  }
  return rows
}

function parts(ms) {
  var t = Math.max(0, Math.floor(ms))
  return {
    hours: Math.floor(t / 3600000),
    minutes: Math.floor(t / 60000) % 60,
    seconds: Math.floor(t / 1000) % 60,
    tenths: Math.floor(t / 100) % 10
  }
}

// "12:34.5", and "1:02:03.4" once there is an hour on it.
//
// Tenths and not hundredths. A hundredth is 10ms, a thumb arrives within about
// 200 of where it meant to, and the second digit of a phone stopwatch is
// therefore decoration that costs ten times the wakeups to draw. The marks
// themselves are kept to the millisecond -- it is the *display* that stops at
// a tenth, so a lap read off the screen is a lap the screen could see.
function watchText(ms) {
  var p = parts(ms)
  var whole = p.hours
    ? p.hours + ":" + pad(p.minutes) + ":" + pad(p.seconds)
    : pad(p.minutes) + ":" + pad(p.seconds)
  return whole + "." + p.tenths
}

// Where the seconds hand of the stopwatch's own ring points: the minute, as a
// fraction. Redrawn once a second rather than ten times, because a ring 240px
// across cannot show a tenth of a degree and a Mali-400 is asked to fill it.
function watchSweep(ms) {
  return (Math.floor(Math.max(0, ms) / 1000) % 60) / 60
}

// --- the timer ------------------------------------------------------------

function blankTimer() {
  return { running: false, total: 0, endsAt: 0, left: 0 }
}

function timerLeft(timer, now) {
  if (!timer.running) return Math.max(0, timer.left)
  return Math.max(0, timer.endsAt - now)
}

// One when it has not started draining and zero when it is done, so the ring
// empties clockwise as the number falls.
function timerProgress(timer, now) {
  if (timer.total <= 0) return 0
  var fraction = timerLeft(timer, now) / timer.total
  return Math.max(0, Math.min(1, fraction))
}

function startTimer(total, now) {
  var ms = Math.max(0, Math.min(TIMER_MAX, Math.floor(total)))
  if (!ms) return blankTimer()
  return { running: true, total: ms, endsAt: now + ms, left: ms }
}

function pauseTimer(timer, now) {
  if (!timer.running) return timer
  return { running: false, total: timer.total, endsAt: 0, left: timerLeft(timer, now) }
}

function resumeTimer(timer, now) {
  if (timer.running || timer.left <= 0) return timer
  return { running: true, total: timer.total, endsAt: now + timer.left, left: timer.left }
}

// A minute on, and the total grows with it -- otherwise the ring would be
// asked to show 6/5 of itself.
function extendTimer(timer, now, ms) {
  var added = Math.max(0, Math.floor(ms))
  if (!added) return timer
  if (timer.running) {
    var endsAt = Math.min(now + TIMER_MAX, timer.endsAt + added)
    return { running: true, total: timer.total + added, endsAt: endsAt,
             left: Math.max(0, endsAt - now) }
  }
  if (timer.left <= 0) return startTimer(added, now)
  var left = Math.min(TIMER_MAX, timer.left + added)
  return { running: false, total: timer.total + added, endsAt: 0, left: left }
}

// The instant a running timer is over, or 0, so that it can be rung late and
// told how late it is by the same code the alarms use.
function timerDue(timer, now, lateLimit) {
  if (!timer.running || timer.total <= 0) return 0
  if (now < timer.endsAt) return 0
  var limit = (lateLimit === undefined ? LATE_LIMIT : lateLimit) * 1000
  return (now - timer.endsAt <= limit) ? timer.endsAt : 0
}

function timerMissed(timer, now, lateLimit) {
  if (!timer.running || timer.total <= 0) return 0
  if (now < timer.endsAt) return 0
  var limit = (lateLimit === undefined ? LATE_LIMIT : lateLimit) * 1000
  return (now - timer.endsAt > limit) ? timer.endsAt : 0
}

// A countdown, rounded up, so that "0:01" is on the screen for the whole of
// the last second rather than for none of it.
function timerText(ms) {
  var total = Math.max(0, Math.ceil(ms / 1000))
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor(total / 60) % 60
  var seconds = total % 60
  return hours
    ? hours + ":" + pad(minutes) + ":" + pad(seconds)
    : pad(minutes) + ":" + pad(seconds)
}

// "5 min", "1 h 30 min" -- for the preset chips and for the label under a
// running ring.
function spanLabel(ms) {
  var total = Math.round(ms / 1000)
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor(total / 60) % 60
  var seconds = total % 60
  if (!hours && !minutes) return seconds + " s"
  if (!hours) return seconds ? minutes + " min " + seconds + " s" : minutes + " min"
  return minutes ? hours + " h " + minutes + " min" : hours + " h"
}

// --- the keypad -----------------------------------------------------------
//
// Digits push in from the right, which is how every microwave and every phone
// timer has worked: 5, 0, 0 is five minutes, not five hundred of something. Six
// at most, HHMMSS.

function push(digits, digit) {
  var d = Math.floor(digit)
  if (d < 0 || d > 9) return digits
  if (digits.length >= 6) return digits
  // A leading zero would spend one of the six on nothing.
  if (!digits.length && d === 0) return digits
  return digits.concat([d])
}

function pop(digits) {
  return digits.slice(0, Math.max(0, digits.length - 1))
}

function padded(digits) {
  var text = ""
  for (var i = 0; i < digits.length; i++) text += digits[i]
  while (text.length < 6) text = "0" + text
  return text
}

// Six cells, each with the digit and whether it has been typed, so the leading
// zeros can be drawn dim -- which is what makes "00h 05m 00s" read as five
// minutes rather than as a number.
function keypadCells(digits) {
  var text = padded(digits)
  var from = 6 - digits.length
  var cells = []
  for (var i = 0; i < 6; i++) cells.push({ text: text.charAt(i), on: i >= from })
  return cells
}

// What the typed digits come to. Ninety seconds typed as 0-0-9-0 is a minute
// and a half rather than an error: the microwave rule again, and the only
// place the app normalises what somebody typed is when it starts.
function keypadMs(digits) {
  var text = padded(digits)
  var hours = parseInt(text.slice(0, 2), 10)
  var minutes = parseInt(text.slice(2, 4), 10)
  var seconds = parseInt(text.slice(4, 6), 10)
  return Math.min(TIMER_MAX, (hours * 3600 + minutes * 60 + seconds) * 1000)
}

// The digits a preset would have been typed as, so that tapping "5 min" leaves
// the keypad in a state somebody can then edit.
function digitsFor(ms) {
  var total = Math.max(0, Math.min(TIMER_MAX, Math.round(ms / 1000)))
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor(total / 60) % 60
  var seconds = total % 60
  var text = pad(hours) + pad(minutes) + pad(seconds)
  var digits = []
  var started = false
  for (var i = 0; i < text.length; i++) {
    var d = parseInt(text.charAt(i), 10)
    if (!started && d === 0) continue
    started = true
    digits.push(d)
  }
  return digits
}

// "00:05:00", always six digits and two colons, so that the entry does not
// change shape as it is typed.
function keypadClock(digits) {
  var text = padded(digits)
  return text.slice(0, 2) + ":" + text.slice(2, 4) + ":" + text.slice(4, 6)
}

// Where the typed part of that string starts, so the leading zeros can be
// drawn dim. Eight -- past the end -- when nothing has been typed at all.
function keypadLit(digits) {
  var order = [0, 1, 3, 4, 6, 7]
  var n = Math.min(6, digits.length)
  return n ? order[6 - n] : 8
}

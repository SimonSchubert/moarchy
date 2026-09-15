// Dates, without a Date object in sight.
//
// Everything in this app is a local calendar day written "2026-09-15" and a
// time written as minutes past midnight. No UTC, no offset, no timezone: an
// event at nine on Tuesday is at nine on Tuesday in Berlin and at nine on
// Tuesday in Lisbon. That is iCalendar's *floating time* -- RFC 5545's
// DATE-TIME form with neither a Z nor a TZID, "not bound to any time zone" --
// and it is what a dentist's appointment in somebody's own phone actually
// means. Habits made the same choice for the same reason, and its comment
// says it shorter: a day is a label, not an instant.
//
// `new Date("2026-09-15")` would have been one line, and the ECMAScript spec
// says a date-only string is parsed as **UTC**, so `.getDate()` on it returns
// the 14th anywhere west of Greenwich. That bug is invisible in Berlin, which
// is where it would have been written.
//
// So a day is an integer here -- days since 1970-01-01 -- and the two
// functions that convert are Howard Hinnant's `days_from_civil` and
// `civil_from_days`, which are exact for every year, proleptic Gregorian, and
// twenty lines of integer arithmetic between them.
.pragma library

// 0 is Sunday, which is how Qt.locale() numbers a weekday and therefore what
// `firstDayOfWeek` hands the app. English names, because the rest of the app
// is in English; the *order* follows the phone's locale, which is the half
// that actually changes what somebody sees.
var DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
var DAYS_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var DAYS_INITIAL = ["S", "M", "T", "W", "T", "F", "S"]

var MONTHS = ["January", "February", "March", "April", "May", "June",
              "July", "August", "September", "October", "November", "December"]
var MONTHS_SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// Six rows, always, whatever the month needs.
//
// A month spans four, five or six of them depending on where it starts, and a
// grid that changes height moves everything under it -- which on this screen
// is the day's events. Tapping the 30th and having the list jump a row up is
// the sort of thing nobody reports and everybody feels.
var ROWS = 6
var MINUTES = 1440

var LENGTHS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

function isLeap(y) {
  return (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0
}

function daysInMonth(y, m) {
  if (m < 1 || m > 12) return 0
  return (m === 2 && isLeap(y)) ? 29 : LENGTHS[m - 1]
}

function two(n) {
  return n < 10 ? "0" + n : String(n)
}

function toIso(y, m, d) {
  return String(y) + "-" + two(m) + "-" + two(d)
}

// A day, or nothing. The check is against the length of the month rather than
// against the shape of the string, so "2026-02-30" is not a day -- which is
// what a hand-edited file eventually contains.
function isDay(s) {
  return parts(s) !== null
}

function parts(iso) {
  if (typeof iso !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(iso)) return null
  var y = parseInt(iso.slice(0, 4), 10)
  var m = parseInt(iso.slice(5, 7), 10)
  var d = parseInt(iso.slice(8, 10), 10)
  if (m < 1 || m > 12) return null
  if (d < 1 || d > daysInMonth(y, m)) return null
  return { y: y, m: m, d: d }
}

// --- the two that everything else stands on --------------------------------

function daysFromCivil(y, m, d) {
  var year = y - (m <= 2 ? 1 : 0)
  var era = Math.floor(year / 400)
  var yoe = year - era * 400
  var doy = Math.floor((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  var doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
}

function civilFromDays(z) {
  var n = z + 719468
  var era = Math.floor(n / 146097)
  var doe = n - era * 146097
  var yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524)
                        - Math.floor(doe / 146096)) / 365)
  var y = yoe + era * 400
  var doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100))
  var mp = Math.floor((5 * doy + 2) / 153)
  var d = doy - Math.floor((153 * mp + 2) / 5) + 1
  var m = mp + (mp < 10 ? 3 : -9)
  return { y: y + (m <= 2 ? 1 : 0), m: m, d: d }
}

function dayNumber(iso) {
  var p = parts(iso)
  return p === null ? NaN : daysFromCivil(p.y, p.m, p.d)
}

function fromDayNumber(n) {
  var c = civilFromDays(Math.round(n))
  return toIso(c.y, c.m, c.d)
}

function addDays(iso, n) {
  var at = dayNumber(iso)
  return isFinite(at) ? fromDayNumber(at + n) : iso
}

function between(from, to) {
  return dayNumber(to) - dayNumber(from)
}

// 0 Sunday to 6 Saturday. 1970-01-01 was a Thursday, so day 0 is 4; the +11
// is +7+4, which keeps the modulo positive for days before the epoch.
function weekday(iso) {
  var at = dayNumber(iso)
  if (!isFinite(at)) return -1
  return ((at % 7) + 11) % 7
}

function isWeekend(day) {
  return day === 0 || day === 6
}

// --- months as one number --------------------------------------------------

// The pager is a list of months and a list needs an index, so a month is
// y * 12 + (m - 1). Adding one is the next month, including across December,
// which is the arithmetic every "next month" button gets wrong at least once.
function monthIndex(y, m) {
  return y * 12 + (m - 1)
}

function yearOf(index) {
  return Math.floor(index / 12)
}

function monthOf(index) {
  return index - Math.floor(index / 12) * 12 + 1
}

function monthOfDay(iso) {
  var p = parts(iso)
  return p === null ? NaN : monthIndex(p.y, p.m)
}

function firstOfMonth(index) {
  return toIso(yearOf(index), monthOf(index), 1)
}

// The day of `index`'s month nearest to `iso`'s day of the month -- what the
// selection becomes when a swipe lands on a month that is too short to hold
// the day that was selected. The 31st of a month swiped into February is its
// 28th, and not its 3rd of March.
function sameDayIn(index, iso) {
  var p = parts(iso)
  var y = yearOf(index)
  var m = monthOf(index)
  var d = p === null ? 1 : Math.min(p.d, daysInMonth(y, m))
  return toIso(y, m, d)
}

// --- the grid --------------------------------------------------------------

// Forty-two cells, starting on the weekday the phone's locale starts a week
// on, with the days either side of the month included rather than left blank.
// A blank corner is a hole in a grid; a dim 31st is a date somebody can still
// tap, which is what they are reaching for when the month has just turned.
function grid(y, m, weekStart) {
  var first = daysFromCivil(y, m, 1)
  var start = first - ((((first % 7) + 11) % 7) - (weekStart || 0) + 7) % 7
  var out = []
  for (var i = 0; i < ROWS * 7; i++) {
    var c = civilFromDays(start + i)
    out.push({
      iso: toIso(c.y, c.m, c.d),
      day: c.d,
      weekday: (i + (weekStart || 0)) % 7,
      inMonth: c.m === m && c.y === y
    })
  }
  return out
}

function weekdayLabels(weekStart, kind) {
  var out = []
  for (var i = 0; i < 7; i++) {
    var d = (i + (weekStart || 0)) % 7
    out.push(kind === "long" ? DAYS[d] : (kind === "initial" ? DAYS_INITIAL[d] : DAYS_SHORT[d]))
  }
  return out
}

// --- saying a date out loud ------------------------------------------------

function monthLabel(y, m) {
  return MONTHS[m - 1] + " " + y
}

function dayLabel(iso) {
  var p = parts(iso)
  if (p === null) return ""
  return DAYS[weekday(iso)] + " " + p.d + " " + MONTHS[p.m - 1]
}

function fullDayLabel(iso) {
  var p = parts(iso)
  return p === null ? "" : dayLabel(iso) + " " + p.y
}

function shortDayLabel(iso) {
  var p = parts(iso)
  if (p === null) return ""
  return DAYS_SHORT[weekday(iso)] + " " + p.d + " " + MONTHS_SHORT[p.m - 1]
}

// "Today", "Tomorrow", "Yesterday", or nothing. Three words that save somebody
// working out what today's date is in order to read their own calendar.
function relative(iso, today) {
  var gap = between(today, iso)
  if (!isFinite(gap)) return ""
  if (gap === 0) return "Today"
  if (gap === 1) return "Tomorrow"
  if (gap === -1) return "Yesterday"
  return ""
}

function headline(iso, today) {
  return relative(iso, today) || dayLabel(iso)
}

function todayFrom(now, override) {
  if (override && isDay(override)) return override
  var d = now ? new Date(now) : new Date()
  return toIso(d.getFullYear(), d.getMonth() + 1, d.getDate())
}

// Minutes past midnight, from the phone's clock, rounded up to the next half
// hour. What a new event on today starts at, because the thing somebody is
// writing down while standing up is almost never in the past.
function nextHalfHour(now) {
  var d = now ? new Date(now) : new Date()
  var at = d.getHours() * 60 + d.getMinutes()
  var up = Math.ceil((at + 1) / 30) * 30
  return up >= MINUTES ? MINUTES - 60 : up
}

// --- times -----------------------------------------------------------------

// What somebody typed, or -1.
//
// The field is a text field because a phone with an on-screen keyboard has no
// room for a spinner and no patience for a wheel, and because "930" is what
// people type when a box says 09:30. So all of "9", "930", "0930", "9:30",
// "9.30", "9h30", "9 30" and "9:30 pm" are that time, and anything that is not
// a time at all is refused rather than guessed at -- the field keeps what was
// typed and says so, which is the only honest answer to "qq:30".
function parseTime(text) {
  var raw = String(text === null || text === undefined ? "" : text).toLowerCase().trim()
  if (!raw.length) return -1

  var half = 0
  var suffix = raw.match(/([ap])\.?m\.?$/)
  if (suffix) {
    half = suffix[1] === "a" ? 1 : 2
    raw = raw.slice(0, suffix.index).trim()
  }

  if (!/^\d{1,4}$/.test(raw) && !/^\d{1,2}\s*[:.h,\s]\s*\d{1,2}$/.test(raw)) return -1

  var hours, mins
  if (/^\d+$/.test(raw)) {
    if (raw.length <= 2) { hours = parseInt(raw, 10); mins = 0 }
    else if (raw.length === 3) { hours = parseInt(raw.slice(0, 1), 10); mins = parseInt(raw.slice(1), 10) }
    else { hours = parseInt(raw.slice(0, 2), 10); mins = parseInt(raw.slice(2), 10) }
  } else {
    var bits = raw.split(/[^0-9]+/)
    hours = parseInt(bits[0], 10)
    mins = parseInt(bits[1], 10)
  }

  if (!isFinite(hours) || !isFinite(mins) || mins > 59) return -1
  if (half) {
    if (hours < 1 || hours > 12) return -1
    hours = half === 1 ? (hours === 12 ? 0 : hours) : (hours === 12 ? 12 : hours + 12)
  }
  if (hours > 23) return -1
  return hours * 60 + mins
}

// Twenty-four hours, always, and not a setting.
//
// The phone's clock, the shell's bar and moarchy's own theme files are all on
// the 24-hour clock; a calendar that disagreed with the bar above it would be
// the only thing on the screen needing to be read twice.
function formatTime(minutes) {
  if (typeof minutes !== "number" || !isFinite(minutes) || minutes < 0) return ""
  var at = Math.floor(minutes) % MINUTES
  return two(Math.floor(at / 60)) + ":" + two(at % 60)
}

function formatSpan(start, end) {
  var from = formatTime(start)
  if (!from.length) return ""
  var to = formatTime(end)
  // An en dash with spaces, which is what a range is set in. A hyphen next to
  // a colon reads as a minus sign at caption size.
  return (!to.length || end <= start) ? from : from + " – " + to
}

function formatLength(minutes) {
  var n = Math.round(minutes)
  if (!isFinite(n) || n <= 0) return ""
  var hours = Math.floor(n / 60)
  var mins = n % 60
  if (!hours) return mins + " min"
  var said = hours === 1 ? "1 hour" : hours + " hours"
  return mins ? said + " " + mins + " min" : said
}

function clampMinutes(n) {
  if (!isFinite(n)) return 0
  return Math.max(0, Math.min(MINUTES - 1, Math.round(n)))
}

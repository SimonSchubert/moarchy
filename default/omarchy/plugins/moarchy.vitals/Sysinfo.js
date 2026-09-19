// The machine, out of /proc and /sys.
//
// The port of apps/vitals/moarchy_vitals/sysinfo.py, keeping the split that
// file exists for: the parsing and the arithmetic are here, with no QML in
// them, so a reading can be tested against a recorded fixture on any machine.
// That is where 72 of the GTK app's tests lived.
//
// What changes is the reading, not the parsing. Python opened each file
// itself; QML has no filesystem, and a FileView per file would be a dozen
// watchers plus one per process. So Collect.js builds a single shell command
// that prints the lot with markers between, and `split()` below turns its
// output back into the same strings Python's Sysroot.read() returned. Three
// processes a tick -- sh, awk and tr -- whatever the machine is doing.
.pragma library

// /proc/<pid>/stat, counted from field 1 as proc(5) numbers them. The comm is
// field 2 and is parsed out separately, so everything here is measured from
// field 3 onward.
var STAT = {
  state: 3, ppid: 4, utime: 14, stime: 15, threads: 20, starttime: 22, rss: 24
}
var STAT_FIRST = 3

// Both are compile-time constants on every kernel this runs on: USER_HZ has
// been 100 since Linux 2.6, and the page size is 4096 on aarch64 and x86_64.
var HZ = 100
var PAGE = 4096

var NOT_A_DISK = /^(loop|ram|zram|dm-|md|sr|fd)/

var STATES = {
  R: "running", S: "sleeping", D: "waiting", Z: "zombie",
  T: "stopped", t: "traced", X: "dead", I: "idle"
}

function clamp(value, low, high) {
  var lo = low === undefined ? 0 : low
  var hi = high === undefined ? 1 : high
  return value < lo ? lo : (value > hi ? hi : value)
}

function num(text) {
  if (text === null || text === undefined) return null
  var v = parseFloat(String(text).trim())
  return isNaN(v) ? null : v
}

// --- the collector's output ------------------------------------------------

// Collect.js emits `\x1e<name>\x1f<contents>` for each file it read, which is
// two characters the kernel never puts in these files (record and unit
// separators, which is what they are for).
var RS = "\x1e"
var US = "\x1f"

function split(blob) {
  var files = ({})
  var parts = String(blob || "").split(RS)
  for (var i = 0; i < parts.length; i++) {
    var at = parts[i].indexOf(US)
    if (at < 0) continue
    files[parts[i].slice(0, at)] = parts[i].slice(at + 1)
  }
  return files
}

function lines(text) {
  return String(text || "").split("\n")
}

function words(text) {
  var out = String(text || "").trim().split(/\s+/)
  return (out.length === 1 && out[0] === "") ? [] : out
}

// --- processor -------------------------------------------------------------

function uptimeOf(files) {
  var w = words(files["proc/uptime"])
  var v = w.length ? parseFloat(w[0]) : NaN
  return isNaN(v) ? 0 : v
}

// Idle *and* iowait are subtracted: a processor waiting for the eMMC is not
// working, and counting iowait as load makes every boot look pegged.
function cpuCounters(files) {
  var out = ({})
  var ls = lines(files["proc/stat"])
  for (var i = 0; i < ls.length; i++) {
    var parts = words(ls[i])
    if (!parts.length || parts[0].indexOf("cpu") !== 0) continue
    var values = []
    var bad = false
    for (var j = 1; j < parts.length; j++) {
      var v = parseInt(parts[j], 10)
      if (isNaN(v)) { bad = true; break }
      values.push(v)
    }
    if (bad || values.length < 5) continue
    var total = 0
    for (var k = 0; k < values.length; k++) total += values[k]
    out[parts[0]] = { busy: total - values[3] - values[4], total: total }
  }
  return out
}

function cpuFractions(now, before) {
  var out = ({})
  for (var name in now) {
    var was = before ? before[name] : undefined
    if (was === undefined) {
      // The first reading has nothing to subtract from, so it is the average
      // since boot. Zero would be a lie about an idle machine and 100% a worse
      // one about a busy phone.
      out[name] = now[name].total ? now[name].busy / now[name].total : 0
    } else {
      var span = now[name].total - was.total
      out[name] = span > 0 ? (now[name].busy - was.busy) / span : 0
    }
  }
  return out
}

function cpuOf(files, fractions) {
  // The file's own order, not sorted as strings -- cpu10 sorts before cpu2.
  var count = 0
  for (var name in fractions) if (/^cpu\d+$/.test(name)) count += 1
  var cores = []
  for (var n = 0; n < count; n++)
    cores.push(clamp(fractions["cpu" + n] === undefined ? 0 : fractions["cpu" + n]))

  var load = [0, 0, 0], tasks = 0, running = 0
  var parts = words(files["proc/loadavg"])
  if (parts.length >= 4) {
    var a = parseFloat(parts[0]), b = parseFloat(parts[1]), c = parseFloat(parts[2])
    if (!isNaN(a) && !isNaN(b) && !isNaN(c)) load = [a, b, c]
    var slash = parts[3].indexOf("/")
    if (slash > 0) {
      running = parseInt(parts[3].slice(0, slash), 10) || 0
      tasks = parseInt(parts[3].slice(slash + 1), 10) || 0
    }
  }

  return {
    total: clamp(fractions["cpu"] === undefined ? 0 : fractions["cpu"]),
    cores: cores,
    load: load,
    uptime: uptimeOf(files),
    tasks: tasks,
    running: running,
    temperature: temperatureOf(files),
    frequency: frequencyOf(files)
  }
}

// The hottest thermal zone, preferring one that names the processor.
//
// A phone has several -- battery, charger, modem, GPU -- and which index is
// which differs per SoC, so the type is read rather than assuming
// thermal_zone0 is the one anybody means.
var CPU_ZONE_HINTS = ["cpu", "soc", "pkg", "core", "tsens"]

function temperatureOf(files) {
  var best = null, bestCpu = null
  for (var key in files) {
    var m = /^sys\/class\/thermal\/(thermal_zone\d+)\/temp$/.exec(key)
    if (!m) continue
    var milli = parseInt(String(files[key]).trim(), 10)
    if (isNaN(milli)) continue
    var celsius = milli / 1000.0
    // A zone reporting -273 or 60000 is a driver that is not answering.
    if (!(celsius > -50 && celsius < 200)) continue
    var kind = String(files["sys/class/thermal/" + m[1] + "/type"] || "").trim().toLowerCase()
    for (var h = 0; h < CPU_ZONE_HINTS.length; h++) {
      if (kind.indexOf(CPU_ZONE_HINTS[h]) >= 0) {
        bestCpu = bestCpu === null ? celsius : Math.max(bestCpu, celsius)
        break
      }
    }
    best = best === null ? celsius : Math.max(best, celsius)
  }
  return bestCpu !== null ? bestCpu : best
}

// Averaged over the cores that report one, in MHz.
function frequencyOf(files) {
  var sum = 0, seen = 0
  for (var key in files) {
    if (!/^sys\/devices\/system\/cpu\/cpu\d+\/cpufreq\/scaling_cur_freq$/.test(key)) continue
    var khz = num(files[key])
    if (khz === null) continue
    sum += khz / 1000
    seen += 1
  }
  return seen ? sum / seen : null
}

// --- memory ----------------------------------------------------------------

function memoryOf(files) {
  var values = ({})
  var ls = lines(files["proc/meminfo"])
  for (var i = 0; i < ls.length; i++) {
    var colon = ls[i].indexOf(":")
    if (colon < 0) continue
    var key = ls[i].slice(0, colon)
    var parts = words(ls[i].slice(colon + 1))
    if (!parts.length) continue
    var amount = parseInt(parts[0], 10)
    if (isNaN(amount)) continue
    // A line with a unit is in kB; one without is already bytes.
    values[key] = parts.length > 1 ? amount * 1024 : amount
  }
  function at(name) { return values[name] === undefined ? 0 : values[name] }

  var total = at("MemTotal")
  // MemAvailable is the kernel's own estimate of what a new process could get
  // without swapping, which is the question anybody looking at a memory bar is
  // asking. Total minus free counts the page cache as used and reports every
  // idle Linux machine as full.
  var available = values["MemAvailable"] === undefined
                  ? at("MemFree") + at("Cached") + at("Buffers")
                  : values["MemAvailable"]
  var used = Math.max(0, total - available)
  var swapTotal = at("SwapTotal"), swapFree = at("SwapFree")
  var swapUsed = Math.max(0, swapTotal - swapFree)
  return {
    total: total,
    available: available,
    cached: at("Cached") + at("SReclaimable") + at("Buffers"),
    swap_total: swapTotal,
    swap_free: swapFree,
    used: used,
    fraction: total ? used / total : 0,
    swap_used: swapUsed,
    swap_fraction: swapTotal ? swapUsed / swapTotal : 0
  }
}

// --- network ---------------------------------------------------------------

// Where a signal in dBm stops improving and where it stops working. -40 is a
// phone on top of the router and -85 is the edge of the flat.
var DBM_BEST = -40.0
var DBM_WORST = -85.0

function dbmQuality(dbm) {
  return clamp((dbm - DBM_WORST) / (DBM_BEST - DBM_WORST))
}

// How good the wireless is, from the one column that means something.
//
// /proc/net/wireless has three figures per interface -- link, level, noise --
// and only one can be read without knowing the driver. The *link* column is a
// figure of merit whose denominator is not in the file: 70 for mac80211, 100
// for several vendor drivers, and nothing says which, so it is not used at all.
// The *level* column carries its units in its sign: negative is dBm, zero or
// above is the driver's own 0-100.
function wirelessOf(files) {
  var out = ({})
  var ls = lines(files["proc/net/wireless"])
  // Two header lines.
  for (var i = 2; i < ls.length; i++) {
    var colon = ls[i].indexOf(":")
    if (colon < 0) continue
    var name = ls[i].slice(0, colon).trim()
    var parts = words(ls[i].slice(colon + 1))
    if (!name || parts.length < 3) continue
    // Printed with a trailing dot, which parseFloat would stop at anyway --
    // stripped so an integer conversion is exact rather than lucky.
    var level = parseFloat(String(parts[2]).replace(/\.$/, ""))
    if (isNaN(level)) continue
    level = Math.round(level < 0 ? Math.ceil(level) : Math.floor(level))
    if (level < 0) out[name] = { quality: dbmQuality(level), signal: level }
    else out[name] = { quality: clamp(level / 100.0), signal: null }
  }
  return out
}

function netCounters(files) {
  var out = ({})
  var ls = lines(files["proc/net/dev"])
  for (var i = 0; i < ls.length; i++) {
    var colon = ls[i].indexOf(":")
    if (colon < 0) continue
    var name = ls[i].slice(0, colon).trim()
    var parts = words(ls[i].slice(colon + 1))
    if (!name || parts.length < 9) continue
    var rx = parseInt(parts[0], 10), tx = parseInt(parts[8], 10)
    if (isNaN(rx) || isNaN(tx)) continue
    out[name] = { rx: rx, tx: tx }
  }
  return out
}

function interfacesOf(files, now, before, elapsed) {
  var wireless = wirelessOf(files)
  var found = []
  for (var name in now) {
    var was = before ? before[name] : undefined
    var rxRate = 0, txRate = 0
    if (was !== undefined && elapsed) {
      // max(0, ...): an interface that goes down and comes back up starts its
      // counters again, and a negative throughput is a spike downwards that
      // never happened.
      rxRate = Math.max(0, (now[name].rx - was.rx) / elapsed)
      txRate = Math.max(0, (now[name].tx - was.tx) / elapsed)
    }
    var link = wireless[name] || { quality: null, signal: null }
    var state = String(files["sys/class/net/" + name + "/operstate"] || "").trim() || "unknown"
    found.push({
      name: name, rx: now[name].rx, tx: now[name].tx,
      rx_rate: rxRate, tx_rate: txRate, state: state,
      quality: link.quality, signal: link.signal,
      wireless: link.quality !== null || link.signal !== null,
      up: state === "up"
    })
  }
  // Loopback last. It is not a lie -- it carries real traffic -- but it is
  // never the answer to "what is using my data".
  found.sort(function (a, b) {
    if ((a.name === "lo") !== (b.name === "lo")) return a.name === "lo" ? 1 : -1
    var byTraffic = (b.rx + b.tx) - (a.rx + a.tx)
    if (byTraffic) return byTraffic
    return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
  })
  return found
}

// --- disks -----------------------------------------------------------------

// Sectors read and written across the real disks, as bytes.
//
// Whole devices only: /proc/diskstats lists every partition as well, and
// adding sda and sda1 together double-counts everything on it.
function ioCounters(files) {
  var names = ({})
  var ls = lines(files["proc/diskstats"])
  for (var i = 0; i < ls.length; i++) {
    var parts = words(ls[i])
    if (parts.length < 10 || NOT_A_DISK.test(parts[2])) continue
    var r = parseInt(parts[5], 10), w = parseInt(parts[9], 10)
    if (isNaN(r) || isNaN(w)) continue
    names[parts[2]] = { read: r, write: w }
  }
  var read = 0, write = 0
  for (var name in names) {
    var isPartition = false
    for (var other in names)
      if (other !== name && name.indexOf(other) === 0) { isPartition = true; break }
    if (isPartition) continue
    read += names[name].read * 512
    write += names[name].write * 512
  }
  return { read: read, write: write }
}

function ioOf(now, before, elapsed) {
  if (!before || !elapsed) return { read_rate: 0, write_rate: 0 }
  return {
    read_rate: Math.max(0, (now.read - before.read) / elapsed),
    write_rate: Math.max(0, (now.write - before.write) / elapsed)
  }
}

// --- battery ---------------------------------------------------------------

function batteryOf(files) {
  for (var key in files) {
    var m = /^sys\/class\/power_supply\/([^/]+)\/capacity$/.exec(key)
    if (!m) continue
    var base = "sys/class/power_supply/" + m[1] + "/"
    if (String(files[base + "type"] || "").trim() !== "Battery") continue
    var percent = num(files[key])
    if (percent === null) continue
    var watts = null
    var micro = num(files[base + "power_now"])
    if (micro !== null) {
      watts = Math.abs(micro) / 1e6
    } else {
      var current = num(files[base + "current_now"])
      var volts = num(files[base + "voltage_now"])
      if (current !== null && volts !== null)
        watts = Math.abs(current) * Math.abs(volts) / 1e12
    }
    return {
      percent: Math.round(percent),
      status: String(files[base + "status"] || "").trim() || "Unknown",
      watts: watts
    }
  }
  return null
}

// --- processes -------------------------------------------------------------

// The command is in parentheses and may contain spaces *and* parentheses --
// "(Web Content)", "(sh (deleted))" -- so the split is from the last close
// paren rather than by whitespace.
function parseStat(raw) {
  var open = raw.indexOf("("), close = raw.lastIndexOf(")")
  if (open < 0 || close < open) return null
  var comm = raw.slice(open + 1, close)
  var fields = words(raw.slice(close + 1))
  if (fields.length < STAT.rss - STAT_FIRST + 1) return null
  function at(name) { return fields[STAT[name] - STAT_FIRST] }
  var ppid = parseInt(at("ppid"), 10)
  var utime = parseInt(at("utime"), 10), stime = parseInt(at("stime"), 10)
  var threads = parseInt(at("threads"), 10)
  var started = parseInt(at("starttime"), 10)
  var rss = parseInt(at("rss"), 10)
  if (isNaN(ppid) || isNaN(utime) || isNaN(stime) || isNaN(rss)) return null
  return {
    comm: comm,
    state: at("state"),
    ppid: ppid,
    seconds: (utime + stime) / HZ,
    threads: isNaN(threads) ? 1 : threads,
    started: (isNaN(started) ? 0 : started) / HZ,
    rss: rss * PAGE
  }
}

// A command line, out of the NUL-separated blob the kernel gives.
function cmdlineOf(raw) {
  return String(raw || "").replace(/\0+$/, "").split("\0").join(" ").trim()
}

// The full name of a process whose comm was truncated. /proc/<pid>/stat caps
// the command at 15 characters, so "gnome-calendar" survives and
// "NetworkManager" is a coincidence -- the argv[0] basename is the real one.
function untruncated(comm, cmdline) {
  if (!cmdline) return comm
  var first = cmdline.split(" ")[0]
  var slash = first.lastIndexOf("/")
  var base = slash >= 0 ? first.slice(slash + 1) : first
  if (!base) return comm
  // Only when the short one is a prefix of the long one: an interpreter's
  // argv[0] is "python3" for a process whose comm is the script's name, and
  // replacing one with the other loses the answer.
  if (base.length > comm.length && base.indexOf(comm) === 0) return base
  return comm
}

// --- numbers as somebody reads them ----------------------------------------

var UNITS = ["B", "kB", "MB", "GB", "TB"]

function humanBytes(value, digits) {
  var scale = 0
  var amount = Math.max(0, value)
  while (amount >= 1000 && scale < UNITS.length - 1) { amount /= 1000.0; scale += 1 }
  // One decimal below ten, none above: "1.4 GB" and "428 MB" are both three
  // glyphs of information, which is what fits in a phone's column.
  var places = (digits === undefined || digits === null)
               ? ((amount < 10 && scale) ? 1 : 0) : digits
  return amount.toFixed(places) + " " + UNITS[scale]
}

function humanRate(value) { return humanBytes(value) + "/s" }

// A duration as the largest two units that say anything.
function humanSeconds(value) {
  var seconds = Math.floor(Math.max(0, value))
  var days = Math.floor(seconds / 86400); seconds -= days * 86400
  var hours = Math.floor(seconds / 3600); seconds -= hours * 3600
  var minutes = Math.floor(seconds / 60); seconds -= minutes * 60
  if (days) return days + "d " + hours + "h"
  if (hours) return hours + "h " + minutes + "m"
  if (minutes) return minutes + "m " + seconds + "s"
  return seconds + "s"
}

function humanPercent(value) { return Math.round(clamp(value) * 100) + "%" }

// A process's share of the machine, which is usually a small number. Rounded to
// whole percent, the busiest twenty processes on an idle phone all read "0%"
// and the list appears to be sorted by nothing.
function taskPercent(value) {
  var share = clamp(value) * 100
  return share < 9.95 ? share.toFixed(1) + "%" : Math.round(share) + "%"
}

// --- one reading -----------------------------------------------------------

// Everything a screen draws, out of one collection. `before` is the previous
// return of this function, which is where every rate in this app comes from --
// the same reason sysinfo.Sampler is stateful.
function read(blob, before) {
  var files = split(blob)
  var uptime = uptimeOf(files)
  var elapsed = null
  if (before && before.uptime > 0) {
    elapsed = uptime - before.uptime
    // No time has passed: two reads inside one clock tick. The honest answer is
    // the reading we already have.
    if (elapsed <= 0) return before
  }

  var cpuNow = cpuCounters(files)
  var cpu = cpuOf(files, cpuFractions(cpuNow, before ? before._cpuRaw : null))
  var netNow = netCounters(files)
  var ioNow = ioCounters(files)

  // The network page does not read the process half. When a reading has none,
  // the last table that did is carried forward with the time it was taken, so
  // the page after it measures against that -- a rate over the minute spent on
  // the network page -- rather than printing a column of zeroes for a tick.
  var procsRead = hasProcesses(files)
  var last = before && before._procRaw ? before : null
  var procs = procsRead
              ? processesOf(files, uptime, last, last ? uptime - last._procAt : null,
                            cpu.cores.length)
              : []

  return {
    uptime: uptime,
    cpu: cpu,
    memory: memoryOf(files),
    interfaces: interfacesOf(files, netNow, before ? before._netRaw : null, elapsed),
    io: ioOf(ioNow, before ? before._ioRaw : null, elapsed),
    battery: batteryOf(files),
    processes: procs,
    apps: appsOf(procs),
    _procRaw: procsRead ? procs._raw : (last ? last._procRaw : null),
    _procAt: procsRead ? uptime : (last ? last._procAt : 0),
    _cpuRaw: cpuNow,
    _netRaw: netNow,
    _ioRaw: ioNow
  }
}

function hasProcesses(files) {
  for (var key in files) if (/^proc\/\d+\/stat$/.test(key)) return true
  return false
}

// The task list. Every process's share is measured against the previous
// reading, so the first one after launch reports its average since it started
// rather than nothing.
// `cores` is not decoration: a share is of the whole machine, the way the
// workspace overview reports it, so one process pegging one core of eight is 12.5% and
// not 100%. Leaving it out put the collector's own `sh` at the top of the list
// at 100% on every tick, which is how this was found.
//
// The collector is left out: its shell, and the awk and tr that shell started.
// They are in the listing they print, they are gone before the next one, and on
// the first reading each is a whole core -- a process a millisecond old that
// has used a millisecond of processor.
function processesOf(files, uptime, before, elapsed, cores) {
  var out = []
  var previous = before ? before._procRaw : null
  var now = ({})
  var collector = parseInt(files["collector"], 10)
  for (var key in files) {
    var m = /^proc\/(\d+)\/stat$/.exec(key)
    if (!m) continue
    var pid = parseInt(m[1], 10)
    var st = parseStat(files[key])
    if (!st) continue
    if (pid === collector || st.ppid === collector) continue
    var cmdline = cmdlineOf(files["proc/" + pid + "/cmdline"])
    now[pid] = { seconds: st.seconds, started: st.started }

    var howMany = Math.max(1, cores || 1)
    var share = 0
    var was = previous ? previous[pid] : undefined
    // A pid that has been reused is a different process: its start time says
    // so, and crediting the new one with the old one's processor time is how a
    // freshly started shell appears at the top of the list.
    if (was !== undefined && was.started === st.started && elapsed) {
      share = Math.max(0, (st.seconds - was.seconds) / (elapsed * howMany))
    } else if (!before) {
      // The first tick of the list has nothing to subtract from, so a process
      // is reported as its average since it started -- which is what sorts the
      // very first list by something real instead of by a column of zeroes.
      var alive = Math.max(0.001, uptime - st.started)
      share = st.seconds / (alive * howMany)
    }
    // A process that appeared *since* the last reading gets nothing, and the
    // reason is not caution: its lifetime is a fraction of a tick, so
    // seconds/alive is one whole core however little work it did. The collector
    // here is a shell that is born and dies every tick, and it sat at the top
    // of this list at 100% until this branch existed. A rate needs two
    // readings; one reading of a millisecond-old process is not a rate.

    out.push({
      pid: pid,
      ppid: st.ppid,
      name: untruncated(st.comm, cmdline),
      cmdline: cmdline,
      state: STATES[st.state] === undefined ? st.state : STATES[st.state],
      threads: st.threads,
      rss: st.rss,
      seconds: st.seconds,
      cpu: clamp(share),
      kernel: !cmdline
    })
  }
  out.sort(function (a, b) {
    if (b.cpu !== a.cpu) return b.cpu - a.cpu
    return b.rss - a.rss
  })
  // Carried on the sample so the next read can measure against it.
  out._raw = now
  return out
}

// --- apps ------------------------------------------------------------------

// Processes, gathered into what somebody would call one thing.
//
// The GTK app believes the session first: a desktop entry launched through a
// systemd user session runs in an app-<id>.scope, and every helper it forks
// inherits it. This phone has none of those. Sway starts every app itself, so
// all of them share the login's session-N.scope, and the cgroup says nothing
// the name does not -- so the name is the whole grouping here, and the file is
// not read.
//
// Kernel threads are one group, as they are there. The Pixel 3a has 172 of
// them, none is an app by any reading, and a list of five they can crowd is a
// list where the app eating the battery is not on it.
function appsOf(processes) {
  var byKey = ({})
  var out = []
  for (var i = 0; i < processes.length; i++) {
    var p = processes[i]
    // kthreadd is pid 2 and every kernel thread is its child. `kernel` on the
    // row is "no command line", which a zombie has as well.
    var kernel = p.pid === 2 || p.ppid === 2
    var key = kernel ? "kernel" : "name:" + p.name
    var app = byKey[key]
    if (app === undefined) {
      app = byKey[key] = {
        key: key, name: kernel ? "Kernel threads" : p.name, kernel: kernel,
        pids: [], cpu: 0, rss: 0
      }
      out.push(app)
    }
    app.pids.push(p.pid)
    app.cpu += p.cpu
    // A sum of resident sizes counts a page two processes share twice, so an
    // app of many processes reads larger than it is. Proportional size is in
    // smaps_rollup, which walks every page table to produce it, and doing that
    // for every process every two seconds is the cost this app is for catching.
    app.rss += p.rss
  }
  for (var j = 0; j < out.length; j++) {
    // Lowest pid first: for anything with helper processes that is the one
    // that started them.
    out[j].pids.sort(function (a, b) { return a - b })
    out[j].cpu = clamp(out[j].cpu)
  }
  return out
}

function byName(a, b) {
  return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
}

// The processor page's list. Memory breaks a tie, which on an idle phone is
// most of the list: five apps at 0.0% in the order they were read would be a
// list sorted by nothing.
function busiest(apps, count) {
  return apps.slice().sort(function (a, b) {
    return (b.cpu - a.cpu) || (b.rss - a.rss) || byName(a, b)
  }).slice(0, count)
}

// The memory page's. Kernel threads have no address space and are left out
// rather than listed at 0 B.
function largest(apps, count) {
  return apps.filter(function (app) { return app.rss > 0 }).sort(function (a, b) {
    return (b.rss - a.rss) || (b.cpu - a.cpu) || byName(a, b)
  }).slice(0, count)
}

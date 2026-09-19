// One shell command that reads the whole machine.
//
// Python opened each file itself through sysinfo.Sysroot. QML has no
// filesystem: a FileView per file would be a dozen watchers plus one per
// process, and a phone with 300 processes would be 600 file objects rebuilt
// every two seconds. So this builds a single `sh -c` that prints the lot with a
// marker before each, and Sysinfo.split() turns the output back into the same
// strings Sysroot.read() returned.
//
// One awk reads every file. It used to be a `cat` per file, which is a fork and
// an exec for each of five hundred of them: on the Pixel 3a that was 2.4
// seconds of processor for one reading, against a clock that asks for one
// every two. The app pegged a core on the page that lists what is pegging the
// cores, and the list stayed empty for as long as a reading took to arrive.
// The same reading through one awk is 71 ms, and the whole app on the Tasks
// page went from 85% of one core to 16%.
//
// The network page does not ask for the process half at all -- the same
// argument sample(processes=False) makes.
.pragma library

var FIXED = [
  "proc/uptime", "proc/stat", "proc/loadavg", "proc/meminfo",
  "proc/net/dev", "proc/net/wireless", "proc/diskstats", "proc/self/mounts"
]

var GLOBS = [
  "sys/class/thermal/thermal_zone*/temp",
  "sys/class/thermal/thermal_zone*/type",
  "sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq",
  "sys/class/net/*/operstate",
  "sys/class/power_supply/*/type",
  "sys/class/power_supply/*/capacity",
  "sys/class/power_supply/*/status",
  "sys/class/power_supply/*/power_now",
  "sys/class/power_supply/*/current_now",
  "sys/class/power_supply/*/voltage_now"
]

var PROCESSES = ["proc/[0-9]*/stat", "proc/[0-9]*/cmdline"]

// Every file is opened with getline inside BEGIN, rather than named as input
// and read by the main loop, because awk treats an input file it cannot open
// as fatal. A process exits between the glob that listed it and the read on
// every tick of a busy machine, and one of those would end the reading there.
// getline returns -1 instead, and the file is silence rather than an error.
//
// The marker is printed with the first line, so an empty file -- a kernel
// thread's command line -- is absent, the same as one that was not there.
//
// The markers are octal 036 and 037, the ASCII record and unit separators,
// which is exactly what they are for and which the kernel puts in none of
// these files.
var AWK = [
  "BEGIN {",
  "  for (i = 1; i < ARGC; i++) {",
  "    first = 1",
  "    while ((getline line < ARGV[i]) > 0) {",
  "      if (first) printf \"\\036%s\\037\", ARGV[i]",
  "      first = 0",
  "      print line",
  "    }",
  "    close(ARGV[i])",
  "  }",
  "}"
].join("\n")

function shellQuote(text) {
  return "'" + String(text).split("'").join("'\\''") + "'"
}

function script(root, withProcesses) {
  var names = FIXED.concat(GLOBS)
  if (withProcesses) names = names.concat(PROCESSES)
  var out = []
  // Relative names, so the marker is already the key Sysinfo looks files up
  // by. A glob that matches nothing is passed on as itself, and getline
  // cannot open it.
  out.push("cd " + shellQuote(root || "/") + " || exit 1")
  // The collector's own pid. Its shell, awk and tr are all in the listing they
  // produce, and all of them a millisecond old: Sysinfo leaves them out rather
  // than report a process that is gone before the next reading.
  out.push("printf '\\036collector\\037%s\\n' \"$$\"")
  // /proc/<pid>/cmdline is NUL-separated, and stdout here is read as text: a
  // NUL either truncates the stream or is dropped with a warning, and in both
  // cases the arguments after the first are gone. Translated to spaces on the
  // way out, which is what the string was going to be turned into anyway, and
  // no other file read here has a NUL in it.
  out.push("awk " + shellQuote(AWK) + " " + names.join(" ") + " | tr '\\0' ' '")
  return out.join("\n")
}

function command(root, withProcesses) {
  return ["sh", "-c", script(root, withProcesses)]
}

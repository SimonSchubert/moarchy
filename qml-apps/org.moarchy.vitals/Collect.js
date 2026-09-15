// One shell command that reads the whole machine.
//
// Python opened each file itself through sysinfo.Sysroot. QML has no
// filesystem: a FileView per file would be a dozen watchers plus one per
// process, and a phone with 300 processes would be 600 file objects rebuilt
// every two seconds. So this builds a single `sh -c` that cats the lot with a
// marker before each, and Sysinfo.split() turns the output back into the same
// strings Sysroot.read() returned.
//
// One fork a tick. The overview does not ask for the process half at all,
// which is the difference between an app you can leave open on a phone and one
// you cannot -- the same argument sample(processes=False) makes.
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

function shellQuote(text) {
  return "'" + String(text).split("'").join("'\\''") + "'"
}

// `emit` prints the marker and then the file, and says nothing when the file is
// not there -- a read failure is silence rather than an error, because a
// process can exit between being listed and being read, and that is the normal
// case on every tick of a busy machine.
//
// The markers are octal 036 and 037, the ASCII record and unit separators,
// which is exactly what they are for and which the kernel puts in none of
// these files.
function script(root, withProcesses) {
  var out = []
  out.push("R=" + shellQuote(root || "/"))
  out.push('emit() { [ -r "$R/$1" ] || return 0; printf "\\036%s\\037" "$1"; cat "$R/$1" 2>/dev/null; }')
  // /proc/<pid>/cmdline is NUL-separated, and stdout here is read as text: a
  // NUL either truncates the stream or is dropped with a warning, and in both
  // cases the arguments after the first are gone. Translated to spaces at the
  // source, which is what the string was going to be turned into anyway.
  out.push('emitz() { [ -r "$R/$1" ] || return 0; printf "\\036%s\\037" "$1"; tr "\\0" " " < "$R/$1" 2>/dev/null; }')
  for (var i = 0; i < FIXED.length; i++) out.push("emit " + shellQuote(FIXED[i]))

  // Globs rather than a listing: the shell expands them in one pass, and one
  // that matches nothing expands to itself, which `[ -r ]` then rejects.
  var globs = []
  for (var g = 0; g < GLOBS.length; g++) globs.push('"$R"/' + GLOBS[g])
  if (withProcesses) globs.push('"$R"/proc/[0-9]*/stat')
  out.push("for f in " + globs.join(" ") + '; do emit "${f#"$R"/}"; done')
  if (withProcesses)
    out.push('for f in "$R"/proc/[0-9]*/cmdline; do emitz "${f#"$R"/}"; done')
  return out.join("\n")
}

function command(root, withProcesses) {
  return ["sh", "-c", script(root, withProcesses)]
}

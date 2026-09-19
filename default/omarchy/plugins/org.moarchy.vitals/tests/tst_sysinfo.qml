// The parsers, against /proc text and the numbers
// apps/vitals/moarchy_vitals/sysinfo.py produces from it.
//
// The reading changed in the port -- one shell command instead of a dozen
// opens -- and the parsing did not, so this is where that claim is checked.
import QtQuick
import QtTest
import "../Sysinfo.js" as Sysinfo

TestCase {
  name: "VitalsSysinfo"

  function blob(files) {
    var out = ""
    for (var name in files) out += Sysinfo.RS + name + Sysinfo.US + files[name]
    return out
  }

  function test_the_markers_survive_a_round_trip() {
    var files = Sysinfo.split(blob({ "proc/uptime": "123.45 400.00\n",
                                     "proc/stat": "cpu 1 2 3 4 5\n" }))
    compare(files["proc/uptime"], "123.45 400.00\n")
    compare(files["proc/stat"], "cpu 1 2 3 4 5\n")
  }

  function test_a_file_that_was_not_there_is_simply_absent() {
    var files = Sysinfo.split(blob({ "proc/uptime": "1 2\n" }))
    compare(files["proc/meminfo"], undefined)
    // A read failure is silence rather than an error: a process can exit
    // between being listed and being read, and that is the normal case.
    compare(Sysinfo.memoryOf(files).total, 0)
  }

  // --- processor ----------------------------------------------------------

  readonly property string stat1:
    "cpu  100 0 100 700 100 0 0 0 0 0\n" +
    "cpu0 50 0 50 350 50 0 0 0 0 0\n" +
    "cpu1 50 0 50 350 50 0 0 0 0 0\n" +
    "intr 12345\n"

  readonly property string stat2:
    "cpu  150 0 150 900 100 0 0 0 0 0\n" +
    "cpu0 100 0 100 400 50 0 0 0 0 0\n" +
    "cpu1 50 0 50 500 50 0 0 0 0 0\n" +
    "intr 12999\n"

  function test_the_first_reading_is_the_average_since_boot() {
    // Zero would be a lie about an idle machine and 100% a worse one about a
    // busy phone. 200 busy of 1000 total.
    var f = Sysinfo.cpuFractions(Sysinfo.cpuCounters(Sysinfo.split(blob({ "proc/stat": stat1 }))), null)
    fuzzyCompare(f["cpu"], 0.2, 1e-9)
  }

  function test_the_second_reading_is_the_difference() {
    var a = Sysinfo.cpuCounters(Sysinfo.split(blob({ "proc/stat": stat1 })))
    var b = Sysinfo.cpuCounters(Sysinfo.split(blob({ "proc/stat": stat2 })))
    // busy 200->300 (+100), total 1000->1300 (+300)
    fuzzyCompare(Sysinfo.cpuFractions(b, a)["cpu"], 100 / 300, 1e-9)
  }

  function test_iowait_is_not_load() {
    // A processor waiting for the eMMC is not working, and counting iowait as
    // load makes every boot look pegged.
    var idle = Sysinfo.cpuCounters(Sysinfo.split(blob({ "proc/stat": "cpu 0 0 0 500 500 0 0 0 0 0\n" })))
    compare(Sysinfo.cpuFractions(idle, null)["cpu"], 0)
  }

  function test_cores_are_in_the_files_order_not_sorted_as_strings() {
    // cpu10 sorts before cpu2 as a string, and a phone with eight cores would
    // draw its bars in the wrong order.
    var text = "cpu 0 0 0 1 0\n"
    for (var i = 0; i < 12; i++) text += "cpu" + i + " " + i + " 0 0 " + (100 - i) + " 0\n"
    var files = Sysinfo.split(blob({ "proc/stat": text, "proc/loadavg": "0 0 0 1/1 1\n" }))
    var cpu = Sysinfo.cpuOf(files, Sysinfo.cpuFractions(Sysinfo.cpuCounters(files), null))
    compare(cpu.cores.length, 12)
    // cpu10 is busier than cpu2, so index 10 must be the busier one.
    verify(cpu.cores[10] > cpu.cores[2])
  }

  function test_loadavg_carries_running_and_total() {
    var files = Sysinfo.split(blob({ "proc/stat": stat1, "proc/loadavg": "0.52 0.41 0.33 2/431 9999\n" }))
    var cpu = Sysinfo.cpuOf(files, Sysinfo.cpuFractions(Sysinfo.cpuCounters(files), null))
    fuzzyCompare(cpu.load[0], 0.52, 1e-9)
    compare(cpu.running, 2)
    compare(cpu.tasks, 431)
  }

  function test_the_hottest_zone_that_names_the_processor_wins() {
    // Which index is which differs per SoC, so the type is read rather than
    // assuming thermal_zone0 is the one anybody means.
    var files = Sysinfo.split(blob({
      "sys/class/thermal/thermal_zone0/temp": "68000\n",
      "sys/class/thermal/thermal_zone0/type": "battery-therm\n",
      "sys/class/thermal/thermal_zone1/temp": "42500\n",
      "sys/class/thermal/thermal_zone1/type": "cpu0-silver-usr\n"
    }))
    // The battery is hotter and is not the answer.
    fuzzyCompare(Sysinfo.temperatureOf(files), 42.5, 1e-9)
  }

  function test_with_no_processor_zone_the_hottest_wins() {
    var files = Sysinfo.split(blob({
      "sys/class/thermal/thermal_zone0/temp": "31000\n",
      "sys/class/thermal/thermal_zone0/type": "pm8998_tz\n",
      "sys/class/thermal/thermal_zone1/temp": "44000\n",
      "sys/class/thermal/thermal_zone1/type": "xo-therm\n"
    }))
    fuzzyCompare(Sysinfo.temperatureOf(files), 44.0, 1e-9)
  }

  function test_a_driver_that_is_not_answering_is_ignored() {
    var files = Sysinfo.split(blob({
      "sys/class/thermal/thermal_zone0/temp": "-274000\n",
      "sys/class/thermal/thermal_zone0/type": "cpu-therm\n"
    }))
    compare(Sysinfo.temperatureOf(files), null)
  }

  function test_frequency_is_khz_averaged_over_the_cores_that_report_one() {
    var files = Sysinfo.split(blob({
      "sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq": "nonsense\n",
      "sys/devices/system/cpu/cpu1/cpufreq/scaling_cur_freq": "1200000\n",
      "sys/devices/system/cpu/cpu2/cpufreq/scaling_cur_freq": "1800000\n"
    }))
    fuzzyCompare(Sysinfo.frequencyOf(files), 1500.0, 1e-9)
  }

  // --- memory -------------------------------------------------------------

  readonly property string meminfo:
    "MemTotal:        1994752 kB\n" +
    "MemFree:          123456 kB\n" +
    "MemAvailable:     987654 kB\n" +
    "Buffers:           10000 kB\n" +
    "Cached:           600000 kB\n" +
    "SReclaimable:      50000 kB\n" +
    "SwapTotal:       1000000 kB\n" +
    "SwapFree:         750000 kB\n"

  function test_memory_used_is_total_minus_available() {
    // Total minus free counts the page cache as used and reports every idle
    // Linux machine as full.
    var m = Sysinfo.memoryOf(Sysinfo.split(blob({ "proc/meminfo": meminfo })))
    compare(m.total, 1994752 * 1024)
    compare(m.available, 987654 * 1024)
    compare(m.used, (1994752 - 987654) * 1024)
    compare(m.cached, (600000 + 50000 + 10000) * 1024)
    compare(m.swap_used, 250000 * 1024)
    fuzzyCompare(m.swap_fraction, 0.25, 1e-9)
  }

  function test_a_kernel_without_memavailable_is_estimated() {
    var m = Sysinfo.memoryOf(Sysinfo.split(blob({ "proc/meminfo":
      "MemTotal: 1000 kB\nMemFree: 100 kB\nCached: 200 kB\nBuffers: 50 kB\n" })))
    compare(m.available, 350 * 1024)
  }

  // --- network ------------------------------------------------------------

  readonly property string netdev:
    "Inter-|   Receive                                                |  Transmit\n" +
    " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets\n" +
    "    lo: 1000 10 0 0 0 0 0 0 1000 10 0 0 0 0 0 0\n" +
    "  wlan0: 5000 50 0 0 0 0 0 0 2000 20 0 0 0 0 0 0\n"

  function test_rates_need_two_readings() {
    var files = Sysinfo.split(blob({ "proc/net/dev": netdev }))
    var a = Sysinfo.netCounters(files)
    var first = Sysinfo.interfacesOf(files, a, null, null)
    compare(first[0].rx_rate, 0)

    var later = Sysinfo.netCounters(Sysinfo.split(blob({ "proc/net/dev":
      netdev.replace("5000 50", "9000 90") })))
    var second = Sysinfo.interfacesOf(files, later, a, 2.0)
    // wlan0 gained 4000 bytes in two seconds.
    compare(second[0].name, "wlan0")
    fuzzyCompare(second[0].rx_rate, 2000, 1e-9)
  }

  function test_a_counter_that_went_backwards_is_not_a_negative_spike() {
    // An interface that goes down and comes back up starts its counters again.
    var files = Sysinfo.split(blob({ "proc/net/dev": netdev }))
    var high = Sysinfo.netCounters(files)
    var low = Sysinfo.netCounters(Sysinfo.split(blob({ "proc/net/dev":
      netdev.replace("5000 50", "10 1") })))
    var got = Sysinfo.interfacesOf(files, low, high, 2.0)
    for (var i = 0; i < got.length; i++) verify(got[i].rx_rate >= 0)
  }

  function test_loopback_sorts_last() {
    // It carries real traffic, but it is never the answer to "what is using my
    // data", and on a phone with one wlan it would otherwise sit at the top.
    var files = Sysinfo.split(blob({ "proc/net/dev": netdev }))
    var got = Sysinfo.interfacesOf(files, Sysinfo.netCounters(files), null, null)
    compare(got[got.length - 1].name, "lo")
  }

  function test_a_negative_level_is_dbm_and_a_positive_one_is_a_percentage() {
    // The level column carries its units in its sign, which is the one piece of
    // luck in that file. The link column's denominator is not in it at all.
    var files = Sysinfo.split(blob({ "proc/net/wireless":
      "Inter-| sta-|   Quality        |   Discarded packets\n" +
      " face | tus | link level noise |  nwid  crypt   frag\n" +
      " wlan0: 0000   73.  -52.  -256.  0 0 0 0 0 0 0\n" +
      " wlan1: 0000   60.   65.  -256.  0 0 0 0 0 0 0\n" }))
    var w = Sysinfo.wirelessOf(files)
    compare(w["wlan0"].signal, -52)
    // (-52 - -85) / (-40 - -85) = 33/45
    fuzzyCompare(w["wlan0"].quality, 33 / 45, 1e-9)
    // A driver's own 0-100 figure, taken at face value, with no dBm to show.
    compare(w["wlan1"].signal, null)
    fuzzyCompare(w["wlan1"].quality, 0.65, 1e-9)
  }

  // --- disks --------------------------------------------------------------

  function test_a_partition_is_not_counted_beside_its_whole_disk() {
    // Adding sda and sda1 together double-counts everything on it.
    var files = Sysinfo.split(blob({ "proc/diskstats":
      "   8  0 sda 1 2 100 4 5 6 200 8 9 10 11\n" +
      "   8  1 sda1 1 2 100 4 5 6 200 8 9 10 11\n" +
      "   7  0 loop0 1 2 999 4 5 6 999 8 9 10 11\n" }))
    var io = Sysinfo.ioCounters(files)
    compare(io.read, 100 * 512)
    compare(io.write, 200 * 512)
  }

  // --- processes ----------------------------------------------------------

  function test_a_command_with_spaces_and_parens_still_parses() {
    // "(Web Content)" and "(sh (deleted))" are both real.
    var tail = ""
    for (var i = 0; i < 30; i++) tail += "0 "
    var st = Sysinfo.parseStat("42 (Web Content) S 1 42 42 0 -1 4194304 100 0 0 0 " +
      "300 200 0 0 20 0 8 0 99000 1234 5678 " + tail)
    compare(st.comm, "Web Content")
    compare(st.state, "S")
    compare(st.ppid, 1)
    fuzzyCompare(st.seconds, 5.0, 1e-9)
  }

  function test_a_truncated_comm_is_recovered_from_argv() {
    // /proc/<pid>/stat caps the command at 15 characters.
    compare(Sysinfo.untruncated("gnome-calendar-", "/usr/bin/gnome-calendar-server --x"),
            "gnome-calendar-server")
    // Only when the short one is a prefix: an interpreter's argv[0] is
    // "python3" for a process whose comm is the script's name.
    compare(Sysinfo.untruncated("myscript.py", "/usr/bin/python3 myscript.py"), "myscript.py")
    compare(Sysinfo.untruncated("foot", ""), "foot")
  }

  function test_a_cmdline_arrives_space_separated() {
    // The collector translates the NULs at the source, because stdout here is
    // read as text and a NUL would take every argument after the first.
    compare(Sysinfo.cmdlineOf("/usr/bin/foo -x --flag "), "/usr/bin/foo -x --flag")
    compare(Sysinfo.cmdlineOf(""), "")
  }

  // --- the formatters -----------------------------------------------------

  function test_human_bytes_data() {
    return [
      { tag: "bytes",    v: 512,        text: "512 B" },
      { tag: "kB",       v: 1500,       text: "1.5 kB" },
      { tag: "tens",     v: 15000,      text: "15 kB" },
      { tag: "MB",       v: 428000000,  text: "428 MB" },
      { tag: "GB",       v: 1400000000, text: "1.4 GB" },
      { tag: "zero",     v: 0,          text: "0 B" },
      { tag: "negative", v: -5,         text: "0 B" }
    ]
  }
  function test_human_bytes(row) { compare(Sysinfo.humanBytes(row.v), row.text) }

  function test_human_seconds_data() {
    return [
      { tag: "seconds", v: 45,     text: "45s" },
      { tag: "minutes", v: 125,    text: "2m 5s" },
      { tag: "hours",   v: 7325,   text: "2h 2m" },
      { tag: "days",    v: 200000, text: "2d 7h" }
    ]
  }
  function test_human_seconds(row) { compare(Sysinfo.humanSeconds(row.v), row.text) }

  function test_a_small_share_still_orders_the_list() {
    // Rounded to whole percent the busiest twenty processes on an idle phone
    // all read "0%" and the list appears to be sorted by nothing.
    compare(Sysinfo.taskPercent(0.001), "0.1%")
    compare(Sysinfo.taskPercent(0.052), "5.2%")
    compare(Sysinfo.taskPercent(0.4), "40%")
    compare(Sysinfo.humanPercent(0.5), "50%")
  }

  function test_a_share_is_of_the_whole_machine_not_of_one_core() {
    // One process pegging one core of eight is 12.5%, not 100%. Without the
    // core count the collector's own shell sat at the top of the list at 100%
    // on every tick.
    var tail = ""
    for (var i = 0; i < 30; i++) tail += "0 "
    // 200 ticks of utime = 2s of processor, over a 2s window.
    var stat = "7 (busy) R 1 7 7 0 -1 0 0 0 0 0 200 0 0 0 20 0 1 0 0 0 100 " + tail
    var files = Sysinfo.split(blob({ "proc/7/stat": stat, "proc/7/cmdline": "busy " }))
    var before = { _procRaw: { 7: { seconds: 0, started: 0 } } }
    var eight = Sysinfo.processesOf(files, 100, before, 2.0, 8)
    fuzzyCompare(eight[0].cpu, 0.125, 1e-9)
    var one = Sysinfo.processesOf(files, 100, before, 2.0, 1)
    fuzzyCompare(one[0].cpu, 1.0, 1e-9)
  }

  function test_a_reused_pid_is_not_credited_with_the_old_processs_time() {
    var tail = ""
    for (var i = 0; i < 30; i++) tail += "0 "
    var stat = "7 (fresh) R 1 7 7 0 -1 0 0 0 0 0 10 0 0 0 20 0 1 0 9000 0 100 " + tail
    var files = Sysinfo.split(blob({ "proc/7/stat": stat, "proc/7/cmdline": "fresh " }))
    // The previous reading had this pid starting at a different time.
    var before = { _procRaw: { 7: { seconds: 5000, started: 12 } } }
    var got = Sysinfo.processesOf(files, 100, before, 2.0, 4)
    // Nothing, and that is the point: a reused pid is a process nobody has a
    // previous reading of, so there is no rate to report. Subtracting the old
    // process's counter would have given a negative, and using the since-start
    // average would have given a whole core -- both of which put a freshly
    // started shell at the top of the list.
    compare(got[0].cpu, 0)
  }

  function test_a_process_born_since_the_last_reading_has_no_rate_yet() {
    // Its lifetime is a fraction of a tick, so seconds/alive is one whole core
    // however little work it did -- which put the collector's own shell at the
    // top of the list at 100% on every tick.
    var tail = ""
    for (var i = 0; i < 30; i++) tail += "0 "
    // starttime 999000 ticks = 9990s, against an uptime of 9990.001s.
    var stat = "31682 (sh) S 1 1 1 0 -1 0 0 0 0 0 1 0 0 0 20 0 1 0 999000 0 100 " + tail
    var files = Sysinfo.split(blob({ "proc/31682/stat": stat, "proc/31682/cmdline": "sh " }))
    // Not the first sample: something was read before, and this pid was not in it.
    var before = { _procRaw: { 1: { seconds: 5, started: 0 } } }
    compare(Sysinfo.processesOf(files, 9990.001, before, 2.0, 8)[0].cpu, 0)
    // On the very first sample there is nothing to subtract from, so the
    // since-boot average is still what sorts the list.
    verify(Sysinfo.processesOf(files, 9990.001, null, null, 8)[0].cpu > 0)
  }

  // A /proc/<pid>/stat line with the fields this app reads, and zeroes for the
  // rest.
  function statLine(pid, comm, ppid, ticks, started, pages) {
    var tail = ""
    for (var i = 0; i < 30; i++) tail += "0 "
    return pid + " (" + comm + ") S " + ppid + " " + pid + " " + pid + " 0 -1 0 0 0 0 0 " +
           ticks + " 0 0 0 20 0 1 0 " + started + " 0 " + pages + " " + tail
  }

  function test_the_collector_is_not_in_its_own_listing() {
    // Its shell, and the awk and tr that shell started. On the first reading
    // each is a millisecond old with a millisecond of processor, which is a
    // whole core at the top of the processor page.
    var files = Sysinfo.split(blob({
      "collector": "500\n",
      "proc/1/stat": statLine(1, "systemd", 0, 100, 0, 10), "proc/1/cmdline": "/sbin/init ",
      "proc/500/stat": statLine(500, "sh", 400, 1, 999000, 10), "proc/500/cmdline": "sh -c x ",
      "proc/501/stat": statLine(501, "awk", 500, 1, 999000, 10), "proc/501/cmdline": "awk x ",
      "proc/502/stat": statLine(502, "tr", 500, 1, 999000, 10), "proc/502/cmdline": "tr x "
    }))
    var got = Sysinfo.processesOf(files, 9990.001, null, null, 8)
    compare(got.length, 1)
    compare(got[0].name, "systemd")
  }

  function test_a_reading_without_processes_keeps_the_last_table_to_measure_against() {
    // The network page reads no processes. The page after it measures against
    // the last table that was read, over the time since -- not against nothing,
    // which was a column of zeroes for a tick.
    var a = Sysinfo.read(blob({ "proc/uptime": "100.00 0\n",
                                "proc/7/stat": statLine(7, "busy", 1, 0, 0, 10),
                                "proc/7/cmdline": "busy " }), null)
    var b = Sysinfo.read(blob({ "proc/uptime": "102.00 0\n" }), a)
    compare(b.processes.length, 0)
    compare(b.apps.length, 0)
    // 200 ticks is two seconds of processor, four seconds after the table was
    // taken. No proc/stat, so no cores counted, so a share of one.
    var c = Sysinfo.read(blob({ "proc/uptime": "104.00 0\n",
                                "proc/7/stat": statLine(7, "busy", 1, 200, 0, 10),
                                "proc/7/cmdline": "busy " }), b)
    fuzzyCompare(c.processes[0].cpu, 0.5, 1e-9)
  }

  function test_processes_of_one_name_are_one_app() {
    var apps = Sysinfo.appsOf([
      { pid: 900, ppid: 1, name: "firefox", cpu: 0.05, rss: 300 },
      { pid: 960, ppid: 900, name: "Isolated Web Co", cpu: 0.01, rss: 100 },
      { pid: 950, ppid: 900, name: "Isolated Web Co", cpu: 0.02, rss: 200 }
    ])
    compare(apps.length, 2)
    var web = apps[1]
    compare(web.name, "Isolated Web Co")
    // Lowest pid first: the one that started the others.
    compare(web.pids, [950, 960])
    fuzzyCompare(web.cpu, 0.03, 1e-9)
    compare(web.rss, 300)
  }

  function test_kernel_threads_are_one_app() {
    // kthreadd and its children. Ninety rows of them would crowd a list of five.
    var apps = Sysinfo.appsOf([
      { pid: 2, ppid: 0, name: "kthreadd", cpu: 0, rss: 0 },
      { pid: 40, ppid: 2, name: "kworker/0:1", cpu: 0.003, rss: 0 },
      { pid: 41, ppid: 2, name: "sugov:0", cpu: 0.002, rss: 0 },
      { pid: 700, ppid: 1, name: "sway", cpu: 0.001, rss: 5000 }
    ])
    compare(apps.length, 2)
    compare(apps[0].name, "Kernel threads")
    verify(apps[0].kernel)
    compare(apps[0].pids, [2, 40, 41])
    fuzzyCompare(apps[0].cpu, 0.005, 1e-9)
    verify(!apps[1].kernel)
  }

  function test_the_busiest_and_the_largest_lists() {
    var apps = [
      { name: "b", cpu: 0, rss: 10, kernel: false },
      { name: "a", cpu: 0, rss: 50, kernel: false },
      { name: "c", cpu: 0.2, rss: 1, kernel: false },
      { name: "Kernel threads", cpu: 0.01, rss: 0, kernel: true }
    ]
    function names(list) { return list.map(function (app) { return app.name }) }
    // A tie at 0.0% is broken by memory, not left in the order it was read.
    compare(names(Sysinfo.busiest(apps, 3)), ["c", "Kernel threads", "a"])
    // Kernel threads have no memory of their own to list.
    compare(names(Sysinfo.largest(apps, 5)), ["a", "b", "c"])
  }
}

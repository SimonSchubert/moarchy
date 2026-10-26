# CPU boost — specification

The shell gets the fast cores at full clock while a finger is on the screen,
and work nobody is looking at is kept off them: OWL widgets' command sources,
and every app behind home. Android does the same with its input boost and its
background cgroup. Present tense, normative.

The mechanism is utilization clamping (`CONFIG_UCLAMP_TASK`): `uclamp.min`
tells schedutil and the energy-aware scheduler to treat a task as at least that
busy, `uclamp.max` as at most that busy. On sargo cpu0-5 are A55 (capacity
522) and cpu6-7 A75 (capacity 1024), so `max 512` keeps a task on the A55s at a
low clock and `min 1024` puts one on an A75 at full clock. An unprivileged
process may raise and lower both clamps on its own user's tasks, so none of this
needs root. `nice` would need root to undo (`RLIMIT_NICE` is 0), so it is used
only for processes that never need undoing (CB8).

Ids are `CB<n>`, cited by any check that proves one.

---

## What is boosted, and what is not

Only the shell, and only while a finger is down (CB2). A permanent boost costs
power at rest: with no finger on the screen the A75s spend 25-26% of the time
at 1.75 GHz or more, against 14-16% unboosted, because gregoftheweb-sip's
once-a-second redraw then runs at full clock. Hyprland is not boosted: with
Hyprland boosted too, turns measured no better than with the shell boosted
alone (table below). The app in front is not boosted either. No app has been
measured yet.

## What was measured

12 page turns between face, page 1 and page 2, scripted with `moarchy-touch`
(`home-page-turn-perf`), each row 2-3 runs. `omarchy-shell home stalls`
measures the GUI thread's lateness, and shell CPU is the shell's CPU time
during the run.

| clamp | stall-max | stalls >= 33 ms | fps | shell CPU |
|---|---|---|---|---|
| none | 62-72 ms | 3 | 59-60 | 22-23% |
| min 512, shell + Hyprland | 60-64 ms | 2-3 | 60 | 19-20% |
| min 1024, shell + Hyprland | 38-54 ms | 2 | 61 | 15-16% |
| min 1024, shell only | 43 ms | 1-2 | 60 | 16% |

Unboosted, the GUI thread already sat on an A75 89-95% of the time. The boost
works by clock speed (mean A75 frequency 1.1 → 1.3 GHz during turns), not by
moving the thread to a faster core. The shell's CPU time fell from 22% to 15%
of a core because the same work finished faster.

## A. The touch boost

**CB1** With no finger down for more than 1 s, every thread of the shell
(`quickshell`) has `uclamp.min` 0.
→ `q=$(pgrep -xo quickshell); for t in /proc/$q/task/*; do uclampset -p ${t##*/}; done | grep -vc 'min: 0 '`
prints `0`, and `| wc -l` is the thread count (> 0, so the loop read something)

**CB2** From the first finger down on any touchscreen until 1 s after the last
finger lifts, every thread of the shell has `uclamp.min` 1024. That includes
threads the shell starts during the boost, and a touchscreen that appears after
the service starts: `moarchy-touch`'s virtual panel counts, or a scripted turn
measures nothing.
→ `moarchy-touch` down at (360, 700), hold 2 s: CB1's loop with `'min: 1024 '`
prints `0`; release, and within 0.8 s it still prints `0`; at 1.5 s CB1 holds

**CB3** The boost follows the shell across a restart without restarting the
service: the first touch after `moarchy-restart-shell` boosts the new pid.
→ restart the shell, wait for an IPC verb to answer, then run CB2 against the new pid

**CB4** A process the shell starts during the boost does not inherit it: the
boost is set with reset-on-fork, so an OWL source, or an app the shell
launches, starts at `uclamp.min` 0.
→ during a 3 s held touch, every child of the shell started after touch-down
(`ps -o lstart`) reports `min: 0`; the check fails if no such child exists

**CB5** At rest the boost costs nothing: over 30 s with no finger down, the
A75s' share of time at 1.75 GHz or more (`policy6/stats/time_in_state`) is
within 3 points of the service stopped, not the 10 points a permanent boost
adds.
→ the time_in_state delta over 30 s, with the service running and with it stopped

**CB6** Page turns with the touch boost do as well as the permanent boost: 12
turns give stall-max at most 55 ms and shell CPU at most 17% of a core.
→ `omarchy-shell home stalls` (HM5c) after 12 scripted `moarchy-touch` turns
between face, page 1 and page 2, following one warm-up round; run twice

**CB7** The service wakes only on finger down and up, not on every movement:
it masks its touchscreen reads to `EV_KEY` (`EVIOCSMASK`). Over 60 s with no
finger down its CPU time does not move, and during CB6's 12 turns it stays
under 1% of a core.
→ `utime+stime` of the service's pid from `/proc/<pid>/stat`, before and after each

## B. Background work

**CB8** OWL `cmd` and `stream` sources run at `nice` 10 with `uclamp.max` 512.
They are one-shot or restarted children of the shell, so the `nice` never needs
undoing.
→ while a source runs, `ps -o ni= -p <its bash>` is `10` and `uclampset -p` shows `max: 512`

**CB9** Every app window's process that is not on the focused workspace has
`uclamp.max` 512 on every thread and every descendant. The app in front has
1024. On home (an empty workspace) every app is behind.
→ `foot` on workspace 2, focus workspace 1: foot's threads show `max: 512`;
focus 2: `max: 1024`

**CB10** An app comes forward within 100 ms of its workspace being focused, so
the first frames after a switch are not drawn at the background clock.
→ the clamp read 100 ms after `hl.dsp.focus({ workspace = "2" })` returns shows `max: 1024`

**CB11** Processes owned by another user, such as Waydroid's container, are
left alone. The service cannot clamp them, and a failure to clamp one is not
logged once per event.
→ with Waydroid running, 20 workspace switches add at most one line to the
service's journal

## C. Failure

**CB12** The service is `moarchy-boost.service`, a user unit pulled in by
`moarchy-session.target`. Stopping it undoes every clamp it set: the shell
back to `min` 0, every app back to `max` 1024. A crash cannot undo anything, so
the service resets the same clamps when it starts, and systemd restarts it. The
shell and apps work the same without it, only slower.
→ `systemctl --user stop moarchy-boost`, then CB1 holds and `foot`'s threads show `max: 1024`;
`systemctl --user kill -s KILL moarchy-boost`: the same once systemd restarts it

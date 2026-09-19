#!/usr/bin/env python3
"""Four alarms, a stopwatch mid-lap and a timer running, where the app reads them.

The screens in this plugin are only interesting once there is something on
them, and three of the four are only interesting while something is *moving* --
a stopwatch at zero and a timer nobody has started are both an empty box. The
GTK apps solve that with a `demo.py` that writes their store by hand and a
harness that runs it before it photographs anything; this is that file for a
plugin rather than an app, same idea and same place on the disk.

    MOARCHY_CLOCK_DIR=/tmp/c plugins/moarchy.clock/demo.py
    MOARCHY_CLOCK_DIR=/tmp/c MOARCHY_CLOCK_NOW=1789466976 \\
        plugins/moarchy.clock/run-local.sh

Everything is dated from `MOARCHY_CLOCK_NOW`, the same variable the app reads
its clock from, so the two halves agree about what time it is. Without that a
stopwatch fixture would read 3:41 in one picture and 4:18 in the next.

The one subtle field is `fired`. It is set to that instant on every alarm that
is switched on, and it has to be: the app rings an alarm whose most recent
occurrence has not been rung yet, and pinning the clock to ten in the morning
would otherwise put this morning's six-forty in the past and unrung. A
screenshot run would then open on a ringing screen, correctly, and photograph
the wrong thing. `fired` is what the app itself would have written by ten
o'clock, so this is the fixture saying the morning already happened.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

# hour, minute, label, days (0 Sunday), on
ALARMS = [
    (6, 40, "Work", [1, 2, 3, 4, 5], True),
    (7, 30, "Swim", [2, 4], True),
    (13, 0, "Pills", [0, 1, 2, 3, 4, 5, 6], True),
    (22, 30, "Wind down", [0, 1, 2, 3, 4, 5, 6], False),
]

# Marks on the elapsed time, in milliseconds, and where the watch has got to.
# The first lap is the quickest and the third the slowest, so that the best and
# worst marks in the list have something to point at.
LAPS = [58_400, 117_200, 179_900]
ELAPSED = 221_600

TIMER_TOTAL = 5 * 60 * 1000
TIMER_LEFT = 3 * 60 * 1000 + 22 * 1000


def main() -> None:
    directory = Path(os.environ.get("MOARCHY_CLOCK_DIR")
                     or Path.home() / ".local/share/moarchy-clock")
    directory.mkdir(parents=True, exist_ok=True)
    now = int(os.environ.get("MOARCHY_CLOCK_NOW") or time.time()) * 1000

    alarms = []
    for index, (hour, minute, label, days, on) in enumerate(ALARMS):
        row = {
            "id": f"demo-{index + 1}",
            "hour": hour,
            "minute": minute,
            "label": label,
            "days": days,
            "enabled": on,
        }
        if on:
            row["fired"] = now
        alarms.append(row)

    (directory / "clock.json").write_text(json.dumps({
        "schema": 1,
        "alarms": alarms,
        "stopwatch": {
            "running": True,
            "since": now - ELAPSED,
            "accrued": 0,
            "laps": LAPS,
        },
        "timer": {
            "running": True,
            "total": TIMER_TOTAL,
            "endsAt": now + TIMER_LEFT,
            "left": TIMER_LEFT,
        },
        # Written rather than left to the locale, so that a picture taken on a
        # machine set to American English is the same picture.
        "settings": {"hour24": True, "silent": False},
    }, indent=1) + "\n", encoding="utf-8")

    print(f"wrote {directory}/clock.json")


if __name__ == "__main__":
    main()

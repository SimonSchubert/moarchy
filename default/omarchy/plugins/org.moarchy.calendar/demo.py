#!/usr/bin/env python3
"""A fortnight of a life, where the app reads it.

A calendar with nothing in it is a grid of numbers, and every screen here --
the dots under a date, the day's list, the agenda, the row being edited -- is
only itself once something is on it. The GTK apps solve that with a `demo.py`
that writes their store by hand and a harness that runs it before it
photographs anything; this is that file for a plugin rather than an app, same
idea and same place on the disk.

    MOARCHY_CALENDAR_DIR=/tmp/c plugins/org.moarchy.calendar/demo.py
    MOARCHY_CALENDAR_DIR=/tmp/c MOARCHY_CALENDAR_TODAY=2026-09-15 \\
        plugins/org.moarchy.calendar/run-local.sh

Everything is dated from `MOARCHY_CALENDAR_TODAY`, the same variable the app
reads its day from, so the two halves agree about what today is. Without it a
fixture written before midnight and photographed after it would put the
dentist on yesterday.

The dates are offsets and not literals for the same reason the habit fixture's
are: run on any day, this is still a Tuesday with three things on it, a bin day
on Thursday, and a birthday in December that the agenda has to look nearly a
year ahead to find.
"""

from __future__ import annotations

import datetime
import json
import os
from pathlib import Path

# days from today, title, where, start, end, all day, repeat, colour
#
# The times are the ones a day actually has in it: a standing meeting first
# thing, two appointments in the middle, and an errand at the end. "Pick up the
# parcel" has no end, which is the shape of a reminder -- the app draws one
# time rather than a range for it.
EVENTS = [
    (-1, "Standup", "", "09:30", "09:45", False, "weekly", "blue"),
    (-12, "Rent", "", "", "", True, "monthly", "red"),
    (2, "Bin day", "", "", "", True, "weekly", "green"),
    (0, "Dentist", "Charlottenstraße 4", "11:00", "11:45", False, "none", "orange"),
    (0, "Lunch with Ada", "Café Einstein", "13:00", "14:00", False, "none", "magenta"),
    (0, "Pick up the parcel", "", "17:30", "17:30", False, "none", "yellow"),
    (3, "Train to Hamburg", "Hbf, platform 8", "07:12", "09:04", False, "none", "brown"),
    (8, "Film club", "", "20:00", "22:30", False, "none", "magenta"),
    (15, "Quarterly review", "", "14:00", "16:00", False, "none", "orange"),
]

# A birthday is the one event that is years old and still in the next year's
# agenda, which is the whole argument for a yearly repeat being in the app
# rather than in a reminder.
BIRTHDAY = (datetime.date(1984, 12, 10), "Ada's birthday", "cyan")


def main() -> None:
    directory = Path(os.environ.get("MOARCHY_CALENDAR_DIR")
                     or Path.home() / ".local/share/moarchy-calendar")
    directory.mkdir(parents=True, exist_ok=True)

    pinned = os.environ.get("MOARCHY_CALENDAR_TODAY") or ""
    try:
        today = datetime.date.fromisoformat(pinned)
    except ValueError:
        today = datetime.date.today()

    rows = []
    for index, (offset, title, where, start, end, all_day, repeat, colour) in enumerate(EVENTS):
        day = today + datetime.timedelta(days=offset)
        # Rent is on the first of the month wherever the offset landed: an
        # event that repeats monthly on the 14th is not what anybody's rent is.
        if title == "Rent":
            day = day.replace(day=1)
        row = {
            "id": f"demo-{index + 1}",
            "title": title,
            "date": day.isoformat(),
        }
        if where:
            row["where"] = where
        if all_day:
            row["allDay"] = True
        else:
            row["start"] = start
            if end and end != start:
                row["end"] = end
        if repeat != "none":
            row["repeat"] = repeat
        row["colour"] = colour
        rows.append(row)

    born, title, colour = BIRTHDAY
    rows.append({
        "id": "demo-birthday",
        "title": title,
        "date": born.isoformat(),
        "allDay": True,
        "repeat": "yearly",
        "colour": colour,
    })

    (directory / "calendar.json").write_text(
        json.dumps({"schema": 1, "events": rows}, indent=1, ensure_ascii=False) + "\n",
        encoding="utf-8")

    print(f"wrote {directory}/calendar.json")


if __name__ == "__main__":
    main()

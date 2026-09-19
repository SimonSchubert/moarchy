#!/usr/bin/env python3
"""A call log with a week in it, and the address book it names people from.

Recents with nothing in it photographs as an empty box, and the parts of the
screen that are the point -- a missed call in red, a name where a number was,
"Yesterday" -- only exist once there are calls. So this writes calls.json in
Store.js's shape, and a contacts.json beside it in the place Contacts keeps
one, because Phone reads names from there and nowhere else.

    MOARCHY_PHONE_DIR=/tmp/p/moarchy-phone plugins/moarchy.phone/demo.py

Every number is one nobody was issued: 555 in North America, 7700 900xxx in
the UK, and Germany's 0152 range with a subscriber number made up.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

PEOPLE = [
    ("Ada Okonkwo", "+44 7700 900412"),
    ("Bike shop", "+49 30 5550311"),
    ("Carla Reyes", "+1 555 0142"),
    ("Dentist", "+49 30 5550188"),
    ("Hannah Lindqvist", "+46 70 5550119"),
    ("Jonas Weber", "+49 152 90144556"),
    ("Mum", "+44 7700 900030"),
    ("Priya Raman", "+1 555 0199"),
]

HOUR = 3600 * 1000
DAY = 24 * HOUR

# (hours ago, number as the network sent it, dir, answered, missed, seconds)
CALLS = [
    (0.4, "+447700900030", "in", False, True, 0),
    (2.2, "+4930 5550188", "out", True, False, 214),
    (5.0, "+4915290999999", "in", True, False, 48),
    (26, "+447700900412", "out", False, False, 0),
    (29, "+447700900030", "in", True, False, 1260),
    (50, "+15550142", "in", False, False, 0),
    (75, "", "in", False, True, 0),
    (100, "+46705550119", "out", True, False, 3725),
    (170, "+4930 5550311", "out", True, False, 95),
]


def main() -> None:
    directory = Path(
        os.environ.get("MOARCHY_PHONE_DIR")
        or Path.home() / ".local/share/moarchy-phone"
    )
    directory.mkdir(parents=True, exist_ok=True)
    now = int(time.time() * 1000)

    rows = []
    for index, (ago, number, direction, answered, missed, seconds) in enumerate(CALLS):
        at = now - int(ago * HOUR)
        row = {"id": "k-demo-%02d" % index, "number": number, "dir": direction, "at": at}
        if answered:
            row["answered"] = True
        if missed:
            row["missed"] = True
        if seconds:
            row["seconds"] = seconds
        rows.append(row)
    (directory / "calls.json").write_text(
        json.dumps({"schema": 1, "seen": now - DAY, "calls": rows}, indent=1))

    contacts = directory.parent / "moarchy-contacts"
    contacts.mkdir(parents=True, exist_ok=True)
    book = [{"id": "c-demo-%02d" % i, "name": n, "phone": p} for i, (n, p) in enumerate(PEOPLE)]
    (contacts / "contacts.json").write_text(json.dumps({"schema": 1, "contacts": book}, indent=1))
    print(directory / "calls.json")


if __name__ == "__main__":
    main()

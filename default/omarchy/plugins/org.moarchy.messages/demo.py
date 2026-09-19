#!/usr/bin/env python3
"""A week of texts, and the address book that names the people in them.

The conversation list is only itself with conversations in it: a name where a
number was, a bold row with a count, "Yesterday", a sender that is a word. So
this writes messages.json in Store.js's shape, and a contacts.json where
Contacts keeps one, because Messages takes names from there and nowhere else.

    MOARCHY_MESSAGES_DIR=/tmp/m/moarchy-messages plugins/org.moarchy.messages/demo.py

Every number is one nobody was issued: 555 in North America, 7700 900xxx in
the UK, Germany's 0152 range with a subscriber number made up.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

PEOPLE = [
    ("Ada Okonkwo", "+44 7700 900412"),
    ("Dentist", "+49 30 5550188"),
    ("Hannah Lindqvist", "+46 70 5550119"),
    ("Jonas Weber", "+49 152 90144556"),
    ("Mum", "+44 7700 900030"),
]

MINUTE = 60 * 1000
HOUR = 60 * MINUTE

# (hours ago, number as the network sent it, dir, text, status, read)
TEXTS = [
    (170, "+447700900412", "in", "Bouldering Thursday? New wall opened at the old tram depot", "received", True),
    (169.8, "+447700900412", "out", "Yes! 7pm?", "sent", True),
    (169.5, "+447700900412", "in", "7 works. Bring chalk, mine ran out", "received", True),
    (75, "DHL", "in", "Your parcel 00340434161094022115 will be delivered today between 13:00 and 15:00.", "received", True),
    (50, "+46705550119", "in", "Landed. Train to the city is 20 min, see you at the station", "received", True),
    (49.9, "+46705550119", "out", "On my way, 10 min", "sent", True),
    (27, "+4930 5550188", "in", "Reminder: your appointment is on Thursday at 09:30. Reply C to cancel.", "received", True),
    (3.2, "+447700900030", "in", "Are you coming on Sunday? Your aunt is bringing the good cake", "received", True),
    (3.1, "07700900030", "out", "Wouldn't miss it. What time?", "sent", True),
    (2.9, "+447700900030", "in", "Lunch is at 1. Can you pick up Grandpa on the way?", "received", True),
    (2.5, "07700900030", "out", "Sure, I'll be at his at 12:15", "failed", True),
    (0.6, "+447700900030", "in", "Also \"the good cake\" means the one with the cherries, not the lemon one", "received", False),
    (0.5, "+447700900030", "in", "Call me when you can", "received", False),
    (0.2, "+4915290144556", "in", "Keys are under the mat", "received", False),
]


def main() -> None:
    directory = Path(
        os.environ.get("MOARCHY_MESSAGES_DIR")
        or Path.home() / ".local/share/moarchy-messages"
    )
    directory.mkdir(parents=True, exist_ok=True)
    now = int(time.time() * 1000)

    rows = []
    for index, (ago, number, direction, text, status, read) in enumerate(TEXTS):
        at = now - int(ago * HOUR)
        row = {"id": "m-demo-%02d" % index, "number": number, "dir": direction,
               "text": text, "at": at, "status": status}
        if direction == "in":
            row["stamp"] = at
            row["read"] = read
        rows.append(row)
    (directory / "messages.json").write_text(
        json.dumps({"schema": 1, "messages": rows}, indent=1, ensure_ascii=False))

    contacts = directory.parent / "moarchy-contacts"
    contacts.mkdir(parents=True, exist_ok=True)
    book = [{"id": "c-demo-%02d" % i, "name": n, "phone": p} for i, (n, p) in enumerate(PEOPLE)]
    (contacts / "contacts.json").write_text(json.dumps({"schema": 1, "contacts": book}, indent=1))
    print(directory / "messages.json")


if __name__ == "__main__":
    main()

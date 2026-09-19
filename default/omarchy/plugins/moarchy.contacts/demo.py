#!/usr/bin/env python3
"""A book with people in it, where the app reads it.

An address book with nothing in it photographs as an empty screen, and every
part of this app -- the initial a name is filed under, the two lines under it,
the detail sheet -- is only itself once somebody is in the list. Contacts has
no GTK half to borrow a fixture from, which is why this one writes the JSON by
hand rather than running an app's own writer.

    MOARCHY_CONTACTS_DIR=/tmp/c plugins/moarchy.contacts/demo.py

The names are invented, and so is every number: the exchange prefixes are the
ones reserved for drama (555 in North America, 7700 900xxx in the UK, and
Germany's own 0152 range used with a number nobody was issued), so nothing here
can ring a person who exists. The schema and the one-space indent are Store.js's
`serialize()`, so the app reads this file without a special case and rewrites
it in the same shape.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

SCHEMA = 1

# A book has a shape, and the list draws it: several letters with two or three
# people under them and several with one, a few entries with everything filled
# in, some with only a number, one with only an email, and the ones filed under
# a single word -- "Dentist", "Mum" -- which are the rows a list sorted by name
# gets wrong.
PEOPLE = [
    ("Ada Okonkwo", "+44 7700 900412", "ada@okonkwo.dev", "Bouldering, Thursdays"),
    ("Alex Brenner", "+49 152 90118844", "", ""),
    ("Amira Haddad", "+44 7700 900255", "amira.haddad@example.uk", "Doctor"),
    ("Bruno Halvorsen", "+49 152 90112233", "bruno.h@posteo.de", ""),
    ("Bike shop", "+49 30 5550311", "", "Oranienstraße, closed Mondays"),
    ("Carla Reyes", "+1 555 0142", "carla.reyes@example.com", "Landlord"),
    ("Chen Wei", "", "chen.wei@example.cn", "Met at Chaos Communication"),
    ("Dentist", "+49 30 5550188", "", "Charlottenstraße 4"),
    ("Diego Santos", "+55 11 955500123", "diego@santos.example", ""),
    ("Emil Nakamura", "", "emil@nakamura.jp", ""),
    ("Fatima Zahra", "+44 7700 900871", "", "School run, alternate weeks"),
    ("Grigor Petrov", "+1 555 0177", "g.petrov@example.org", ""),
    ("Hannah Lindqvist", "+46 70 5550119", "hannah@lindqvist.se", "Sister"),
    ("Ines Moreau", "+33 6 55501234", "", ""),
    ("Jonas Weber", "+49 152 90144556", "jonas.weber@example.de", ""),
    ("Kenji Watanabe", "", "kenji@example.jp", ""),
    ("Locksmith", "+49 30 5550244", "", "24h, Kreuzberg"),
    ("Mira Solberg", "+47 40 5550166", "mira@solberg.no", ""),
    ("Mum", "+44 7700 900030", "", ""),
    ("Omar Diallo", "+221 77 5550188", "", ""),
    ("Priya Raman", "+1 555 0199", "priya@raman.example", "Standup, 09:30"),
    ("Rafael Costa", "+351 91 5550177", "rafael@costa.example", ""),
]


def main() -> None:
    directory = Path(
        os.environ.get("MOARCHY_CONTACTS_DIR")
        or Path.home() / ".local/share/moarchy-contacts"
    )
    directory.mkdir(parents=True, exist_ok=True)

    rows = []
    for index, (name, phone, email, note) in enumerate(PEOPLE, start=1):
        row = {"id": "c-demo-%02d" % index, "name": name}
        if phone:
            row["phone"] = phone
        if email:
            row["email"] = email
        if note:
            row["note"] = note
        rows.append(row)

    path = directory / "contacts.json"
    path.write_text(json.dumps({"schema": SCHEMA, "contacts": rows}, indent=1))
    print(path)


if __name__ == "__main__":
    main()

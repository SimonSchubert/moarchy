#!/usr/bin/env python3
"""Files to open, and the list that remembers them, where the app reads both.

An editor with nothing in it photographs as a plus on an empty screen, and the
parts of this app worth looking at -- a row that says which folder and when, a
file in monospace with its lines wrapped, the box that says why a file is read
only -- are only themselves once there are files. So this writes five, under a
home/ of its own inside the data directory, and the state.json that lists them.

    MOARCHY_EDITOR_DIR=/tmp/e plugins/moarchy.editor/demo.py

The screenshots point MOARCHY_EDITOR_HOME at that home/, so a row reads
~/Documents rather than the scratch directory's full path. Nothing here is
written anywhere but the directory it is given.

The fourth file has a no-break space in it, pasted the way one arrives from a
web page. It is the fixture for the read-only box, and it is a real case: a
menu copied off a restaurant's site is exactly how one reaches a phone.

MOARCHY_EDITOR_EMPTY=1 writes nothing, for the first-run screen.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

SCHEMA = 1
NBSP = "\u00a0"

FILES = [
    (
        "Documents/Packing list.md",
        20 * 60,
        "# Lisbon, 3 nights\n"
        "\n"
        "- passport\n"
        "- charger, and the short cable\n"
        "- two shirts, one jumper\n"
        "- swimming things\n"
        "- the book I did not finish on the last trip\n"
        "\n"
        "Check in opens 24 h before. Seat by the window if it is still there.\n",
    ),
    (
        ".config/foot/foot.ini",
        2 * 3600,
        "# The terminal, at a size a thumb can read.\n"
        "font=monospace:size=9\n"
        "pad=6x6\n"
        "\n"
        "[scrollback]\n"
        "lines=4000\n"
        "\n"
        "[cursor]\n"
        "style=beam\n"
        "blink=yes\n",
    ),
    (
        "Documents/Letter to the landlord.txt",
        26 * 3600,
        "Dear Ms Reyes,\n"
        "\n"
        "The boiler has stopped again, the same fault as in March: the pressure "
        "drops overnight and it will not relight in the morning. Could the "
        "engineer come this week? I am in on Tuesday and Thursday after four.\n"
        "\n"
        "Thank you,\n"
        "Ada\n",
    ),
    (
        "Downloads/Menu from the web.txt",
        3 * 86400,
        f"Soup of the day{NBSP}6.50\n"
        f"Bread and butter{NBSP}3.00\n"
        f"Grilled sardines{NBSP}14.00\n",
    ),
    (
        "Documents/Ideas.txt",
        9 * 86400,
        "A shelf for the hallway, 80 cm.\n"
        "Ask about the allotment waiting list.\n",
    ),
]


def main() -> None:
    directory = Path(
        os.environ.get("MOARCHY_EDITOR_DIR")
        or Path.home() / ".local/share/moarchy-editor"
    )
    directory.mkdir(parents=True, exist_ok=True)
    if os.environ.get("MOARCHY_EDITOR_EMPTY"):
        return

    home = directory / "home"
    now = time.time()
    recent = []
    for relative, age, text in FILES:
        path = home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        recent.append({"path": str(path), "opened": round(now - age)})

    state = {"schema": SCHEMA, "wrap": True, "recent": recent}
    (directory / "state.json").write_text(json.dumps(state, indent=1) + "\n")
    print(directory / "state.json")


if __name__ == "__main__":
    main()

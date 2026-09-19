#!/usr/bin/env python3
"""A home directory to photograph, instead of whoever is running the harness.

Every other demo.py here writes the one JSON file its app reads. This app's
data *is* the filesystem, so the fixture is a small tree of real directories
and real files -- sparse ones, so a 1.4 GB video costs nothing to make and
still reports 1.4 GB to `find`.

Where it goes is `$MOARCHY_FILES_HOME`, which is the same variable the app
reads to decide what "home" is, so nothing here has to agree with the app
about a path. `$MOARCHY_FILES_NOW` is the clock both halves are pinned to:
the app reads its "Yesterday" and "Tue" against it, and the mtimes below are
set from it, so a picture taken on one day and a picture taken on another are
of the same directory.

It refuses to write anywhere it did not make, because the whole point of this
app is that it can delete things and the whole point of this file is that it
is run by a harness with a scratch directory it has just made.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

# Tuesday 15 September 2026, 14:32 UTC. A Tuesday because "Yesterday" and a
# weekday name are both wanted in the same picture, and only a midweek day has
# room for both.
NOW = float(os.environ.get("MOARCHY_FILES_NOW") or 1789482720)

HOUR = 3600
DAY = 86400

# name, bytes, how long ago it was last written
FILES: list[tuple[str, int, float]] = [
    ("Documents/Rechnungen/Strom 2026-08.pdf", 184_000, 13 * DAY),
    ("Documents/Rechnungen/Telefon 2026-08.pdf", 96_400, 13 * DAY),
    ("Documents/Bahn ticket.pdf", 241_000, 2 * DAY),
    ("Documents/notes.md", 3_100, 5 * HOUR),
    ("Downloads/postmarketOS-v24.06-pinephone.img.xz", 1_430_000_000, 3 * DAY),
    ("Downloads/quickshell-manual.pdf", 2_240_000, DAY + 2 * HOUR),
    ("Downloads/firmware.tar.gz", 18_900_000, 47 * DAY),
    ("Pictures/Camera/IMG_2.jpg", 3_120_000, 2 * HOUR),
    ("Pictures/Camera/IMG_3.jpg", 2_880_000, 2 * HOUR),
    ("Pictures/Camera/IMG_9.jpg", 3_400_000, 90 * 60),
    ("Pictures/Camera/IMG_10.jpg", 4_010_000, 80 * 60),
    ("Pictures/Camera/IMG_11.jpg", 3_960_000, 70 * 60),
    ("Pictures/Schaltplan.png", 412_000, 6 * DAY),
    ("Music/Erik Satie - Gymnopedie 1.flac", 28_400_000, 210 * DAY),
    ("Videos/Kran am Hafen.mp4", 964_000_000, 4 * DAY),
    ("todo.txt", 840, 3 * HOUR),
    (".bashrc", 1_260, 400 * DAY),
]

# The directories that are places, and stay empty ones.
DIRS = ["Desktop"]

USER_DIRS = """# This file is written by xdg-user-dirs-update
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
"""


def touch(path: Path, size: int, ago: float) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        handle.truncate(size)
    when = NOW - ago
    os.utime(path, (when, when))


def main() -> int:
    home = os.environ.get("MOARCHY_FILES_HOME") or ""
    if not home:
        print("MOARCHY_FILES_HOME is not set; refusing to guess", file=sys.stderr)
        return 1

    root = Path(home)
    # A tree this deletes and rewrites has to be one it made. Anything that
    # already holds something other than this fixture is left alone, loudly.
    marker = root / ".moarchy-files-demo"
    if root.exists() and not marker.exists() and any(root.iterdir()):
        print(f"{root} has things in it and is not a fixture; refusing",
              file=sys.stderr)
        return 1

    root.mkdir(parents=True, exist_ok=True)
    marker.write_text("A fixture written by plugins/moarchy.files/demo.py\n")

    for name in DIRS:
        (root / name).mkdir(parents=True, exist_ok=True)
    for name, size, ago in FILES:
        touch(root / name, size, ago)

    config = root / ".config"
    config.mkdir(parents=True, exist_ok=True)
    (config / "user-dirs.dirs").write_text(USER_DIRS)

    # Folders are dated last, because writing a file into one moves its own
    # mtime to now and the list shows that date under the folder's name.
    for name, ago in [("Documents", 2 * DAY), ("Documents/Rechnungen", 13 * DAY),
                      ("Downloads", DAY + 2 * HOUR), ("Pictures", 70 * 60),
                      ("Pictures/Camera", 70 * 60), ("Music", 210 * DAY),
                      ("Videos", 4 * DAY), ("Desktop", 300 * DAY),
                      (".config", 400 * DAY)]:
        when = NOW - ago
        os.utime(root / name, (when, when))

    print(f"wrote a home at {root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

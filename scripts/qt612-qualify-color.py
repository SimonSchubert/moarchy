#!/usr/bin/env python3
"""Qualify the shell's palette singleton for Qt 6.12: `Color.x` -> `Commons.Color.x`.

Qt 6.12 adds a `Color` type to QtQuick. In any QML file that imports QtQuick,
a bare `Color` now resolves to Qt's type instead of the shell's `Color`
singleton (qs.Commons), so every palette lookup returns undefined: menus render
black, text has no colour, and the log fills with
`Property 'loadColors' of object QQuickColor is not a function`.

Upstream Omarchy fixed its own tree in b83d3df0 ("Qualify shell palette
references for Qt 6.12", #14553) by importing `qs.Commons as Commons` and
writing `Commons.Color`. moarchy pins an Omarchy ref older than that and ships
its own plugins, so this applies the same mechanical change to both. Running it
on files that are already qualified changes nothing.

Usage: qt612-qualify-color.py DIR [DIR...]   (rewrites *.qml in place)
"""
import pathlib
import re
import sys

BARE = re.compile(r"(?<![\w.])Color(?=\s*\.)")
TARGET = re.compile(r"(\btarget\s*:\s*)Color\b(?!\s*\.)")
ALIAS = "import qs.Commons as Commons"


def fix(path: pathlib.Path) -> bool:
    if path.name == "Color.qml":
        return False
    src = path.read_text(encoding="utf-8")
    out = BARE.sub("Commons.Color", src)
    out = TARGET.sub(r"\1Commons.Color", out)
    if out == src:
        return False
    if ALIAS not in out:
        lines = out.split("\n")
        idx = None
        for i, line in enumerate(lines):
            if line.strip() == "import qs.Commons":
                idx = i
        if idx is None:
            for i, line in enumerate(lines):
                if re.match(r"\s*import QtQuick\s*$", line):
                    idx = i
                    break
        if idx is None:
            for i, line in enumerate(lines):
                if line.startswith("import "):
                    idx = i
                    break
        if idx is None:
            idx = -1
        lines.insert(idx + 1, ALIAS)
        out = "\n".join(lines)
    path.write_text(out, encoding="utf-8")
    return True


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    changed = 0
    for d in sys.argv[1:]:
        for p in sorted(pathlib.Path(d).rglob("*.qml")):
            if fix(p):
                changed += 1
    print(f"qt612-qualify-color: {changed} file(s) qualified")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Qualify the shell's Color singleton for Qt 6.12.

QtQuick 6.12 brings its own `Color`, which wins the lookup over the
qs.Commons singleton of the same name, so `Color.background` and friends
resolve to Qt's type and every themed surface renders black. Upstream Omarchy
fixed this by importing qs.Commons under the alias Commons and writing
`Commons.Color.`; this applies the same rewrite to a tree of QML files.
"""
import pathlib
import re
import sys

REF = re.compile(r"(?<![\w.])Color\.")
ALIAS = "import qs.Commons as Commons"


def qualify(text):
    new, n = REF.subn("Commons.Color.", text)
    if not n or ALIAS in new:
        return new, n
    lines = new.split("\n")
    imports = [i for i, l in enumerate(lines) if l.startswith("import ")]
    commons = [i for i in imports if lines[i].strip() == "import qs.Commons"]
    at = (commons or imports or [-1])[-1] + 1
    lines.insert(at, ALIAS)
    return "\n".join(lines), n


def main(roots):
    files = refs = 0
    for root in roots:
        for p in sorted(pathlib.Path(root).rglob("*.qml")):
            old = p.read_text()
            new, n = qualify(old)
            if new != old:
                p.write_text(new)
                files += 1
                refs += n
    print(f"qualified {refs} Color references in {files} files")


if __name__ == "__main__":
    main(sys.argv[1:])

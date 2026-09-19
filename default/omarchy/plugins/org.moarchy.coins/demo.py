#!/usr/bin/env python3
"""The fixture this plugin photographs, which is the GTK app's own.

Both halves read and write one directory in one format -- that is the whole
claim coins makes about being a port rather than a rewrite -- so the fixture
that fills the GTK app fills this one too. Running it rather than copying it is
what keeps the claim honest: a schema change that broke the plugin would break
these screenshots on the same run, instead of leaving a second fixture quietly
describing a file format nothing writes any more.

    MOARCHY_COINS_DIR=/tmp/coins plugins/org.moarchy.coins/demo.py
"""

from __future__ import annotations

import runpy
import sys
from pathlib import Path

GTK = Path(__file__).resolve().parents[2] / "apps" / "coins" / "demo.py"

if not GTK.is_file():
    sys.exit("no fixture at " + str(GTK))

sys.argv[0] = str(GTK)
runpy.run_path(str(GTK), run_name="__main__")

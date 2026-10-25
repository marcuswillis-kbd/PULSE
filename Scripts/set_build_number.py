#!/usr/bin/env python3
"""Set CURRENT_PROJECT_VERSION in an XcodeGen project.pbxproj."""

from __future__ import annotations

import re
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 3 or not sys.argv[1].isdigit():
        raise SystemExit("usage: set_build_number.py BUILD_NUMBER project.pbxproj")
    number = sys.argv[1]
    path = Path(sys.argv[2])
    text = path.read_text()
    updated, count = re.subn(
        r"CURRENT_PROJECT_VERSION = [^;]+;",
        f"CURRENT_PROJECT_VERSION = {number};",
        text,
    )
    if count == 0:
        raise SystemExit(f"CURRENT_PROJECT_VERSION not found in {path}")
    path.write_text(updated)
    print(f"Set CURRENT_PROJECT_VERSION = {number} in {count} place(s)")


if __name__ == "__main__":
    main()

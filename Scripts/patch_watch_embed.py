#!/usr/bin/env python3
"""Point the Watch embed phase at PlugIns and sign it on copy.

Xcode 26 installs a single-target watchOS app only from the iPhone bundle's
PlugIns directory. XcodeGen 2.45 still emits the legacy Watch directory
(dstSubfolderSpec 16). Device install then fails with:

    PULSEWatch.app is a Foundation extension and must be embedded in the
    parent app bundle's PlugIns directory

The unsigned simulator compile does not install, so this patch runs only in
the TestFlight workflow. Leaving the generated project alone keeps
pulse-ios-watch on the embed phase that already compiled.
"""

from __future__ import annotations

import sys
from pathlib import Path


WATCH_DST = 'dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";'
PLUGINS_DST = 'dstPath = "";'
LEGACY_SPEC = "dstSubfolderSpec = 16;"
PLUGINS_SPEC = "dstSubfolderSpec = 13;"
EMBED_NAME = 'name = "Embed Watch Content";'
BUILD_FILE_MARK = "/* PULSEWatch.app in Embed Watch Content */ = {"
SIGN_SETTINGS = "settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); };"


def _object_end(text: str, open_brace: int) -> int:
    depth = 0
    for index in range(open_brace, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                if end < len(text) and text[end] == ";":
                    end += 1
                return end
    raise SystemExit("Unclosed pbxproj object while patching the Watch embed")


def _object_containing(text: str, index: int) -> tuple[int, int]:
    """Return the `{...};` object that contains `index`."""
    depth = 0
    for cursor in range(index, -1, -1):
        char = text[cursor]
        if char == "}":
            depth += 1
        elif char == "{":
            if depth == 0:
                return cursor, _object_end(text, cursor)
            depth -= 1
    raise SystemExit("Watch embed entry is not inside a pbxproj object")


def patch(text: str) -> str:
    if EMBED_NAME not in text:
        raise SystemExit(
            "Generated project has no Embed Watch Content phase. "
            "The iPhone target is not embedding PULSEWatch."
        )

    open_brace, end = _object_containing(text, text.find(EMBED_NAME))
    block = text[open_brace:end]
    if WATCH_DST in block:
        block = block.replace(WATCH_DST, PLUGINS_DST, 1)
        if LEGACY_SPEC not in block:
            raise SystemExit("Embed Watch Content phase has no dstSubfolderSpec 16")
        block = block.replace(LEGACY_SPEC, PLUGINS_SPEC, 1)
    elif PLUGINS_DST not in block or PLUGINS_SPEC not in block:
        raise SystemExit(
            "Embed Watch Content phase is neither the legacy Watch folder "
            "nor PlugIns. Refusing to guess a destination."
        )
    text = text[:open_brace] + block + text[end:]

    if BUILD_FILE_MARK not in text:
        raise SystemExit("Embed Watch Content build file for PULSEWatch.app is missing")
    marker_at = text.find(BUILD_FILE_MARK)
    open_brace = marker_at + len(BUILD_FILE_MARK) - 1
    end = _object_end(text, open_brace)
    block = text[open_brace:end]
    if "isa = PBXBuildFile" not in block:
        raise SystemExit("PULSEWatch embed entry is not a PBXBuildFile")
    if "CodeSignOnCopy" not in block:
        insert_at = block.rfind("}")
        block = block[:insert_at] + SIGN_SETTINGS + " " + block[insert_at:]
    return text[:open_brace] + block + text[end:]


def main() -> None:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "PULSE.xcodeproj/project.pbxproj")
    original = path.read_text()
    updated = patch(original)
    if 'name = "Embed Watch Content";' not in updated or "dstSubfolderSpec = 13;" not in updated:
        raise SystemExit("Watch embed patch did not land in PlugIns")
    if "CodeSignOnCopy" not in updated:
        raise SystemExit("Watch embed patch did not set CodeSignOnCopy")
    path.write_text(updated)
    print(f"Embedded PULSEWatch.app in PlugIns with CodeSignOnCopy ({path})")


if __name__ == "__main__":
    main()

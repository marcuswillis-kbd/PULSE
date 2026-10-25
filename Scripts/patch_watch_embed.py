#!/usr/bin/env python3
"""Keep the Watch app in PULSE.app/Watch and sign it on copy.

altool reads every embedded APPL bundle when it decides the IPA platform.
A single-target watchOS app belongs at Watch/PULSEWatch.app:

    dstSubfolderSpec = 16
    dstPath = $(CONTENTS_FOLDER_PATH)/Watch

PlugIns is for appex extensions. An APPL bundle whose platform is WatchOS
in PlugIns makes altool fail with "Cannot determine the 'platform' from
the info.plist". XcodeGen already emits the Watch destination. This patch
puts that destination back if it was pointed at PlugIns, and sets
CodeSignOnCopy. It runs only in the TestFlight workflow.
"""

from __future__ import annotations

import sys
from pathlib import Path


WATCH_DST = 'dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";'
PLUGINS_DST = 'dstPath = "";'
WATCH_SPEC = "dstSubfolderSpec = 16;"
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
    block = block.replace(PLUGINS_DST, WATCH_DST)
    block = block.replace(PLUGINS_SPEC, WATCH_SPEC)
    if WATCH_DST not in block or WATCH_SPEC not in block:
        raise SystemExit(
            "Embed Watch Content phase is not PULSE.app/Watch "
            "(dstSubfolderSpec 16, dstPath $(CONTENTS_FOLDER_PATH)/Watch)."
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


def _assert_watch_embed(text: str) -> None:
    if EMBED_NAME not in text or WATCH_SPEC not in text or WATCH_DST not in text:
        raise SystemExit("Watch embed patch did not land in PULSE.app/Watch")
    open_brace, end = _object_containing(text, text.find(EMBED_NAME))
    block = text[open_brace:end]
    if PLUGINS_SPEC in block or PLUGINS_DST in block:
        raise SystemExit("Watch embed patch left the PlugIns destination in place")
    if "CodeSignOnCopy" not in text:
        raise SystemExit("Watch embed patch did not set CodeSignOnCopy")


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        _self_test()
        return
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "PULSE.xcodeproj/project.pbxproj")
    updated = patch(path.read_text())
    _assert_watch_embed(updated)
    path.write_text(updated)
    print(f"Embedded PULSEWatch.app in Watch with CodeSignOnCopy ({path})")


def _fixture(dst_path: str, spec: str) -> str:
    return f"""
		DEAD /* PULSEWatch.app in Embed Watch Content */ = {{
			isa = PBXBuildFile;
			fileRef = BEEF /* PULSEWatch.app */;
		}};
		FACE /* Embed Watch Content */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = {dst_path};
			dstSubfolderSpec = {spec};
			files = (
				DEAD /* PULSEWatch.app in Embed Watch Content */,
			);
			name = "Embed Watch Content";
			runOnlyForDeploymentPostprocessing = 0;
		}};
"""


def _self_test() -> None:
    for label, text in (
        ("plugins", _fixture('""', "13")),
        ("watch", _fixture('"$(CONTENTS_FOLDER_PATH)/Watch"', "16")),
    ):
        updated = patch(text)
        _assert_watch_embed(updated)
        if updated.count("CodeSignOnCopy") != 1:
            raise SystemExit(f"{label} fixture CodeSignOnCopy count is wrong")
    print("self-test ok")


if __name__ == "__main__":
    main()

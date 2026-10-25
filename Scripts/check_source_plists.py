#!/usr/bin/env python3
"""Fail if XcodeGen will not compile the hand-written Info.plists.

An `info:` block makes XcodeGen replace that path on every generate with a
default template: bundle id, name, versions 1.0 and 1, and package type.
CI generates the project before archiving, so the template is what Xcode
compiles. Xcode then injects platform, SDK, deployment, and device-family
keys. It does not invent WKApplication or WKCompanionAppBundleIdentifier.
"""

from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PHONE_PLIST = "Phone/Info.plist"
WATCH_PLIST = "Watch/Info.plist"
PHONE_ID = "com.pulsebreath.local.PULSE"


def fail(messages: list[str]) -> None:
    print("Info.plist source check failed:", file=sys.stderr)
    for message in messages:
        print(f"- {message}", file=sys.stderr)
    raise SystemExit(1)


def load_plist(relative: str) -> dict:
    path = ROOT / relative
    with path.open("rb") as handle:
        data = plistlib.load(handle)
    if not isinstance(data, dict):
        raise SystemExit(f"{relative} is not a dictionary")
    return data


def require(errors: list[str], ok: bool, message: str) -> None:
    if not ok:
        errors.append(message)


def _without_comment(line: str) -> str:
    quote = ""
    for index, char in enumerate(line):
        if quote:
            if char == quote:
                quote = ""
            continue
        if char in {'"', "'"}:
            quote = char
            continue
        if char == "#":
            return line[:index]
    return line


def _indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def target_bodies(text: str) -> dict[str, list[str]]:
    """Return the lines belonging to each target in project.yml.

    This is the subset of YAML this file uses: a `targets:` mapping whose
    children are the target names. Comments are ignored. It is intentionally
    not a YAML parser, so the Codemagic image does not need PyYAML.
    """
    lines = [_without_comment(line).rstrip() for line in text.splitlines()]
    start = next((index for index, line in enumerate(lines) if line.strip() == "targets:"), None)
    if start is None:
        return {}
    child_indent = None
    for line in lines[start + 1 :]:
        if not line.strip():
            continue
        if _indent(line) == 0:
            return {}
        child_indent = _indent(line)
        break
    if child_indent is None:
        return {}

    bodies: dict[str, list[str]] = {}
    current = ""
    buffer: list[str] = []
    for line in lines[start + 1 :]:
        if not line.strip():
            if current:
                buffer.append("")
            continue
        indent = _indent(line)
        if indent < child_indent or (indent == 0):
            break
        stripped = line.strip()
        if indent == child_indent and stripped.endswith(":") and not stripped.startswith("-"):
            if current:
                bodies[current] = buffer
            current = stripped[:-1].strip().strip("\"'")
            buffer = []
            continue
        if current:
            buffer.append(line)
    if current:
        bodies[current] = buffer
    return bodies


def _direct_keys(body: list[str]) -> list[tuple[str, str]]:
    indents = [_indent(line) for line in body if line.strip()]
    if not indents:
        return []
    direct = min(indents)
    keys: list[tuple[str, str]] = []
    for line in body:
        if not line.strip() or _indent(line) != direct:
            continue
        stripped = line.strip()
        if stripped.startswith("-") or ":" not in stripped:
            continue
        key, _, value = stripped.partition(":")
        key = key.strip()
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
            keys.append((key, value.strip()))
    return keys


def _setting_values(body: list[str], name: str) -> list[str]:
    values = []
    for line in body:
        stripped = line.strip()
        prefix = name + ":"
        if stripped.startswith(prefix):
            values.append(stripped[len(prefix) :].strip())
    return values


def _quoted(value: str) -> str | None:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1]
    return None


def check_spec_text(errors: list[str], text: str) -> None:
    expected = {"PULSE": PHONE_PLIST, "PULSEWatch": WATCH_PLIST}
    bodies = target_bodies(text)
    for name, plist in expected.items():
        body = bodies.get(name)
        if body is None:
            errors.append(f"project.yml has no {name} target.")
            continue
        info = [value for key, value in _direct_keys(body) if key == "info"]
        if info:
            errors.append(
                f"{name} still has an info: block. xcodegen generate would "
                f"overwrite {plist}."
            )
        infolist = _setting_values(body, "INFOPLIST_FILE")
        require(
            errors,
            infolist == [plist],
            f"{name} INFOPLIST_FILE is {infolist!r}.",
        )
        generated = _setting_values(body, "GENERATE_INFOPLIST_FILE")
        require(
            errors,
            [_quoted(value) for value in generated] == ["NO"],
            f"{name} GENERATE_INFOPLIST_FILE must be the quoted string "
            f'"NO". Got {generated!r}.',
        )


def check_spec(errors: list[str]) -> None:
    check_spec_text(errors, (ROOT / "project.yml").read_text())


def check_phone(errors: list[str], info: dict) -> None:
    require(
        errors,
        info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"],
        "Phone/Info.plist CFBundleSupportedPlatforms is "
        f"{info.get('CFBundleSupportedPlatforms')!r}.",
    )
    require(
        errors,
        info.get("LSRequiresIPhoneOS") is True,
        f"Phone/Info.plist LSRequiresIPhoneOS is {info.get('LSRequiresIPhoneOS')!r}.",
    )
    require(
        errors,
        info.get("UIDeviceFamily") == [1],
        f"Phone/Info.plist UIDeviceFamily is {info.get('UIDeviceFamily')!r}.",
    )
    for key in ("NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"):
        value = info.get(key)
        require(
            errors,
            isinstance(value, str) and bool(value.strip()),
            f"Phone/Info.plist {key} is {value!r}.",
        )


def check_watch(errors: list[str], info: dict) -> None:
    require(
        errors,
        info.get("CFBundleSupportedPlatforms") == ["WatchOS"],
        "Watch/Info.plist CFBundleSupportedPlatforms is "
        f"{info.get('CFBundleSupportedPlatforms')!r}.",
    )
    require(
        errors,
        info.get("LSRequiresIPhoneOS") is False,
        "Watch/Info.plist LSRequiresIPhoneOS is "
        f"{info.get('LSRequiresIPhoneOS')!r}.",
    )
    require(
        errors,
        info.get("WKApplication") is True,
        f"Watch/Info.plist WKApplication is {info.get('WKApplication')!r}.",
    )
    require(
        errors,
        info.get("WKCompanionAppBundleIdentifier") == PHONE_ID,
        "Watch/Info.plist WKCompanionAppBundleIdentifier is "
        f"{info.get('WKCompanionAppBundleIdentifier')!r}.",
    )
    require(
        errors,
        info.get("WKRunsIndependentlyOfCompanionApp") is False,
        "Watch/Info.plist WKRunsIndependentlyOfCompanionApp is "
        f"{info.get('WKRunsIndependentlyOfCompanionApp')!r}.",
    )
    require(
        errors,
        info.get("WKBackgroundModes") == ["workout-processing"],
        "Watch/Info.plist WKBackgroundModes is "
        f"{info.get('WKBackgroundModes')!r}.",
    )
    for key in ("NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"):
        value = info.get(key)
        require(
            errors,
            isinstance(value, str) and bool(value.strip()),
            f"Watch/Info.plist {key} is {value!r}.",
        )


def check_project(errors: list[str]) -> None:
    path = ROOT / "PULSE.xcodeproj" / "project.pbxproj"
    if not path.is_file():
        print("No PULSE.xcodeproj yet; skipped the generated-project check.")
        return
    text = path.read_text()
    phone_set = re.search(r'INFOPLIST_FILE = "?Phone/Info\.plist"?;', text)
    watch_set = re.search(r'INFOPLIST_FILE = "?Watch/Info\.plist"?;', text)
    require(errors, phone_set is not None, "Generated project does not set Phone/Info.plist.")
    require(errors, watch_set is not None, "Generated project does not set Watch/Info.plist.")
    require(
        errors,
        re.search(r'GENERATE_INFOPLIST_FILE = "?YES"?;', text) is None,
        "Generated project still generates Info.plist files.",
    )
    require(
        errors,
        len(re.findall(r'GENERATE_INFOPLIST_FILE = "?NO"?;', text)) >= 2,
        "Generated project does not turn off Info.plist generation for both apps.",
    )


def _expect_error(text: str, needle: str) -> None:
    errors: list[str] = []
    check_spec_text(errors, text)
    if not any(needle in message for message in errors):
        raise SystemExit(f"expected {needle!r} in {errors!r}")


def _self_test() -> None:
    source = (ROOT / "project.yml").read_text()
    errors: list[str] = []
    check_spec_text(errors, source)
    if errors:
        fail(errors)
    commented = source.replace(
        "    # No `info:` key.",
        "    # info: path would be ignored because this line is a comment",
        1,
    )
    comment_errors: list[str] = []
    check_spec_text(comment_errors, commented)
    if comment_errors:
        fail(comment_errors)
    broken = source.replace(
        "    settings:\n",
        "    info:\n      path: Phone/Info.plist\n    settings:\n",
        1,
    )
    _expect_error(broken, "info:")
    unquoted = source.replace(
        'GENERATE_INFOPLIST_FILE: "NO"',
        "GENERATE_INFOPLIST_FILE: NO",
        1,
    )
    _expect_error(unquoted, "GENERATE_INFOPLIST_FILE")
    print("self-test ok")


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        _self_test()
        return
    errors: list[str] = []
    check_spec(errors)
    check_phone(errors, load_plist(PHONE_PLIST))
    check_watch(errors, load_plist(WATCH_PLIST))
    check_project(errors)
    if errors:
        fail(errors)
    print(
        "Phone/Info.plist and Watch/Info.plist are the files the project "
        "compiles, including WKApplication and WKCompanionAppBundleIdentifier."
    )


if __name__ == "__main__":
    main()

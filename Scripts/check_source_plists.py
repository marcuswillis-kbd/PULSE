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

import yaml


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


def check_spec(errors: list[str]) -> None:
    spec = yaml.safe_load((ROOT / "project.yml").read_text())
    expected = {"PULSE": PHONE_PLIST, "PULSEWatch": WATCH_PLIST}
    targets = spec.get("targets") or {}
    for name, plist in expected.items():
        target = targets.get(name)
        if not isinstance(target, dict):
            errors.append(f"project.yml has no {name} target.")
            continue
        if "info" in target:
            errors.append(
                f"{name} still has an info: block. xcodegen generate would "
                f"overwrite {plist}."
            )
        settings = (target.get("settings") or {}).get("base") or {}
        require(
            errors,
            settings.get("INFOPLIST_FILE") == plist,
            f"{name} INFOPLIST_FILE is {settings.get('INFOPLIST_FILE')!r}.",
        )
        require(
            errors,
            settings.get("GENERATE_INFOPLIST_FILE") == "NO",
            f"{name} GENERATE_INFOPLIST_FILE is "
            f"{settings.get('GENERATE_INFOPLIST_FILE')!r}.",
        )


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


def main() -> None:
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

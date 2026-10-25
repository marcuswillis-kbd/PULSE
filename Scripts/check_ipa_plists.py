#!/usr/bin/env python3
"""Check the IPA bundles altool uses to decide a platform.

Codemagic's publish summary reads Payload/*.app/Info.plist and can report
iPhoneOS while altool still fails with "Cannot determine the 'platform'
from the info.plist". altool also inspects the embedded watch bundle.
Both plists must name exactly one platform, as an array.
"""

from __future__ import annotations

import plistlib
import sys
from pathlib import Path


PHONE_ID = "com.pulsebreath.local.PULSE"
WATCH_ID = "com.pulsebreath.local.PULSE.watchkitapp"
PRINT_KEYS = (
    "CFBundleIdentifier",
    "CFBundlePackageType",
    "CFBundleShortVersionString",
    "CFBundleSupportedPlatforms",
    "CFBundleVersion",
    "DTPlatformName",
    "DTSDKName",
    "LSRequiresIPhoneOS",
    "MinimumOSVersion",
    "NSHealthShareUsageDescription",
    "NSHealthUpdateUsageDescription",
    "UIDeviceFamily",
    "WKApplication",
    "WKBackgroundModes",
    "WKCompanionAppBundleIdentifier",
    "WKRunsIndependentlyOfCompanionApp",
)


def load_plist(app: Path) -> dict:
    path = app / "Info.plist"
    if not path.is_file():
        raise SystemExit(f"{app} has no Info.plist")
    with path.open("rb") as handle:
        data = plistlib.load(handle)
    if not isinstance(data, dict):
        raise SystemExit(f"{path} is not a dictionary")
    return data


def print_plist(label: str, app: Path, info: dict) -> None:
    print(f"{label}: {app}")
    for key in PRINT_KEYS:
        if key in info:
            print(f"  {key}: {info[key]!r}")
        else:
            print(f"  {key}: <missing>")


def require(errors: list[str], ok: bool, message: str) -> None:
    if not ok:
        errors.append(message)


def require_usage(errors: list[str], label: str, info: dict) -> None:
    for key in ("NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"):
        value = info.get(key)
        require(
            errors,
            isinstance(value, str) and bool(value.strip()),
            f"{label} {key} is {value!r}.",
        )


def check_payload(payload: Path) -> None:
    apps = sorted(path for path in payload.rglob("*.app") if path.is_dir())
    if not apps:
        raise SystemExit(f"No .app bundles under {payload}")

    phone = payload / "PULSE.app"
    watch = phone / "Watch" / "PULSEWatch.app"
    allowed = {phone.resolve(), watch.resolve()}
    unexpected = [app for app in apps if app.resolve() not in allowed]
    print("App bundles in the IPA:")
    for app in apps:
        print(f"  {app.relative_to(payload)}")

    errors: list[str] = []
    if unexpected:
        rendered = ", ".join(str(app.relative_to(payload)) for app in unexpected)
        errors.append(
            "Unexpected app bundle(s): "
            f"{rendered}. Payload may only contain PULSE.app and "
            "PULSE.app/Watch/PULSEWatch.app."
        )
    if not phone.is_dir():
        errors.append("Payload/PULSE.app is missing.")
    if not watch.is_dir():
        errors.append("Payload/PULSE.app/Watch/PULSEWatch.app is missing.")
    if errors:
        raise SystemExit("\n".join(errors))

    phone_info = load_plist(phone)
    watch_info = load_plist(watch)
    print_plist("iPhone", phone, phone_info)
    print_plist("Watch", watch, watch_info)

    require(
        errors,
        phone_info.get("CFBundleIdentifier") == PHONE_ID,
        f"iPhone CFBundleIdentifier is {phone_info.get('CFBundleIdentifier')!r}.",
    )
    require(
        errors,
        phone_info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"],
        "iPhone CFBundleSupportedPlatforms must be the array ['iPhoneOS']. "
        f"Got {phone_info.get('CFBundleSupportedPlatforms')!r}.",
    )
    require(
        errors,
        phone_info.get("DTPlatformName") == "iphoneos",
        f"iPhone DTPlatformName is {phone_info.get('DTPlatformName')!r}.",
    )
    require(
        errors,
        phone_info.get("LSRequiresIPhoneOS") is True,
        f"iPhone LSRequiresIPhoneOS is {phone_info.get('LSRequiresIPhoneOS')!r}.",
    )
    require(
        errors,
        phone_info.get("UIDeviceFamily") == [1],
        f"iPhone UIDeviceFamily is {phone_info.get('UIDeviceFamily')!r}.",
    )
    require(
        errors,
        str(phone_info.get("MinimumOSVersion", "")).startswith("17."),
        f"iPhone MinimumOSVersion is {phone_info.get('MinimumOSVersion')!r}.",
    )
    require(
        errors,
        phone_info.get("CFBundlePackageType") == "APPL",
        f"iPhone CFBundlePackageType is {phone_info.get('CFBundlePackageType')!r}.",
    )
    require_usage(errors, "iPhone", phone_info)

    require(
        errors,
        watch_info.get("CFBundleIdentifier") == WATCH_ID,
        f"Watch CFBundleIdentifier is {watch_info.get('CFBundleIdentifier')!r}.",
    )
    require(
        errors,
        watch_info.get("CFBundleSupportedPlatforms") == ["WatchOS"],
        "Watch CFBundleSupportedPlatforms must be the array ['WatchOS']. "
        f"Got {watch_info.get('CFBundleSupportedPlatforms')!r}.",
    )
    require(
        errors,
        watch_info.get("DTPlatformName") == "watchos",
        f"Watch DTPlatformName is {watch_info.get('DTPlatformName')!r}.",
    )
    # Xcode drops LSRequiresIPhoneOS while processing a watchOS bundle.
    # Absent and false are both valid. True is not.
    require(
        errors,
        watch_info.get("LSRequiresIPhoneOS", False) is False,
        "Watch LSRequiresIPhoneOS must be absent or false. "
        f"Got {watch_info.get('LSRequiresIPhoneOS')!r}.",
    )
    require(
        errors,
        watch_info.get("UIDeviceFamily") == [4],
        f"Watch UIDeviceFamily is {watch_info.get('UIDeviceFamily')!r}.",
    )
    require(
        errors,
        str(watch_info.get("MinimumOSVersion", "")).startswith("10."),
        f"Watch MinimumOSVersion is {watch_info.get('MinimumOSVersion')!r}.",
    )
    require(
        errors,
        watch_info.get("WKApplication") is True,
        f"Watch WKApplication is {watch_info.get('WKApplication')!r}.",
    )
    require(
        errors,
        watch_info.get("WKCompanionAppBundleIdentifier") == PHONE_ID,
        "Watch WKCompanionAppBundleIdentifier is "
        f"{watch_info.get('WKCompanionAppBundleIdentifier')!r}.",
    )
    require(
        errors,
        watch_info.get("WKRunsIndependentlyOfCompanionApp") is False,
        "Watch WKRunsIndependentlyOfCompanionApp is "
        f"{watch_info.get('WKRunsIndependentlyOfCompanionApp')!r}.",
    )
    require(
        errors,
        watch_info.get("WKBackgroundModes") == ["workout-processing"],
        "Watch WKBackgroundModes is "
        f"{watch_info.get('WKBackgroundModes')!r}.",
    )
    require_usage(errors, "Watch", watch_info)
    if errors:
        print("Info.plist platform check failed:", file=sys.stderr)
        for message in errors:
            print(f"- {message}", file=sys.stderr)
        raise SystemExit(1)
    print("Info.plist platform keys are valid for the iPhone app and the Watch app.")


def _write(app: Path, payload: dict) -> None:
    app.mkdir(parents=True)
    with (app / "Info.plist").open("wb") as handle:
        plistlib.dump(payload, handle)


def _self_test() -> None:
    import tempfile

    phone = {
        "CFBundleIdentifier": PHONE_ID,
        "CFBundlePackageType": "APPL",
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "DTPlatformName": "iphoneos",
        "LSRequiresIPhoneOS": True,
        "MinimumOSVersion": "17.0",
        "NSHealthShareUsageDescription": "share",
        "NSHealthUpdateUsageDescription": "update",
        "UIDeviceFamily": [1],
    }
    watch = {
        "CFBundleIdentifier": WATCH_ID,
        "CFBundleSupportedPlatforms": ["WatchOS"],
        "DTPlatformName": "watchos",
        "LSRequiresIPhoneOS": False,
        "MinimumOSVersion": "10.0",
        "NSHealthShareUsageDescription": "share",
        "NSHealthUpdateUsageDescription": "update",
        "UIDeviceFamily": [4],
        "WKApplication": True,
        "WKBackgroundModes": ["workout-processing"],
        "WKCompanionAppBundleIdentifier": PHONE_ID,
        "WKRunsIndependentlyOfCompanionApp": False,
    }
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _write(root / "PULSE.app", phone)
        _write(root / "PULSE.app" / "Watch" / "PULSEWatch.app", watch)
        check_payload(root)
        stripped = root / "stripped"
        _write(stripped / "PULSE.app", phone)
        _write(
            stripped / "PULSE.app" / "Watch" / "PULSEWatch.app",
            {key: value for key, value in watch.items() if key != "LSRequiresIPhoneOS"},
        )
        check_payload(stripped)
        watch_requires_ios = root / "watch-requires-ios"
        _write(watch_requires_ios / "PULSE.app", phone)
        _write(
            watch_requires_ios / "PULSE.app" / "Watch" / "PULSEWatch.app",
            {**watch, "LSRequiresIPhoneOS": True},
        )
        try:
            check_payload(watch_requires_ios)
        except SystemExit as error:
            if error.code in (None, 0):
                raise SystemExit("Watch LSRequiresIPhoneOS true was accepted")
        else:
            raise SystemExit("Watch LSRequiresIPhoneOS true was accepted")
        broken = root / "broken"
        _write(broken / "PULSE.app", {**phone, "CFBundleSupportedPlatforms": "iPhoneOS"})
        _write(broken / "PULSE.app" / "Watch" / "PULSEWatch.app", watch)
        try:
            check_payload(broken)
        except SystemExit as error:
            if error.code in (None, 0):
                raise SystemExit("string CFBundleSupportedPlatforms was accepted")
        else:
            raise SystemExit("string CFBundleSupportedPlatforms was accepted")
        missing_wk = root / "missing-wk"
        _write(missing_wk / "PULSE.app", phone)
        _write(
            missing_wk / "PULSE.app" / "Watch" / "PULSEWatch.app",
            {key: value for key, value in watch.items() if key != "WKApplication"},
        )
        try:
            check_payload(missing_wk)
        except SystemExit as error:
            if error.code in (None, 0):
                raise SystemExit("missing WKApplication was accepted")
        else:
            raise SystemExit("missing WKApplication was accepted")
    print("self-test ok")


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        _self_test()
        return
    if len(sys.argv) != 2:
        raise SystemExit("usage: check_ipa_plists.py PayloadDir | --self-test")
    check_payload(Path(sys.argv[1]))


if __name__ == "__main__":
    main()

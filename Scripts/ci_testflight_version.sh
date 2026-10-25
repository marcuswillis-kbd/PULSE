#!/bin/bash
# Set CURRENT_PROJECT_VERSION above the latest TestFlight build.
# Codemagic's BUILD_NUMBER is the floor, so a missed App Store lookup
# cannot leave the exported IPA at the project.yml default of 1.
set -euo pipefail

cd "${CM_BUILD_DIR:-.}"

: "${BUNDLE_ID:?BUNDLE_ID is required}"

apple_id="${APP_STORE_APPLE_ID:-}"
if [ -z "$apple_id" ]; then
  listing="$(app-store-connect apps list \
    --bundle-id-identifier "$BUNDLE_ID" \
    --strict-match-identifier \
    --no-color || true)"
  if ! apple_id="$(printf '%s' "$listing" | python3 Scripts/asc_id.py app "$BUNDLE_ID")"; then
    echo "No App Store Connect app record for ${BUNDLE_ID}."
    echo "The existing app is \"Connected pulse\" (Apple ID 6826766285, SKU PULSE001)."
    echo "Do not create a separate app for the Watch; it is embedded."
    exit 1
  fi
fi
echo "App Store Connect Apple ID: ${apple_id}"

set +e
raw="$(app-store-connect get-latest-testflight-build-number "$apple_id" \
  --platform IOS \
  --all-versions \
  --no-color 2>/tmp/pulse-testflight-build.err)"
status=$?
set -e
echo "get-latest-testflight-build-number status ${status}"
printf '%s\n' "$raw"
if [ -s /tmp/pulse-testflight-build.err ]; then
  cat /tmp/pulse-testflight-build.err
fi

combined="${raw}
$(cat /tmp/pulse-testflight-build.err 2>/dev/null || true)"
# Drop ANSI color from the CLI log, then accept either a bare number line
# or "Found build number N". Other integers, including the Apple ID, are ignored.
plain="$(printf '%s\n' "$combined" | sed $'s/\033\\[[0-9;]*m//g')"
bare="$(printf '%s\n' "$plain" | grep -E '^[0-9]+$' | tail -n 1 || true)"
found="$(printf '%s\n' "$plain" | sed -n 's/.*[Bb]uild number \([0-9][0-9]*\).*/\1/p' | tail -n 1 || true)"
latest=""
if [ -n "$bare" ]; then
  latest="$bare"
fi
if [ -n "$found" ] && { [ -z "$latest" ] || [ "$found" -gt "$latest" ]; }; then
  latest="$found"
fi
if [ -z "$latest" ]; then
  if printf '%s' "$plain" | grep -Eqi 'did not find|no builds'; then
    latest=0
  elif [ "$status" -eq 0 ] && [ -z "$(printf '%s' "$raw" | tr -d '[:space:]')" ]; then
    latest=0
  else
    echo "Could not read the latest TestFlight build number."
    exit 1
  fi
fi

if [ -z "${BUILD_NUMBER:-}" ]; then
  echo "BUILD_NUMBER is unset. The floor is the TestFlight build only."
  cm_build=0
elif [[ "${BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
  cm_build="${BUILD_NUMBER}"
else
  echo "BUILD_NUMBER is not an integer: ${BUILD_NUMBER}"
  exit 1
fi

# Builds through 6 already used CFBundleVersion 1 and 6. Never export those again.
minimum_build=7
next="$((latest + 1))"
if [ "$cm_build" -gt "$next" ]; then
  next="$cm_build"
fi
if [ "$next" -lt "$minimum_build" ]; then
  next="$minimum_build"
fi
if [ "$next" -le "$latest" ]; then
  echo "Build number ${next} is not greater than TestFlight build ${latest}."
  exit 1
fi
echo "Next build number: ${next} (latest TestFlight build ${latest}, BUILD_NUMBER ${BUILD_NUMBER:-unset})"

for plist in Phone/Info.plist Watch/Info.plist; do
  if ! grep -q '$(CURRENT_PROJECT_VERSION)' "$plist"; then
    echo "${plist} must keep CFBundleVersion as \$(CURRENT_PROJECT_VERSION)."
    exit 1
  fi
done

python3 Scripts/set_build_number.py "$next" PULSE.xcodeproj/project.pbxproj
if [ "$next" != "1" ] && grep -q "CURRENT_PROJECT_VERSION = 1;" PULSE.xcodeproj/project.pbxproj; then
  echo "CURRENT_PROJECT_VERSION 1 is still in the Xcode project."
  exit 1
fi
grep "CURRENT_PROJECT_VERSION" PULSE.xcodeproj/project.pbxproj
printf '%s' "$next" > /tmp/pulse-build-number

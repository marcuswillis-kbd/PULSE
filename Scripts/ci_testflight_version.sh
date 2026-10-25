#!/bin/bash
# Set CURRENT_PROJECT_VERSION to one higher than the latest TestFlight build.
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
if [ -s /tmp/pulse-testflight-build.err ]; then
  cat /tmp/pulse-testflight-build.err
fi

latest="$(printf '%s\n' "$raw" | grep -E '^[0-9]+$' | tail -n 1 || true)"
if [ -z "$latest" ]; then
  combined="${raw} $(cat /tmp/pulse-testflight-build.err 2>/dev/null || true)"
  if [ "$status" -eq 0 ] || printf '%s' "$combined" | grep -Eqi 'did not find|no builds'; then
    latest=0
  else
    echo "Could not read the latest TestFlight build number."
    printf '%s\n' "$raw"
    exit 1
  fi
fi

next="$((latest + 1))"
echo "Next build number: ${next} (latest TestFlight build was ${latest})"

if ! xcrun agvtool new-version -all "$next"; then
  echo "agvtool could not update the XcodeGen project. Writing CURRENT_PROJECT_VERSION directly."
fi
if ! grep -q "CURRENT_PROJECT_VERSION = ${next};" PULSE.xcodeproj/project.pbxproj; then
  python3 Scripts/set_build_number.py "$next" PULSE.xcodeproj/project.pbxproj
fi
grep "CURRENT_PROJECT_VERSION" PULSE.xcodeproj/project.pbxproj

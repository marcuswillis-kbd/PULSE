#!/bin/bash
# Create App Store signing files for the iPhone app and the embedded Watch app.
# Uses the Codemagic "PULSE ASC" integration (APP_STORE_CONNECT_* env vars).
# distribution_type is app_store, which the CLI calls IOS_APP_STORE.
set -euo pipefail

cd "${CM_BUILD_DIR:-.}"

: "${BUNDLE_ID:?BUNDLE_ID is required}"
: "${WATCH_BUNDLE_ID:?WATCH_BUNDLE_ID is required}"
: "${DISTRIBUTION_TYPE:?DISTRIBUTION_TYPE is required}"
if [ -z "${CERTIFICATE_PRIVATE_KEY:-}" ]; then
  echo "CERTIFICATE_PRIVATE_KEY is not set."
  echo "Add it as a secret in the Codemagic variable group pulse_signing."
  echo "The README lists the exact screens. Do not commit the key."
  exit 1
fi
if [ "$DISTRIBUTION_TYPE" != "app_store" ]; then
  echo "This workflow only signs distribution_type app_store (got ${DISTRIBUTION_TYPE})."
  exit 1
fi

PROFILE_TYPE="IOS_APP_STORE"

resource_id() {
  local kind="$1"
  local identifier="$2"
  local listing="$3"
  printf '%s' "$listing" | python3 Scripts/asc_id.py "$kind" "$identifier"
}

ensure_bundle_id() {
  local identifier="$1"
  local display_name="$2"
  local listing rid
  listing="$(app-store-connect bundle-ids list \
    --bundle-id-identifier "$identifier" \
    --strict-match-identifier \
    --no-color || true)"
  if ! rid="$(resource_id bundle "$identifier" "$listing")"; then
    echo "Bundle ID ${identifier} is not registered. Creating it on platform IOS."
    app-store-connect bundle-ids create "$identifier" \
      --name "$display_name" \
      --platform IOS \
      --no-color
    listing="$(app-store-connect bundle-ids list \
      --bundle-id-identifier "$identifier" \
      --strict-match-identifier \
      --no-color)"
    rid="$(resource_id bundle "$identifier" "$listing")"
  fi
  echo "Enabling HealthKit (not Clinical Health Records) on ${identifier} (${rid})"
  if ! app-store-connect bundle-ids enable-capabilities "$rid" --capability HealthKit --no-color; then
    echo "HealthKit enable returned non-zero. Checking capabilities that are already on."
    app-store-connect bundle-ids capabilities "$rid" --no-color | tee "/tmp/pulse-caps-${rid}.txt"
    grep -q "HealthKit" "/tmp/pulse-caps-${rid}.txt"
  fi
}

ensure_bundle_id "$BUNDLE_ID" "PULSE"
ensure_bundle_id "$WATCH_BUNDLE_ID" "PULSE Watch"

keychain initialize

fetch_profile() {
  local identifier="$1"
  app-store-connect fetch-signing-files "$identifier" \
    --type "$PROFILE_TYPE" \
    --create \
    --strict-match-identifier \
    --certificate-key "@env:CERTIFICATE_PRIVATE_KEY"
}

# Parent id first so the distribution certificate exists before the Watch profile.
fetch_profile "$BUNDLE_ID"
fetch_profile "$WATCH_BUNDLE_ID"

keychain add-certificates
xcode-project use-profiles
echo "App Store profiles applied for ${BUNDLE_ID} and ${WATCH_BUNDLE_ID}"

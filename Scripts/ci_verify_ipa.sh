#!/bin/bash
# Fail the build unless the exported IPA contains a signed Watch app at
# PULSE.app/Watch, with real executables, and altool can validate it.
set -euo pipefail

cd "${CM_BUILD_DIR:-.}"

shopt -s nullglob
ipas=(build/ios/ipa/*.ipa)
ipa="${ipas[0]:-}"
if [ -z "$ipa" ]; then
  echo "No .ipa was exported."
  find build -type f \( -name '*.ipa' -o -name '*.xcarchive' \) || true
  exit 1
fi

echo "IPA: $ipa ($(du -h "$ipa" | awk '{print $1}'))"
tmp="$(mktemp -d)"
unzip -q "$ipa" -d "$tmp"
echo "Payload files:"
find "$tmp/Payload" -type f -exec ls -lh {} \;

phone=""
watch=""
plugins=""
while IFS= read -r app; do
  case "$app" in
    */PULSE.app/Watch/PULSEWatch.app) watch="$app" ;;
    */PULSE.app/PlugIns/PULSEWatch.app) plugins="$app" ;;
    */PULSE.app) phone="$app" ;;
  esac
done < <(find "$tmp/Payload" -type d -name '*.app')

print_plist() {
  local label="$1"
  local app="$2"
  echo "===== ${label} Info.plist ====="
  echo "path: ${app#"$tmp"/}/Info.plist"
  python3 -c 'import plistlib, sys; print(plistlib.dumps(plistlib.load(open(sys.argv[1], "rb"))).decode())' "$app/Info.plist"
}

if [ -n "$phone" ]; then
  print_plist "iPhone" "$phone"
fi
if [ -n "$watch" ]; then
  print_plist "Watch" "$watch"
elif [ -n "$plugins" ]; then
  print_plist "Watch" "$plugins"
fi

if [ -z "$phone" ] || [ -z "$watch" ]; then
  echo "Expected Payload/PULSE.app and Payload/PULSE.app/Watch/PULSEWatch.app."
  if [ -n "$plugins" ]; then
    echo "Found the Watch app in PlugIns. altool cannot decide the platform of an APPL WatchOS bundle there."
  fi
  find "$tmp/Payload" -type d
  exit 1
fi
echo "Watch app embedded at ${watch#"$tmp"/}"

executable_name() {
  python3 -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb"))["CFBundleExecutable"])' "$1/Info.plist"
}

require_executable() {
  local app="$1"
  local name
  name="$(executable_name "$app")"
  local bin="$app/$name"
  if [ ! -f "$bin" ]; then
    echo "Missing executable ${bin#"$tmp"/}."
    find "$app" -maxdepth 2 -print
    exit 1
  fi
  local bytes
  bytes="$(wc -c < "$bin" | tr -d ' ')"
  echo "Executable ${bin#"$tmp"/}: ${bytes} bytes"
  if [ "$bytes" -lt 4096 ]; then
    echo "Executable is too small to be a linked arm64 binary."
    exit 1
  fi
  file "$bin"
  local archs
  if ! archs="$(lipo -archs "$bin")"; then
    echo "lipo could not read architectures for $bin."
    exit 1
  fi
  echo "Architectures: $archs"
  case " $archs " in
    *" arm64 "*|*" arm64_32 "*) ;;
    *)
      echo "Expected arm64 or arm64_32, got: $archs"
      exit 1
      ;;
  esac
  codesign --verify --verbose=4 "$app"
  codesign -dv --verbose=4 "$app"
}

require_executable "$phone"
require_executable "$watch"
codesign -d --entitlements :- "$phone" 2>/dev/null | grep -q 'com.apple.developer.healthkit'
codesign -d --entitlements :- "$watch" 2>/dev/null | grep -q 'com.apple.developer.healthkit'
echo "HealthKit entitlement is present on PULSE.app and PULSEWatch.app"

bundle_version() {
  python3 -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb")).get("CFBundleVersion"))' "$1/Info.plist"
}

if [ ! -s /tmp/pulse-build-number ]; then
  echo "Missing /tmp/pulse-build-number from the version step."
  exit 1
fi
expected="$(tr -d '[:space:]' < /tmp/pulse-build-number)"
phone_version="$(bundle_version "$phone")"
watch_version="$(bundle_version "$watch")"
echo "CFBundleVersion iPhone=${phone_version} Watch=${watch_version} expected=${expected}"
if [ "$phone_version" != "$expected" ] || [ "$watch_version" != "$expected" ]; then
  echo "Exported CFBundleVersion does not match the build number written before archive."
  exit 1
fi

python3 Scripts/check_ipa_plists.py "$tmp/Payload"

# A passing plist check falls through to altool. Publish later runs
# altool --upload-app, which fails with
# "Cannot determine the 'platform' from the info.plist" before any
# server response. Validate here so that error sits under the plist dump.
echo "Validating $ipa with altool"
set +e
app-store-connect publish \
  --path "$ipa" \
  --enable-package-validation \
  --skip-package-upload \
  --no-color
status=$?
set -e
if [ "$status" -ne 0 ]; then
  echo "app-store-connect validation failed with status ${status}."
  echo "Re-running: xcrun altool --validate-app -f $(basename "$ipa") -t ios --verbose"
  key_args=()
  if [ -n "${APP_STORE_CONNECT_KEY_IDENTIFIER:-}" ] && [ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]; then
    if [ -n "${APP_STORE_CONNECT_PRIVATE_KEY:-}" ]; then
      mkdir -p "${HOME}/.private_keys"
      printf '%s\n' "$APP_STORE_CONNECT_PRIVATE_KEY" > "${HOME}/.private_keys/AuthKey_${APP_STORE_CONNECT_KEY_IDENTIFIER}.p8"
      chmod 600 "${HOME}/.private_keys/AuthKey_${APP_STORE_CONNECT_KEY_IDENTIFIER}.p8"
    fi
    key_args=(--apiKey "$APP_STORE_CONNECT_KEY_IDENTIFIER" --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID")
    echo "Verbose altool will use the App Store Connect API key from the environment."
  else
    echo "APP_STORE_CONNECT_KEY_IDENTIFIER is unset. Verbose altool will run without --apiKey."
  fi
  (
    cd "$(dirname "$ipa")"
    if [ "${#key_args[@]}" -eq 0 ]; then
      xcrun altool --validate-app -f "$(basename "$ipa")" -t ios --verbose
    else
      xcrun altool --validate-app -f "$(basename "$ipa")" -t ios --verbose "${key_args[@]}"
    fi
  ) || true
  exit "$status"
fi
echo "IPA: $ipa"

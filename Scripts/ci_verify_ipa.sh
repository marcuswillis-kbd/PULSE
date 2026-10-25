#!/bin/bash
# Fail the build unless the exported ipa contains the signed Watch app.
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

tmp="$(mktemp -d)"
unzip -q "$ipa" -d "$tmp"
watch=""
phone=""
while IFS= read -r app; do
  case "$app" in
    */PlugIns/PULSEWatch.app) watch="$app" ;;
    */PULSE.app) phone="$app" ;;
  esac
done < <(find "$tmp/Payload" -type d -name '*.app')
if [ -z "$watch" ] || [ -z "$phone" ]; then
  echo "Expected Payload/PULSE.app and Payload/PULSE.app/PlugIns/PULSEWatch.app."
  find "$tmp/Payload" -type d
  exit 1
fi
echo "Watch app embedded at ${watch#"$tmp"/}"
codesign -d --entitlements :- "$phone" 2>/dev/null | grep -q 'com.apple.developer.healthkit'
codesign -d --entitlements :- "$watch" 2>/dev/null | grep -q 'com.apple.developer.healthkit'
echo "HealthKit entitlement is present on PULSE.app and PULSEWatch.app"
echo "IPA: $ipa"

# PULSE

Native iPhone + Apple Watch breathing coach. Heart rate is read on the Watch during a temporary workout and sent to the iPhone. There is no health-data server.

Two Codemagic workflows:

- `pulse-ios-watch` — unsigned iOS Simulator compile. Use this to check that the project still builds. It does not produce an installable app.
- `pulse-testflight` — signed App Store archive with the Watch app inside the iPhone app, uploaded to TestFlight.

App Store distribution signing covers both bundle IDs:

- `com.pulsebreath.local.PULSE`
- `com.pulsebreath.local.PULSE.watchkitapp`

The Watch identifier is the companion embedded in the iPhone app. It is not a second App Store Connect app. Team ID `9XZURCB7T9`.

## Already set up

- Both bundle IDs exist, with HealthKit on and Clinical Health Records off.
- App Store Connect app **Connected pulse**, Apple ID `6826766285`, SKU `PULSE001`, bundle ID `com.pulsebreath.local.PULSE`.
- Codemagic Developer Portal integration name `PULSE ASC`. This must match `integrations.app_store_connect` in `codemagic.yaml`.
- Apple Distribution certificate in Codemagic Code signing identities, reference name `pulse_distribution` (expires 25 Oct 2027).

The Apple Distribution certificate and its private key live in Codemagic under `pulse_distribution`. No `CERTIFICATE_PRIVATE_KEY` variable is used.

App Store provisioning profiles are created in Apple Developer and imported into Codemagic Code signing identities. The workflow fetches them by reference name:

| Reference name | Bundle ID |
| --- | --- |
| `pulse_app_store` | `com.pulsebreath.local.PULSE` |
| `pulse_watch_app_store` | `com.pulsebreath.local.PULSE.watchkitapp` |

```yaml
ios_signing:
  provisioning_profiles:
    - pulse_app_store
    - pulse_watch_app_store
  certificates:
    - pulse_distribution
```

Codemagic rejects `ios_signing` when only `certificates` is set. The other legal form is `distribution_type: app_store` plus `bundle_identifier`, which also matches `com.pulsebreath.local.PULSE.*`, and that form cannot be combined with the reference-name lists. Naming both profiles is what the workflow uses, so the Watch profile is fetched directly. `xcode-project use-profiles` applies them. The Watch app stays embedded in `PULSE.app/PlugIns`.

## What is left before the build

Import both profiles into Codemagic → Code signing identities → iOS provisioning profiles, using the reference names above, each tied to `pulse_distribution`. Then start the build. These names must match `codemagic.yaml`:

- Integration: `PULSE ASC`
- Certificate reference: `pulse_distribution`
- Profile references: `pulse_app_store` and `pulse_watch_app_store`

Screen: Codemagic → Applications → PULSE → Start new build.

1. Branch: `cursor/pulse-testflight-b9f4` until this is merged, then `main`.
2. Workflow: `pulse-testflight`.
3. Start the build.

The workflow generates the Xcode project, embeds `PULSEWatch.app` in `PULSE.app/PlugIns`, fetches `pulse_distribution`, `pulse_app_store`, and `pulse_watch_app_store`, applies them with `xcode-project use-profiles`, sets the build number to one higher than the latest TestFlight build for Apple ID `6826766285`, exports an `.ipa`, checks the Watch app, HealthKit entitlement, and Info.plist companion keys are inside it, uploads to App Store Connect, and sets `submit_to_testflight: true`.

`Phone/Info.plist` and `Watch/Info.plist` are the files Xcode compiles. `project.yml` points at them with `INFOPLIST_FILE` and `GENERATE_INFOPLIST_FILE: "NO"`, and it has no XcodeGen `info:` block. `xcodegen generate` rewrites any plist named by `info.path` down to a default template, which drops `WKApplication` and `WKCompanionAppBundleIdentifier`. Leave those keys in `Watch/Info.plist`.

`submit_to_testflight` asks Apple to accept the build for beta review. Internal testers (App Store Connect users on the team, including the Account Holder) can install after processing without an external group. No beta group name is configured. If the publishing step fails because review metadata is incomplete, open TestFlight anyway: the binary is often already uploaded.

TestFlight shows the App Store Connect name **Connected pulse**. The icon label on the home screen is **PULSE**.

## Install on the iPhone and Watch

1. Install TestFlight from the App Store on the iPhone.
2. Sign in with the Apple Account that is on the developer team.
3. Install Pulse.
4. Open the Watch app on the iPhone → My Watch → Available Apps → PULSE → Install.
5. On the Watch, open PULSE, tap Start, and allow heart rate and workout access.
6. The iPhone shows BPM only after the Watch sends a reading. It shows `-- BPM` until then. That is not a placeholder measurement.

## Features

iPhone breathing pacer with adjustable inhale, hold and exhale. Apple Watch heart-rate collection using HealthKit (`HKWorkoutSession` / `HKLiveWorkoutBuilder`) and WatchConnectivity messages.

## Limitations

No continuous HRV stream. Live BPM depends on Watch sensor sampling and WatchConnectivity reachability. The breathing guide is a timer, not a measurement of breathing. No cloud storage of health data.

The iPhone target has the HealthKit entitlement because the Watch workout is part of the companion app. The iPhone code does not read HealthKit itself. The Watch discards the workout when the session stops. The iPhone app does not declare a workout background mode; `workout-processing` is only on the Watch, which is what keeps the heart-rate session running.

Placeholder icons are a dark square with a cyan ring. Replace them before any public App Store release. App Store Connect rejects an upload that has no 1024×1024 icon.

## Privacy

No third-party analytics. Health samples stay on the devices. The Watch workout is discarded at the end of the session. Export compliance is declared as using no non-exempt encryption, so TestFlight does not stop on the encryption question.

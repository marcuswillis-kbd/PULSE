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

No provisioning profiles exist yet. Do not create them by hand, and do not add a `CERTIFICATE_PRIVATE_KEY` variable. The certificate and its private key already live in Codemagic under `pulse_distribution`.

## Why profiles are created during the build

Codemagic's `ios_signing` block with `distribution_type: app_store` and `bundle_identifier` only downloads profiles that are already stored in Code signing identities. With an empty profile list, Codemagic stops the build before any script runs and reports `No matching profiles found`. A parent bundle ID would also match `com.pulsebreath.local.PULSE.watchkitapp`, but only among profiles already uploaded. That form cannot create the missing profiles.

`pulse-testflight` therefore fetches the certificate by reference name:

```yaml
ios_signing:
  certificates:
    - certificate: pulse_distribution
```

The `PULSE ASC` integration then creates one App Store profile (`IOS_APP_STORE`) for each bundle ID, tied to that distribution certificate. `xcode-project use-profiles` applies both. Later builds reuse the profiles when they are still valid for this certificate. The Watch app stays embedded in `PULSE.app/PlugIns`.

## What is left before the build

Nothing else in Apple or Codemagic, as long as these two names are unchanged:

- Integration: `PULSE ASC`
- Certificate reference: `pulse_distribution`

Screen: Codemagic → Applications → PULSE → Start new build.

1. Branch: `cursor/pulse-testflight-b9f4` until this is merged, then `main`.
2. Workflow: `pulse-testflight`.
3. Start the build.

The workflow generates the Xcode project, embeds `PULSEWatch.app` in `PULSE.app/PlugIns`, creates and applies both App Store profiles, sets the build number to one higher than the latest TestFlight build for Apple ID `6826766285`, exports an `.ipa`, checks the Watch app and HealthKit entitlement are inside it, uploads to App Store Connect, and sets `submit_to_testflight: true`.

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

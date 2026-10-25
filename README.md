# PULSE

Native iPhone + Apple Watch breathing coach. Heart rate is read on the Watch during a temporary workout and sent to the iPhone. There is no health-data server.

Two Codemagic workflows:

- `pulse-ios-watch` — unsigned iOS Simulator compile. Use this to check that the project still builds. It does not produce an installable app.
- `pulse-testflight` — signed App Store archive with the Watch app inside the iPhone app, uploaded to TestFlight.

The App Store Connect API key name in Codemagic must match this line in `codemagic.yaml`:

```yaml
integrations:
  app_store_connect: PULSE ASC
```

If the key is saved under a different name, change `PULSE ASC` there and nowhere else. Do not commit the `.p8` file, the certificate private key, or a provisioning profile.

Signing is automatic App Store distribution (`distribution_type: app_store`, CLI type `IOS_APP_STORE`) for both bundle IDs:

- `com.pulsebreath.local.PULSE`
- `com.pulsebreath.local.PULSE.watchkitapp`

The workflow creates the distribution certificate and both profiles on the build machine. It does not use an `ios_signing:` block, because that block stops the build with "No matching profiles found" before the profiles exist.

## What you still do on iPhone (and one step on a computer)

Do these in order. The computer step is only the certificate private key. An assistant can do that once.

### 1. Register both bundle IDs and turn on HealthKit

Screen: Apple Developer → Certificates, Identifiers & Profiles → Identifiers.

Open https://developer.apple.com/account/resources/identifiers/list

1. Tap the plus button, choose App IDs, then App.
2. Description: `PULSE`. Bundle ID, Explicit: `com.pulsebreath.local.PULSE`.
3. Enable **HealthKit**. Leave **Clinical Health Records** off. Register.
4. Repeat for the Watch companion. Description: `PULSE Watch`. Bundle ID, Explicit: `com.pulsebreath.local.PULSE.watchkitapp`.
5. Enable **HealthKit** on that identifier too. Leave Clinical Health Records off. Register.

The Watch identifier is not a second App Store app. It is the companion embedded in the iPhone app. The portal still lists it as an identifier. If `PULSE` already exists, only add the Watch identifier and confirm HealthKit is on for both.

The TestFlight script also tries to create a missing identifier and to enable HealthKit. Registering them here avoids an API permission failure. App Manager keys can turn capabilities on; creating identifiers sometimes requires Account Holder or Admin.

### 2. Create the App Store Connect API key

Screen: App Store Connect → Users and Access → Integrations → App Store Connect API.

Open https://appstoreconnect.apple.com/access/integrations/api

1. Open the **Team Keys** tab (not Individual Keys).
2. Tap the plus button to generate a key.
3. Name: `Codemagic PULSE`. Access: **App Manager**.
4. Generate, then download the `.p8` file. Apple allows that download once. It lands in Files. Also copy the **Issuer ID** (above the key list) and this key's **Key ID**.

### 3. Add the key in Codemagic as `PULSE ASC`

Screen: Codemagic → Team settings → Team integrations → Developer Portal.

Open https://codemagic.io/teams

1. Choose the team that owns the PULSE app.
2. Under Developer Portal, open **Manage keys**, then **Add key**.
3. App Store Connect API key name: `PULSE ASC`. This text must match `codemagic.yaml`. The rename note is at the top of this file.
4. Paste the Issuer ID and Key ID.
5. Upload the `.p8` from Files. Save.

### 4. Add the certificate private key (computer, once)

Codemagic needs an RSA key so it can create one reusable Apple Distribution certificate. This is not the `.p8` API key. Do not put it in git or in chat.

On any computer:

```bash
ssh-keygen -t rsa -b 2048 -m PEM -f ios_distribution_private_key -q -N ""
```

Screen: Codemagic → the PULSE application → Environment variables.

1. Variable name: `CERTIFICATE_PRIVATE_KEY`.
2. Paste the whole file, including `-----BEGIN RSA PRIVATE KEY-----` and `-----END RSA PRIVATE KEY-----`, with real line breaks.
3. Mark it **Secret**.
4. Group name: `pulse_signing`. Create the group if it is new.
5. Add the variable. Delete `ios_distribution_private_key` from the computer after it is saved.

`pulse_signing` is the group name in `codemagic.yaml` (`environment.groups`). Change both if you use another group name.

Apple allows three Distribution certificates on a normal developer account. Reuse this same key for later builds. A new key makes Codemagic request another certificate.

Optional, in the same group: `APP_STORE_APPLE_ID` (the numeric Apple ID from App Store Connect → the app → General → App Information). Leave it unset and the workflow looks the app up by bundle ID.

### 5. Create the App Store Connect app, if it is not there

Screen: App Store Connect → Apps.

Open https://appstoreconnect.apple.com/apps

If Pulse is already listed, open it and check the bundle ID is `com.pulsebreath.local.PULSE`. Do not add a second app for the Watch.

If it is missing, tap New App:

| Field | Value |
| --- | --- |
| Platforms | iOS |
| Name | Pulse |
| Primary language | English (Australia) |
| Bundle ID | com.pulsebreath.local.PULSE |
| SKU | PULSE001 |
| User access | Full Access |

Screenshots and a privacy policy are not required for the upload itself. They can block a later App Store review. Internal TestFlight only needs the processed build.

### 6. Run `pulse-testflight`

Screen: Codemagic → Applications → PULSE → Start new build.

1. Branch: the branch that contains this workflow (after it is merged, `main`).
2. Workflow: `pulse-testflight`.
3. Start the build.

The workflow generates the Xcode project, embeds `PULSEWatch.app` in `PULSE.app/PlugIns`, signs both bundle IDs, sets the build number to one higher than the latest TestFlight build, exports an `.ipa`, checks the Watch app and HealthKit entitlement are inside it, uploads to App Store Connect, and sets `submit_to_testflight: true`.

`submit_to_testflight` asks Apple to accept the build for beta review. Internal testers (App Store Connect users on the team, including the Account Holder) can install after processing without an external group. No beta group name is configured. If the publishing step fails because review metadata is incomplete, open TestFlight anyway: the binary is often already uploaded.

### 7. Install on the iPhone and Watch

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

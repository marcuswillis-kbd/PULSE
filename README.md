# PULSE
Native iPhone + Apple Watch breathing coach prototype.

## First test
Connect this GitHub repository to Codemagic. Choose the pulse-ios-watch workflow and run an unsigned simulator compile check. This is not a distributable app yet.

## Features
iPhone breathing pacer with adjustable inhale, hold and exhale, plus Apple Watch heart-rate collection using HealthKit and live WatchConnectivity messages.

## Limitations
No continuous HRV stream. Live BPM depends on Watch sensor sampling and WatchConnectivity reachability. Apple Developer signing, capabilities and App Store Connect configuration are needed for TestFlight. No cloud storage of health data is implemented.

## Privacy
No third-party analytics or server upload in this starter.

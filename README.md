# Gyma

A native, local-first strength training app built from scratch with Swift and SwiftUI for **iOS 26 and watchOS 26**. The iPhone and Apple Watch apps share a Swift package and communicate directly through Apple's WatchConnectivity APIs.

## Train on iPhone and Apple Watch

On iPhone, add your OpenAI API key in Settings, then check in with the GPT Luna coach. Discuss and revise a workout with ordered exercises, sets, reps, weights and rest seconds. Review and accept the plan before starting it on iPhone. Log actual weights and reps, review workout history and rest durations, restore deleted workouts, and export or restore native JSON backups in Settings.

The Watch opens the current exercise with weight and expected-rep controls. **Start Set → Finish Set → Confirm Reps → Confirm Weight → rest → Dismiss** guides each set. Reps and kilograms have separate review screens; kilograms support native Watch text entry and half-kilogram adjustments. Actual rest is tracked. Rest vibration defaults on with six full notification-haptic pulses spaced over ten seconds, stopping on Dismiss; enable Watch Silent Mode to mute system tones. Allow workout access for a native Watch workout session that keeps running with your wrist down and provides the system return-to-app icon. Only iPhone starts an accepted workout; the Watch follows it. Pending or rejected changes remain visible when action is needed.

The coach uses OpenAI's Responses API with `gpt-6-luna`. The personal API key stays in the iPhone Keychain; workout backups and Watch snapshots never contain it. See [coach setup and device checks](native/COACH.md). The Watch uses HealthKit for active workout runtime but does not save a duplicate Health workout. A body-photo journal and heart-rate tracking are not included.

## Build through GitHub Actions

Push native changes to `swift` to run **Swift iPhone + Watch build**. Native changes on `main` and pull requests also run it. Manual dispatch:

```sh
gh workflow run swift.yml --ref swift
```

The macOS 26 job uses the runner's latest stable Xcode, runs shared Swift tests, generates the project with XcodeGen, and archives the iPhone app with its embedded Watch app. Download `gyma-swift-ios-watch-<run number>` for `gyma-swift-unsigned.ipa`. Compiler/test logs and SDK versions are recorded, including on failures. The unsigned build needs no signing credentials.

Sign both bundles with compatible provisioning before installing: `com.mato.gyma` and `com.mato.gyma.watchkitapp`. If a signing tool changes the phone bundle identifier, update the Watch prefix and `WKCompanionAppBundleIdentifier` to match. Connectivity needs a physical paired iPhone and Watch for validation.

## Project structure

| Path | Responsibility |
| --- | --- |
| `native/iOS` | SwiftUI iPhone screens, authoritative store, rest notifications |
| `native/Watch` | SwiftUI Watch screens and rest notifications |
| `native/Shared` | WCSession lifecycle, snapshots, durable Watch command outbox |
| `native/GymaCore` | Foundation models, workout rules, native persistence, command validation and tests |
| `native/project.yml` | App targets, bundle relationship and schemes |
| `.github/workflows/swift.yml` | macOS tests, archive and unsigned IPA artifact |

Local development on a Mac:

```sh
brew install xcodegen
cd native
swift test --package-path GymaCore
xcodegen generate
open Gyma.xcodeproj
```

Select the same signing team for both targets. `Gyma` builds both apps; `GymaWatch` runs the companion. Edit `project.yml`; generated Xcode files are ignored. Swift 6 tooling runs in Swift 5 language mode with concurrency checking enabled.

## Connection and persistence

The phone owns workout state. The Watch persists a command before sending it and waits for confirmation before allowing another change. The phone checks its store identity, workout and revision, then atomically writes the change and receipt before acknowledging. Repeated delivery cannot log another set. Rest controls check timer identity. Restoring a native backup creates a new store identity so old Watch commands cannot change restored data.

Snapshots use `updateApplicationContext`, with `sendMessage` for prompt updates when reachable. Commands also use `transferUserInfo` for queued delivery. Activation, reachability, Watch switching and WatchConnectivity background tasks are handled. Routine snapshots contain a bounded active workout, not full history. See [Apple's WatchConnectivity APIs](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity).

Data lives in `gyma-native.json`. Unreadable files block mutations instead of being overwritten; Settings can export their original bytes. Restoring a backup first preserves existing native workout data in the app's Documents directory. This protects user workout data, not source-code backups.

The single-target Watch app uses `WKApplication` and `WKCompanionAppBundleIdentifier`. It is embedded at `Gyma.app/Watch/GymaWatch.app`, following [Apple's bundle layout](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle). CI rejects misplaced or missing Watch bundles and verifies the companion identity and build number. Physical-device installation still needs verification.

For Sideloadly, use version 0.70.1 or newer: its [changelog](https://sideloadly.io/changelog) documents preserving and re-signing bundled WatchKit apps, while older releases stripped them. Install the combined IPA on the paired iPhone, then check the iPhone's Watch app under My Watch > Available Apps. Both devices must meet the deployment targets above. A correct unsigned IPA alone does not validate the re-signing tool's Watch provisioning or guarantee installation.

Development-signed apps also require Developer Mode on the physical Watch. [Apple's documented setup](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) exposes the setting through developer pairing with Xcode. The Windows helper below can also reveal the setting through the paired iPhone. GitHub Actions cannot reach the physical devices. TestFlight avoids Developer Mode but requires Apple Developer Program membership and a separately configured signed distribution workflow.

### Windows Watch setup

Connect the paired iPhone to Windows by USB, unlock both devices, and keep them nearby. Apple's USB driver/service must be installed. From the repository root in PowerShell:

```powershell
python -m venv native/build/device-tools/venv
native/build/device-tools/venv/Scripts/python.exe -m pip install -r native/tools/requirements-device-tools.txt
native/build/device-tools/venv/Scripts/python.exe native/tools/watch_developer_mode.py --inspect
native/build/device-tools/venv/Scripts/python.exe native/tools/watch_developer_mode.py --reveal
```

Accept the Trust prompt **on the Watch**. After it confirms the reveal request, open the Watch's Settings > Privacy & Security > Developer Mode, enable it, restart, and confirm Turn On/Trust. Run `--inspect` again to verify that Developer Mode is enabled. The helper verifies the connected Watch's identity, refuses ambiguous device selections, and sends only the reveal request; it does not enable Developer Mode, restart devices, or change passcodes. Pairing records stay in the Git-ignored `native/build/device-tools/pairing/` directory. This reveal request succeeded against a physical iPhone on iOS 26.6.1 and Watch on watchOS 26.0.2; other combinations still need testing.

For Watch provisioning and direct installation on Windows, this repository builds an [unofficial iLoader 2.3.6 with Watch support](native/tools/iloader-watch/README.md), adapted from the [iLoader Watch companion project](https://github.com/Rzbck/iloader-watch-companion). The **iLoader 2.3.6 Watch build** GitHub Actions workflow produces a Windows installer with source provenance and SHA-256 hashes. It rewrites the companion identifiers together, provisions and signs the Watch separately, and installs through the paired iPhone. An ordinary installed Watch app is updated in place; only an explicitly identified placeholder is removed. Sign in inside the desktop tool, select the iPhone's USB connection, and choose the combined Gyma IPA. Free-account installation and app launch still need physical verification. Official iLoader 2.3.6 does not contain these Watch changes.

## Device checks

1. Start a phone workout; verify Watch exercises and targets.
2. Log a Watch set; confirm exactly one saved record after reconnecting/reopening both apps.
3. Disconnect, queue an action, reconnect, and confirm its pending state resolves once.
4. Change/end the phone workout while an action is pending; verify visible stale-action rejection.
5. Background both apps during rest; verify deadlines, skip/extend and notification opt-in. Warm-ups and the final target set must not start rest.
6. Restore a native backup, reinstall the phone app and switch Watches; cached state must not resurrect another store's workout.
7. Import an invalid backup or simulate unavailable storage; verify previous data remains recoverable and uncommitted Watch actions stay pending.

CI verifies compilation, core behavior and IPA packaging. Pairing, notification routing, delivery timing and device UI layout require device testing.

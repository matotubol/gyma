# Gyma

A native, local-first strength training app built from scratch with Swift and SwiftUI for **iOS 26 and watchOS 26**. The iPhone and Apple Watch apps share a Swift package and communicate directly through Apple's WatchConnectivity APIs.

## Train on iPhone and Apple Watch

On iPhone, check in before a workout, choose or create exercises, set targets, and log weight, reps, warm-up status and optional effort. Rest countdowns use persisted deadlines. Review workout history and training totals, restore deleted workouts, and export or restore native JSON backups in Settings.

The Watch app shows the active workout, targets and rest countdown. Log sets, extend/skip rest, or finish the workout from your wrist. Connection and pending-action indicators distinguish saved phone data from changes waiting to sync. Notification permission is requested only when enabling rest alerts on each device.

This first version focuses on logging and reliable phone–Watch communication. It does not yet include AI coaching, a body-photo journal, HealthKit workout recording or heart-rate tracking.

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

The single-target Watch app uses `WKApplication` and `WKCompanionAppBundleIdentifier`. Its explicit embedding destination accounts for the [XcodeGen Xcode 26 issue](https://github.com/yonaskolb/XcodeGen/issues/1613). Physical-device installation still needs verification.

## Device checks

1. Start a phone workout; verify Watch exercises and targets.
2. Log a Watch set; confirm exactly one saved record after reconnecting/reopening both apps.
3. Disconnect, queue an action, reconnect, and confirm its pending state resolves once.
4. Change/end the phone workout while an action is pending; verify visible stale-action rejection.
5. Background both apps during rest; verify deadlines, skip/extend and notification opt-in. Warm-ups and the final target set must not start rest.
6. Restore a native backup, reinstall the phone app and switch Watches; cached state must not resurrect another store's workout.
7. Import an invalid backup or simulate unavailable storage; verify previous data remains recoverable and uncommitted Watch actions stay pending.

CI verifies compilation, core behavior and IPA packaging. Pairing, notification routing, delivery timing and device UI layout require device testing.

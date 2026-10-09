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

For Watch provisioning and direct installation, the experimental [iLoader Watch companion project](https://github.com/Rzbck/iloader-watch-companion) reports a physically tested Windows path. Its pinned [iLoader build](https://github.com/Rzbck/iloader/actions/runs/34436587217) uses iLoader `70f37e9b4afc659ab44ec1944c034093f4cda416` and isideload `f7b9f3da570edd6824c29680545e710846d07df5`; select its `windows-exe` artifact. This is a community fork, not an official iLoader release. Sign in inside the desktop tool and select the combined Gyma IPA. Free-account installation of Gyma through this fork still needs physical verification. Its direct Watch installation removes an existing Watch app/placeholder before installing, so sync pending Watch actions to the phone before using it for updates.

## Device checks

1. Start a phone workout; verify Watch exercises and targets.
2. Log a Watch set; confirm exactly one saved record after reconnecting/reopening both apps.
3. Disconnect, queue an action, reconnect, and confirm its pending state resolves once.
4. Change/end the phone workout while an action is pending; verify visible stale-action rejection.
5. Background both apps during rest; verify deadlines, skip/extend and notification opt-in. Warm-ups and the final target set must not start rest.
6. Restore a native backup, reinstall the phone app and switch Watches; cached state must not resurrect another store's workout.
7. Import an invalid backup or simulate unavailable storage; verify previous data remains recoverable and uncommitted Watch actions stay pending.

CI verifies compilation, core behavior and IPA packaging. Pairing, notification routing, delivery timing and device UI layout require device testing.

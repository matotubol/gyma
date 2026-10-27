# Gyma

The native iPhone app for **gym-web**. It talks to the same Cloudflare Worker (`/api/v1`, Hono + D1) as the web client, so the browser and the phone always show the same calendar, plans, workouts and progress. There is no local database: every change is an API call and the Worker's response replaces the local copy.

Built with Swift and SwiftUI for iOS 17 and later. There is no Apple Watch app or AI coach.

## What it does

A standard iOS app: tab bar, navigation stacks with back and swipe-back, inset-grouped lists and forms, system steppers, menus, swipe actions and sheets. It follows the system light/dark setting; the tint is gym-web's green.

- **Home**: the system calendar (`UICalendarView`) with green/blue dots for training and rest days, and the selected day's plan with buttons into its workout or plan.
- **Day plan** (sheet): day type, exercises you can reorder (Edit) or swipe to delete, and a pushed screen per exercise with sets, reps and kg steppers. Each exercise shows last time, a *Same / Add* kg suggestion (double progression) and a verdict on the chosen weight. New exercises are picked from, or created in, the shared library.
- **Workout**: the day's exercises in *To Do* and *Done*. Tapping one pushes its screen: set rows (✓ done, ★ PR, a live timer on the running set), weight and reps steppers with the last-time and PR target hint, then **Start Set** / **Log Set**. While a set runs, back is hidden and the app keeps that exercise open. Finishing its last set returns to the list. Swipe a set to delete it, tap it to correct it; swipe an exercise to edit or remove it. The ⋯ menu adds exercises and finishes or reopens the workout. Records trigger a banner and haptics.
- **Progress**: pick an exercise to chart its heaviest set, most reps or volume per date (Swift Charts), with PR markers, stats and recent sessions that open that day's workout.

## Sign in

Open the app and enter the Worker's `API_TOKEN` (the same key you use for the web sign-in). It is checked against `GET /api/v1/status` and stored in the iPhone Keychain. The server defaults to `https://gym-api.matotubol.workers.dev`; change it under **Server** on the sign-in screen, for example to `http://<your-pc-ip>:8787` while running `npm run dev` in gym-web.

The app sends `Authorization: Bearer <token>` on every request. The Worker already accepts bearer requests without cookies or an `Origin` header, so gym-web needs no changes for the app.

## Build the IPA with GitHub Actions

Pushing changes under `apple/` or `tools/apple/` to `main` or `gym-web-ios` runs **Swift iPhone build** (`.github/workflows/swift.yml`). You can also start it from the Actions tab or with:

```powershell
gh workflow run swift.yml --ref gym-web-ios
```

The macOS job runs the IPA-check tests and the `GymaCore` Swift tests (API client, records, kg suggestions, calendar), generates the Xcode project with XcodeGen, archives the app without signing and verifies the IPA. Download the `gyma-ios-<run number>` artifact for `gyma-unsigned.ipa`:

```powershell
gh run download <run-id> -n gyma-ios-<run-number> -D build/apple/runs/<run-number>
```

Then sign and install it with iLoader or Sideloadly using your Apple ID. Bundle identifier: `com.mato.gyma`.

## Develop on a Mac

```bash
brew install xcodegen
xcodegen generate --spec apple/project.yml --project apple
open apple/Gyma.xcodeproj
swift test --package-path apple/Packages/GymaCore
```

Edit `apple/project.yml`; the generated Xcode project and Info.plist are ignored.

## Project structure

| Path | Contents |
| --- | --- |
| `apple/Packages/GymaCore` | API types and client (`GymAPI`), personal records and kg suggestions ported from gym-web's `records.ts`, workout progress rules, civil dates. Foundation only, tested on CI |
| `apple/iOS/App` | Entry point, root tabs, `AppModel` (sign-in, selected day, server data) |
| `apple/iOS/Features` | `SignIn`, `Home`, `Plan`, `Exercises` (library picker), `Workout`, `Progress` |
| `apple/iOS/Services` | Keychain token store, haptics |
| `apple/iOS/UI` | Semantic colours, shared form rows (value stepper, kg suggestion section), date formatting |
| `apple/Resources` | App icon, colours, privacy manifest |
| `tools/apple` | IPA verification used by CI |
| `tools/iloader` | Patched iLoader build scripts for installing from Windows |

See [the architecture](docs/ARCHITECTURE.md) for how state flows. Generated output goes under the Git-ignored `build/` directory; `.local/` keeps reusable tool caches and device pairing records.

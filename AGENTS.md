# Build preferences

- Gyma is the native iPhone client of gym-web's Cloudflare Worker API. Keep the API (and D1) as the only source of truth; do not add a local database or move business rules into the app.
- Build with the macOS GitHub Actions workflow (`.github/workflows/swift.yml`). Signing and device installation happen locally.
- Build the custom Windows iLoader locally with `tools/iloader/build-local.ps1`, reusing `.local/iloader/cache`. Do not rebuild iLoader for ordinary app changes; its GitHub workflow is a manual fallback.
- Keep the native Swift/SwiftUI implementation. There is no Watch app and no AI coach.

# Project layout

- iPhone app in `apple/iOS` (`App`, `Features/<Feature>`, `Services`, `UI`); API client and shared rules in `apple/Packages/GymaCore`.
- Edit `apple/project.yml`; generated Xcode projects and property lists are ignored.
- Generated output goes under root `build/` (`build/apple/runs/<run-number>`, `build/apple/latest`). Do not blanket-delete `.local`: it holds build caches and device pairing records.

# Rules

- Read `docs/ARCHITECTURE.md` before changing app code.
- `AppModel` is the single store; views invoke its actions and keep only presentation state.
- Mirror gym-web exactly: when an endpoint, schema or `web/src/records.ts` changes there, update `GymaCore` and its tests together.
- Core sources import Foundation only. Avoid catch-all `Models.swift`, `Helpers.swift` or `Utils.swift` files.
- Run `python -m unittest discover -s tools/apple -p 'test_*.py'` before pushing. CI compiles Swift and runs `swift test`; device behavior still needs checking on the phone.

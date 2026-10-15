# Build preferences

- Build Gyma's Swift iPhone and Watch apps with the existing macOS GitHub Actions workflow. Signing and device installation happen locally.
- Normal Swift builds run shared tests, archive both device apps, and verify the combined IPA. Run the additional Watch simulator build and launch checks only when explicitly requested, using `gh workflow run swift.yml --ref <branch> -f watch_smoke=true`.
- Build the custom Windows iLoader locally on this PC using `tools/iloader/build-local.ps1`. Reuse the local build caches in `.local/iloader/cache`. Do not rebuild iLoader for ordinary Gyma app changes.
- The iLoader GitHub Actions workflow is a manual fallback. Use it only when the user explicitly asks for a GitHub build. The initial custom 2.3.6 GitHub build was already authorized; the local-build preference applies to subsequent builds.
- Preserve the native Swift/SwiftUI implementation. Flutter was intentionally removed.

# Project layout

- Keep the sibling iPhone and Watch targets in `apple/iOS` and `apple/watchOS`. Group screens and presentation code by feature; keep app wiring in `App` and device services in `Services`.
- Keep shared workout rules and data types in `apple/Packages/GymaCore`, and Apple device synchronization in `apple/Shared/Connectivity`. The phone owns saved workout state; the Watch sends durable commands and waits for phone receipts.
- Edit `apple/project.yml`; generated Xcode projects and property lists are ignored.
- Keep development and installation scripts in `tools/apple` and `tools/iloader`, and documentation in `docs`.
- Put generated app output in root `build/apple`, iLoader installers in `build/iloader`, and reusable tools, caches, source checkouts, and device pairing state in `.local`. Never add feature-named build folders beside source code.
- Download app runs to `build/apple/runs/<run-number>` and use `build/apple/latest` for the current installable IPA. Use `build/archive` only for historical downloads worth retaining.
- Do not blanket-delete `.local`: it contains reusable build caches and device pairing records. Do not change preserved upstream source checkouts while tidying artifacts.

# Architecture and team rules

- Read `docs/ARCHITECTURE.md` before changing app code. Follow the existing feature-first structure and one-way state flow; do not introduce a competing architecture for an individual feature.
- `GymaState` and its domain extensions in `GymaCore` own durable data and workout rules. `GymaAppModel` owns the phone's single commit path: copy, mutate, validate, save, publish. Do not add another saved-state store or write state directly from a view.
- Put app feature actions in the owning `Features/<Feature>/GymaAppModel+<Feature>.swift` extension when needed. Keep transient request state with that feature; keep persistence and lifecycle wiring in `App`. Extract collaborators when they own a distinct responsibility, not just to reduce line count.
- Views own local presentation state and invoke actions. Reusable child views receive values and callbacks. Device/network/keychain/file I/O belongs in `Services` or the shared connectivity adapter. Core source imports stay limited to Foundation/CoreFoundation.
- Search existing core rules and components before adding a helper. Reuse shared business calculations from core. Keep feature presentation beside the feature; use `UI` only for components used across features. Avoid catch-all `Models.swift`, `Helpers.swift`, `Utils.swift`, or `Presentation.swift` files.
- Preserve persisted names, Codable layout, stable IDs, revision semantics, and the Watch command/receipt contract during structural refactors. Keep behavior changes separate and cover intentional rule changes with focused core tests.
- Before parallel edits, assign one writer per file or non-overlapping directory. Agree on shared APIs first; the coordinating agent owns integration. Agents must report edits and validation, and must not create alternate copies of another agent's rule, model, or service.
- Run `python tools/apple/check_architecture.py` and `python -m unittest discover -s tools/apple -p 'test_*.py'` before the normal macOS workflow. A structural check is not proof of Swift compilation or device behavior. Update this document and the architecture guide together when intentionally changing these conventions.

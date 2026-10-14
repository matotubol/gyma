# Build preferences

- Build Gyma's Swift iPhone and Watch apps with the existing macOS GitHub Actions workflow. Signing and device installation happen locally.
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

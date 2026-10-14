# Build preferences

- Build Gyma's Swift iPhone and Watch apps with the existing macOS GitHub Actions workflow. Signing and device installation happen locally.
- Build the custom Windows iLoader locally on this PC using `native/tools/iloader-watch/build-local.ps1`. Reuse the local build caches. Do not rebuild iLoader for ordinary Gyma app changes.
- The iLoader GitHub Actions workflow is a manual fallback. Use it only when the user explicitly asks for a GitHub build. The initial custom 2.3.6 GitHub build was already authorized; the local-build preference applies to subsequent builds.
- Preserve the native Swift/SwiftUI implementation. Flutter was intentionally removed.

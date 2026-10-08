# Gyma

Personal, local-only iOS 26+ fitness tracker built with Flutter. Built in the cloud with [Codemagic](https://codemagic.io) (`codemagic.yaml`).

- Push to `main` → Codemagic analyzes, tests, and builds an **unsigned** IPA (`gyma-unsigned.ipa`).
- Install it on an iPhone by re-signing with your Apple ID, e.g. via Sideloadly on Windows.
- The `ios/` folder is generated in CI by `flutter create` until it's committed to the repo.

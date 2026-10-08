# Gyma

Personal, local-only fitness tracker built with Flutter. Built in the cloud with [Codemagic](https://codemagic.io) (`codemagic.yaml`).

- Push to `main` → Codemagic analyzes, tests, and builds a release APK (signed with the debug key for sideloading).
- The `android/` folder is generated in CI by `flutter create` until it's committed to the repo.

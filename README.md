# Gyma

Personal, local-only iOS 26+ fitness tracker built with Flutter. Built in the cloud with GitHub Actions (`.github/workflows/ios.yml`).

- Push to `main` (or run the workflow manually) → analyze, test, and build an **unsigned** IPA.
- Download it: `gh run download --name gyma-ios-<run number>` or from the run's Artifacts on GitHub.
- Install it on an iPhone by re-signing with your Apple ID, e.g. via Sideloadly on Windows.
- The `ios/` folder is generated in CI by `flutter create` until it's committed to the repo.

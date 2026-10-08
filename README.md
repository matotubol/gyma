# Gyma

Personal, local-only iOS 26+ fitness tracker built with Flutter. Built in the cloud with GitHub Actions (`.github/workflows/ios.yml`).

## Workout flow

Start or resume a session from the dashboard. The workout screen shows a compact exercise list; choosing an exercise from the searchable picker opens its own logging screen immediately. Weight (kg), reps and **Log set** stay together above the scrolling set history. Tap a saved set to edit it in the same form, or return with **Done** to choose the next exercise. Sets save when logged; the last weight and reps are carried forward. Past workouts use the same editor.

Overview separates today's workout and optional soreness check-in from the selected period's activity. Higher and lower loads are presented neutrally, muscle bars show recorded sets rather than targets, and exercise history expands when needed. Both light and dark themes use consistent spacing and touch targets.

## Dashboard, recovery and corrections

Overview shows comparable increases/decreases, period totals and logged sets per primary muscle group. Trends compare the last two sessions in the chosen 7/28/84-day window at a shared rep count. These are limited observations, not causal conclusions or readiness scores.

Daily soreness is optional and works on rest days. Record None/Mild/Moderate/Severe separately for 12 muscle groups, flag unusual pain separately, and use the date picker to review or correct past days. Unrecorded muscles remain unknown. Recovery is attached to a calendar day, not a workout; correcting a workout date does not move a recovery entry.

Past workouts remain editable, including their date. Deleted workouts can be restored from **Your data**. That screen also provides JSON backup/restore and the last 100 corrections. Version 1 data migrates automatically to version 2 without inventing recovery entries. Back up your data before reinstalling the app.

## Optional AI coach — no server needed

The app calls OpenAI directly from your iPhone. Open **Settings → OpenAI API key** and paste your personal API key once. You can replace or remove it there. It is stored in device-only iOS Keychain, available while unlocked, and excluded from workout backups. No key is bundled in the IPA or passed through GitHub Actions. The local development .env is ignored by Git and never loaded by the app.

Workout tracking, soreness logs and analytics work offline. AI coaching requires internet and uses your own OpenAI API credits. The Coach tab sends data only after you tap Send: your question, up to three previous exchanges, training preferences, the last 28 days of workouts and daily recovery, exercise IDs and calculated trends. Deleted workouts and edit history are excluded. Use Preview data sent to AI to inspect the current training context. Conversation history stays in memory and can be cleared with Start a new conversation.

The integration uses the Responses API with gpt-6-luna, strict structured outputs and store: false. The app validates returned exercise IDs, evidence IDs and prescription ranges. Replies remain drafts; nothing is written into completed workouts. Drafts are marked outdated after local data changes or a new day starts. Soreness is self-reported context, not proof of growth, readiness, injury or an optimal routine. Effort, warm-up status, sleep and equipment variations are not yet recorded and these limitations are included in AI context.

### Validation

Run flutter analyze and flutter test. Tests cover recovery persistence and migration, missing versus zero soreness, corrected trends, backup validation, small-screen layout, direct OpenAI response handling, and Keychain save/replace/remove using mocked secure storage.

## iPhone build

- Push to `main` (or run the workflow manually) → analyze, test, and build an **unsigned** IPA.
- Download it: `gh run download --name gyma-ios-<run number>` or from the run's Artifacts on GitHub.
- Install it on an iPhone by re-signing with your Apple ID, e.g. via Sideloadly on Windows.
- The `ios/` folder is generated in CI by `flutter create` until it's committed to the repo.

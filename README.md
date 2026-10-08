# Gyma

Personal, local-first iOS 26+ fitness tracker built with Flutter. Build the iPhone app with GitHub Actions (`.github/workflows/ios.yml`).

## Train with a plan

**Overview → Start workout** opens a short preparation conversation. Choose your energy, work shift and available time, then optionally add sleep, how you feel, movement limitations and training that was not logged here. Ask the coach to prepare a session or start a manual workout offline.

The coach sees today's check-in, the active session, the last 28 days of completed workouts and daily soreness, plus the last recorded session and most recent exposure to each exercise from older history. A break in logging is not assumed to be a break in training. Goals, schedule, equipment, experience and preferences are editable in Coach.

Discuss the draft before starting. Accepted exercises receive targets for sets, rep range, load where supported, and rest. Targets never count as completed sets. Changed data, a changed check-in or a new day requires a refreshed draft. During a workout, the toolbar's coach action can review and apply changes to the remaining plan. Target set counts describe the entire session; applying a revision preserves every completed set.

## Log effort and learn what to do next

Weight, reps and Log set stay together above the scrolling set history. A set can also record warm-up/working status and optional effort: several more reps, one or two more, or at your limit. Effort is not carried forward to the next set. Old data keeps unknown effort and set classification.

Exercise screens show planned targets separately and allow target adjustment. Fresh targets take precedence over older suggested values. Historical loads are only reusable with recent, suitable working-set context. The 14-day historical-load cutoff is a conservative product rule, not a medical threshold.

The session review suggests a repeatable target, holding the load, adding a rep or considering the smallest available increase. These are transparent, local rules using planned work and reported effort. Pain, low energy, a long gap or missing context limits progression suggestions. Advice is never applied automatically.

## Progress you can see

Overview includes a seven-day review, workout activity, comparable load changes, and rep changes at matching weight. Marked warm-ups are excluded from these comparisons and muscle-group counts. Older unclassified sets remain explicitly identified. Muscle bars describe primary muscle groups, not growth or readiness.

The **Progress** tab offers optional dated check-ins with front/side/back photos, weight, waist and notes. Compare selected check-ins side by side. Photos are selected from the system library, resized and re-encoded to app-owned PNGs without embedded metadata. They stay on the device and are never included in AI requests. There are no appearance scores or automatic body-fat estimates.

Progress photos and measurements use a separate local store and are **not included in workout JSON backups**. Keep original photos and your own measurement record before reinstalling. The screen supports editing, deletion, missing-photo placeholders and recovery from an interrupted index save.

## Recovery, history and backups

Daily soreness remains optional and can be recorded on rest days. None/Mild/Moderate/Severe are separate from unusual pain; unrecorded muscles remain unknown. Workout dates, check-ins and sets remain editable. Deleted workouts can be restored in Settings.

Settings provides JSON backup/restore for workouts, targets, effort, session check-ins, recovery, preferences, coaching history, deleted workouts and recent corrections. Version 1 and 2 workout data migrates to version 3 without inventing missing effort, warm-up status or recovery. Invalid coaching caches cannot prevent valid workouts from loading. Backups contain personal conversations and should be stored privately.

## Optional AI coach

Settings → OpenAI API key stores your own key in device-only iOS Keychain, available while unlocked and excluded from backups. No key is bundled in the app or CI. The ignored local `.env` is never loaded by the app.

Requests happen only after Send and the data-sharing dialog. They include the question, up to 40 saved messages, training preferences and the context described above. Photos, body measurements, deleted workouts and correction history are excluded from structured training context. Previous messages can still mention earlier training; clear the conversation to remove them. Preview shared data in Coach to inspect the payload.

The integration uses the Responses API, `gpt-6-luna`, strict structured outputs and `store: false`. Exercise IDs, evidence IDs, unique exercises, set/rep ranges and rest values are validated. Coaching conversations persist locally; Clear conversation removes saved messages and the draft. Stale in-flight responses are not persisted. All logging and local progression feedback work offline; AI requires internet and your API credits.

## Validation and iPhone build

Run `flutter analyze` and `flutter test`. Tests cover migration and restoration, preparation and follow-ups, stale responses, accepted and revised plans, effort logging, progression rules, small-screen/keyboard layouts, photo persistence, path validation and Keychain handling. Native photo-library selection and real AI responses still need device testing.

Push to `main` or run the iOS workflow manually to analyze, test and build an unsigned IPA. Download the `gyma-ios-<run number>` artifact and re-sign it with your Apple ID, for example using Sideloadly on Windows. CI generates `ios/` when absent and configures Keychain and photo-library usage settings.

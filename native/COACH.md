# AI coach and guided Watch workouts

## Use the app

1. In iPhone Settings → AI coach, save your personal OpenAI API key. Gyma uses `gpt-6-luna`; the API project must have access and API billing. Keys stay in this iPhone's Keychain, excluded from JSON backups and Watch sync.
2. Open Coach and check in. Tell the coach your goals, equipment and preferences in the check-in notes or conversation. Messages, the current check-in, exercise catalog and summaries of up to six completed workouts are sent directly to OpenAI when you request a reply. Past check-in notes are excluded. API requests use `store: false`.
3. Discuss changes to the draft. Each exercise has working sets, reps, optional target kilograms, rest seconds and a reason. Gyma validates the complete plan against the exercise library before saving it. Missing loads mean you choose the load; zero means bodyweight.
4. Tap **Accept workout plan**, then **Start workout** on iPhone. Acceptance is saved separately; revising the draft requires accepting again. The Watch cannot start a workout or create a plan.
5. On Watch, tap **Start exercise**, perform the set, and log actual kilograms and reps. Rest begins after each working set except the final target set of an exercise. Tap **Start next set** when you actually resume; the elapsed rest is saved using the Watch tap time, even if delivery is delayed. Continue with **Start next exercise** when the current exercise is complete.
6. Enable Watch rest alerts at the first rest or in its settings. Gyma plays one foreground haptic at the deadline and schedules an OS notification for background use. Background delivery depends on Watch notification/Focus settings. Rest stays visible after the alert until acknowledged. Finishing early is in Watch settings; all-sets-complete shows Finish workout directly.

The phone remains the authoritative store. Watch changes are saved to a durable outbox and wait for a phone receipt before another mutation. Keep the paired iPhone available. A disconnected Watch is not an independent multi-set workout recorder.

## Validation

Shared tests cover legacy data decoding, acceptance and revisions, invalid AI plans, structured response parsing, original/actual rest durations, delayed and duplicate commands, and progress in bounded snapshots. The existing `swift.yml` workflow tests GymaCore and builds both native apps.

Device checks:

- Add/replace/remove a key. Generate a plan, request different reps/rest/exercises, accept, relaunch and start. Verify no workout appears on Watch before starting on iPhone.
- Test invalid key, unavailable network and retry; the current draft and pending message must survive without duplicate chat messages. Restoring a backup or replacing a check-in during a request must discard a stale response.
- Log one fewer rep and different kilograms on Watch. Verify the target remains visible, actual performance saves once, and the next exercise appears after the target number of working sets.
- Acknowledge rest early and late. History should show actual versus original planned seconds. Extend rest on iPhone; the original plan remains recorded.
- Test rest alerts with Watch foreground, wrist down/background, Focus enabled, and notification permission denied. Check no duplicate foreground taps on reopening or refreshing.
- Reconnect after a queued set or rest acknowledgment. Review rejection messages if the phone session changed meanwhile. Reopen older data and restore a previous-format JSON backup.

Live AI calls need a user-supplied API key. Physical pairing, haptic delivery and on-device layout require an iPhone/Watch check after signing and installing the combined IPA locally. App changes do not require rebuilding iLoader.

API references: [GPT Luna](https://developers.openai.com/api/docs/models/gpt-6-luna), [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses).

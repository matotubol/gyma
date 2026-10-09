# Paired workout synchronization

Both app targets compile `WorkoutConnectivity.swift` and link the local `GymaCore` package. Only the watch target compiles `Watch/`. Create one `WorkoutConnectivity.shared` owner in each process.

The iPhone configures `configurePhone(snapshotProvider:commandHandler:)` at app initialization. Its command handler copies the state, applies `GymaReducer`, writes the changed state **and** command receipt atomically, then assigns the published state and returns the acknowledgment. A failed write throws. The shared service serializes incoming commands, so interactive and background deliveries cannot race the transaction. `publishSnapshot()` must also run after every successful phone edit.

The watch starts its session and notification observer during app initialization, including background launches. SwiftUI's `.backgroundTask(.watchConnectivity)` keeps the delivery task open until activation, pending session content, queued delegate processing, and notification scheduling finish. Neither app needs continuous background execution for Watch Connectivity.

## Transport and recovery

- `updateApplicationContext` publishes the latest bounded workout snapshot. Reachable devices also receive a live message.
- A watch command is written atomically to its local journal before transport. `transferUserInfo` queues background delivery; `sendMessage` provides an immediate path when reachable. Both carry the same command ID.
- Only a persisted phone acknowledgment clears the outbox. Successful WCSession transfer completion alone never means the set was saved. Retry after relaunch or from the watch's Retry sync button retains the original command ID.
- One watch command can be pending at a time. This makes an offline change explicit and avoids inventing a sequence of unconfirmed revisions.
- Receipts and payload fingerprints in the phone state make duplicate delivery idempotent and reject command-ID reuse with different values.
- Store IDs identify a phone data store. Revision guards reject conflicting edits. A replacement store can restart revisions; the watch retires the old store ID and preserves an unconfirmed old command for review instead of replaying it.
- Snapshots show the first 12 exercises and latest 20 sets per exercise; the watch labels truncated data. The phone retains the complete workout. Wire data has an additional 60 KiB bound, with an 8 KiB command bound.
- Rest notifications use the phone's confirmed deadline, explicit watch permission, and one replaceable notification ID. Expired restored deadlines do not trigger immediate reminders. Notification delivery follows watchOS settings and Focus; there is no background haptic guarantee.

## Device validation

Build both targets with Xcode 26, then test on a paired iPhone and Apple Watch. Verify live phone-to-watch changes, offline queuing, force-quit/relaunch with a pending set, duplicate delivery, stale revision rejection, phone data replacement, switching paired watches, finish confirmation, rest extension/skip, expired rest restoration, and denied notification permission. Confirm that each accepted command appears exactly once in phone history and that a forced persistence error leaves the watch command pending. Apple states that Simulator does not support `transferUserInfo`, so simulator UI/build checks cannot replace paired-device transport tests.

Primary references: [WCSession lifecycle and multiple watches](https://developer.apple.com/documentation/watchconnectivity/wcsession), [background transfer delivery](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:)), [watchOS background tasks](https://developer.apple.com/documentation/watchkit/using-background-tasks), [SwiftUI Watch Connectivity task](https://developer.apple.com/documentation/swiftui/backgroundtask/watchconnectivity), and [single-target companion app configuration](https://developer.apple.com/documentation/technotes/tn3157-updating-your-watchos-project-for-swiftui-and-widgetkit).

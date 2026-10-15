# Gyma architecture

Gyma uses a feature-first SwiftUI architecture with one-way state flow. Files are grouped by the behavior they own. The iPhone owns persisted workout state; the Watch displays confirmed snapshots and submits durable commands. Both apps use the same Foundation rules in `GymaCore`.

## State and dependency flow

```text
iPhone view -> feature action / GymaAppModel.update
             -> GymaState domain mutation
             -> validate -> atomic save -> publish state
                                        -> notifications + Watch snapshot

Watch view -> local journal -> WatchConnectivity command
           -> phone reducer -> same phone commit path -> receipt
           -> confirmed Watch snapshot
```

`GymaAppModel` is the phone's sole observable coordinator for durable state. Its single commit path validates and saves a candidate state before assigning published state, notifying device services, or acknowledging a Watch command. The published durable state has a private setter; feature extensions can call the commit method. A failed save must never publish an uncommitted workout or send a success receipt.

Feature extensions on `GymaAppModel` organize application actions without introducing independent stores. Coach request tasks, generations, errors and proposals are transient feature session state. Saved conversations, plans and workouts remain in `GymaState`. Feature actions call existing services and core operations; views bind to results and dispatch actions. View-local navigation, sheets and edit drafts stay in `@State`.

`GymaState` declares its persisted fields in `State/GymaState.swift`. Aggregate validation stays beside it. Domain extensions own operations that change those fields. This preserves one serialized state and transaction boundary while giving each rule a clear home. These directories are organization inside one Swift package, not independent modules with artificial interfaces.

## Where code belongs

| Location | Owns |
| --- | --- |
| `apple/iOS/App` | Entry point, root navigation, durable-state coordinator, lifecycle and composition |
| `apple/iOS/Features/<Feature>` | Screens, child components, presentation and application actions for that feature |
| `apple/iOS/Services` | OpenAI transport, credentials and notification adapters |
| `apple/iOS/UI` | Cross-feature visual primitives, style and display formatting |
| `apple/watchOS/App` | Watch entry point and service composition |
| `apple/watchOS/Features/<Feature>` | Watch screens, local interaction state, presentation and callbacks |
| `apple/watchOS/Services` | Native workout runtime, notifications and persisted Watch edit drafts |
| `apple/watchOS/UI` | Cross-feature Watch controls and styles |
| `apple/Shared/Connectivity` | One WCSession owner per process, transport encoding, delegate bridge and durable journal I/O |
| `apple/Packages/GymaCore/Sources/GymaCore/<Domain>` | Shared models, deterministic rules and persistence format |
| `apple/Packages/GymaCore/Tests/GymaCoreTests/<Domain>` | Tests grouped by the same domain ownership |

Core domains are `State`, `Workout`, `Exercises`, `Coach`, `Program`, `Calendar`, `Progress`, `Profile`, `Connectivity` and `Persistence`. Tests may also use `Support` for shared fixtures. For example, exercise replacement belongs in `Workout`, library identity rules in `Exercises`, and calendar eligibility in `Calendar`. A caller can use another domain's operations; it must not copy their implementation.

The core package depends only on Foundation/CoreFoundation. It has no SwiftUI, UIKit, HealthKit, WatchConnectivity, networking or credential access. Its `Persistence` folder owns native backup encoding and the atomic JSON store. App services adapt platform APIs. The shared connectivity folder is compiled into both apps; it transports the core protocol and never becomes a second workout authority.

## File and API conventions

- Name files for their principal type or cohesive responsibility, such as `WorkSet.swift`, `WorkoutState.swift`, `WatchSetScreen.swift` or `GymaAppModel+Coach.swift`. Small supporting types may live with their owner.
- Split a file when it contains independently understandable responsibilities. Do not create arbitrary line-count limits or dozens of forwarding methods just to hide a large file.
- Keep feature presentation beside the feature. Move a component to `UI` only when multiple features use it. A coach message row can remain owned by Coach while a workout screen reuses it.
- Child screens receive data and callbacks when they do not need the app coordinator. Preserve a single owner for draft/selection state; extraction must not create competing copies.
- Keep setters private where possible. Cross-file core extensions may use internal helpers when aggregate validation requires them; avoid enlarging the public API solely for file organization.
- Business calculations such as set totals, volume, eligibility and target derivation belong in core. UI formatting such as titles, elapsed-time labels, colors and symbols belongs in app presentation.
- Keep asynchronous request cancellation and generation checks together with the request flow. They prevent stale responses from overwriting restored or edited data.
- Refactors preserve Codable fields, schema versions, identifiers and revision behavior. A rename of a Swift source file is safe; a rename of a persisted property requires an explicit compatibility plan.

## Working as a team, including agents

Before implementation, identify the existing owner of the behavior and search for equivalent rules or components. Agree on the smallest shared API needed. Assign one writer per file or disjoint directory; shared files belong to the coordinating agent. An agent needing another owner's change should send a focused request rather than copying code or editing that owner's file.

Each change should explain its responsibility, behavioral effect and verification. The coordinator reviews the combined result for duplicated rules, visibility changes, state ownership and build discovery. File moves and extractions should stay behavior-preserving; intentional behavior changes need separate reasoning and focused tests.

## Verification and limits

Run from the repository root:

```sh
python tools/apple/check_architecture.py
python -m unittest discover -s tools/apple -p 'test_*.py'
```

The architecture check rejects unowned source locations, catch-all filenames, platform imports in core, and direct platform I/O in feature/UI files. Its own regression tests exercise those failures. It is a structural check, not a full Swift dependency graph or duplicate-code detector; semantic duplication and state ownership still require review.

Use `.github/workflows/swift.yml` for Swift validation on macOS. A normal run executes all core tests, generates the Xcode project, archives the iPhone and embedded Watch apps, and verifies the combined IPA. Watch simulator checks remain opt-in only when explicitly requested. Do not rebuild iLoader for app refactors.

The first cleanup establishes domain folders and separates the largest mixed files, including the app model, workout screens, core models and connectivity support. Some substantial files remain cohesive coordinators or domain operations. Further extraction should follow a concrete responsibility boundary and retain the same architecture.

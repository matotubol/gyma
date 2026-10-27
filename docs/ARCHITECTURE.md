# Gyma architecture

Gyma is a native client of the gym-web API. The Cloudflare Worker owns every rule and all data in D1; the app presents it and requests documented operations, exactly like the web client. It has no local database and no business rules of its own beyond presentation calculations that gym-web's client also runs (records, kg suggestions).

## State flow

```text
View action -> AppModel (savePlan / mutateSession) -> GymAPI -> Worker /api/v1 -> D1
            <- AppModel publishes the returned plan or session <- JSON { data }
```

- `AppModel` (`apple/iOS/App`) is the single observable store: sign-in state, selected date and month, the month's calendar days, and the selected day's `WorkoutPlan` and `WorkoutSession`. A response always replaces the local copy; nothing is edited optimistically.
- Writes carry the version the client last saw (`expectedVersion` / `expectedPlanVersion`). A `409` means the data changed elsewhere (for example in the browser): the screen keeps the user's input, shows the conflict and offers a reload.
- Client-chosen IDs (`setId` for a started or logged set, `entryId` for an added exercise) are created once per attempt so a retried request cannot duplicate work, matching the web client.
- A `401` signs out and returns to the sign-in screen.
- Views keep only transient presentation state: focused exercise, typed kg/reps, open editors and drafts of the day plan until saved.

## Where code belongs

| Location | Owns |
| --- | --- |
| `GymaCore/API` | Codable mirrors of the API schemas, request bodies (explicit `null`s where the API requires them), `GymAPI` transport |
| `GymaCore/Records` | Port of gym-web `web/src/records.ts`: e1RM, PR analysis, kg plan and verdicts, celebration copy |
| `GymaCore/Sessions` | Port of `workout-progress.ts` and session queries |
| `GymaCore/Calendar` | Civil `YYYY-MM-DD` dates in the device calendar, month grids |
| `iOS/App` | Entry point, tabs, `AppModel` |
| `iOS/Features/<Feature>` | Screens and feature-local components |
| `iOS/Services` | Keychain and haptics adapters |
| `iOS/UI` | Theme (gym-web palette), components used by more than one feature, formatting |

When gym-web's API or `records.ts` changes, update the matching `GymaCore` file and its tests in the same change.

import GymaCore
import SwiftUI

@MainActor
struct WatchDraftRecoveryView: View {
    let draft: WatchSetDraft?
    let exerciseName: String?
    let reviewDraft: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "exclamationmark.circle").font(.title2).foregroundStyle(.orange)
            Text("Workout changed").font(.headline)
            if let draft {
                Text(exerciseName ?? draft.exerciseID)
                    .font(.caption).lineLimit(1)
                Text("\(draft.actualKg.formatted()) kg × \(draft.actualReps)")
                    .font(.title3.bold())
            }
            WatchWorkoutButton("Review draft", symbol: "exclamationmark.circle", action: reviewDraft)
        }
    }
}

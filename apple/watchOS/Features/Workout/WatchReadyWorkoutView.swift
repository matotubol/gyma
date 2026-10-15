import GymaCore
import SwiftUI

@MainActor
struct WatchReadyWorkoutView: View {
    let snapshot: CompanionSnapshot?
    let hasStorageError: Bool
    let canStartPlan: (String, Date) -> Bool
    let start: (WatchReadyContext) -> Void
    let refresh: () -> Void

    var body: some View {
        // Re-evaluate absolute availability and the Watch's local day even if no
        // new phone snapshot arrives at midnight or after a time-zone change.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 8) {
                if let snapshot, let plan = snapshot.readyPlan,
                   plan.isAvailable(at: context.date), Calendar.current.isDate(plan.scheduledFor, inSameDayAs: context.date) {
                    WatchWorkoutEyebrow("TODAY")
                    Text(plan.title).font(.system(size: 23, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.8)
                    WatchWorkoutButton("Start Workout", symbol: "play.fill") {
                        start(WatchReadyContext(storeID: snapshot.storeID, revision: snapshot.revision, plan: plan))
                    }
                    .disabled(!canStartPlan(plan.id, context.date) || hasStorageError)
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 36)).foregroundStyle(.mint)
                    Text("No workout ready").font(.headline)
                    Text("Save your program and training calendar in Gyma on iPhone, or accept a workout for today.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .onChange(of: Calendar.current.startOfDay(for: context.date)) { _, _ in refresh() }
        }
    }
}

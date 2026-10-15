import GymaCore
import SwiftUI

@MainActor
struct WatchRestScreen: View {
    let timer: RestTimer
    let compact: Bool
    let pausedAt: Date?
    let draft: WatchSetDraft?
    let exerciseName: String?
    let canEditPreparation: Bool
    let canDismissRest: Bool
    let chooseSetType: () -> Void
    let editValue: (WatchValueField) -> Void
    let dismissRest: () -> Void

    var body: some View {
        VStack(spacing: compact ? 3 : 5) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let date = pausedAt ?? context.date
                let remaining = Int(ceil(timer.remaining(at: date)))
                VStack(spacing: 3) {
                    WatchWorkoutEyebrow(remaining > 0 ? "REST" : "REST COMPLETE")
                    Text(remaining > 0 ? WatchRestPresentation.duration(Double(remaining)) : "Ready")
                        .font(.system(size: compact ? 39 : 44, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.mint).minimumScaleFactor(0.65).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
            if let draft {
                Text(exerciseName ?? draft.exerciseID).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 12) {
                    Button(draft.isWarmupSet ? "Warm-up" : "Working") { chooseSetType() }
                    Button("\(draft.kg.formatted()) kg") { editValue(.preparedKg) }
                    Button("\(draft.expectedReps) reps") { editValue(.expectedReps) }
                }
                .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                .disabled(!canEditPreparation)
            }
            WatchWorkoutButton("Dismiss", symbol: "play.fill", subtitle: "Start next set", action: dismissRest)
                .disabled(!canDismissRest)
        }
    }
}

enum WatchRestPresentation {
    static func duration(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, min(86400, seconds)))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

import SwiftUI
import GymaCore

struct WorkoutSummaryRow: View {
    let workout: Workout

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(workout.start, format: .dateTime.day()).font(.title2.bold())
                Text(workout.start, format: .dateTime.month(.abbreviated)).font(.caption.weight(.semibold))
            }
            .frame(width: 52, height: 58)
            .background(GymaStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(workout.title).font(.headline)
                Text("\(workout.totalSets) sets · \(workout.volume.gymaNumber) kg · \(workout.minutes()) min")
                    .font(.caption).foregroundStyle(.secondary)
                if workout.end == nil {
                    Label("In progress", systemImage: "record.circle").font(.caption).foregroundStyle(GymaStyle.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

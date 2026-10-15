import SwiftUI
import GymaCore

struct CoachCheckInSummary: View {
    let checkIn: SessionCheckIn
    var heading = "TODAY’S CHECK-IN"

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(heading).font(.caption.weight(.bold)).foregroundStyle(GymaStyle.accent)
            Text("\(checkIn.energy.label) energy · \(checkIn.timeMinutes) min · \(checkIn.shift.label) shift")
                .font(.subheadline)
            if let hours = checkIn.sleepHours {
                Text("\(hours.gymaNumber) hours of sleep").font(.caption).foregroundStyle(.secondary)
            }
            if checkIn.soreness != nil {
                let sore = Muscle.allCases.filter { checkIn.soreness(for: $0) != .none }
                Text(sore.isEmpty ? "Soreness: none" : sore.map { "\($0.label): \(checkIn.soreness(for: $0).label.lowercased())" }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !checkIn.notes.isEmpty { Text(checkIn.notes).font(.subheadline).foregroundStyle(.secondary) }
            if !checkIn.recentTrainingNote.isEmpty {
                Text("Recent training: \(checkIn.recentTrainingNote)").font(.subheadline).foregroundStyle(.secondary)
            }
            if !checkIn.painNote.isEmpty {
                Text("Limitations: \(checkIn.painNote)").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }
}

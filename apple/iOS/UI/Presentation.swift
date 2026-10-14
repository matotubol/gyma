import SwiftUI
import GymaCore

enum GymaStyle {
    static let accent = Color(red: 0.25, green: 0.62, blue: 0.42)
    static let ink = Color.primary
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let background = Color(uiColor: .systemGroupedBackground)
}

extension Double {
    var gymaNumber: String { formatted(.number.precision(.fractionLength(0...1))) }
}

extension Workout {
    var loggedSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    var liftedVolume: Double { exercises.reduce(0) { $0 + $1.sets.reduce(0) { $0 + $1.kg * Double($1.reps) } } }
    var title: String { planTitle?.isEmpty == false ? planTitle! : "Workout" }
    func minutes(at date: Date = Date()) -> Int { max(0, Int((end ?? date).timeIntervalSince(start) / 60)) }
}

extension Muscle {
    var tint: Color {
        switch self {
        case .chest: return .red
        case .back: return .blue
        case .legs: return .green
        case .shoulders: return .orange
        case .arms: return .purple
        case .core: return .teal
        }
    }
}

extension Energy {
    var symbol: String {
        switch self {
        case .great: return "flame.fill"
        case .good: return "sun.max.fill"
        case .medium: return "cloud.sun.fill"
        case .poor: return "moon.fill"
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var symbol: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !symbol.isEmpty {
                Image(systemName: symbol).foregroundStyle(GymaStyle.accent).font(.title3)
            }
            Text(value).font(.title2.bold()).monospacedDigit().minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

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
                Text("\(workout.loggedSets) sets · \(workout.liftedVolume.gymaNumber) kg · \(workout.minutes()) min")
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

struct EmptyState: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 38, weight: .light)).foregroundStyle(GymaStyle.accent)
            Text(title).font(.title3.bold())
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.bold())
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

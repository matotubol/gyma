import Foundation

/// Optional activity alongside the strength calendar. These entries are never program sessions.
public enum CalendarActivityKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case inclineWalking, stretching, abs

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .inclineWalking: return "Incline treadmill walking"
        case .stretching: return "Gentle stretching"
        case .abs: return "Abs"
        }
    }
    public var guidance: String {
        switch self {
        case .inclineWalking:
            return "Optional easy walking. Adjust the treadmill incline and pace so you can comfortably talk. Shorten or skip it when tired, especially after night shifts."
        case .stretching:
            return "Optional gentle stretching in a comfortable range. Avoid bouncing or pushing into pain; skip sore areas when needed."
        case .abs:
            return "Optional direct ab training, not a daily requirement. Leave a day between hard ab sessions, including abs in strength workouts. Keep it easy or skip it when sore, fatigued, or in pain."
        }
    }
    public var defaultDurationMinutes: Int { self == .inclineWalking ? 20 : 10 }
    public var durationRange: ClosedRange<Int> { self == .inclineWalking ? 5...120 : 5...30 }
}

/// Completion records the optional activity only; it cannot advance a strength program.
public struct CalendarActivity: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(dayOffset):\(kind.rawValue)" }
    public var dayOffset: Int
    public var kind: CalendarActivityKind
    public var durationMinutes: Int
    public var isCompleted: Bool

    public init(dayOffset: Int, kind: CalendarActivityKind, durationMinutes: Int? = nil, isCompleted: Bool = false) {
        self.dayOffset = dayOffset
        self.kind = kind
        self.durationMinutes = durationMinutes ?? kind.defaultDurationMinutes
        self.isCompleted = isCompleted
    }

    public func validate() throws {
        guard (0..<TrainingCalendarPlan.dayCount).contains(dayOffset), kind.durationRange.contains(durationMinutes) else {
            throw GymaError.invalid("Choose an activity inside this block with a duration in its supported range.")
        }
    }
}

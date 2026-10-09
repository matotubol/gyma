import Foundation

/// The Watch receives only the information needed to review readiness and start
/// an accepted plan; planning notes and coach messages remain on iPhone.
public struct ReadyWorkoutPlan: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var scheduledFor: Date
    public var availableFrom: Date
    public var expiresAt: Date
    public var energy: Energy
    public var soreness: [Muscle: Soreness]
    public var exerciseCount: Int

    public init(plan: WorkoutPlan, calendar: Calendar = .current) {
        id = plan.id; title = String(plan.title.prefix(160)); scheduledFor = plan.scheduledDate
        availableFrom = calendar.startOfDay(for: scheduledFor)
        expiresAt = calendar.date(byAdding: .day, value: 1, to: availableFrom) ?? availableFrom.addingTimeInterval(86400)
        energy = plan.checkIn.energy; soreness = plan.checkIn.allSoreness; exerciseCount = plan.exercises.count
    }
    public func isAvailable(at now: Date = Date()) -> Bool { now >= availableFrom && now < expiresAt }
    public func validate() throws {
        let supportedDates = -2_208_988_800.0...4_102_444_800.0
        guard !id.isEmpty, id.count <= 200, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 160,
              [scheduledFor, availableFrom, expiresAt].allSatisfy({ supportedDates.contains($0.timeIntervalSince1970) }),
              availableFrom <= scheduledFor, scheduledFor < expiresAt, expiresAt.timeIntervalSince(availableFrom) <= 172800,
              Set(soreness.keys) == Set(Muscle.allCases), (1...12).contains(exerciseCount) else {
            throw GymaError.invalid("The ready workout plan is invalid. Refresh from iPhone.")
        }
    }
}

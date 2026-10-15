import Foundation

/// A proposed session stays separate from workout history until explicitly accepted and started.
public struct WorkoutPlan: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var exercises: [WorkoutExercise]
    public var checkIn: SessionCheckIn
    public var createdAt: Date
    public var acceptedAt: Date?
    public var scheduledFor: Date?
    public var programID: String?
    public var programSessionID: String?
    public var programRevision: Int?
    public var scheduledDate: Date { scheduledFor ?? createdAt }
    public init(id: String = UUID().uuidString, title: String, exercises: [WorkoutExercise], checkIn: SessionCheckIn, createdAt: Date = Date(), acceptedAt: Date? = nil, scheduledFor: Date? = nil) {
        self.id = id; self.title = title; self.exercises = exercises; self.checkIn = checkIn; self.createdAt = createdAt; self.acceptedAt = acceptedAt; self.scheduledFor = scheduledFor
    }
    public func isScheduledForToday(at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.isDate(scheduledDate, inSameDayAs: now)
    }
    public func validate(catalog: [ExerciseDefinition]) throws {
        let supportedDates = -2_208_988_800.0...4_102_444_800.0
        guard !id.isEmpty, id.count <= 200, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200,
              supportedDates.contains(createdAt.timeIntervalSince1970),
              supportedDates.contains(scheduledDate.timeIntervalSince1970),
              acceptedAt.map({ supportedDates.contains($0.timeIntervalSince1970) && $0 >= createdAt }) ?? true,
              (1...12).contains(exercises.count), Set(exercises.map(\.exerciseID)).count == exercises.count else {
            throw GymaError.invalid("A workout plan needs a title and 1–12 unique exercises.")
        }
        try checkIn.validate()
        let hasProgram = programID != nil
        guard (programSessionID != nil) == hasProgram, (programRevision != nil) == hasProgram,
              programID.map({ !$0.isEmpty && $0.count <= 200 }) ?? true,
              programSessionID.map({ !$0.isEmpty && $0.count <= 200 }) ?? true,
              programRevision.map({ (1...1_000_000).contains($0) }) ?? true else {
            throw GymaError.invalid("Invalid program link in workout plan.")
        }
        let catalogIDs = Set(catalog.map(\.id))
        for exercise in exercises {
            guard catalogIDs.contains(exercise.exerciseID), exercise.sets.isEmpty, exercise.snapshotWorkingSetCount == nil,
                  exercise.skippedSetCount == 0, exercise.skippedRemainingAt == nil, let target = exercise.target else {
                throw GymaError.invalid("Every planned exercise needs a known exercise and a target, with no completed sets.")
            }
            try target.validate()
        }
    }
}

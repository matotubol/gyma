import Foundation

public struct Workout: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var start: Date
    public var end: Date?
    public var shift: Shift
    public var energy: Energy
    public var checkIn: SessionCheckIn?
    public var readiness: WorkoutReadiness?
    public var coachConversation: WorkoutCoachConversation?
    public var planTitle: String?
    public var acceptedPlanID: String?
    public var planAcceptedAt: Date?
    public var exercises: [WorkoutExercise]
    public var selectedExerciseID: String?
    public var restHistory: [CompletedRest]?
    public var programID: String?
    public var programSessionID: String?
    public var programRevision: Int?
    public init(id: String = UUID().uuidString, start: Date = Date(), end: Date? = nil, shift: Shift = .off, energy: Energy = .good, checkIn: SessionCheckIn? = nil, readiness: WorkoutReadiness? = nil, coachConversation: WorkoutCoachConversation? = nil, planTitle: String? = nil, acceptedPlanID: String? = nil, planAcceptedAt: Date? = nil, exercises: [WorkoutExercise] = [], restHistory: [CompletedRest]? = nil, programID: String? = nil, programSessionID: String? = nil, programRevision: Int? = nil) {
        self.id = id; self.start = start; self.end = end; self.shift = shift; self.energy = energy; self.checkIn = checkIn; self.readiness = readiness; self.coachConversation = coachConversation; self.planTitle = planTitle; self.acceptedPlanID = acceptedPlanID; self.planAcceptedAt = planAcceptedAt; self.exercises = exercises; self.restHistory = restHistory; self.programID = programID; self.programSessionID = programSessionID; self.programRevision = programRevision
    }
    public var isActive: Bool { end == nil }
    public var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    public var totalReps: Int { exercises.reduce(0) { $0 + $1.reps } }
    public var volume: Double { exercises.reduce(0) { $0 + $1.volume } }
    public var nextExercise: WorkoutExercise? {
        if let selectedExerciseID, let selected = exercises.first(where: { $0.exerciseID == selectedExerciseID && !$0.isTargetResolved }) {
            return selected
        }
        return exercises.first { !$0.isTargetResolved }
    }
    public func duration(at now: Date = Date()) -> TimeInterval { max(0, (end ?? now).timeIntervalSince(start)) }
    public func validate() throws {
        let supportedDates = -2_208_988_800.0...4_102_444_800.0 // 1900 through 2100; also safe for UI duration arithmetic.
        guard !id.isEmpty, id.count <= 200, supportedDates.contains(start.timeIntervalSince1970),
              end.map({ supportedDates.contains($0.timeIntervalSince1970) && $0 >= start }) ?? true,
              acceptedPlanID.map({ !$0.isEmpty && $0.count <= 200 }) ?? true,
              (acceptedPlanID == nil) == (planAcceptedAt == nil),
              planAcceptedAt.map({ supportedDates.contains($0.timeIntervalSince1970) && $0 <= start }) ?? true,
              (planTitle?.count ?? 0) <= 2000 else { throw GymaError.invalid("Invalid workout identity or duration.") }
        try checkIn?.validate()
        if programID != nil || programSessionID != nil || programRevision != nil {
            guard let programID, let programSessionID, let programRevision,
                  !programID.isEmpty, programID.count <= 200, !programSessionID.isEmpty, programSessionID.count <= 200,
                  (1...1_000_000).contains(programRevision) else { throw GymaError.invalid("Invalid program link on workout.") }
        }
        try readiness?.validate()
        if let readiness, abs(readiness.recordedAt.timeIntervalSince(start)) > 300 {
            throw GymaError.invalid("Workout readiness must be recorded immediately before the workout starts.")
        }
        try coachConversation?.validate()
        if Set(exercises.map(\.exerciseID)).count != exercises.count { throw GymaError.invalid("A workout cannot contain duplicate exercises.") }
        if let selectedExerciseID, !exercises.contains(where: { $0.exerciseID == selectedExerciseID }) {
            throw GymaError.invalid("The selected exercise is no longer in the workout.")
        }
        var setIDs = Set<String>()
        var skippedIDs = Set<String>()
        for exercise in exercises {
            guard !exercise.exerciseID.isEmpty, exercise.exerciseID.count <= 200 else { throw GymaError.invalid("Missing or invalid exercise identity.") }
            try exercise.target?.validate()
            guard exercise.skippedSetCount <= 10 else { throw GymaError.invalid("Too many skipped sets for an exercise.") }
            if let skippedAt = exercise.skippedRemainingAt {
                guard supportedDates.contains(skippedAt.timeIntervalSince1970), skippedAt >= start,
                      end.map({ skippedAt <= $0 }) ?? true else { throw GymaError.invalid("Invalid skipped exercise date.") }
            }
            for skipped in exercise.skippedSets ?? [] {
                guard !skipped.id.isEmpty, skipped.id.count <= 200, skippedIDs.insert(skipped.id).inserted,
                      supportedDates.contains(skipped.skippedAt.timeIntervalSince1970), skipped.skippedAt >= start,
                      end.map({ skipped.skippedAt <= $0 }) ?? true else {
                    throw GymaError.invalid("Invalid skipped set.")
                }
            }
            if let count = exercise.snapshotWorkingSetCount {
                guard (0...1_000_000).contains(count), count >= exercise.sets.filter({ $0.isWarmup == false }).count else { throw GymaError.invalid("Invalid snapshot set count.") }
            }
            for set in exercise.sets {
                try set.validate()
                guard setIDs.insert(set.id).inserted else { throw GymaError.invalid("Duplicate set identity.") }
            }
        }
        var restIDs = Set<String>()
        for rest in restHistory ?? [] {
            try rest.validate()
            guard restIDs.insert(rest.id).inserted, rest.startedAt >= start,
                  end.map({ rest.endedAt <= $0 }) ?? true,
                  exercises.contains(where: { $0.exerciseID == rest.exerciseID && $0.sets.contains(where: { $0.id == rest.sourceSetID && $0.isWarmup == false }) }) else {
                throw GymaError.invalid("Completed rest no longer matches its workout and set.")
            }
        }
    }
}

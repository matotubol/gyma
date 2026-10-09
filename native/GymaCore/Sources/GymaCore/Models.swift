import Foundation

public enum Shift: String, Codable, CaseIterable, Sendable, Identifiable {
    case morning, afternoon, night, off
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}
public enum Energy: String, Codable, CaseIterable, Sendable, Identifiable {
    case great, good, medium, poor
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}
public enum Muscle: String, Codable, CaseIterable, Sendable, Identifiable {
    case chest, back, legs, shoulders, arms, core
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}
public enum SetEffort: String, Codable, CaseIterable, Sendable, Identifiable {
    case easy, challenging, limit
    public var id: String { rawValue }
    public var label: String {
        switch self { case .easy: return "Several more reps"; case .challenging: return "1–2 more reps"; case .limit: return "At my limit" }
    }
}

public struct ExerciseDefinition: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var muscle: Muscle
    public var iconKey: String
    public var custom: Bool
    public init(id: String, name: String, muscle: Muscle, iconKey: String = "barbell", custom: Bool = false) {
        self.id = id; self.name = name; self.muscle = muscle; self.iconKey = iconKey; self.custom = custom
    }
}

public struct ExerciseTarget: Codable, Sendable, Equatable {
    public var sets: Int
    public var repsMin: Int
    public var repsMax: Int
    public var loadKg: Double?
    public var restSeconds: Int
    public var reason: String
    public init(sets: Int, repsMin: Int, repsMax: Int, loadKg: Double? = nil, restSeconds: Int = 90, reason: String = "") {
        self.sets = sets; self.repsMin = repsMin; self.repsMax = repsMax; self.loadKg = loadKg; self.restSeconds = restSeconds; self.reason = reason
    }
    public func validate() throws {
        guard (1...10).contains(sets), (1...50).contains(repsMin), repsMax >= repsMin, repsMax <= 50,
              (15...600).contains(restSeconds), reason.count <= 2000, loadKg.map({ $0.isFinite && (0...1000).contains($0) }) ?? true else {
            throw GymaError.invalid("Invalid exercise target.")
        }
    }
}

public struct SessionCheckIn: Codable, Sendable, Equatable {
    public var shift: Shift
    public var energy: Energy
    public var timeMinutes: Int
    public var sleepHours: Double?
    public var notes: String
    public var recentTrainingNote: String
    public var painNote: String
    public init(shift: Shift, energy: Energy, timeMinutes: Int = 45, sleepHours: Double? = nil, notes: String = "", recentTrainingNote: String = "", painNote: String = "") {
        self.shift = shift; self.energy = energy; self.timeMinutes = timeMinutes; self.sleepHours = sleepHours; self.notes = notes; self.recentTrainingNote = recentTrainingNote; self.painNote = painNote
    }
    public func validate() throws {
        guard (10...180).contains(timeMinutes), sleepHours.map({ $0.isFinite && (0...24).contains($0) }) ?? true,
              [notes, recentTrainingNote, painNote].allSatisfy({ $0.count <= 2000 }) else {
            throw GymaError.invalid("Invalid session check-in.")
        }
    }
}

public struct WorkSet: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var kg: Double
    public var reps: Int
    public var effort: SetEffort?
    /// Nil means the user has not classified the set.
    public var isWarmup: Bool?
    public init(id: String = UUID().uuidString, kg: Double, reps: Int, effort: SetEffort? = nil, isWarmup: Bool? = nil) {
        self.id = id; self.kg = kg; self.reps = reps; self.effort = effort; self.isWarmup = isWarmup
    }
    public var volume: Double { kg * Double(reps) }
    public var oneRepMax: Double { reps <= 1 ? kg : kg * (1 + Double(reps) / 30) }
    public func validate() throws {
        guard !id.isEmpty, id.count <= 200, kg.isFinite, (0...1000).contains(kg), (1...10000).contains(reps) else { throw GymaError.invalid("Invalid completed set.") }
    }
}

public struct WorkoutExercise: Codable, Sendable, Identifiable, Equatable {
    public var exerciseID: String
    public var sets: [WorkSet]
    public var target: ExerciseTarget?
    /// Watch snapshots contain only a recent set window; this preserves progress from the full session.
    public var snapshotWorkingSetCount: Int?
    public var id: String { exerciseID }
    public init(exerciseID: String, sets: [WorkSet] = [], target: ExerciseTarget? = nil) {
        self.exerciseID = exerciseID; self.sets = sets; self.target = target
    }
    public var reps: Int { sets.reduce(0) { $0 + $1.reps } }
    public var volume: Double { sets.reduce(0) { $0 + $1.volume } }
    public var topKg: Double { sets.map(\.kg).max() ?? 0 }
    public var best1rm: Double { sets.map(\.oneRepMax).max() ?? 0 }
    public var workingSetCount: Int { snapshotWorkingSetCount ?? sets.filter { $0.isWarmup == false }.count }
    public var isTargetComplete: Bool { target.map { workingSetCount >= $0.sets } ?? false }
}

public struct Workout: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var start: Date
    public var end: Date?
    public var shift: Shift
    public var energy: Energy
    public var checkIn: SessionCheckIn?
    public var planTitle: String?
    public var acceptedPlanID: String?
    public var planAcceptedAt: Date?
    public var exercises: [WorkoutExercise]
    public var restHistory: [CompletedRest]?
    public init(id: String = UUID().uuidString, start: Date = Date(), end: Date? = nil, shift: Shift = .off, energy: Energy = .good, checkIn: SessionCheckIn? = nil, planTitle: String? = nil, acceptedPlanID: String? = nil, planAcceptedAt: Date? = nil, exercises: [WorkoutExercise] = [], restHistory: [CompletedRest]? = nil) {
        self.id = id; self.start = start; self.end = end; self.shift = shift; self.energy = energy; self.checkIn = checkIn; self.planTitle = planTitle; self.acceptedPlanID = acceptedPlanID; self.planAcceptedAt = planAcceptedAt; self.exercises = exercises; self.restHistory = restHistory
    }
    public var isActive: Bool { end == nil }
    public var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    public var totalReps: Int { exercises.reduce(0) { $0 + $1.reps } }
    public var volume: Double { exercises.reduce(0) { $0 + $1.volume } }
    public var nextExercise: WorkoutExercise? { exercises.first { !$0.isTargetComplete } }
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
        if Set(exercises.map(\.exerciseID)).count != exercises.count { throw GymaError.invalid("A workout cannot contain duplicate exercises.") }
        var setIDs = Set<String>()
        for exercise in exercises {
            guard !exercise.exerciseID.isEmpty, exercise.exerciseID.count <= 200 else { throw GymaError.invalid("Missing or invalid exercise identity.") }
            try exercise.target?.validate()
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

public struct CompletedRest: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var exerciseID: String
    public var sourceSetID: String
    public var plannedSeconds: Int
    public var startedAt: Date
    public var endedAt: Date
    public init(id: String, exerciseID: String, sourceSetID: String, plannedSeconds: Int, startedAt: Date, endedAt: Date) {
        self.id = id; self.exerciseID = exerciseID; self.sourceSetID = sourceSetID; self.plannedSeconds = plannedSeconds; self.startedAt = startedAt; self.endedAt = endedAt
    }
    public var elapsedSeconds: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
    public func validate() throws {
        let supportedDates = -2_208_988_800.0...4_102_444_800.0
        guard [id, exerciseID, sourceSetID].allSatisfy({ !$0.isEmpty && $0.count <= 200 }),
              (0...86400).contains(plannedSeconds), supportedDates.contains(startedAt.timeIntervalSince1970),
              supportedDates.contains(endedAt.timeIntervalSince1970), endedAt >= startedAt else {
            throw GymaError.invalid("Invalid completed rest interval.")
        }
    }
}

public struct RestTimer: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var workoutID: String
    public var exerciseID: String
    public var startedAt: Date
    public var endsAt: Date
    public var sourceSetID: String
    /// Original plan duration, retained when the user extends the countdown.
    public var plannedSeconds: Int?
    public init(id: String = UUID().uuidString, workoutID: String, exerciseID: String, startedAt: Date, endsAt: Date, sourceSetID: String, plannedSeconds: Int? = nil) {
        self.id = id; self.workoutID = workoutID; self.exerciseID = exerciseID; self.startedAt = startedAt; self.endsAt = endsAt; self.sourceSetID = sourceSetID; self.plannedSeconds = plannedSeconds
    }
    public func remaining(at now: Date = Date()) -> TimeInterval {
        let seconds = endsAt.timeIntervalSince(now)
        // Keep watchOS arm64_32 countdown arithmetic safe even when a restored device clock differs.
        guard seconds.isFinite else { return 0 }
        return min(86400, max(0, seconds))
    }
}

public enum GymaError: Error, LocalizedError, Equatable {
    case invalid(String)
    case stale(String)
    public var errorDescription: String? { switch self { case .invalid(let message), .stale(let message): return message } }
}

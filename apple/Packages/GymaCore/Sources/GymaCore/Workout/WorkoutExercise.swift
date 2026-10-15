import Foundation

public struct WorkoutExercise: Codable, Sendable, Identifiable, Equatable {
    public var exerciseID: String
    public var sets: [WorkSet]
    public var target: ExerciseTarget?
    /// Optional so saved workouts from before skipping was supported still decode.
    public var skippedSets: [SkippedSet]?
    /// Also allows an unplanned exercise with no set target to be left unfinished explicitly.
    public var skippedRemainingAt: Date?
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
    public var skippedSetCount: Int { skippedSets?.count ?? 0 }
    public var resolvedSetCount: Int { workingSetCount + skippedSetCount }
    public var remainingSetCount: Int { max(0, (target?.sets ?? 0) - resolvedSetCount) }
    public var isTargetResolved: Bool { skippedRemainingAt != nil || (target.map { resolvedSetCount >= $0.sets } ?? false) }
    /// Completion reflects actual work; skipped sets only resolve navigation.
    public var isTargetComplete: Bool { target.map { workingSetCount >= $0.sets } ?? false }
}

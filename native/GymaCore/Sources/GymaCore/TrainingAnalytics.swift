import Foundation

public struct MuscleVolume: Codable, Sendable, Identifiable, Equatable {
    public var muscle: TrainingMuscle
    public var directSets: Int
    public var secondarySets: Int
    public var id: String { muscle.rawValue }
    public init(muscle: TrainingMuscle, directSets: Int = 0, secondarySets: Int = 0) {
        self.muscle = muscle; self.directSets = directSets; self.secondarySets = secondarySets
    }
}

public struct TrainingDataQuality: Codable, Sendable, Equatable {
    public var completedWorkoutCount: Int
    public var workingSetCount: Int
    public var workingSetsWithEffort: Int
    public var warmupSetCount: Int
    public var unclassifiedSetCount: Int
    public var workingSetsWithoutMuscleMetadata: Int
    public var effortCoverage: Double? {
        workingSetCount > 0 ? Double(workingSetsWithEffort) / Double(workingSetCount) : nil
    }
}

public struct ExerciseExposure: Codable, Sendable, Equatable, Identifiable {
    public var workoutID: String
    public var completedAt: Date
    public var target: ExerciseTarget?
    public var workingSetCount: Int
    public var unclassifiedSetCount: Int
    public var totalWorkingReps: Int
    public var topWorkingLoadKg: Double?
    public var easySets: Int
    public var challengingSets: Int
    public var limitSets: Int
    public var unknownEffortSets: Int
    public var id: String { workoutID }
}

public struct ExerciseExposureSummary: Codable, Sendable, Equatable, Identifiable {
    public var exerciseID: String
    public var totalCompletedExposures: Int
    public var lastPerformedAt: Date?
    public var recentExposures: [ExerciseExposure]
    public var id: String { exerciseID }
}

/// Computed locally from all retained completed history. No model-estimated counts or recovery scores.
public struct TrainingAnalytics: Codable, Sendable, Equatable {
    public var asOf: Date
    public var volume7Days: [MuscleVolume]
    public var volume28Days: [MuscleVolume]
    public var exposures: [ExerciseExposureSummary]
    public var dataQuality: TrainingDataQuality
    public var quality7Days: TrainingDataQuality
    public var quality28Days: TrainingDataQuality
    public var interpretation: String

    /// A rough Epley trend estimate, not a measured maximum or an RIR-adjusted prediction.
    /// Compare only the same exercise and load convention; easy or unknown-effort sets are ineligible.
    public static func estimatedOneRepMax(for sets: [WorkSet]) -> Double? {
        sets.filter { $0.isWarmup == false && $0.kg.isFinite && $0.kg > 0 && (1...10).contains($0.reps) && ($0.effort == .challenging || $0.effort == .limit) }
            .map(\.oneRepMax).filter(\.isFinite).max()
    }

    public static func make(workouts: [Workout], catalog: [ExerciseDefinition], now: Date = Date(), relevantExerciseIDs: [String] = []) -> TrainingAnalytics {
        let completed = workouts.filter { $0.end.map({ $0 <= now }) == true }.sorted {
            let lhs = $0.end ?? $0.start, rhs = $1.end ?? $1.start
            return lhs == rhs ? $0.id < $1.id : lhs > rhs
        }
        let definitions = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let week = completed.filter { ($0.end ?? $0.start) > now.addingTimeInterval(-7 * 86400) }
        let month = completed.filter { ($0.end ?? $0.start) > now.addingTimeInterval(-28 * 86400) }
        let ids = relevantExerciseIDs.isEmpty ? Set(completed.flatMap { $0.exercises.map(\.exerciseID) }).sorted() : Array(Set(relevantExerciseIDs)).sorted()
        let exposures = ids.map { exerciseID in
            let records: [ExerciseExposure] = completed.compactMap { workout in
                guard let entry = workout.exercises.first(where: { $0.exerciseID == exerciseID }), entry.sets.contains(where: { $0.isWarmup != true }) else { return nil }
                let sets = entry.sets.filter { $0.isWarmup == false }
                return .init(workoutID: workout.id, completedAt: workout.end ?? workout.start, target: entry.target,
                             workingSetCount: sets.count, unclassifiedSetCount: entry.sets.filter { $0.isWarmup == nil }.count,
                             totalWorkingReps: sets.reduce(0) { $0 + $1.reps }, topWorkingLoadKg: sets.map(\.kg).max(),
                             easySets: sets.filter { $0.effort == .easy }.count,
                             challengingSets: sets.filter { $0.effort == .challenging }.count,
                             limitSets: sets.filter { $0.effort == .limit }.count,
                             unknownEffortSets: sets.filter { $0.effort == nil }.count)
            }
            return ExerciseExposureSummary(exerciseID: exerciseID, totalCompletedExposures: records.count,
                                           lastPerformedAt: records.first?.completedAt, recentExposures: Array(records.prefix(4)))
        }
        return .init(asOf: now, volume7Days: volume(workouts: week, definitions: definitions), volume28Days: volume(workouts: month, definitions: definitions),
                     exposures: exposures, dataQuality: quality(workouts: completed, definitions: definitions),
                     quality7Days: quality(workouts: week, definitions: definitions), quality28Days: quality(workouts: month, definitions: definitions),
                     interpretation: "Direct and secondary sets are separate catalog estimates, not fractional or effective sets. Warm-ups and unclassified sets are excluded. Windows use workout completion time. Missing effort stays unknown; these counts do not measure recovery or muscle growth.")
    }

    private static func volume(workouts: [Workout], definitions: [String: ExerciseDefinition]) -> [MuscleVolume] {
        var direct: [TrainingMuscle: Int] = [:], secondary: [TrainingMuscle: Int] = [:]
        for entry in workouts.flatMap(\.exercises) {
            guard let metadata = definitions[entry.exerciseID]?.trainingMetadata else { continue }
            let count = entry.sets.filter { $0.isWarmup == false }.count
            for muscle in Set(metadata.primaryMuscles) { direct[muscle, default: 0] += count }
            for muscle in Set(metadata.secondaryMuscles).subtracting(metadata.primaryMuscles) { secondary[muscle, default: 0] += count }
        }
        return TrainingMuscle.allCases.map { .init(muscle: $0, directSets: direct[$0, default: 0], secondarySets: secondary[$0, default: 0]) }
    }

    private static func quality(workouts: [Workout], definitions: [String: ExerciseDefinition]) -> TrainingDataQuality {
        let entries = workouts.flatMap(\.exercises)
        let sets = entries.flatMap(\.sets)
        let working = sets.filter { $0.isWarmup == false }
        let missing = entries.filter { definitions[$0.exerciseID]?.trainingMetadata == nil }
            .reduce(0) { $0 + $1.sets.filter { $0.isWarmup == false }.count }
        return .init(completedWorkoutCount: workouts.count, workingSetCount: working.count,
                     workingSetsWithEffort: working.filter { $0.effort != nil }.count,
                     warmupSetCount: sets.filter { $0.isWarmup == true }.count,
                     unclassifiedSetCount: sets.filter { $0.isWarmup == nil }.count,
                     workingSetsWithoutMuscleMetadata: missing)
    }
}

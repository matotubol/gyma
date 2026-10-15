import Foundation

/// Observed work from one completed session. A load change alone does not establish a strength gain.
public struct ExercisePerformanceSnapshot: Codable, Sendable, Equatable {
    public var workoutID: String
    public var completedAt: Date
    public var workingSetCount: Int
    public var totalWorkingReps: Int
    public var topWorkingLoadKg: Double
    public var workingVolumeKg: Double
    public var estimatedOneRepMaxKg: Double?
    public var workingSetsWithEffort: Int
    /// Bounded detail for coaching; the totals above include every classified working set.
    public var workingSetSample: [WorkSet]
}

/// First and latest recorded working exposures across all retained calendar blocks.
/// Compare the same exercise, equipment and load convention, and consider reps and effort too.
public struct ExerciseProgressComparison: Codable, Sendable, Equatable, Identifiable {
    public var exerciseID: String
    public var completedExposureCount: Int
    public var first: ExercisePerformanceSnapshot
    public var latest: ExercisePerformanceSnapshot
    public var topWorkingLoadChangeKg: Double
    public var id: String { exerciseID }
    public var hasMultipleExposures: Bool { completedExposureCount > 1 }

    public static func make(exercise: ExerciseDefinition, workouts: [Workout], now: Date = Date()) -> Self? {
        let metadata = exercise.trainingMetadata
        let supportsEstimate = metadata.map {
            $0.measurement == .repetitions && $0.loadConvention != .unknown && $0.loadConvention != .bodyweight
        } ?? false
        let completed = workouts.filter { $0.end.map { $0 <= now } == true }.sorted {
            let left = $0.end ?? $0.start, right = $1.end ?? $1.start
            return left == right ? $0.id < $1.id : left < right
        }
        let records: [ExercisePerformanceSnapshot] = completed.compactMap { workout in
            guard let entry = workout.exercises.first(where: { $0.exerciseID == exercise.id }) else { return nil }
            let working = entry.sets.filter { $0.isWarmup == false }
            guard let topLoad = working.map(\.kg).max() else { return nil }
            return ExercisePerformanceSnapshot(workoutID: workout.id, completedAt: workout.end ?? workout.start,
                                               workingSetCount: working.count, totalWorkingReps: working.reduce(0) { $0 + $1.reps },
                                               topWorkingLoadKg: topLoad, workingVolumeKg: working.reduce(0) { $0 + $1.volume },
                                               estimatedOneRepMaxKg: supportsEstimate ? TrainingAnalytics.estimatedOneRepMax(for: working) : nil,
                                               workingSetsWithEffort: working.filter { $0.effort != nil }.count,
                                               workingSetSample: Array(working.prefix(10)))
        }
        guard let first = records.first, let latest = records.last else { return nil }
        return Self(exerciseID: exercise.id, completedExposureCount: records.count, first: first, latest: latest,
                    topWorkingLoadChangeKg: latest.topWorkingLoadKg - first.topWorkingLoadKg)
    }
}

import Foundation

public struct ExerciseWorkoutReview: Codable, Sendable, Identifiable, Equatable {
    public var exerciseID: String
    public var exerciseName: String
    public var target: ExerciseTarget?
    public var actualWorkingSets: Int
    public var warmupSets: Int
    public var unclassifiedSets: Int
    public var totalWorkingReps: Int
    public var minWorkingLoadKg: Double?
    public var maxWorkingLoadKg: Double?
    public var setsBelowRepMinimum: Int?
    public var setsAtRepMaximum: Int?
    public var missingEffortSets: Int
    public var recommendation: NextTargetRecommendation?
    public var summary: String
    public var id: String { exerciseID }
}

/// A reproducible local review of recorded work. It does not diagnose fatigue or infer missing effort.
public struct WorkoutReview: Codable, Sendable, Identifiable, Equatable {
    public var id: String { workoutID }
    public var workoutID: String
    public var createdAt: Date
    public var summary: String
    public var exercises: [ExerciseWorkoutReview]

    public static func make(workout: Workout, history: [Workout], program: TrainingProgram?, catalog: [ExerciseDefinition], now: Date = Date(), priorPrograms: [TrainingProgram] = []) -> WorkoutReview {
        var records = history.filter { $0.id != workout.id }
        records.append(workout)
        var recommendations: [NextTargetRecommendation] = []
        if let program, workout.programID == program.id, workout.programRevision == program.revision,
           let session = program.sessions.first(where: { $0.id == workout.programSessionID }) {
            recommendations = program.recommendations(for: session, history: records, now: now, catalog: catalog, priorPrograms: priorPrograms)
        }
        let definitions = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = workout.exercises.map { entry in
            let sets = entry.sets.filter { $0.isWarmup == false }
            let unknown = entry.sets.filter { $0.isWarmup == nil }.count
            let missingEffort = sets.filter { $0.effort == nil }.count
            let name = definitions[entry.exerciseID]?.name ?? entry.exerciseID
            var summary = "\(sets.count) working sets recorded"
            if let target = entry.target { summary += " of \(target.sets) planned, targeting \(target.repsMin)–\(target.repsMax) reps" }
            summary += "."
            if unknown > 0 { summary += " \(unknown) unclassified sets excluded." }
            if missingEffort > 0 { summary += " Effort missing for \(missingEffort) working sets." }
            return ExerciseWorkoutReview(exerciseID: entry.exerciseID, exerciseName: name, target: entry.target,
                                         actualWorkingSets: sets.count, warmupSets: entry.sets.filter { $0.isWarmup == true }.count,
                                         unclassifiedSets: unknown, totalWorkingReps: sets.reduce(0) { $0 + $1.reps },
                                         minWorkingLoadKg: sets.map(\.kg).min(), maxWorkingLoadKg: sets.map(\.kg).max(),
                                         setsBelowRepMinimum: entry.target.map { target in sets.filter { $0.reps < target.repsMin }.count },
                                         setsAtRepMaximum: entry.target.map { target in sets.filter { $0.reps >= target.repsMax }.count },
                                         missingEffortSets: missingEffort, recommendation: recommendations.first { $0.exerciseID == entry.exerciseID }, summary: summary)
        }
        let workingCount = entries.reduce(0) { $0 + $1.actualWorkingSets }
        let unknownCount = entries.reduce(0) { $0 + $1.unclassifiedSets }
        let missingCount = entries.reduce(0) { $0 + $1.missingEffortSets }
        var summary = "Completed \(workingCount) classified working sets across \(entries.filter { $0.actualWorkingSets > 0 }.count) exercises."
        if unknownCount > 0 { summary += " \(unknownCount) unclassified sets were excluded from training volume." }
        if missingCount > 0 { summary += " Effort is unknown for \(missingCount) working sets; no effort was assumed." }
        if recommendations.contains(where: { $0.action == .increaseLoad }) { summary += " A load increase is proposed for the next comparable session; review the targets before accepting." }
        if recommendations.contains(where: { $0.action == .review }) { summary += " Some targets need review before progressing." }
        return .init(workoutID: workout.id, createdAt: now, summary: summary, exercises: entries)
    }

    public func validate() throws {
        guard !workoutID.isEmpty, workoutID.count <= 200,
              (-2_208_988_800.0...4_102_444_800.0).contains(createdAt.timeIntervalSince1970), summary.count <= 4000,
              Set(exercises.map(\.exerciseID)).count == exercises.count else { throw GymaError.invalid("Invalid workout review.") }
        for entry in exercises {
            guard !entry.exerciseID.isEmpty, entry.exerciseID.count <= 200, entry.exerciseName.count <= 200,
                  [entry.actualWorkingSets, entry.warmupSets, entry.unclassifiedSets, entry.totalWorkingReps, entry.missingEffortSets].allSatisfy({ $0 >= 0 }),
                  entry.missingEffortSets <= entry.actualWorkingSets, entry.summary.count <= 4000,
                  [entry.minWorkingLoadKg, entry.maxWorkingLoadKg].allSatisfy({ $0.map({ $0.isFinite && (0...1000).contains($0) }) ?? true }),
                  [entry.setsBelowRepMinimum, entry.setsAtRepMaximum].allSatisfy({ $0.map({ (0...entry.actualWorkingSets).contains($0) }) ?? true }) else {
                throw GymaError.invalid("Invalid exercise workout review.")
            }
            try entry.target?.validate()
            if let recommendation = entry.recommendation {
                guard recommendation.exerciseID == entry.exerciseID, recommendation.reason.count <= 4000,
                      recommendation.evidenceWorkoutIDs.count <= 5,
                      recommendation.evidenceWorkoutIDs.allSatisfy({ !$0.isEmpty && $0.count <= 200 }) else { throw GymaError.invalid("Invalid progression recommendation.") }
                try recommendation.target.validate()
            }
        }
    }
}

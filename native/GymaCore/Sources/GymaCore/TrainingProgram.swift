import Foundation

/// A transparent product rule, not a claim about an individual's physiological optimum.
public struct ProgressionRule: Codable, Sendable, Equatable {
    public var loadIncrementKg: Double
    public var successfulExposuresRequired: Int
    public var exerciseIncrements: [String: Double]
    public init(loadIncrementKg: Double = 2.5, successfulExposuresRequired: Int = 2, exerciseIncrements: [String: Double] = [:]) {
        self.loadIncrementKg = loadIncrementKg; self.successfulExposuresRequired = successfulExposuresRequired; self.exerciseIncrements = exerciseIncrements
    }
    public func validate() throws {
        guard loadIncrementKg.isFinite, (0.1...100).contains(loadIncrementKg), (1...5).contains(successfulExposuresRequired),
              exerciseIncrements.count <= 200,
              exerciseIncrements.allSatisfy({ !$0.key.isEmpty && $0.key.count <= 200 && $0.value.isFinite && (0.1...100).contains($0.value) }) else {
            throw GymaError.invalid("Progression needs a 0.1–100 kg increment and 1–5 successful exposures.")
        }
    }
}

public struct ProgramSession: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var exercises: [WorkoutExercise]
    public init(id: String = UUID().uuidString, title: String, exercises: [WorkoutExercise]) {
        self.id = id; self.title = title; self.exercises = exercises
    }
}

public enum ProgressionAction: String, Codable, Sendable {
    case calibrate, addReps, increaseLoad, repeatTarget, needsEffort, review
}

public struct NextTargetRecommendation: Codable, Sendable, Equatable, Identifiable {
    public var exerciseID: String
    public var target: ExerciseTarget
    public var action: ProgressionAction
    public var reason: String
    public var evidenceWorkoutIDs: [String]
    public var id: String { exerciseID }
    public init(exerciseID: String, target: ExerciseTarget, action: ProgressionAction, reason: String, evidenceWorkoutIDs: [String] = []) {
        self.exerciseID = exerciseID; self.target = target; self.action = action; self.reason = reason; self.evidenceWorkoutIDs = evidenceWorkoutIDs
    }
}

public struct TrainingProgram: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var goal: String
    public var rationale: String
    public var sessions: [ProgramSession]
    public var progressionRule: ProgressionRule
    public var revision: Int
    public var createdAt: Date
    public var updatedAt: Date
    public init(id: String = UUID().uuidString, title: String, goal: String, rationale: String = "", sessions: [ProgramSession], progressionRule: ProgressionRule = .init(), revision: Int = 1, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.title = title; self.goal = goal; self.rationale = rationale; self.sessions = sessions
        self.progressionRule = progressionRule; self.revision = revision; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
    public func validate(catalog: [ExerciseDefinition]) throws {
        let dates = -2_208_988_800.0...4_102_444_800.0
        guard !id.isEmpty, id.count <= 200, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200,
              !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, goal.count <= 2000, rationale.count <= 4000,
              (1...1_000_000).contains(revision), dates.contains(createdAt.timeIntervalSince1970), dates.contains(updatedAt.timeIntervalSince1970), updatedAt >= createdAt,
              (1...7).contains(sessions.count), Set(sessions.map(\.id)).count == sessions.count else {
            throw GymaError.invalid("A program needs a goal and 1–7 unique rotating sessions.")
        }
        try progressionRule.validate()
        let catalogByID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for session in sessions {
            guard !session.id.isEmpty, session.id.count <= 200, !session.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, session.title.count <= 200,
                  (1...12).contains(session.exercises.count), Set(session.exercises.map(\.exerciseID)).count == session.exercises.count else {
                throw GymaError.invalid("Each program session needs a title and 1–12 unique exercises.")
            }
            for exercise in session.exercises {
                guard let definition = catalogByID[exercise.exerciseID], let target = exercise.target,
                      exercise.sets.isEmpty, exercise.snapshotWorkingSetCount == nil else {
                    throw GymaError.invalid("Program exercises need catalog identities and targets without completed sets.")
                }
                guard definition.trainingMetadata?.measurement != .seconds else {
                    throw GymaError.invalid("Timed exercises are not supported in repetition-based programs yet.")
                }
                try target.validate()
            }
        }
        guard Set(progressionRule.exerciseIncrements.keys).isSubset(of: Set(sessions.flatMap { $0.exercises.map(\.exerciseID) })) else {
            throw GymaError.invalid("A progression increment refers to an exercise outside this program.")
        }
    }

    /// Rotate only after a linked, completed workout. Calendar gaps never create catch-up sessions.
    public func nextSession(history: [Workout], now: Date = Date()) -> ProgramSession? {
        let knownIDs = Set(sessions.map(\.id))
        let latest = history.filter {
            $0.programID == id && $0.end.map({ $0 <= now }) == true && knownIDs.contains($0.programSessionID ?? "") &&
            $0.exercises.contains(where: { $0.sets.contains(where: { $0.isWarmup == false }) })
        }
            .sorted(by: Self.newestFirst).first
        guard let previous = latest?.programSessionID, let index = sessions.firstIndex(where: { $0.id == previous }) else { return sessions.first }
        return sessions[(index + 1) % sessions.count]
    }

    public func nextExercises(history: [Workout], now: Date = Date(), catalog: [ExerciseDefinition] = ExerciseCatalog.builtIn, priorPrograms: [TrainingProgram] = []) -> [WorkoutExercise] {
        guard let session = nextSession(history: history, now: now) else { return [] }
        let proposed = recommendations(for: session, history: history, now: now, catalog: catalog, priorPrograms: priorPrograms)
        return proposed.map { recommendation in
            var target = recommendation.target; target.reason = recommendation.reason
            return .init(exerciseID: recommendation.exerciseID, target: target)
        }
    }

    public func recommendations(for session: ProgramSession, history: [Workout], now: Date = Date(), catalog: [ExerciseDefinition] = ExerciseCatalog.builtIn, priorPrograms: [TrainingProgram] = []) -> [NextTargetRecommendation] {
        let linked = history.filter { $0.programID == id && $0.programSessionID == session.id && $0.end.map({ $0 <= now }) == true }
            .sorted(by: Self.newestFirst)
        return session.exercises.compactMap { planned in
            guard var target = planned.target else { return nil }
            let exposures: [(Workout, WorkoutExercise)] = linked.compactMap { workout in
                guard let exercise = workout.exercises.first(where: { $0.exerciseID == planned.exerciseID }) else { return nil }
                return (workout, exercise)
            }
            func result(_ action: ProgressionAction, _ reason: String, evidence: [String] = []) -> NextTargetRecommendation {
                .init(exerciseID: planned.exerciseID, target: target, action: action, reason: reason, evidenceWorkoutIDs: evidence)
            }
            guard let (latestWorkout, latestEntry) = exposures.first else {
                return result(.calibrate, "No completed exposure for this program session. Start conservatively and record effort.")
            }
            let evidence = [latestWorkout.id]
            // A coach's temporary change in set/rep/effort prescription is not comparable to the recurring target.
            let priorTemplate = priorPrograms.last(where: { $0.id == id && $0.revision == latestWorkout.programRevision })?
                .sessions.first(where: { $0.id == session.id })?.exercises.first(where: { $0.exerciseID == planned.exerciseID })?.target
            let unchangedTemplate = priorTemplate.map { Self.samePrescription($0, target, compareLoad: true) } ?? false
            if let actualTarget = latestEntry.target,
               Self.samePrescription(actualTarget, target, compareLoad: latestWorkout.programRevision != revision && !unchangedTemplate) {
                target.loadKg = actualTarget.loadKg
            } else {
                return result(.review, "The last prescription differs from this program. Review the target before progressing.", evidence: evidence)
            }
            if now.timeIntervalSince(latestWorkout.end ?? latestWorkout.start) > 28 * 86400 {
                target.loadKg = nil
                return result(.review, "More than 28 days since this session. Reassess a comfortable load instead of increasing the old weight.", evidence: evidence)
            }
            if Self.hasRecoveryConcern(latestWorkout) {
                return result(.review, "The last check-in recorded pain, poor energy, or high soreness. Review recovery and a comfortable target before increasing load.", evidence: evidence)
            }
            let sets = latestEntry.sets.filter { $0.isWarmup == false }
            guard latestEntry.sets.allSatisfy({ $0.isWarmup != nil }), let desiredEffort = target.targetEffort,
                  !sets.isEmpty, sets.allSatisfy({ $0.effort != nil }) else {
                return result(.needsEffort, "A load increase needs classified working sets and known target and actual effort. Missing values remain unknown.", evidence: evidence)
            }
            // Establish an observed baseline when the first accepted plan deliberately left load open.
            // This is not an estimated 1RM or a transfer of weight from another exercise or machine.
            if target.loadKg == nil, sets.count >= target.sets, let observedLoad = sets.first?.kg,
               sets.allSatisfy({ abs($0.kg - observedLoad) < 0.0001 }) {
                target.loadKg = observedLoad
            }
            guard sets.count == target.sets else {
                return result(.repeatTarget, "The completed working-set count differs from the prescription. Review or repeat the target before increasing.", evidence: evidence)
            }
            guard sets.allSatisfy({ $0.reps >= target.repsMin && Self.effortRank($0.effort!) <= Self.effortRank(desiredEffort) }) else {
                return result(.review, "Some sets missed the rep range or were harder than intended. Review the load, rest, and recovery before progressing.", evidence: evidence)
            }
            guard let load = target.loadKg, load > 0, sets.allSatisfy({ abs($0.kg - load) < 0.0001 }) else {
                return result(.review, "Record a consistent working load before calculating a weight increase. Bodyweight and mixed-load sets need an explicit target.", evidence: evidence)
            }
            guard sets.allSatisfy({ $0.reps >= target.repsMax }) else {
                return result(.addReps, "Keep the working load and aim for more repetitions within the range at the intended effort.", evidence: evidence)
            }
            var successful: [String] = []
            var newerDate = now
            for (workout, entry) in exposures {
                let date = workout.end ?? workout.start
                guard newerDate.timeIntervalSince(date) <= 28 * 86400,
                      !Self.hasRecoveryConcern(workout), let completedTarget = entry.target,
                      Self.samePrescription(completedTarget, target, compareLoad: completedTarget.loadKg != nil),
                      entry.sets.allSatisfy({ $0.isWarmup != nil }) else { break }
                let work = entry.sets.filter { $0.isWarmup == false }
                guard work.count == target.sets, work.allSatisfy({ set in
                    guard let effort = set.effort else { return false }
                    return abs(set.kg - load) < 0.0001 && set.reps >= target.repsMax && Self.effortRank(effort) <= Self.effortRank(desiredEffort)
                }) else { break }
                successful.append(workout.id); newerDate = date
                if successful.count >= progressionRule.successfulExposuresRequired { break }
            }
            guard successful.count >= progressionRule.successfulExposuresRequired else {
                return result(.repeatTarget, "Top of the rep range reached with recorded effort in \(successful.count) of \(progressionRule.successfulExposuresRequired) required consecutive comparable exposures. Repeat before increasing.", evidence: successful)
            }
            let definition = catalog.first { $0.id == planned.exerciseID }
            let convention = definition?.trainingMetadata?.loadConvention ?? .unknown
            let needsSpecificIncrement = convention == .unknown || convention == .machineStack || definition?.trainingMetadata?.equipment == .machines || definition?.trainingMetadata?.equipment == .cables
            guard !needsSpecificIncrement || progressionRule.exerciseIncrements[planned.exerciseID] != nil else {
                return result(.review, "The load convention or machine increment is unspecified. Set an increment for this exercise before proposing more weight.", evidence: successful)
            }
            let increment = progressionRule.exerciseIncrements[planned.exerciseID] ?? progressionRule.loadIncrementKg
            // Product guardrail: the available plate/stack step can be too large for an automatic proposal.
            // This is not a physiological threshold; the coach can discuss repetitions or another explicit plan.
            guard increment <= max(2.5, load * 0.15) else {
                return result(.review, "The configured \(increment) kg step is too large for automatic progression from \(load) kg. Keep this load and review repetitions or another available increment with the coach. The app's limit is a conservative product rule, not a physiological threshold.", evidence: successful)
            }
            let nextLoad = (load + increment) * 1000
            guard nextLoad.isFinite, nextLoad / 1000 <= 1000 else { return result(.review, "The next load exceeds supported limits. Review the prescription.", evidence: successful) }
            target.loadKg = nextLoad.rounded() / 1000
            return result(.increaseLoad, "All working sets reached the upper rep target at the intended effort across \(successful.count) comparable exposures. Propose the configured \(increment) kg increment; stay within the rep range.", evidence: successful)
        }
    }

    private static func newestFirst(_ lhs: Workout, _ rhs: Workout) -> Bool {
        let left = lhs.end ?? lhs.start, right = rhs.end ?? rhs.start
        return left == right ? lhs.id < rhs.id : left > right
    }
    private static func samePrescription(_ lhs: ExerciseTarget, _ rhs: ExerciseTarget, compareLoad: Bool) -> Bool {
        lhs.sets == rhs.sets && lhs.repsMin == rhs.repsMin && lhs.repsMax == rhs.repsMax && lhs.targetEffort == rhs.targetEffort && lhs.restSeconds == rhs.restSeconds && (!compareLoad || lhs.loadKg == rhs.loadKg)
    }
    private static func effortRank(_ effort: SetEffort) -> Int {
        switch effort { case .easy: return 0; case .challenging: return 1; case .limit: return 2 }
    }
    private static func hasRecoveryConcern(_ workout: Workout) -> Bool {
        !(workout.checkIn?.painNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
        workout.energy == .poor || workout.readiness?.energy == .poor ||
        workout.readiness?.soreness.values.contains(.high) == true || workout.checkIn?.soreness?.values.contains(.high) == true
    }
}

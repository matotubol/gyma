import Foundation

/// App-owned evidence and calculations. The language model explains these; it does not manufacture them.
public enum CoachContext {
    public static let principles = """
    Training principles, reviewed 2026-10-09: use a repeatable program matched to goals, equipment, preferences and available time. More volume and training to failure are not automatically better. ACSM 2026: https://acsm.org/resistance-training-guidelines-update-2026/ . Repetition and load progression are both viable: https://pubmed.ncbi.nlm.nih.gov/36199287/ . Near-failure training can build muscle without requiring failure on every set: https://pubmed.ncbi.nlm.nih.gov/38393985/ . These population findings are starting principles, not proof of an individual's optimal dose. Progression thresholds and session-duration estimates in this app are transparent product heuristics. Do not infer injury risk, medical diagnoses, exact recovery percentages or causation from correlations. Preserve unknown effort and unclassified sets. Pain differs from soreness. A normal wearable reading cannot establish muscular recovery. Stable profile facts are confirmed by the user; dated check-ins and workout feedback are temporary context, never permanent facts. Never claim to have saved a new fact or changed the profile through chat.
    """

    public static func text(profile: AthleteProfile?, program: TrainingProgram?, history: [Workout],
                            catalog: [ExerciseDefinition], reviews: [WorkoutReview] = [], feedback: [WorkoutFeedback] = [],
                            relevantExerciseIDs: [String] = [], now: Date = Date(), priorPrograms: [TrainingProgram] = []) throws -> String {
        try profile?.validate()
        try program?.validate(catalog: catalog)
        var boundedProfile = profile
        boundedProfile?.bodyweightHistory = Array((profile?.bodyweightHistory ?? []).sorted { $0.recordedAt > $1.recordedAt }.prefix(90))
        let requested = relevantExerciseIDs.isEmpty ? (program?.nextSession(history: history, now: now)?.exercises.map(\.exerciseID) ?? []) : relevantExerciseIDs
        let completed = history.filter { $0.end.map { $0 <= now } == true }.sorted { $0.start > $1.start }
        var seen = Set<String>()
        let candidates = requested + completed.flatMap { $0.exercises.map(\.exerciseID) }
        let relevant = Array(candidates.filter { seen.insert($0).inserted }.prefix(12))
        let analytics = TrainingAnalytics.make(workouts: history, catalog: catalog, now: now, relevantExerciseIDs: relevant)
        let completedIDs = Set(history.filter { !$0.isActive }.map(\.id))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
        return """
        Observation date: \(try json(now))
        Confirmed athlete profile (bodyweight limited to latest 90 measurements): \(try json(boundedProfile))
        Accepted program: \(try json(program))
        Next rotating session: \(try json(program?.nextSession(history: history, now: now)))
        Deterministic next-session targets before today's readiness/time adjustments: \(try json(program.flatMap { p in p.nextSession(history: history, now: now).map { p.recommendations(for: $0, history: history, now: now, catalog: catalog, priorPrograms: priorPrograms) } }))
        Exercise equipment, direct and secondary muscle metadata: \(try json(catalog.map { CatalogContext(id: $0.id, metadata: $0.trainingMetadata) }))
        Computed full-history analytics, relevant exposures and missing-data coverage: \(try json(analytics))
        Actual sets for relevant exercises (latest four exposures per exercise, latest ten sets per exposure): \(try json(relevant.map { id in
            RelevantExerciseRecords(exerciseID: id, exposures: Array(completed.compactMap { workout in
                workout.exercises.first(where: { $0.exerciseID == id && !$0.sets.isEmpty }).map { entry in
                    RelevantRecord(workoutID: workout.id, date: workout.start, target: entry.target, sets: Array(entry.sets.suffix(10)), totalLoggedSets: entry.sets.count)
                }
            }.prefix(4)))
        }))
        Latest saved workout reviews: \(try json(Array(reviews.filter { completedIDs.contains($0.workoutID) }.sorted { $0.createdAt > $1.createdAt }.prefix(4))))
        Dated workout feedback, not permanent restrictions: \(try json(Array(feedback.filter { completedIDs.contains($0.workoutID) }.sorted { $0.recordedAt > $1.recordedAt }.prefix(6))))
        Reviews capture the evidence at finish time. Newer pain/discomfort feedback takes precedence over earlier progression proposals and needs discussion before increasing demands.
        \(principles)
        """
    }

    private struct CatalogContext: Encodable { let id: String; let metadata: ExerciseMetadata? }
    private struct RelevantExerciseRecords: Encodable { let exerciseID: String; let exposures: [RelevantRecord] }
    private struct RelevantRecord: Encodable { let workoutID: String; let date: Date; let target: ExerciseTarget?; let sets: [WorkSet]; let totalLoggedSets: Int }
}

public enum CoachingConstraints {
    public static func validate(exercises: [WorkoutExercise], profile: AthleteProfile?, catalog: [ExerciseDefinition]) throws {
        let excluded = Set((profile?.avoidedExercises ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        for entry in exercises {
            guard let definition = catalog.first(where: { $0.id == entry.exerciseID }), definition.trainingMetadata?.measurement != .seconds else {
                throw GymaError.invalid("Choose a supported repetition-based exercise from your library.")
            }
            guard !excluded.contains(definition.id.lowercased()), !excluded.contains(definition.name.lowercased()) else {
                throw GymaError.invalid("\(definition.name) is in your profile's avoided exercises. Ask the coach for a substitution.")
            }
            if let profile, !profile.equipment.isEmpty, let required = definition.trainingMetadata?.equipment,
               required != .bodyweight, !profile.equipment.contains(required) {
                throw GymaError.invalid("\(definition.name) requires \(required.label.lowercased()), which is not selected in your profile. Choose a compatible exercise or update your equipment.")
            }
        }
    }
}

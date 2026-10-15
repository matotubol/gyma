import Foundation

/// A reviewed library addition, separate from a program or workout prescription.
public struct CoachExerciseProposal: Codable, Sendable, Identifiable, Equatable {
    public var id: String { exercise.id }
    public var exercise: ExerciseDefinition
    public var explanation: String

    public init(name: String, muscle: Muscle, metadata: ExerciseMetadata, explanation: String) {
        exercise = .init(id: "custom_\(UUID().uuidString)", name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                         muscle: muscle, iconKey: "barbell", custom: true, metadata: metadata)
        self.explanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func validate(catalog: [ExerciseDefinition]) throws {
        guard exercise.custom, !exercise.id.isEmpty, exercise.id.count <= 200,
              !Self.normalizedName(exercise.name).isEmpty, exercise.name.count <= 200, exercise.iconKey.count <= 100,
              !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, explanation.count <= 2000,
              let metadata = exercise.metadata, metadata.measurement == .repetitions else {
            throw GymaError.invalid("A proposed exercise needs a name, explanation and repetition-based training metadata.")
        }
        try metadata.validate()
        guard !catalog.contains(where: { $0.id == exercise.id || Self.normalizedName($0.name) == Self.normalizedName(exercise.name) }) else {
            throw GymaError.invalid("That exercise is already in your library. Use its existing entry or name the specific equipment variant.")
        }
    }

    static func validate(_ proposals: [CoachExerciseProposal], catalog: [ExerciseDefinition]) throws {
        guard proposals.count <= 6 else { throw GymaError.invalid("Review at most six new exercises at a time.") }
        var available = catalog
        for proposal in proposals {
            try proposal.validate(catalog: available)
            available.append(proposal.exercise)
        }
    }

    private static func normalizedName(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

public extension GymaState {
    /// Save exactly the additions the user reviewed. This never accepts a program or starts training.
    mutating func acceptCoachExerciseProposals(_ proposals: [CoachExerciseProposal]) throws {
        guard activeWorkout == nil, !proposals.isEmpty, var conversation = coachConversation,
              conversation.startedWorkoutID == nil, conversation.messages.last?.role == .assistant,
              conversation.proposedExercises == proposals else {
            throw GymaError.stale("The proposed exercises changed. Review the current suggestions before saving them.")
        }
        try conversation.validate(catalog: catalog)
        var next = self
        next.coachConversation?.proposedExercises = nil
        for proposal in proposals { try next.addCustomExercise(proposal.exercise) }
        conversation.proposedExercises = nil
        conversation.acceptedProgramID = nil
        let saved = proposals.map { "\($0.exercise.name) (\($0.exercise.id))" }.joined(separator: "; ")
        conversation.messages.append(.init(role: .user, content: "I reviewed and saved these exercise entries to my library: \(saved). Continue with my plan using these saved catalog IDs where appropriate. Saving these exercises did not accept a program or start a workout."))
        try conversation.validate(catalog: next.catalog)
        next.coachConversation = conversation
        next.revision += 1
        try next.validate()
        self = next
    }
}

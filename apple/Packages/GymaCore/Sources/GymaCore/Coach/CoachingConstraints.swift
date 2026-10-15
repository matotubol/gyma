import Foundation

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

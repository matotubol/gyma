import Foundation

extension GymaState {
    public var catalog: [ExerciseDefinition] {
        ExerciseCatalog.builtIn.map { original in
            exerciseOverrides?.first(where: { $0.id == original.id }) ?? original
        } + customExercises
    }
    public var availableExercises: [ExerciseDefinition] {
        let hidden = Set(hiddenExerciseIDs ?? [])
        return catalog.filter { !hidden.contains($0.id) }
    }
    public func exercise(_ id: String) -> ExerciseDefinition {
        catalog.first { $0.id == id } ?? .init(id: id, name: "Unknown exercise", muscle: .core, iconKey: "bolt")
    }

    public mutating func addCustomExercise(_ exercise: ExerciseDefinition) throws {
        try exercise.metadata?.validate()
        guard !catalog.contains(where: { $0.id == exercise.id }), !exercise.id.isEmpty, exercise.id.count <= 200,
              !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, exercise.name.count <= 200,
              exercise.iconKey.count <= 100 else { throw GymaError.invalid("Custom exercise must have a unique identity and a name of at most 200 characters.") }
        var item = exercise; item.custom = true; customExercises.append(item)
        coachConversation?.proposedExercises = nil
        revision += 1
    }
}

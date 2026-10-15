import GymaCore

extension GymaAppModel {
    @discardableResult
    func addWorkoutExercise(_ exerciseID: String, workoutID: String, replacingExerciseID: String? = nil) -> Bool {
        update { state in
            try placeWorkoutExercise(exerciseID, workoutID: workoutID, replacingExerciseID: replacingExerciseID, in: &state)
        }
    }

    @discardableResult
    func addCustomWorkoutExercise(_ exercise: ExerciseDefinition, workoutID: String, replacingExerciseID: String? = nil) -> Bool {
        update { state in
            // Library creation and workout selection must either both persist or neither persist.
            try state.addCustomExercise(exercise)
            try placeWorkoutExercise(exercise.id, workoutID: workoutID, replacingExerciseID: replacingExerciseID, in: &state)
        }
    }

    private func placeWorkoutExercise(_ exerciseID: String, workoutID: String, replacingExerciseID: String?, in state: inout GymaState) throws {
        if let replacingExerciseID {
            // Core derives the remaining target and clears the previous movement's load.
            try state.replaceExercise(replacingExerciseID, with: exerciseID, workoutID: workoutID)
        } else {
            try state.addExercise(exerciseID, to: workoutID)
        }
    }
}

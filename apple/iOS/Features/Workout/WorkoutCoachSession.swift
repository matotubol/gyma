/// Transient per-workout request status owned by the app coordinator.
struct WorkoutCoachSession {
    var requestWorkoutID: String?
    var errors: [String: String] = [:]
}

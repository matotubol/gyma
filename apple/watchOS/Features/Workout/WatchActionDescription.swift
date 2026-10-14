import GymaCore

extension WatchAction {
    var watchDescription: String {
        switch self {
        case .startAcceptedPlan: return "Starting workout…"
        case .logSet: return "Saving set…"
        case .selectExercise: return "Choosing exercise…"
        case .skipSet: return "Skipping set…"
        case .skipExercise: return "Stopping exercise…"
        case .skipRest: return "Starting next set…"
        case .extendRest: return "Updating rest…"
        case .finishWorkout: return "Finishing workout…"
        }
    }
}

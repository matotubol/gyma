enum WatchSettingsAction { case finish, discard, exercises, cancelSet, skipSet, skipExercise }

struct WatchSetChangeRequest {
    let kind: WatchSetChangeKind
    let storeID: String
    let workoutID: String
    let exerciseID: String
    let revision: Int
}

enum WatchSetChangeKind: Equatable {
    case cancel, skipSet, skipExercise

    var title: String {
        switch self {
        case .cancel: return "Cancel this set?"
        case .skipSet: return "Skip this planned set?"
        case .skipExercise: return "Stop this exercise?"
        }
    }

    var buttonTitle: String {
        switch self {
        case .cancel: return "Cancel set"
        case .skipSet: return "Skip set"
        case .skipExercise: return "Skip remaining sets"
        }
    }

    var message: String {
        switch self {
        case .cancel: return "Remove this unsaved set and return to the exercise menu. Nothing will be logged; the planned set stays available."
        case .skipSet: return "This set will be marked skipped, not completed. Any unsaved reps will be discarded."
        case .skipExercise: return "The remaining sets will be marked skipped, not completed. Any unsaved reps will be discarded. Your earlier completed sets stay saved."
        }
    }
}

import Foundation

enum AppError: LocalizedError {
    case storageUnavailable
    case invalidSet
    case invalidTarget
    case invalidCustomName
    case invalidRevision
    case backupTooLarge

    var errorDescription: String? {
        switch self {
        case .storageUnavailable: return "iPhone storage is unavailable. Open Gyma on your iPhone to resolve it."
        case .invalidSet: return "Enter a load from 0 to 1,000 kg and 1 to 1,000 reps."
        case .invalidTarget: return "Enter 1–10 sets, 1–50 reps, a load from 0 to 1,000 kg, and 15–600 seconds of rest."
        case .invalidCustomName: return "Enter an exercise name with no more than 100 characters."
        case .invalidRevision: return "This backup has an invalid revision number."
        case .backupTooLarge: return "The backup must be a readable JSON file no larger than 100 MB."
        }
    }
}

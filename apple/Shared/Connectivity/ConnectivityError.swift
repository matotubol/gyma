import Foundation

enum ConnectivityError: LocalizedError {
    case invalidJournal, waitForPhone, phoneNotReady, unsupportedMessage, invalidPayload, payloadTooLarge, workoutChanged, planUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidJournal: return "Watch storage is unavailable. Your pending change is being preserved. Reopen the app to retry."
        case .waitForPhone: return "Wait for the current change to be confirmed by your iPhone."
        case .phoneNotReady: return "Open Gyma on your iPhone to finish syncing."
        case .unsupportedMessage: return "Update Gyma on both devices to sync."
        case .invalidPayload: return "The received workout could not be read. Refresh from your iPhone."
        case .payloadTooLarge: return "This workout is too large to sync to Apple Watch. Continue on your iPhone."
        case .workoutChanged: return "The workout changed on your iPhone. Review the latest workout and try again."
        case .planUnavailable: return "This accepted plan is no longer available for today. Review your workout in Gyma on iPhone."
        }
    }
}

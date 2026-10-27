import SwiftUI
import GymaCore

struct ShownCelebration: Equatable {
    let key: String
    let value: Celebration
}

extension AppModel {
    /// Runs a workout change. Returns the saved session, or nil after setting `workoutError`.
    @discardableResult
    func perform(_ message: String, celebrateSet: String? = nil,
                 _ operation: (GymAPI) async throws -> WorkoutSession) async -> WorkoutSession? {
        workoutError = nil
        switch await mutateSession(operation) {
        case .success(let next):
            workoutNeedsReload = false
            if let setId = celebrateSet, let record = analyseWorkout(next).records[setId] {
                let copy = celebrate(record, seed: setId)
                celebration = ShownCelebration(key: setId, value: copy)
                Haptics.record(monster: copy.monster)
                UIAccessibility.post(notification: .announcement, argument: "\(copy.title) \(copy.detail)")
            } else {
                if celebrateSet != nil { Haptics.success() }
                UIAccessibility.post(notification: .announcement, argument: message)
            }
            return next
        case .failure(.conflict):
            workoutNeedsReload = true
            workoutError = "This workout changed elsewhere or the action is no longer available. Reload it before continuing."
        case .failure(.failed):
            workoutError = "Couldn’t save workout progress. Check your connection and try again."
        case .failure(.unauthorized):
            break
        }
        return nil
    }

    /// For editor sheets: runs the change and hands back its error instead of raising the workout alert.
    func attempt(_ message: String, celebrateSet: String? = nil,
                 _ operation: (GymAPI) async throws -> WorkoutSession) async -> String? {
        if await perform(message, celebrateSet: celebrateSet, operation) != nil { return nil }
        defer { workoutError = nil }
        return workoutError ?? "Couldn’t save. Try again."
    }
}

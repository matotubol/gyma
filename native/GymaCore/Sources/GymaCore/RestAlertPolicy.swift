import Foundation

public struct RestHapticSchedule: Equatable, Sendable {
    public let key: String
    public let delay: TimeInterval
}

/// Separates workout haptics from optional notification authorization.
public enum RestAlertPolicy {
    public static func key(timer: RestTimer, storeID: String) -> String {
        "\(storeID)/\(timer.id)/\(timer.endsAt.timeIntervalSince1970)"
    }
    public static func isEndingRest(_ timer: RestTimer, pending: WatchCommand?, storeID: String) -> Bool {
        guard let pending, pending.storeID == storeID, pending.workoutID == timer.workoutID else { return false }
        switch pending.action {
        case .skipRest(let id): return id == timer.id
        case .finishWorkout: return true
        default: return false
        }
    }
    public static func hapticSchedule(snapshot: CompanionSnapshot?, pending: WatchCommand?, enabled: Bool,
                                      isAppActive: Bool, workoutRunning: Bool, lastAlertKey: String?,
                                      now: Date = Date()) -> RestHapticSchedule? {
        guard enabled, isAppActive || workoutRunning, let snapshot, let timer = snapshot.restTimer,
              timer.workoutID == snapshot.activeWorkout?.id,
              !isEndingRest(timer, pending: pending, storeID: snapshot.storeID) else { return nil }
        let key = key(timer: timer, storeID: snapshot.storeID)
        let delay = timer.endsAt.timeIntervalSince(now)
        // Catch a late callback or brief interruption, without buzzing for hours-old cached rest.
        guard delay.isFinite, (-30...86400).contains(delay), lastAlertKey != key else { return nil }
        return RestHapticSchedule(key: key, delay: max(0, delay))
    }
}

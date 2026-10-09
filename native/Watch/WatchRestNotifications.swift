import Combine
import Foundation
import GymaCore
import UserNotifications
import WatchKit

/// The system schedules a single reminder from the confirmed, persisted phone
/// deadline. A foreground task adds a single tap; background delivery remains
/// owned by the system notification and the user's notification settings.
@MainActor
final class WatchRestNotifications: ObservableObject {
    static let shared = WatchRestNotifications()

    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "watchRestReminders")
    @Published private(set) var hasChosenAlerts = UserDefaults.standard.bool(forKey: "watchRestAlertsChosen") ||
        UserDefaults.standard.object(forKey: "watchRestReminders") != nil
    @Published private(set) var message: String?
    private let center = UNUserNotificationCenter.current()
    private let identifier = "gyma.confirmed-rest"
    private var snapshot: CompanionSnapshot?
    private var latestGeneration = 0
    private var taskTail: Task<Void, Never>?
    private var scheduledKey: String?
    private var isAppActive = false
    private var hapticTask: Task<Void, Never>?
    private var hapticKey: String?
    private var lastHapticKey = UserDefaults.standard.string(forKey: "watchLastRestHaptic")
    private var pendingAction: WatchAction?

    private init() {}

    func update(_ snapshot: CompanionSnapshot?) {
        self.snapshot = snapshot
        reconcile()
        reconcileHaptic()
    }

    func setAppActive(_ active: Bool) {
        isAppActive = active
        reconcileHaptic()
    }

    func updatePendingCommand(_ command: WatchCommand?) {
        pendingAction = command?.action
        reconcile()
        reconcileHaptic()
    }

    private func isEndingRest(_ timerID: String) -> Bool {
        switch pendingAction {
        case .some(.skipRest(let pendingTimerID)): return pendingTimerID == timerID
        case .some(.finishWorkout): return true
        default: return false
        }
    }

    func finishPendingScheduling() async {
        var generation: Int
        repeat {
            generation = latestGeneration
            await taskTail?.value
        } while generation != latestGeneration && !Task.isCancelled
    }

    func setEnabled(_ value: Bool) async {
        hasChosenAlerts = true
        UserDefaults.standard.set(true, forKey: "watchRestAlertsChosen")
        if value {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                enabled = granted
                message = granted ? nil : "Allow notifications in Watch settings to receive rest reminders."
            } catch {
                enabled = false
                message = "Rest reminders could not be enabled."
            }
        } else {
            enabled = false
            message = nil
        }
        UserDefaults.standard.set(enabled, forKey: "watchRestReminders")
        reconcile()
        reconcileHaptic()
    }

    private func reconcileHaptic() {
        guard enabled, isAppActive, let snapshot, let timer = snapshot.restTimer,
              timer.workoutID == snapshot.activeWorkout?.id, !isEndingRest(timer.id) else {
            hapticTask?.cancel()
            hapticTask = nil
            hapticKey = nil
            return
        }
        let key = "\(timer.id):\(timer.endsAt.timeIntervalSince1970)"
        guard hapticKey != key else { return }
        hapticTask?.cancel()
        hapticTask = nil
        hapticKey = nil
        // Reopening an already-expired rest must not play a late or repeated tap.
        let delay = timer.endsAt.timeIntervalSinceNow
        guard delay > 0, delay <= 86400, lastHapticKey != key else { return }
        hapticKey = key
        hapticTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return }
            guard let self, !Task.isCancelled, self.enabled, self.isAppActive,
                  self.hapticKey == key, self.snapshot?.restTimer?.id == timer.id,
                  self.snapshot?.restTimer?.endsAt == timer.endsAt else { return }
            self.lastHapticKey = key
            UserDefaults.standard.set(key, forKey: "watchLastRestHaptic")
            WKInterfaceDevice.current().play(.notification)
        }
    }

    private func reconcile() {
        latestGeneration += 1
        let generation = latestGeneration
        let previous = taskTail
        taskTail = Task { @MainActor in
            await previous?.value
            guard generation == self.latestGeneration else { return }
            await self.scheduleLatest(generation: generation)
        }
    }

    private func scheduleLatest(generation: Int) async {
        guard enabled, let snapshot, let timer = snapshot.restTimer,
              timer.workoutID == snapshot.activeWorkout?.id, !isEndingRest(timer.id), timer.endsAt > Date() else {
            cancel()
            return
        }
        let settings = await center.notificationSettings()
        guard generation == latestGeneration else { return }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            cancel()
            message = "Rest reminders are disabled in Watch notification settings."
            return
        }
        let key = "\(timer.id):\(timer.endsAt.timeIntervalSince1970)"
        guard scheduledKey != key else { return }
        let seconds = timer.endsAt.timeIntervalSinceNow
        guard seconds > 0 else { cancel(); return }
        let name = snapshot.catalog.first { $0.id == timer.exerciseID }?.name ?? "Your next set"
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "\(name) · Continue when you’re ready."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        )
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        do {
            try await center.add(request)
            scheduledKey = key
            message = nil
        } catch {
            scheduledKey = nil
            message = "The rest countdown is active, but its reminder could not be scheduled."
        }
    }

    private func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        scheduledKey = nil
    }
}

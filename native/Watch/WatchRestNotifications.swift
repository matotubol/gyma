import Combine
import Foundation
import GymaCore
import UserNotifications

/// The system schedules a single reminder from the confirmed, persisted phone
/// deadline. There is no background timer or promise of a background haptic.
@MainActor
final class WatchRestNotifications: ObservableObject {
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "watchRestReminders")
    @Published private(set) var message: String?
    private let center = UNUserNotificationCenter.current()
    private let identifier = "gyma.confirmed-rest"
    private var snapshot: CompanionSnapshot?
    private var latestGeneration = 0
    private var taskTail: Task<Void, Never>?
    private var scheduledKey: String?

    func update(_ snapshot: CompanionSnapshot?) {
        self.snapshot = snapshot
        reconcile()
    }

    func finishPendingScheduling() async {
        var generation: Int
        repeat {
            generation = latestGeneration
            await taskTail?.value
        } while generation != latestGeneration && !Task.isCancelled
    }

    func setEnabled(_ value: Bool) async {
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
              timer.workoutID == snapshot.activeWorkout?.id, timer.endsAt > Date() else {
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

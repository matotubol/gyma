import Foundation
import UserNotifications
import GymaCore

@MainActor
final class RestNotifications: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let identifier = "gyma.native.rest"

    override init() {
        super.init()
        center.delegate = self
    }

    func requestPermission() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }

    func replace(timer: RestTimer?, exerciseName: String, enabled: Bool) async throws {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        guard enabled, let timer, timer.endsAt > Date() else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "\(exerciseName) · Continue when you’re ready."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, timer.endsAt.timeIntervalSinceNow), repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

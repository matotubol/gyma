import Combine
import Foundation
import GymaCore
import UserNotifications
import WatchKit

/// Direct workout haptics work with the wrist down while HKWorkoutSession is
/// running. Silent visual notifications back up an unavailable workout runtime.
/// WatchKit's built-in tones still follow the Watch's system Silent Mode.
@MainActor
final class WatchRestNotifications: NSObject, ObservableObject {
    static let shared = WatchRestNotifications()

    // Vibration is on by default, independent of the old notification preference
    // (which also became false if notification permission was denied).
    @Published private(set) var enabled = UserDefaults.standard.object(forKey: "watchRestHapticsEnabled") as? Bool ?? true
    @Published private(set) var message: String?
    @Published private(set) var isTestingHaptic = false
    private let center = UNUserNotificationCenter.current()
    private let identifier = "gyma.confirmed-rest"
    private var snapshot: CompanionSnapshot?
    private var pending: WatchCommand?
    private var isAppActive = false
    private var workoutRunning = false
    private var requestingPermission = false
    private var foregroundCheckGeneration = 0
    private var checkingDeliveredAlert = false
    private var hapticTask: Task<Void, Never>?
    private var hapticKey: String?
    private var cueTask: Task<Void, Never>?
    private var cueRestKey: String?
    private var cueGeneration = 0
    private var lastHapticKey = UserDefaults.standard.string(forKey: "watchLastRestHapticV2")
    private var latestGeneration = 0
    private var taskTail: Task<Void, Never>?
    private var scheduledKey: String?

    private override init() {
        super.init()
        center.delegate = self
    }

    func update(_ snapshot: CompanionSnapshot?) {
        if self.snapshot?.storeID != snapshot?.storeID ||
            self.snapshot?.activeWorkout?.id != snapshot?.activeWorkout?.id ||
            self.snapshot?.restTimer?.id != snapshot?.restTimer?.id ||
            self.snapshot?.restTimer?.endsAt != snapshot?.restTimer?.endsAt {
            stopHapticPreview()
        }
        self.snapshot = snapshot; reconcile()
    }
    func updatePendingCommand(_ command: WatchCommand?) {
        pending = command
        if let command {
            switch command.action {
            case .skipRest, .finishWorkout: stopHapticPreview()
            default: break
            }
        }
        reconcile()
    }
    func setAppActive(_ active: Bool) {
        isAppActive = active
        foregroundCheckGeneration += 1
        let generation = foregroundCheckGeneration
        checkingDeliveredAlert = active && !workoutRunning
        if !checkingDeliveredAlert { reconcileHaptic(); return }
        // A background fallback is delivered without willPresent. Check it before
        // a catch-up haptic so a delivered reminder isn't followed by another tap.
        Task { @MainActor in
            let delivered = await center.deliveredNotifications()
            guard generation == foregroundCheckGeneration else { return }
            if let snapshot, let timer = snapshot.restTimer {
                let key = RestAlertPolicy.key(timer: timer, storeID: snapshot.storeID)
                if delivered.contains(where: { $0.request.identifier == identifier && $0.request.content.userInfo["restKey"] as? String == key }) {
                    lastHapticKey = key
                    UserDefaults.standard.set(key, forKey: "watchLastRestHapticV2")
                }
            }
            checkingDeliveredAlert = false
            reconcileHaptic()
        }
    }
    func setWorkoutRunning(_ running: Bool) { workoutRunning = running; reconcile() }

    func prepareForWorkout() async {
        guard enabled, !requestingPermission else { return }
        requestingPermission = true
        defer { requestingPermission = false }
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do {
                let granted = try await center.requestAuthorization(options: [.alert])
                message = granted ? nil : "Notification backup is off. Workout vibration is still on."
            } catch { message = "Notification backup is unavailable. Workout vibration is still on." }
        } else {
            message = settings.authorizationStatus == .denied ? "Notification backup is off. Workout vibration is still on." : nil
        }
        reconcile()
    }

    func setEnabled(_ value: Bool) async {
        enabled = value
        UserDefaults.standard.set(value, forKey: "watchRestHapticsEnabled")
        if value { await prepareForWorkout() }
        else { message = nil; stopHapticPreview() }
        reconcile()
    }

    func testHaptic() {
        // A settings preview must never replace an actual rest alert that has
        // already been marked delivered for deduplication.
        guard cueRestKey == nil else { return }
        if isTestingHaptic { stopHapticPreview() }
        else { playRestCue(restKey: nil) }
    }

    func stopHapticPreview() {
        if isTestingHaptic { cancelRestCue() }
    }

    func finishPendingScheduling() async {
        var generation: Int
        repeat {
            generation = latestGeneration
            await taskTail?.value
        } while generation != latestGeneration && !Task.isCancelled
    }

    private func desiredHaptic(at now: Date = Date()) -> RestHapticSchedule? {
        RestAlertPolicy.hapticSchedule(snapshot: snapshot, pending: pending, enabled: enabled,
                                      isAppActive: isAppActive, workoutRunning: workoutRunning,
                                      lastAlertKey: lastHapticKey, now: now)
    }

    private func reconcileHaptic() {
        if cueTask != nil && !canContinueCue(restKey: cueRestKey) { cancelRestCue() }
        guard !checkingDeliveredAlert, let schedule = desiredHaptic() else {
            hapticTask?.cancel(); hapticTask = nil; hapticKey = nil
            return
        }
        guard hapticKey != schedule.key else { return }
        hapticTask?.cancel()
        hapticKey = schedule.key
        hapticTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(ceil(schedule.delay * 1_000_000_000))) }
            catch { return }
            guard let self, !Task.isCancelled, self.hapticKey == schedule.key else { return }
            self.playDueHaptic(key: schedule.key)
            self.hapticKey = nil
            self.hapticTask = nil
        }
    }

    private func playDueHaptic(key: String) {
        guard let desired = desiredHaptic(), desired.key == key, desired.delay <= 0.1 else { return }
        lastHapticKey = key
        UserDefaults.standard.set(key, forKey: "watchLastRestHapticV2")
        playRestCue(restKey: key)
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    /// Use the attention-getting notification pattern for ten seconds rather
    /// than a brief click. WatchKit controls each pulse's intensity and duration;
    /// spacing prevents rapid calls from interrupting an in-flight pattern.
    /// System Silent Mode controls its tones independently of notification audio.
    private func playRestCue(restKey: String?) {
        cancelRestCue()
        guard canContinueCue(restKey: restKey) else { return }
        cueRestKey = restKey
        isTestingHaptic = restKey == nil
        let generation = cueGeneration
        WKInterfaceDevice.current().play(.notification)
        cueTask = Task { @MainActor [weak self] in
            // Six full patterns at 0, 2, 4, 6, 8 and 10 seconds. Recheck the
            // current rest before every pulse so Dismiss stops all later pulses.
            for _ in 0..<5 {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) }
                catch { return }
                guard let self, !Task.isCancelled, self.cueGeneration == generation else { return }
                guard self.canContinueCue(restKey: restKey) else {
                    self.cancelRestCue()
                    return
                }
                WKInterfaceDevice.current().play(.notification)
            }
            guard let self, self.cueGeneration == generation else { return }
            self.cueTask = nil; self.cueRestKey = nil; self.isTestingHaptic = false
        }
    }

    private func canContinueCue(restKey: String?) -> Bool {
        guard isAppActive || workoutRunning else { return false }
        guard let restKey else {
            if let pending {
                switch pending.action {
                case .skipRest, .finishWorkout: return false
                default: break
                }
            }
            return isAppActive // Explicit settings preview.
        }
        guard enabled, let snapshot, let timer = snapshot.restTimer,
              timer.workoutID == snapshot.activeWorkout?.id,
              restKey == RestAlertPolicy.key(timer: timer, storeID: snapshot.storeID),
              !RestAlertPolicy.isEndingRest(timer, pending: pending, storeID: snapshot.storeID),
              timer.endsAt.timeIntervalSinceNow <= 0.1 else { return false }
        return true
    }

    private func cancelRestCue() {
        cueTask?.cancel(); cueTask = nil; cueRestKey = nil; cueGeneration += 1
        isTestingHaptic = false
    }

    private func reconcile() {
        reconcileHaptic()
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
        // The live workout timer owns the cue; its fallback is a silent banner.
        guard enabled, !workoutRunning, let snapshot, let timer = snapshot.restTimer,
              timer.workoutID == snapshot.activeWorkout?.id,
              !RestAlertPolicy.isEndingRest(timer, pending: pending, storeID: snapshot.storeID), timer.endsAt > Date() else {
            cancelNotification(removeDelivered: !enabled || self.snapshot?.restTimer == nil); return
        }
        let settings = await center.notificationSettings()
        guard generation == latestGeneration else { return }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            cancelNotification(); return
        }
        let key = RestAlertPolicy.key(timer: timer, storeID: snapshot.storeID)
        guard scheduledKey != key else { return }
        let seconds = timer.endsAt.timeIntervalSinceNow
        guard seconds > 0 else { cancelNotification(); return }
        let name = snapshot.catalog.first { $0.id == timer.exerciseID }?.name ?? "Your next set"
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "\(name) · Open Gyma and dismiss rest to begin your next set."
        content.sound = nil
        content.userInfo = ["restKey": key]
        let request = UNNotificationRequest(identifier: identifier, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false))
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        do {
            try await center.add(request)
            scheduledKey = key
        } catch {
            scheduledKey = nil
            message = "Notification backup could not be scheduled. Workout vibration is still on."
        }
    }

    private func cancelNotification(removeDelivered: Bool = false) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        if removeDelivered { center.removeDeliveredNotifications(withIdentifiers: [identifier]) }
        scheduledKey = nil
    }
}

extension WatchRestNotifications: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let notificationID = notification.request.identifier
        let key = notification.request.content.userInfo["restKey"] as? String
        return await MainActor.run {
            guard notificationID == self.identifier else { return [.banner] }
            guard self.enabled, let key, let snapshot = self.snapshot, let timer = snapshot.restTimer,
                  key == RestAlertPolicy.key(timer: timer, storeID: snapshot.storeID),
                  !RestAlertPolicy.isEndingRest(timer, pending: self.pending, storeID: snapshot.storeID) else { return [] }
            if self.lastHapticKey == key { return [] }
            if self.isAppActive || self.workoutRunning {
                self.playDueHaptic(key: key)
                return []
            }
            // Inactive without a workout session: show a silent visual reminder.
            // A custom tap cannot be guaranteed without foreground/workout runtime.
            self.lastHapticKey = key
            UserDefaults.standard.set(key, forKey: "watchLastRestHapticV2")
            return [.banner]
        }
    }
}

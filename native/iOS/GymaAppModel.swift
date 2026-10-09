import Foundation
import SwiftUI
import Combine
import UserNotifications
import UniformTypeIdentifiers
import GymaCore

@MainActor
final class GymaAppModel: ObservableObject {
    @Published private(set) var state = GymaState()
    @Published private(set) var storageBlocked = false
    @Published private(set) var notificationEnabled = UserDefaults.standard.bool(forKey: "nativeRestNotificationsEnabled")
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var isRequestingNotifications = false

    let connectivity = WorkoutConnectivity.shared
    private let store: JSONFileStore
    let dataURL: URL
    private let notifications = RestNotifications()
    private var notificationTask: Task<Void, Never>?
    private var isConnectivityConfigured = false

    init() {
        dataURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gyma-native.json")
        store = JSONFileStore(url: dataURL)
        do {
            state = try store.load()
            try state.validate()
            configureConnectivity()
            synchronizeNotifications()
        } catch {
            storageBlocked = true
            errorMessage = "Saved data could not be opened. Your original file is untouched. Use Settings to export it or restore a valid backup. \(error.localizedDescription)"
        }
    }

    var completedWorkouts: [Workout] { state.workouts.filter { $0.end != nil }.sorted { $0.start > $1.start } }
    var sortedWorkouts: [Workout] { state.workouts.sorted { $0.start > $1.start } }
    func name(for exerciseID: String) -> String { state.catalog.first { $0.id == exerciseID }?.name ?? exerciseID }
    func workout(_ id: String) -> Workout? { state.workouts.first { $0.id == id } }

    private func configureConnectivity() {
        guard !isConnectivityConfigured else { return }
        isConnectivityConfigured = true
        connectivity.configurePhone(snapshotProvider: { [weak self] in
            CompanionSnapshot(state: self?.state ?? GymaState())
        }, commandHandler: { [weak self] command in
            guard let self, !self.storageBlocked else { throw AppError.storageUnavailable }
            var next = self.state
            let acknowledgement = GymaReducer.apply(command, to: &next)
            // A Watch receipt is part of the same transaction as its mutation.
            // Even a rejected command must be durable before acknowledging it.
            try self.persist(next)
            return acknowledgement
        })
    }

    private func persist(_ next: GymaState) throws {
        do {
            try next.validate()
            try store.save(next)
        } catch {
            errorMessage = "Changes could not be saved. Your last saved workout remains intact. \(error.localizedDescription)"
            throw error
        }
        state = next
        connectivity.publishSnapshot()
        synchronizeNotifications()
    }

    @discardableResult
    func update(_ mutation: (inout GymaState) throws -> Void) -> Bool {
        guard !storageBlocked else {
            errorMessage = "Restore a valid backup in Settings before making changes. The unreadable file has been preserved."
            return false
        }
        do {
            var next = state
            try mutation(&next)
            try persist(next)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func start(checkIn: SessionCheckIn, title: String) -> String? {
        let workout = Workout(shift: checkIn.shift, energy: checkIn.energy, checkIn: checkIn,
                              planTitle: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title)
        return update { try $0.startWorkout(workout) } ? workout.id : nil
    }

    func exportData() throws -> Data {
        // When opening failed, export the original bytes rather than empty state.
        if storageBlocked { return try Data(contentsOf: dataURL) }
        return try NativeBackup.encode(state)
    }

    func readImport(_ url: URL) throws -> GymaState {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let fileSize, fileSize <= 100 * 1024 * 1024 else { throw AppError.backupTooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let imported = try NativeBackup.decode(data)
        try imported.validate()
        return imported
    }

    @discardableResult
    func restore(_ imported: GymaState) -> Bool {
        do {
            try imported.validate()
            // Preserve the exact previous bytes, including an unreadable file.
            if FileManager.default.fileExists(atPath: dataURL.path) {
                let filename = "gyma-before-restore-\(UUID().uuidString).json"
                let backupURL = dataURL.deletingLastPathComponent().appendingPathComponent(filename)
                try FileManager.default.copyItem(at: dataURL, to: backupURL)
            }
            var next = imported
            let previousRevision = max(state.revision, imported.revision)
            guard previousRevision < Int.max else { throw AppError.invalidRevision }
            next.revision = previousRevision + 1
            next.storeID = UUID().uuidString
            next.commandReceipts = [:]
            next.commandPayloads = [:]
            try persist(next)
            storageBlocked = false
            configureConnectivity()
            connectivity.publishSnapshot()
            synchronizeNotifications()
            notice = "Backup restored. The previous file was kept in Gyma’s Documents folder."
            return true
        } catch {
            errorMessage = "The backup could not be restored. \(error.localizedDescription)"
            return false
        }
    }

    func setNotificationEnabled(_ enabled: Bool) {
        guard !isRequestingNotifications else { return }
        if !enabled {
            notificationEnabled = false
            UserDefaults.standard.set(false, forKey: "nativeRestNotificationsEnabled")
            synchronizeNotifications()
            return
        }
        isRequestingNotifications = true
        Task {
            defer { isRequestingNotifications = false }
            do {
                let allowed = try await notifications.requestPermission()
                notificationEnabled = allowed
                UserDefaults.standard.set(allowed, forKey: "nativeRestNotificationsEnabled")
                if !allowed { notice = "Rest alerts are off. You can allow notifications for Gyma in iPhone Settings." }
                synchronizeNotifications()
            } catch {
                errorMessage = "Notification permission could not be requested. \(error.localizedDescription)"
            }
        }
    }

    func refresh() {
        if storageBlocked {
            do {
                // Protected device data may become readable after an unlock.
                // Retrying never rewrites or replaces an unreadable file.
                let recovered = try store.load()
                try recovered.validate()
                state = recovered
                storageBlocked = false
                errorMessage = nil
                configureConnectivity()
                notice = "Saved data is available again."
            } catch {
                // Keep the existing recovery banner without repeating alerts.
                return
            }
        }
        connectivity.refresh()
        synchronizeNotifications()
    }

    private func synchronizeNotifications() {
        let previous = notificationTask
        let timer = state.restTimer
        let enabled = notificationEnabled && !storageBlocked
        let exerciseName = timer.map { self.name(for: $0.exerciseID) } ?? "Your next set"
        notificationTask = Task { [weak self] in
            // Serialize OS changes so a delayed schedule cannot resurrect a skipped rest.
            await previous?.value
            guard let self else { return }
            do { try await notifications.replace(timer: timer, exerciseName: exerciseName, enabled: enabled) }
            catch { errorMessage = "The workout is saved, but its rest alert could not be scheduled. \(error.localizedDescription)" }
        }
    }
}

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

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor
private final class RestNotifications: NSObject, UNUserNotificationCenterDelegate {
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

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
    @Published private(set) var hasCoachAPIKey = false
    @Published private(set) var coachRequestInFlight = false
    @Published private(set) var coachError: String?

    let connectivity = WorkoutConnectivity.shared
    private let store: JSONFileStore
    let dataURL: URL
    private let notifications = RestNotifications()
    private var notificationTask: Task<Void, Never>?
    private var isConnectivityConfigured = false
    private var coachTask: Task<Void, Never>?
    private var coachGeneration = UUID()

    init() {
        dataURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gyma-native.json")
        store = JSONFileStore(url: dataURL)
        refreshCoachCredentials()
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

    func refreshCoachCredentials() {
        do { hasCoachAPIKey = try CoachCredentials.load()?.isEmpty == false }
        catch {
            hasCoachAPIKey = false
            coachError = "Your OpenAI key could not be read. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func saveCoachAPIKey(_ key: String) -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        do {
            try CoachCredentials.save(key)
            hasCoachAPIKey = true
            coachError = nil
            return true
        } catch {
            errorMessage = "Your OpenAI key could not be saved. \(error.localizedDescription)"
            return false
        }
    }

    func removeCoachAPIKey() {
        do {
            try CoachCredentials.delete()
            cancelCoachRequest()
            hasCoachAPIKey = false
            coachError = nil
        } catch { errorMessage = "Your OpenAI key could not be removed. \(error.localizedDescription)" }
    }

    @discardableResult
    func beginCoachConversation(checkIn: SessionCheckIn, title: String) -> Bool {
        guard state.activeWorkout == nil else {
            coachError = "Finish your current workout before planning the next one."
            return false
        }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = title.isEmpty ? "Create a workout for today's check-in. Include sets, reps, weights and rest seconds for every exercise."
            : "Create a workout named \"\(title)\" for today's check-in. Include sets, reps, weights and rest seconds for every exercise."
        let conversation = CoachConversation(checkIn: checkIn, messages: [CoachMessage(role: .user, content: request)])
        cancelCoachRequest()
        guard update({ try $0.saveCoachConversation(conversation) }) else { return false }
        coachError = nil
        return true
    }

    @discardableResult
    func sendCoachMessage(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !coachRequestInFlight, state.activeWorkout == nil,
              var conversation = state.coachConversation, conversation.startedWorkoutID == nil else { return false }
        guard text.count <= 16_000 else {
            coachError = "Keep your message under 16,000 characters."
            return false
        }
        // A failed request leaves its user message saved. Sending the same text retries it.
        if conversation.messages.last?.role != .user || conversation.messages.last?.content != text {
            conversation.messages.append(CoachMessage(role: .user, content: text))
        }
        conversation.plan?.acceptedAt = nil
        guard update({ try $0.saveCoachConversation(conversation) }) else { return false }
        requestCoachReply()
        return true
    }

    func requestCoachReply() {
        guard !coachRequestInFlight, !storageBlocked, state.activeWorkout == nil,
              let conversation = state.coachConversation, conversation.startedWorkoutID == nil,
              conversation.messages.last?.role == .user else { return }
        let apiKey: String
        do {
            guard let saved = try CoachCredentials.load(), !saved.isEmpty else {
                hasCoachAPIKey = false
                coachError = "Add your OpenAI API key in Settings to talk with your coach."
                return
            }
            apiKey = saved
            hasCoachAPIKey = true
        } catch {
            coachError = "Your OpenAI key could not be read. \(error.localizedDescription)"
            return
        }
        coachError = nil
        coachRequestInFlight = true
        let generation = UUID()
        coachGeneration = generation
        let catalog = state.catalog
        let history = completedWorkouts
        coachTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if coachGeneration == generation {
                    coachRequestInFlight = false
                    coachTask = nil
                }
            }
            do {
                let reply = try await OpenAICoachService.reply(conversation: conversation, catalog: catalog, history: history, apiKey: apiKey)
                // A restore, replacement check-in, or edited conversation must never receive an old reply.
                guard !Task.isCancelled, coachGeneration == generation,
                      state.coachConversation == conversation, state.activeWorkout == nil else { return }
                var next = conversation
                next.messages.append(CoachMessage(role: .assistant, content: reply.message))
                next.plan = reply.plan
                next.plan?.acceptedAt = nil
                if !update({ try $0.saveCoachConversation(next) }) {
                    coachError = "The reply could not be saved. Your conversation and previous draft are still available. Try again."
                }
            } catch {
                guard !Task.isCancelled, coachGeneration == generation else { return }
                coachError = error.localizedDescription
            }
        }
    }

    private func cancelCoachRequest() {
        coachGeneration = UUID()
        coachTask?.cancel()
        coachTask = nil
        coachRequestInFlight = false
    }

    var canAcceptCoachPlan: Bool {
        !storageBlocked && !coachRequestInFlight && state.activeWorkout == nil
            && state.coachConversation?.startedWorkoutID == nil
            && state.coachConversation?.messages.last?.role == .assistant
            && state.coachConversation?.plan != nil
    }

    func acceptCoachPlan(_ planID: String) {
        guard canAcceptCoachPlan else { return }
        _ = update { try $0.acceptCoachPlan(planID: planID) }
    }

    func startCoachPlan(_ planID: String) -> String? {
        guard canAcceptCoachPlan else { return nil }
        var workoutID: String?
        let saved = update { workoutID = try $0.startAcceptedPlan(planID: planID) }
        return saved ? workoutID : nil
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
        cancelCoachRequest()
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
            coachError = nil
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

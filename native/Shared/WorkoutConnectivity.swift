import Combine
import Foundation
import GymaCore
import WatchConnectivity

/// A single session owner per process. The phone owns the workout; the watch owns
/// a durable outbox until the phone acknowledges its committed transaction.
@MainActor
final class WorkoutConnectivity: NSObject, ObservableObject {
    static let shared = WorkoutConnectivity()

    @Published private(set) var snapshot: CompanionSnapshot?
    @Published private(set) var pendingCommand: WatchCommand?
    @Published private(set) var lastAcknowledgement: CommandAcknowledgement?
    @Published private(set) var quarantinedCommand: WatchCommand?
    @Published private(set) var rejectedCommand: WatchCommand?
    @Published private(set) var connectionStatus = "Connecting…"
    @Published private(set) var isReachable = false
    @Published private(set) var lastError: String?

    private let session: WCSession?
    private var snapshotProvider: (() -> CompanionSnapshot)?
    private var commandHandler: ((WatchCommand) async throws -> CommandAcknowledgement)?
    private var snapshotObserver: ((CompanionSnapshot?) -> Void)?
    private var commandTail: Task<Void, Never>?
    private var interactiveCommandID: String?
    private var receivingCount = 0
    private var activationFailed = false
    private var journal = WatchJournal()
    private var journalUnavailable = false
    private let journalURL: URL

    var canSubmit: Bool {
        guard !journalUnavailable, pendingCommand == nil,
              let snapshot, snapshot.activeWorkout != nil else { return false }
        return snapshot.revision >= (lastAcknowledgement?.revision ?? 0)
    }

    private override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        journalURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GymaConnectivity", isDirectory: true)
            .appendingPathComponent("watch-journal.json")
        super.init()
        #if os(watchOS)
        do {
            if FileManager.default.fileExists(atPath: journalURL.path) {
                let data = try Data(contentsOf: journalURL)
                guard data.count <= 256 * 1024 else { throw ConnectivityError.invalidJournal }
                journal = try JSONDecoder().decode(WatchJournal.self, from: data)
            }
            snapshot = journal.snapshot
            pendingCommand = journal.pending
            lastAcknowledgement = journal.acknowledgement
            quarantinedCommand = journal.quarantined
            rejectedCommand = journal.rejected
        } catch {
            // Never overwrite a journal we could not read: it may contain an
            // unacknowledged set. Keep logging disabled until storage recovers.
            journalUnavailable = true
            lastError = "Saved watch data could not be read. Reopen the app to retry."
        }
        #endif
        if session == nil { connectionStatus = "Watch connection unavailable" }
    }

    /// The handler must save the changed state and command receipt atomically
    /// before returning. Throw on save failure; a transient error is not an ack.
    func configurePhone(
        snapshotProvider: @escaping () -> CompanionSnapshot,
        commandHandler: @escaping (WatchCommand) async throws -> CommandAcknowledgement
    ) {
        self.snapshotProvider = snapshotProvider
        self.commandHandler = commandHandler
        activate()
    }

    func configureWatch(onSnapshot: @escaping (CompanionSnapshot?) -> Void) {
        snapshotObserver = onSnapshot
        onSnapshot(snapshot)
        activate()
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        #if os(iOS)
        // Inactive means a watch switch is still draining. Wait for
        // sessionDidDeactivate before activating the replacement watch.
        if session.activationState == .inactive { updateConnectionState(); return }
        #endif
        if session.activationState != .activated { activationFailed = false; session.activate() }
        else { sessionReady() }
    }

    func refresh() {
        guard let session, session.activationState == .activated else {
            activate()
            return
        }
        updateConnectionState()
        #if os(iOS)
        publishSnapshot()
        #else
        sendPendingCommand()
        if session.isReachable {
            session.sendMessage(Wire.request, replyHandler: { [weak self] reply in
                let packet = SessionPacket(reply)
                Task { @MainActor in await self?.receive(packet.dictionary) }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in self?.updateConnectionState() }
            })
        } else {
            queueOnce(Wire.request, key: "request")
        }
        #endif
    }

    func publishSnapshot() {
        guard let value = snapshotProvider?() else { return }
        snapshot = value
        guard canTransfer, let session else { return }
        do {
            let packet = try Wire.encode(value, kind: .snapshot)
            try session.updateApplicationContext(packet)
            if session.isReachable {
                session.sendMessage(packet, replyHandler: { _ in }, errorHandler: { _ in
                    // The latest application context remains available offline.
                })
            }
        }
        catch { lastError = "Could not sync the workout: \(error.localizedDescription)" }
    }

    /// Returns only after the command has been written to the local outbox.
    /// UI must still display it as pending until a phone receipt arrives.
    func submit(_ action: WatchAction, expectedWorkoutID: String? = nil, basedOnRevision: Int? = nil) throws {
        guard canSubmit, let snapshot, let workout = snapshot.activeWorkout else {
            throw ConnectivityError.waitForPhone
        }
        if let expectedWorkoutID, expectedWorkoutID != workout.id { throw ConnectivityError.workoutChanged }
        if let basedOnRevision, basedOnRevision != snapshot.revision { throw ConnectivityError.workoutChanged }
        let command = WatchCommand(storeID: snapshot.storeID, workoutID: workout.id,
                                   basedOnRevision: snapshot.revision, action: action)
        _ = try Wire.encode(command, kind: .command)
        var updated = journal
        updated.pending = command
        updated.acknowledgement = nil
        updated.rejected = nil
        try saveJournal(updated)
        journal = updated
        pendingCommand = command
        lastAcknowledgement = nil
        rejectedCommand = nil
        lastError = nil
        sendPendingCommand()
    }

    func dismissError() { lastError = nil }

    #if os(watchOS)
    /// SwiftUI keeps its watchConnectivity background task open until activation
    /// and all incoming delegate work are finished. Cancellation is owned by OS.
    func receiveBackgroundTransfers() async {
        activate()
        var quietChecks = 0
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if activationFailed { return }
            guard let session else { return }
            if session.activationState == .activated && !session.hasContentPending && receivingCount == 0 {
                quietChecks += 1
                if quietChecks >= 2 { return }
            } else { quietChecks = 0 }
        }
    }
    #endif

    private var canTransfer: Bool {
        guard let session, session.activationState == .activated else { return false }
        #if os(iOS)
        return session.isPaired && session.isWatchAppInstalled
        #else
        return session.isCompanionAppInstalled
        #endif
    }

    private func updateConnectionState() {
        guard let session else { return }
        isReachable = session.activationState == .activated && session.isReachable
        guard session.activationState == .activated else {
            connectionStatus = "Connecting…"
            return
        }
        #if os(iOS)
        if !session.isPaired { connectionStatus = "Pair an Apple Watch in the Watch app" }
        else if !session.isWatchAppInstalled { connectionStatus = "Install Gyma on your Apple Watch" }
        else { connectionStatus = isReachable ? "Apple Watch connected" : "Apple Watch syncs when available" }
        #else
        if !session.isCompanionAppInstalled { connectionStatus = "Install Gyma on your paired iPhone" }
        else { connectionStatus = isReachable ? "iPhone connected" : "iPhone unavailable · saved data" }
        #endif
    }

    private func sessionReady() {
        updateConnectionState()
        #if os(iOS)
        publishSnapshot()
        #else
        if let session, !session.receivedApplicationContext.isEmpty {
            Task { await receive(session.receivedApplicationContext) }
        }
        refresh()
        #endif
    }

    private func queueOnce(_ packet: [String: Any], key: String) {
        guard canTransfer, let session else { return }
        guard !session.outstandingUserInfoTransfers.contains(where: { $0.userInfo["key"] as? String == key }) else { return }
        var packet = packet
        packet["key"] = key
        session.transferUserInfo(packet)
    }

    private func sendPendingCommand() {
        guard let command = pendingCommand, canTransfer, let session else { return }
        do {
            let packet = try Wire.encode(command, kind: .command)
            queueOnce(packet, key: "command:\(command.id)")
            guard session.isReachable, interactiveCommandID != command.id else { return }
            interactiveCommandID = command.id
            session.sendMessage(packet, replyHandler: { [weak self] reply in
                let packet = SessionPacket(reply)
                Task { @MainActor in
                    self?.interactiveCommandID = nil
                    await self?.receive(packet.dictionary)
                }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in
                    self?.interactiveCommandID = nil
                    self?.updateConnectionState()
                    // WCSession's queued background transfer remains outstanding.
                }
            })
        } catch { lastError = error.localizedDescription }
    }

    private func receive(_ packet: [String: Any], reply: (([String: Any]) -> Void)? = nil) async {
        receivingCount += 1
        defer { receivingCount -= 1 }
        do {
            let kind = try Wire.kind(packet)
            switch kind {
            case .request:
                #if os(iOS)
                guard let value = snapshotProvider?() else { throw ConnectivityError.phoneNotReady }
                publishSnapshot()
                reply?(try Wire.encode(value, kind: .snapshot))
                #else
                throw ConnectivityError.unsupportedMessage
                #endif
            case .command:
                #if os(iOS)
                let command: WatchCommand = try Wire.decode(packet)
                let result = try await processOnPhone(command)
                let response = try Wire.encode(result, kind: .acknowledgement)
                queueOnce(response, key: "ack:\(command.id)")
                publishSnapshot()
                reply?(response)
                #else
                throw ConnectivityError.unsupportedMessage
                #endif
            case .snapshot:
                #if os(watchOS)
                let value: CompanionSnapshot = try Wire.decode(packet)
                try acceptSnapshot(value)
                #endif
                reply?(Wire.received)
            case .acknowledgement:
                #if os(watchOS)
                let result: AcknowledgedState = try Wire.decode(packet)
                try acceptAcknowledgement(result)
                #endif
                reply?(Wire.received)
            case .error:
                lastError = (packet["message"] as? String).map { String($0.prefix(300)) } ?? "Sync could not finish. Retry when your iPhone is available."
                reply?(Wire.received)
            case .received:
                break
            }
        } catch {
            lastError = error.localizedDescription
            reply?(Wire.failure(error.localizedDescription))
        }
    }

    private func processOnPhone(_ command: WatchCommand) async throws -> AcknowledgedState {
        guard let commandHandler, let snapshotProvider else { throw ConnectivityError.phoneNotReady }
        let previous = commandTail
        let task = Task { @MainActor in
            await previous?.value
            let acknowledgement = try await commandHandler(command)
            return AcknowledgedState(acknowledgement: acknowledgement, snapshot: snapshotProvider())
        }
        commandTail = Task { _ = try? await task.value }
        return try await task.value
    }

    private func newerSnapshot(_ incoming: CompanionSnapshot) -> CompanionSnapshot {
        guard let current = snapshot else { return incoming }
        if incoming.storeID != current.storeID {
            guard !journal.retiredStoreIDs.contains(incoming.storeID),
                  incoming.generatedAt >= current.generatedAt else { return current }
            return incoming
        }
        if incoming.revision < current.revision { return current }
        if incoming.revision == current.revision && incoming.generatedAt < current.generatedAt { return current }
        return incoming
    }

    private func acceptSnapshot(_ incoming: CompanionSnapshot) throws {
        guard incoming.revision >= 0, !incoming.storeID.isEmpty else { throw ConnectivityError.invalidPayload }
        try incoming.activeWorkout?.validate()
        let value = newerSnapshot(incoming)
        let updated = journalUpdatingSnapshot(value)
        try saveJournal(updated)
        journal = updated
        snapshot = value
        pendingCommand = updated.pending
        lastAcknowledgement = updated.acknowledgement
        quarantinedCommand = updated.quarantined
        rejectedCommand = updated.rejected
        snapshotObserver?(value)
    }

    private func acceptAcknowledgement(_ result: AcknowledgedState) throws {
        let acknowledgement = result.acknowledgement
        let value = newerSnapshot(result.snapshot)
        // A delayed receipt from an old phone store must not affect the current
        // store, including the latest rejection or pending command.
        guard value.storeID == result.snapshot.storeID else { return }
        guard value.revision >= acknowledgement.revision else { throw ConnectivityError.invalidPayload }
        var updated = journalUpdatingSnapshot(value)
        let matchesPending = updated.pending?.id == acknowledgement.commandID
        if matchesPending {
            updated.rejected = acknowledgement.status == .rejected ? updated.pending : nil
            updated.pending = nil
            updated.acknowledgement = acknowledgement
        }
        try saveJournal(updated)
        journal = updated
        snapshot = value
        pendingCommand = updated.pending
        lastAcknowledgement = updated.acknowledgement
        quarantinedCommand = updated.quarantined
        rejectedCommand = updated.rejected
        if matchesPending {
            pendingCommand = nil
            lastAcknowledgement = acknowledgement
            lastError = nil
            session?.outstandingUserInfoTransfers
                .filter { $0.userInfo["key"] as? String == "command:\(acknowledgement.commandID)" }
                .forEach { $0.cancel() }
        }
        snapshotObserver?(value)
    }

    private func journalUpdatingSnapshot(_ value: CompanionSnapshot) -> WatchJournal {
        var updated = journal
        if let previous = journal.snapshot, previous.storeID != value.storeID {
            updated.retiredStoreIDs.append(previous.storeID)
            updated.acknowledgement = nil
            updated.rejected = nil
            if let pending = updated.pending, pending.storeID != value.storeID {
                // Retain the user's original values for recovery, but never
                // replay an old command into a replacement phone data store.
                updated.quarantined = pending
                updated.pending = nil
            }
        }
        updated.snapshot = value
        return updated
    }

    private func saveJournal(_ updated: WatchJournal) throws {
        guard !journalUnavailable else { throw ConnectivityError.invalidJournal }
        try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(updated)
        guard data.count <= 256 * 1024 else { throw ConnectivityError.payloadTooLarge }
        try data.write(to: journalURL, options: .atomic)
    }
}

extension WorkoutConnectivity: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.activationFailed = error != nil
            if let error { self.lastError = error.localizedDescription }
            if activationState == .activated { self.sessionReady() }
            else { self.updateConnectionState() }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let packet = SessionPacket(applicationContext)
        Task { @MainActor in await self.receive(packet.dictionary) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let packet = SessionPacket(userInfo)
        Task { @MainActor in await self.receive(packet.dictionary) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let packet = SessionPacket(message)
        let reply = SessionReply(replyHandler)
        Task { @MainActor in
            await self.receive(packet.dictionary, reply: { reply.send(SessionPacket($0)) })
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let packet = SessionPacket(message)
        Task { @MainActor in await self.receive(packet.dictionary) }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            self.lastError = "Sync is pending: \(error.localizedDescription)"
            self.updateConnectionState()
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in self.updateConnectionState() }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate to connect to the newly selected paired Apple Watch.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refresh() }
    }
    #endif
}

private struct WatchJournal: Codable {
    var snapshot: CompanionSnapshot?
    var pending: WatchCommand?
    var acknowledgement: CommandAcknowledgement?
    var quarantined: WatchCommand?
    var rejected: WatchCommand?
    var retiredStoreIDs: [String] = []
}

private struct AcknowledgedState: Codable {
    let acknowledgement: CommandAcknowledgement
    let snapshot: CompanionSnapshot
}

/// Copy only the protocol's immutable, Sendable values at the Objective-C
/// delegate boundary. No heterogeneous dictionary crosses into the main actor.
private struct SessionPacket: Sendable {
    let version: Int?
    let kind: String?
    let payload: Data?
    let message: String?

    init(_ dictionary: [String: Any]) {
        version = dictionary["version"] as? Int
        kind = dictionary["kind"] as? String
        payload = dictionary["payload"] as? Data
        message = dictionary["message"] as? String
    }

    var dictionary: [String: Any] {
        var value: [String: Any] = [:]
        if let version { value["version"] = version }
        if let kind { value["kind"] = kind }
        if let payload { value["payload"] = payload }
        if let message { value["message"] = message }
        return value
    }
}

/// WCSession supplies an escaping reply callback for asynchronous responses.
/// The SDK callback lacks a Sendable annotation; this narrow bridge transfers
/// it to the processing actor and uses a lock to guarantee exactly one call.
/// Every mutable field is protected, and the outgoing dictionary is constructed
/// at invocation rather than shared across threads.
private final class SessionReply: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (([String: Any]) -> Void)?

    init(_ callback: @escaping ([String: Any]) -> Void) {
        self.callback = callback
    }

    func send(_ packet: SessionPacket) {
        lock.lock()
        let reply = callback
        callback = nil
        lock.unlock()
        reply?(packet.dictionary)
    }
}

private enum Wire {
    enum Kind: String { case request, snapshot, command, acknowledgement, error, received }
    static var request: [String: Any] { ["version": 1, "kind": "request"] }
    static var received: [String: Any] { ["version": 1, "kind": "received"] }

    static func kind(_ packet: [String: Any]) throws -> Kind {
        guard packet["version"] as? Int == 1, let name = packet["kind"] as? String,
              let kind = Kind(rawValue: name) else { throw ConnectivityError.unsupportedMessage }
        return kind
    }

    static func encode<T: Encodable>(_ value: T, kind: Kind) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let limit = kind == .command ? 8 * 1024 : 60 * 1024
        guard data.count <= limit else { throw ConnectivityError.payloadTooLarge }
        return ["version": 1, "kind": kind.rawValue, "payload": data]
    }

    static func decode<T: Decodable>(_ packet: [String: Any]) throws -> T {
        let kind = try kind(packet)
        let limit = kind == .command ? 8 * 1024 : 60 * 1024
        guard let data = packet["payload"] as? Data, data.count <= limit else { throw ConnectivityError.invalidPayload }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func failure(_ message: String) -> [String: Any] {
        ["version": 1, "kind": "error", "message": String(message.prefix(300))]
    }
}

private enum ConnectivityError: LocalizedError {
    case invalidJournal, waitForPhone, phoneNotReady, unsupportedMessage, invalidPayload, payloadTooLarge, workoutChanged
    var errorDescription: String? {
        switch self {
        case .invalidJournal: return "Watch storage is unavailable. Your pending log is being preserved. Reopen the app to retry."
        case .waitForPhone: return "Wait for the current log to be confirmed by your iPhone."
        case .phoneNotReady: return "Open Gyma on your iPhone to finish syncing."
        case .unsupportedMessage: return "Update Gyma on both devices to sync."
        case .invalidPayload: return "The received workout could not be read. Refresh from your iPhone."
        case .payloadTooLarge: return "This workout is too large to sync to Apple Watch. Continue on your iPhone."
        case .workoutChanged: return "The workout changed on your iPhone. Review the latest workout and try again."
        }
    }
}

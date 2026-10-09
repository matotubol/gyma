import Foundation

public enum WatchAction: Codable, Sendable, Equatable {
    case logSet(exerciseID: String, set: WorkSet)
    case skipRest(timerID: String)
    case extendRest(timerID: String, seconds: Int)
    case finishWorkout
}
public struct WatchCommand: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var storeID: String?
    public var workoutID: String
    public var basedOnRevision: Int?
    public var createdAt: Date
    public var action: WatchAction
    public init(id: String = UUID().uuidString, storeID: String? = nil, workoutID: String, basedOnRevision: Int? = nil, createdAt: Date = Date(), action: WatchAction) {
        self.id = id; self.storeID = storeID; self.workoutID = workoutID; self.basedOnRevision = basedOnRevision; self.createdAt = createdAt; self.action = action
    }
}
public enum CommandStatus: String, Codable, Sendable { case applied, duplicate, rejected }
public struct CommandAcknowledgement: Codable, Sendable, Equatable {
    public var commandID: String
    public var status: CommandStatus
    public var revision: Int
    public var message: String?
    public var originalStatus: CommandStatus?
    public init(commandID: String, status: CommandStatus, revision: Int, message: String? = nil, originalStatus: CommandStatus? = nil) {
        self.commandID = commandID; self.status = status; self.revision = revision; self.message = message; self.originalStatus = originalStatus
    }
}

public struct CompanionSnapshot: Codable, Sendable, Equatable {
    public var storeID: String
    public var revision: Int
    public var generatedAt: Date
    public var activeWorkout: Workout?
    public var catalog: [ExerciseDefinition]
    public var restTimer: RestTimer?
    public var isTruncated: Bool
    /// Distinguishes a bounded set window from omitted exercises when deciding whether the session is complete.
    public var totalExerciseCount: Int?
    public init(state: GymaState, now: Date = Date()) {
        storeID = state.storeID; revision = state.revision; generatedAt = now; restTimer = state.restTimer; isTruncated = false
        totalExerciseCount = state.activeWorkout?.exercises.count
        var workout = state.activeWorkout
        if var current = workout {
            // Sync only the active session and a bounded recent set window. Phone keeps full history.
            isTruncated = current.exercises.count > 12 || current.exercises.contains { $0.sets.count > 20 }
            current.exercises = Array(current.exercises.prefix(12)).map { item in
                var item = item; item.snapshotWorkingSetCount = item.workingSetCount; item.sets = Array(item.sets.suffix(20))
                if var target = item.target { target.reason = String(target.reason.prefix(200)); item.target = target }
                return item
            }
            current.planTitle = current.planTitle.map { String($0.prefix(160)) }
            // Notes and other sensitive history are not needed for watch controls.
            current.checkIn = nil
            if let rest = current.restHistory?.last,
               current.exercises.contains(where: { $0.exerciseID == rest.exerciseID && $0.sets.contains(where: { $0.id == rest.sourceSetID }) }) {
                current.restHistory = [rest]
            } else { current.restHistory = nil }
            workout = current
        }
        activeWorkout = workout
        catalog = (workout?.exercises ?? []).map { entry in
            var definition = state.exercise(entry.exerciseID); definition.name = String(definition.name.prefix(200)); return definition
        }
        // Character limits alone do not bound UTF-8 size. Leave headroom below WCSession's message limit.
        let encoder = JSONEncoder()
        while (try? encoder.encode(self).count).map({ $0 > 48 * 1024 }) ?? true {
            guard var current = activeWorkout, !current.exercises.isEmpty else { break }
            isTruncated = true
            if let index = current.exercises.indices.max(by: { current.exercises[$0].sets.count < current.exercises[$1].sets.count }), !current.exercises[index].sets.isEmpty {
                current.exercises[index].sets.removeFirst()
            } else {
                current.exercises.removeLast(); catalog.removeLast()
            }
            if let rest = current.restHistory?.last,
               !current.exercises.contains(where: { $0.exerciseID == rest.exerciseID && $0.sets.contains(where: { $0.id == rest.sourceSetID }) }) { current.restHistory = nil }
            activeWorkout = current
        }
    }
}

public enum GymaReducer {
    /// Caller must persist the resulting state atomically BEFORE acknowledging either acceptance or rejection.
    public static func apply(_ command: WatchCommand, to state: inout GymaState, now: Date = Date()) -> CommandAcknowledgement {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let payload = try? encoder.encode(command), !command.id.isEmpty, command.id.count <= 200, payload.count <= 16_384 else {
            return .init(commandID: command.id, status: .rejected, revision: state.revision, message: "Invalid or oversized command.")
        }
        if let receipt = state.commandReceipts[command.id] {
            guard state.commandPayloads[command.id] == payload else { return .init(commandID: command.id, status: .rejected, revision: state.revision, message: "Command identity was reused for different data.") }
            if receipt.status == .rejected { return receipt }
            return .init(commandID: receipt.commandID, status: .duplicate, revision: receipt.revision, message: receipt.message, originalStatus: .applied)
        }
        // Never evict event IDs: a background replay must not become a new mutation.
        guard state.commandReceipts.count < 50_000 else { return .init(commandID: command.id, status: .rejected, revision: state.revision, message: "Command receipt storage is full. Continue on iPhone.") }
        var next = state
        let receipt: CommandAcknowledgement
        do {
            guard command.storeID == state.storeID else { throw GymaError.stale("Phone data was replaced. Refresh before sending another command.") }
            guard command.workoutID == state.activeWorkout?.id else { throw GymaError.stale("Workout changed on iPhone. Refresh before trying again.") }
            if let revision = command.basedOnRevision, revision != state.revision { throw GymaError.stale("Workout changed on iPhone. Review the latest session and try again.") }
            let age = now.timeIntervalSince(command.createdAt)
            guard age.isFinite, age >= -300, age <= 86400 else { throw GymaError.stale("This command is too old or the watch clock differs significantly. Refresh before trying again.") }
            switch command.action {
            case .logSet(let exerciseID, let set):
                // Queued delivery must not restart a rest interval that already elapsed on watch.
                try next.addSet(set, exerciseID: exerciseID, workoutID: command.workoutID, now: min(command.createdAt, now))
            case .skipRest(let timerID): try next.skipRest(timerID: timerID, now: min(command.createdAt, now))
            case .extendRest(let timerID, let seconds): try next.extendRest(timerID: timerID, seconds: seconds, now: now)
            case .finishWorkout: try next.finishWorkout(command.workoutID, at: min(command.createdAt, now))
            }
            try next.validate()
            receipt = .init(commandID: command.id, status: .applied, revision: next.revision)
            state = next
        } catch {
            receipt = .init(commandID: command.id, status: .rejected, revision: state.revision, message: error.localizedDescription)
        }
        state.commandReceipts[command.id] = receipt; state.commandPayloads[command.id] = payload
        return receipt
    }
}

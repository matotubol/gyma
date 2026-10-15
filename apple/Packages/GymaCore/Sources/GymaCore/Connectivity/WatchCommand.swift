import Foundation

public enum WatchAction: Codable, Sendable, Equatable {
    case startAcceptedPlan(planID: String, readiness: WorkoutReadiness)
    case logSet(exerciseID: String, set: WorkSet)
    case selectExercise(exerciseID: String)
    case skipSet(exerciseID: String)
    case skipExercise(exerciseID: String)
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

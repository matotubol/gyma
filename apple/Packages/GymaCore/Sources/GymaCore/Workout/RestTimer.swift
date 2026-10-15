import Foundation

public struct CompletedRest: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var exerciseID: String
    public var sourceSetID: String
    public var plannedSeconds: Int
    public var startedAt: Date
    public var endedAt: Date
    public init(id: String, exerciseID: String, sourceSetID: String, plannedSeconds: Int, startedAt: Date, endedAt: Date) {
        self.id = id; self.exerciseID = exerciseID; self.sourceSetID = sourceSetID; self.plannedSeconds = plannedSeconds; self.startedAt = startedAt; self.endedAt = endedAt
    }
    public var elapsedSeconds: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
    public func validate() throws {
        let supportedDates = -2_208_988_800.0...4_102_444_800.0
        guard [id, exerciseID, sourceSetID].allSatisfy({ !$0.isEmpty && $0.count <= 200 }),
              (0...86400).contains(plannedSeconds), supportedDates.contains(startedAt.timeIntervalSince1970),
              supportedDates.contains(endedAt.timeIntervalSince1970), endedAt >= startedAt else {
            throw GymaError.invalid("Invalid completed rest interval.")
        }
    }
}

public struct RestTimer: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var workoutID: String
    public var exerciseID: String
    public var startedAt: Date
    public var endsAt: Date
    public var sourceSetID: String
    /// Original plan duration, retained when the user extends the countdown.
    public var plannedSeconds: Int?
    public init(id: String = UUID().uuidString, workoutID: String, exerciseID: String, startedAt: Date, endsAt: Date, sourceSetID: String, plannedSeconds: Int? = nil) {
        self.id = id; self.workoutID = workoutID; self.exerciseID = exerciseID; self.startedAt = startedAt; self.endsAt = endsAt; self.sourceSetID = sourceSetID; self.plannedSeconds = plannedSeconds
    }
    public func remaining(at now: Date = Date()) -> TimeInterval {
        let seconds = endsAt.timeIntervalSince(now)
        // Keep watchOS arm64_32 countdown arithmetic safe even when a restored device clock differs.
        guard seconds.isFinite else { return 0 }
        return min(86400, max(0, seconds))
    }
}

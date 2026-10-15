import Foundation

/// Feedback explains deviations without changing the recorded training or the athlete profile.
public struct WorkoutFeedback: Codable, Sendable, Equatable, Identifiable {
    public var workoutID: String
    public var recordedAt: Date
    public var note: String
    public var painNote: String
    public var id: String { workoutID }
    public init(workoutID: String, recordedAt: Date = Date(), note: String = "", painNote: String = "") {
        self.workoutID = workoutID; self.recordedAt = recordedAt; self.note = note; self.painNote = painNote
    }
    public func validate() throws {
        guard !workoutID.isEmpty, workoutID.count <= 200, note.count <= 2000, painNote.count <= 2000,
              (-2_208_988_800.0...4_102_444_800.0).contains(recordedAt.timeIntervalSince1970) else {
            throw GymaError.invalid("Keep workout feedback under 2,000 characters per field.")
        }
    }
}

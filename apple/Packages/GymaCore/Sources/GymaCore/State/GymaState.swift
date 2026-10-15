import Foundation

public struct GymaState: Codable, Sendable, Equatable {
    public var schemaVersion = 1
    public var storeID = UUID().uuidString
    public var revision = 0
    public var workouts: [Workout] = []
    public var deletedWorkouts: [Workout] = []
    public var customExercises: [ExerciseDefinition] = []
    /// Built-in edits retain stable exercise identities in saved workouts and programs.
    public var exerciseOverrides: [ExerciseDefinition]?
    /// Removed library entries remain resolvable in historical training and backups.
    public var hiddenExerciseIDs: [String]?
    public var restEnabled = true
    public var restTimer: RestTimer?
    public var coachConversation: CoachConversation?
    public var athleteProfile: AthleteProfile?
    public var trainingProgram: TrainingProgram?
    public var trainingCalendar: TrainingCalendarPlan?
    public var trainingCalendarHistory: [TrainingCalendarPlan]?
    public var programHistory: [TrainingProgram]?
    public var workoutReviews: [WorkoutReview]?
    public var workoutFeedback: [WorkoutFeedback]?
    public var commandReceipts: [String: CommandAcknowledgement] = [:]
    public var commandPayloads: [String: Data] = [:]

    public init() {}
}

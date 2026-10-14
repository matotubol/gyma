import Foundation

/// An explicit prescription for one date. Program rotation continues to follow actual training.
public struct CalendarWorkoutOverride: Codable, Sendable, Equatable {
    public var dayOffset: Int
    public var exercises: [WorkoutExercise]
    public init(dayOffset: Int, exercises: [WorkoutExercise]) {
        self.dayOffset = dayOffset; self.exercises = exercises
    }
}

public extension TrainingCalendarPlan {
    func workoutOverride(on date: Date) -> CalendarWorkoutOverride? {
        guard let offset = dayOffset(for: date) else { return nil }
        return workoutOverrides?.first { $0.dayOffset == offset }
    }

    func validateWorkoutOverrides(catalog: [ExerciseDefinition]) throws {
        for override in workoutOverrides ?? [] {
            let plan = WorkoutPlan(title: "Single-day workout", exercises: override.exercises,
                                   checkIn: .init(shift: .off, energy: .good), createdAt: startDate)
            try plan.validate(catalog: catalog)
            guard override.exercises.allSatisfy({ $0.skippedSetCount == 0 && $0.skippedRemainingAt == nil }),
                  override.exercises.allSatisfy({ entry in
                      catalog.first(where: { $0.id == entry.exerciseID })?.trainingMetadata?.measurement != .seconds
                  }) else { throw GymaError.invalid("A day's plan needs repetition-based exercises without recorded or skipped sets.") }
        }
    }
}

public extension GymaState {
    /// Saves the entire ordered prescription for this date, leaving the recurring program untouched.
    mutating func setCalendarWorkout(on date: Date, exercises: [WorkoutExercise]?, now: Date = Date()) throws {
        guard activeWorkout == nil, var plan = trainingCalendar,
              let offset = plan.dayOffset(for: date), plan.isTrainingDay(on: date),
              plan.calendar.startOfDay(for: date) >= plan.calendar.startOfDay(for: now),
              !workouts.contains(where: { plan.calendar.isDate($0.start, inSameDayAs: date) }),
              trainingProgram != nil else {
            throw GymaError.invalid("Edit an upcoming training day with a saved program, before starting its workout.")
        }
        if let exercises {
            let available = Set(availableExercises.map(\.id))
            guard exercises.allSatisfy({ available.contains($0.exerciseID) }) else {
                throw GymaError.invalid("Choose exercises currently available in your library.")
            }
            try CoachingConstraints.validate(exercises: exercises, profile: athleteProfile, catalog: catalog)
        }
        var overrides = plan.workoutOverrides ?? []
        overrides.removeAll { $0.dayOffset == offset }
        if let exercises { overrides.append(.init(dayOffset: offset, exercises: exercises)) }
        plan.workoutOverrides = overrides.isEmpty ? nil : overrides.sorted { $0.dayOffset < $1.dayOffset }
        try plan.validate()
        try plan.validateWorkoutOverrides(catalog: catalog)
        var next = self
        try next.saveTrainingCalendar(plan, now: now)
        try next.validate()
        self = next
    }
}

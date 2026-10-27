import Foundation

// Port of gym-web/web/src/workout-progress.ts plus the small session queries the runner shares.

public extension WorkoutSession {
    var activeSet: PerformedSet? { sets.first { $0.status == .active } }

    func exercise(at position: Int) -> SessionExercise? { exercises.first { $0.position == position } }

    func completedSets(at position: Int) -> [PerformedSet] {
        sets.filter { $0.exercisePosition == position && $0.status == .completed }
    }

    /// Recorded (active or completed) sets of an exercise, ignoring cancelled starts.
    func recordedSets(at position: Int) -> [PerformedSet] {
        sets.filter { $0.exercisePosition == position && $0.status != .cancelled }
    }

    func isDone(_ exercise: SessionExercise) -> Bool {
        completedSets(at: exercise.position).count >= exercise.plannedSets
    }

    /// The lowest set number not yet used by a recorded set.
    func nextSetNumber(at position: Int) -> Int {
        let used = Set(recordedSets(at: position).map(\.setNumber))
        return (1...100).first { !used.contains($0) } ?? 100
    }

    func history(for exerciseId: String) -> ExerciseHistory? { history.first { $0.exerciseId == exerciseId } }

    var plannedSetCount: Int { exercises.reduce(0) { $0 + $1.plannedSets } }
    var completedSetCount: Int { sets.filter { $0.status == .completed }.count }

    /// An actual running set always owns focus. Finishing an exercise returns to the
    /// chooser rather than opening another exercise without the user's selection.
    func nextFocus(current: Int?, preferred: Int? = nil) -> Int? {
        if let active = activeSet { return active.exercisePosition }
        if let preferred, exercise(at: preferred) != nil { return preferred }
        if let current, let exercise = exercise(at: current), !isDone(exercise) { return current }
        return nil
    }
}

private let isoFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()
private let isoPlain = ISO8601DateFormatter()

/// Parses the Worker's UTC timestamps, e.g. `2026-10-27T17:00:00.123Z`.
public func parseTimestamp(_ value: String) -> Date? {
    isoFractional.date(from: value) ?? isoPlain.date(from: value)
}

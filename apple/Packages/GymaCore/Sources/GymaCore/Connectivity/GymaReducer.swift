import Foundation

public enum GymaReducer {
    /// Caller must persist the resulting state atomically BEFORE acknowledging either acceptance or rejection.
    public static func apply(_ command: WatchCommand, to state: inout GymaState, now: Date = Date(), calendar: Calendar = .current) -> CommandAcknowledgement {
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
            if case .startAcceptedPlan = command.action {
                guard state.activeWorkout == nil else { throw GymaError.stale("A workout is already active. Resume it instead.") }
                guard command.basedOnRevision != nil else { throw GymaError.stale("Refresh today's accepted plan before starting.") }
            } else {
                guard command.workoutID == state.activeWorkout?.id else { throw GymaError.stale("Workout changed on iPhone. Refresh before trying again.") }
            }
            if let revision = command.basedOnRevision, revision != state.revision { throw GymaError.stale("Workout changed on iPhone. Review the latest session and try again.") }
            let age = now.timeIntervalSince(command.createdAt)
            guard age.isFinite, age >= -300, age <= 86400 else { throw GymaError.stale("This command is too old or the watch clock differs significantly. Refresh before trying again.") }
            switch command.action {
            case .selectExercise, .skipSet, .skipExercise:
                guard command.basedOnRevision != nil else { throw GymaError.stale("Refresh this workout before changing its remaining sets.") }
            default: break
            }
            switch command.action {
            case .startAcceptedPlan(let planID, let readiness):
                guard command.workoutID == planID else { throw GymaError.invalid("The start command does not match its accepted plan.") }
                guard age <= 300, state.planningCalendar(fallback: calendar).isDate(command.createdAt, inSameDayAs: now),
                      readiness.recordedAt <= command.createdAt,
                      command.createdAt.timeIntervalSince(readiness.recordedAt) <= 300 else {
                    throw GymaError.stale("The start request expired. Refresh today's plan and check your readiness again.")
                }
                if state.readyProgramPlan(now: now, calendar: calendar)?.id == planID {
                    try next.startReadyProgramPlan(planID: planID, readiness: readiness, now: now, calendar: calendar)
                } else {
                    try next.startAcceptedPlan(planID: planID, readiness: readiness, now: now, calendar: calendar)
                }
            case .logSet(let exerciseID, let set):
                // Queued delivery must not restart a rest interval that already elapsed on watch.
                try next.addSet(set, exerciseID: exerciseID, workoutID: command.workoutID, now: min(command.createdAt, now))
            case .selectExercise(let exerciseID):
                try next.selectExercise(exerciseID, workoutID: command.workoutID, now: min(command.createdAt, now))
            case .skipSet(let exerciseID):
                try next.skipSet(exerciseID: exerciseID, workoutID: command.workoutID, now: min(command.createdAt, now))
            case .skipExercise(let exerciseID):
                try next.skipExercise(exerciseID: exerciseID, workoutID: command.workoutID, now: min(command.createdAt, now))
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

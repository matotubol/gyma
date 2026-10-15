import Foundation
import GymaCore

extension GymaAppModel {
    var workoutCoachRequestWorkoutID: String? { workoutCoachSession.requestWorkoutID }

    func workoutCoachError(for workoutID: String) -> String? { workoutCoachSession.errors[workoutID] }

    @discardableResult
    func sendWorkoutCoachMessage(_ text: String, workoutID: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, workoutCoachSession.requestWorkoutID == nil else { return false }
        guard mutateWorkoutCoach(workoutID: workoutID, { try $0.appendWorkoutCoachMessage(text, workoutID: workoutID) }) else { return false }
        requestWorkoutCoachReply(workoutID: workoutID)
        return true
    }

    func requestWorkoutCoachReply(workoutID: String) {
        guard workoutCoachSession.requestWorkoutID == nil, !storageBlocked,
              let workout = workout(workoutID),
              let conversation = workout.coachConversation, conversation.messages.last?.role == .user else { return }
        let apiKey: String
        do {
            guard let key = try CoachCredentials.load(), !key.isEmpty else {
                coachSession.hasAPIKey = false
                workoutCoachSession.errors[workoutID] = "Add your OpenAI API key in Settings to talk with your coach."
                return
            }
            apiKey = key; coachSession.hasAPIKey = true
        } catch {
            workoutCoachSession.errors[workoutID] = "Your OpenAI key could not be read. \(error.localizedDescription)"
            return
        }
        let storeID = state.storeID
        let revision = state.revision
        let restTimer = state.restTimer
        let requestState = state
        let generation = UUID()
        workoutCoachGeneration = generation
        workoutCoachSession.requestWorkoutID = workoutID
        workoutCoachSession.errors[workoutID] = nil
        workoutCoachTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if workoutCoachGeneration == generation {
                    workoutCoachSession.requestWorkoutID = nil
                    workoutCoachTask = nil
                }
            }
            do {
                let reply = try await OpenAICoachService.workoutReply(workout: workout, storeID: storeID, revision: revision,
                                                                     restTimer: restTimer, state: requestState, apiKey: apiKey)
                guard !Task.isCancelled, workoutCoachGeneration == generation else { return }
                var next = state
                // The same check protects advice and edits from using sets logged during the request.
                try next.saveWorkoutCoachReply(reply, workoutID: workoutID, expectedStoreID: storeID,
                                               expectedRevision: revision, expectedConversation: conversation)
                try persist(next)
            } catch {
                guard !Task.isCancelled, workoutCoachGeneration == generation else { return }
                workoutCoachSession.errors[workoutID] = error.localizedDescription
            }
        }
    }

    func canApplyWorkoutCoachChange(_ change: WorkoutCoachChange, workoutID: String) -> Bool {
        guard !storageBlocked, workoutCoachSession.requestWorkoutID == nil, let workout = workout(workoutID),
              workout.coachConversation?.proposal?.id == change.id,
              change.storeID == state.storeID, change.basedOnRevision == state.revision else { return false }
        return (try? change.validate(for: workout, catalog: state.catalog)) != nil
    }

    @discardableResult
    func applyWorkoutCoachChange(_ change: WorkoutCoachChange, workoutID: String) -> Bool {
        guard workoutCoachSession.requestWorkoutID == nil else { return false }
        let saved = mutateWorkoutCoach(workoutID: workoutID) { try $0.applyWorkoutCoachChange(change.id, workoutID: workoutID) }
        if saved {
            let exerciseName = name(for: change.replacementExerciseID ?? change.exerciseID)
            switch change.effectiveAction {
            case .updateTarget: notice = "Updated \(exerciseName) for your upcoming sets."
            case .selectExercise: notice = "\(exerciseName) is up next."
            case .skipSet: notice = "Skipped one planned set. Completed sets stay saved."
            case .skipExercise: notice = "Stopped \(exerciseName) for today. Completed sets stay saved."
            }
        }
        return saved
    }

    func dismissWorkoutCoachChange(workoutID: String) {
        guard workoutCoachSession.requestWorkoutID == nil else { return }
        _ = mutateWorkoutCoach(workoutID: workoutID) { try $0.dismissWorkoutCoachChange(workoutID: workoutID) }
    }

    private func mutateWorkoutCoach(workoutID: String, _ operation: (inout GymaState) throws -> Void) -> Bool {
        guard !storageBlocked else {
            workoutCoachSession.errors[workoutID] = "Restore a valid backup in Settings before making changes."
            return false
        }
        do {
            var next = state
            try operation(&next)
            try persist(next)
            workoutCoachSession.errors[workoutID] = nil
            return true
        } catch {
            workoutCoachSession.errors[workoutID] = error.localizedDescription
            return false
        }
    }

    func cancelWorkoutCoachRequest() {
        workoutCoachGeneration = UUID()
        workoutCoachTask?.cancel()
        workoutCoachTask = nil
        workoutCoachSession.requestWorkoutID = nil
    }
}

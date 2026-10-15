import Foundation
import GymaCore

extension GymaAppModel {
    func prepareProgramWorkout(checkIn: SessionCheckIn) -> WorkoutPlan? {
        guard !storageBlocked, state.activeWorkout == nil else {
            errorMessage = "Finish or resume your current workout before starting another."
            return nil
        }
        cancelCoachRequest()
        do { return try state.nextProgramPlan(checkIn: checkIn) }
        catch { errorMessage = error.localizedDescription; return nil }
    }

    func startProgramWorkout(plan: WorkoutPlan, readiness: WorkoutReadiness, expectedStoreID: String, expectedRevision: Int) -> String? {
        guard !storageBlocked, state.storeID == expectedStoreID, state.revision == expectedRevision else {
            errorMessage = "Your program or training changed. Review today's workout again before starting."
            return nil
        }
        var workoutID: String?
        let saved = update { state in
            guard plan.checkIn.energy == readiness.energy, plan.checkIn.allSoreness == readiness.soreness else {
                throw GymaError.stale("The workout and readiness check changed. Review your current check-in before starting.")
            }
            if plan.acceptedAt != nil, state.coachConversation?.plan == plan {
                workoutID = try state.startAcceptedPlan(planID: plan.id, readiness: readiness)
            } else {
                workoutID = try state.startPreparedProgramPlan(plan, readiness: readiness)
            }
        }
        return saved ? workoutID : nil
    }

    @discardableResult
    func discussProgramWorkout(plan: WorkoutPlan, expectedStoreID: String, expectedRevision: Int) -> Bool {
        guard !storageBlocked, !coachSession.requestInFlight, state.activeWorkout == nil,
              state.storeID == expectedStoreID, state.revision == expectedRevision, coachSession.hasAPIKey else {
            errorMessage = "Review today's workout again and connect your coach before asking for adjustments."
            return false
        }
        do {
            let now = Date()
            try plan.validate(catalog: state.catalog)
            try state.validateProgramLink(plan, now: now)
            try state.validatePlanningContext(plan)
            guard state.dailyTrainingStatus(now: now).allowsWorkoutStart,
                  let sessionID = plan.programSessionID,
                  plan.isScheduledForToday(at: now, calendar: state.planningCalendar()) else {
                throw GymaError.stale("Prepare today's session from your saved program before discussing adjustments.")
            }
            var draft = plan
            draft.acceptedAt = nil
            var conversation = CoachConversation(checkIn: plan.checkIn, messages: [
                .init(role: .user, content: "Review and adjust this prepared workout using the check-in I just entered, especially any pain, soreness, energy or time limits. Explain comfortable changes and ask me if essential information is missing. Keep this a daily workout linked to programSessionID \(sessionID); leave my saved recurring program unchanged. Return a workout proposal when ready, not a replacement program.")
            ], plan: draft)
            conversation.purpose = .workout
            guard update({ try $0.saveCoachConversation(conversation) }) else { return false }
            coachSession.appChanges = nil
            coachSession.error = nil
            requestCoachReply()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func startCoachPlan(_ planID: String, readiness: WorkoutReadiness? = nil) -> String? {
        guard canAcceptCoachPlan else { return nil }
        var workoutID: String?
        let saved = update { workoutID = try $0.startAcceptedPlan(planID: planID, readiness: readiness) }
        return saved ? workoutID : nil
    }
}

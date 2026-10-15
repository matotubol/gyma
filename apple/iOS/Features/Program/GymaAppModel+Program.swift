import Foundation
import GymaCore

extension GymaAppModel {
    var hasUnfinishedProgramPlanning: Bool {
        state.coachConversation?.isProgramPlanning == true && state.coachConversation?.acceptedProgramID == nil
    }

    @discardableResult
    func beginProgramPlanning(replacingConversation: Bool = false) -> Bool {
        guard !storageBlocked, state.activeWorkout == nil else {
            coachSession.error = "Finish your current workout before discussing your program."
            return false
        }
        // Returning to planning must preserve the discussion and any request already in flight.
        // Only the confirmed "New program discussion" action replaces an unfinished program chat.
        if !replacingConversation && hasUnfinishedProgramPlanning { return true }
        cancelCoachRequest()
        let conversation = CoachConversation.programPlanning(profile: state.athleteProfile, existingProgram: state.trainingProgram)
        guard update({ try $0.saveCoachConversation(conversation) }) else { return false }
        coachSession.appChanges = nil
        coachSession.error = nil
        requestCoachReply()
        return true
    }

    @discardableResult
    func beginProgramReview() -> Bool {
        guard state.trainingProgram != nil else { return false }
        return beginProgramPlanning()
    }
}

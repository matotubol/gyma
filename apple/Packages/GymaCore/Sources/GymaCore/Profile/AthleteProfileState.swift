import Foundation

extension GymaState {
    public mutating func saveAthleteProfile(_ profile: AthleteProfile, now: Date = Date()) throws {
        var next = profile
        next.updatedAt = now
        try next.validate()
        athleteProfile = next
        coachConversation?.plan?.acceptedAt = nil
        coachConversation?.proposedProgram = nil
        revision += 1
    }

    public mutating func clearAthleteProfile() {
        guard athleteProfile != nil else { return }
        athleteProfile = nil
        coachConversation?.plan?.acceptedAt = nil
        coachConversation?.proposedProgram = nil
        revision += 1
    }
}

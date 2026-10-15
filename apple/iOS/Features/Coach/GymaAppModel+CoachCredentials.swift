import Foundation
import GymaCore

extension GymaAppModel {
    func refreshCoachCredentials() {
        do { coachSession.hasAPIKey = try CoachCredentials.load()?.isEmpty == false }
        catch {
            coachSession.hasAPIKey = false
            coachSession.error = "Your OpenAI key could not be read. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func saveCoachAPIKey(_ key: String) -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        do {
            try CoachCredentials.save(key)
            coachSession.hasAPIKey = true
            coachSession.error = nil
            return true
        } catch {
            errorMessage = "Your OpenAI key could not be saved. \(error.localizedDescription)"
            return false
        }
    }

    func removeCoachAPIKey() {
        do {
            try CoachCredentials.delete()
            cancelCoachRequest()
            cancelWorkoutCoachRequest()
            coachSession.hasAPIKey = false
            coachSession.error = nil
        } catch { errorMessage = "Your OpenAI key could not be removed. \(error.localizedDescription)" }
    }
}

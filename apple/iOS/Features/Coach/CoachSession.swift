import GymaCore

/// Transient presentation state owned by the app coordinator, never part of a backup.
struct CoachSession {
    var hasAPIKey = false
    var requestInFlight = false
    var error: String?
    var appChanges: CoachAppChangeProposal?
}

import Foundation
import GymaCore

struct WatchJournal: Codable {
    var snapshot: CompanionSnapshot?
    var pending: WatchCommand?
    var acknowledgement: CommandAcknowledgement?
    var quarantined: WatchCommand?
    var rejected: WatchCommand?
    var retiredStoreIDs: [String] = []
}

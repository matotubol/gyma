import Foundation

/// Copy only the protocol's immutable, Sendable values at the Objective-C
/// delegate boundary. No heterogeneous dictionary crosses into the main actor.
struct SessionPacket: Sendable {
    let version: Int?
    let kind: String?
    let payload: Data?
    let message: String?

    init(_ dictionary: [String: Any]) {
        version = dictionary["version"] as? Int
        kind = dictionary["kind"] as? String
        payload = dictionary["payload"] as? Data
        message = dictionary["message"] as? String
    }

    var dictionary: [String: Any] {
        var value: [String: Any] = [:]
        if let version { value["version"] = version }
        if let kind { value["kind"] = kind }
        if let payload { value["payload"] = payload }
        if let message { value["message"] = message }
        return value
    }
}

/// WCSession supplies an escaping reply callback for asynchronous responses.
/// The SDK callback lacks a Sendable annotation; this narrow bridge transfers
/// it to the processing actor and uses a lock to guarantee exactly one call.
/// Every mutable field is protected, and the outgoing dictionary is constructed
/// at invocation rather than shared across threads.
final class SessionReply: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (([String: Any]) -> Void)?

    init(_ callback: @escaping ([String: Any]) -> Void) {
        self.callback = callback
    }

    func send(_ packet: SessionPacket) {
        lock.lock()
        let reply = callback
        callback = nil
        lock.unlock()
        reply?(packet.dictionary)
    }
}

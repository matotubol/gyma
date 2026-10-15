import Foundation
import GymaCore

struct AcknowledgedState: Codable {
    let acknowledgement: CommandAcknowledgement
    let snapshot: CompanionSnapshot
}

enum ConnectivityWire {
    enum Kind: String { case request, snapshot, command, acknowledgement, error, received }
    static var request: [String: Any] { ["version": 1, "kind": "request"] }
    static var received: [String: Any] { ["version": 1, "kind": "received"] }

    static func kind(_ packet: [String: Any]) throws -> Kind {
        guard packet["version"] as? Int == 1, let name = packet["kind"] as? String,
              let kind = Kind(rawValue: name) else { throw ConnectivityError.unsupportedMessage }
        return kind
    }

    static func encode<T: Encodable>(_ value: T, kind: Kind) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let limit = kind == .command ? 8 * 1024 : 60 * 1024
        guard data.count <= limit else { throw ConnectivityError.payloadTooLarge }
        return ["version": 1, "kind": kind.rawValue, "payload": data]
    }

    static func decode<T: Decodable>(_ packet: [String: Any]) throws -> T {
        let kind = try kind(packet)
        let limit = kind == .command ? 8 * 1024 : 60 * 1024
        guard let data = packet["payload"] as? Data, data.count <= limit else { throw ConnectivityError.invalidPayload }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func failure(_ message: String) -> [String: Any] {
        ["version": 1, "kind": "error", "message": String(message.prefix(300))]
    }
}

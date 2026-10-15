import Foundation

public struct CoachMessage: Codable, Sendable, Identifiable, Equatable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public var id: String
    public var role: Role
    public var content: String
    public init(id: String = UUID().uuidString, role: Role, content: String) {
        self.id = id; self.role = role; self.content = content
    }
}

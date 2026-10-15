import Foundation

public enum Shift: String, Codable, CaseIterable, Sendable, Identifiable {
    case morning, afternoon, night, off
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

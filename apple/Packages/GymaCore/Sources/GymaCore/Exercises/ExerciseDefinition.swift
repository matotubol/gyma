import Foundation

public enum Muscle: String, Codable, CaseIterable, Sendable, Identifiable {
    case chest, back, legs, shoulders, arms, core
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

public struct ExerciseDefinition: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var muscle: Muscle
    public var iconKey: String
    public var custom: Bool
    public var metadata: ExerciseMetadata?
    public init(id: String, name: String, muscle: Muscle, iconKey: String = "barbell", custom: Bool = false, metadata: ExerciseMetadata? = nil) {
        self.id = id; self.name = name; self.muscle = muscle; self.iconKey = iconKey; self.custom = custom; self.metadata = metadata
    }
}

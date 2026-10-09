import Foundation

public enum AthleteGoal: String, Codable, Sendable, CaseIterable, Identifiable {
    case unspecified, strength, muscleGain, fatLoss, generalFitness, maintenance
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .unspecified: "Not set"
        case .strength: "Build strength"
        case .muscleGain: "Build muscle"
        case .fatLoss: "Lose body fat"
        case .generalFitness: "General fitness"
        case .maintenance: "Maintain my fitness"
        }
    }
}

public enum TrainingExperience: String, Codable, Sendable, CaseIterable, Identifiable {
    case unspecified, beginner, intermediate, advanced
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .unspecified: "Not set"
        case .beginner: "Beginner / returning"
        case .intermediate: "Regular training"
        case .advanced: "Experienced training"
        }
    }
}

public enum AthleteEquipment: String, Codable, Sendable, CaseIterable, Identifiable {
    case barbell, dumbbells, kettlebells, cables, smithMachine, machines, bands, pullUpBar, bodyweight
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbells: "Dumbbells"
        case .kettlebells: "Kettlebells"
        case .cables: "Cables"
        case .smithMachine: "Smith machine"
        case .machines: "Weight machines"
        case .bands: "Resistance bands"
        case .pullUpBar: "Pull-up bar"
        case .bodyweight: "Bodyweight"
        }
    }
    public var supportsLoadIncrement: Bool {
        switch self {
        case .barbell, .dumbbells, .kettlebells, .cables, .smithMachine, .machines: true
        case .bands, .pullUpBar, .bodyweight: false
        }
    }
}

public struct BodyweightEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var recordedAt: Date
    public var kg: Double

    public init(id: String = UUID().uuidString, recordedAt: Date = Date(), kg: Double) {
        self.id = id; self.recordedAt = recordedAt; self.kg = kg
    }

    public func validate() throws {
        guard !id.isEmpty, id.count <= 200, kg.isFinite, (20...500).contains(kg),
              (-2_208_988_800.0...4_102_444_800.0).contains(recordedAt.timeIntervalSince1970) else {
            throw GymaError.invalid("Bodyweight entries need a valid date and a weight between 20 and 500 kg.")
        }
    }
}

public struct EquipmentLoadIncrement: Codable, Sendable, Equatable {
    public var equipment: AthleteEquipment
    /// Total added load for a barbell/Smith machine; per implement for dumbbells/kettlebells.
    public var incrementKg: Double

    public init(equipment: AthleteEquipment, incrementKg: Double) {
        self.equipment = equipment; self.incrementKg = incrementKg
    }
}

/// User-confirmed facts only. Daily readiness and inferred trends belong outside this profile.
public struct AthleteProfile: Codable, Sendable, Equatable {
    public var primaryGoal: AthleteGoal
    public var secondaryGoals: [AthleteGoal]
    public var goalNotes: String
    public var experience: TrainingExperience
    public var heightCM: Double?
    public var bodyweightHistory: [BodyweightEntry]
    public var daysPerWeek: Int
    public var usualSessionMinutes: Int
    public var scheduleNotes: String
    /// Empty means not supplied, not a bodyweight-only restriction.
    public var equipment: [AthleteEquipment]
    public var loadIncrements: [EquipmentLoadIncrement]
    public var equipmentNotes: String
    public var preferredExercises: [String]
    public var avoidedExercises: [String]
    public var ongoingLimitations: String
    public var updatedAt: Date

    public init(primaryGoal: AthleteGoal = .unspecified, secondaryGoals: [AthleteGoal] = [],
                goalNotes: String = "", experience: TrainingExperience = .unspecified,
                heightCM: Double? = nil, bodyweightHistory: [BodyweightEntry] = [],
                daysPerWeek: Int = 3, usualSessionMinutes: Int = 45, scheduleNotes: String = "",
                equipment: [AthleteEquipment] = [], loadIncrements: [EquipmentLoadIncrement] = [],
                equipmentNotes: String = "", preferredExercises: [String] = [], avoidedExercises: [String] = [],
                ongoingLimitations: String = "", updatedAt: Date = Date()) {
        self.primaryGoal = primaryGoal; self.secondaryGoals = secondaryGoals; self.goalNotes = goalNotes
        self.experience = experience; self.heightCM = heightCM; self.bodyweightHistory = bodyweightHistory
        self.daysPerWeek = daysPerWeek; self.usualSessionMinutes = usualSessionMinutes; self.scheduleNotes = scheduleNotes
        self.equipment = equipment; self.loadIncrements = loadIncrements; self.equipmentNotes = equipmentNotes
        self.preferredExercises = preferredExercises; self.avoidedExercises = avoidedExercises
        self.ongoingLimitations = ongoingLimitations; self.updatedAt = updatedAt
    }

    public var latestBodyweight: BodyweightEntry? { bodyweightHistory.max { $0.recordedAt < $1.recordedAt } }

    public func validate() throws {
        guard (1...7).contains(daysPerWeek), (10...240).contains(usualSessionMinutes) else {
            throw GymaError.invalid("Choose 1–7 training days and 10–240 minutes per session.")
        }
        if let heightCM {
            guard heightCM.isFinite, (50...300).contains(heightCM) else {
                throw GymaError.invalid("Height must be between 50 and 300 cm, or left blank.")
            }
        }
        guard (-2_208_988_800.0...4_102_444_800.0).contains(updatedAt.timeIntervalSince1970),
              [goalNotes, scheduleNotes, equipmentNotes, ongoingLimitations].allSatisfy({ $0.count <= 2_000 }) else {
            throw GymaError.invalid("Profile notes must be at most 2,000 characters and have a valid update date.")
        }
        guard Set(secondaryGoals).count == secondaryGoals.count, !secondaryGoals.contains(.unspecified),
              !secondaryGoals.contains(primaryGoal), secondaryGoals.isEmpty || primaryGoal != .unspecified else {
            throw GymaError.invalid("Choose a primary goal before adding distinct secondary goals.")
        }
        guard Set(equipment).count == equipment.count,
              Set(loadIncrements.map(\.equipment)).count == loadIncrements.count,
              loadIncrements.allSatisfy({ equipment.contains($0.equipment) && $0.equipment.supportsLoadIncrement &&
                  $0.incrementKg.isFinite && (0.1...100).contains($0.incrementKg) }) else {
            throw GymaError.invalid("Each available equipment type can have one load increment between 0.1 and 100 kg.")
        }
        guard bodyweightHistory.count <= 10_000, Set(bodyweightHistory.map(\.id)).count == bodyweightHistory.count else {
            throw GymaError.invalid("Bodyweight history has duplicate entries or exceeds 10,000 measurements.")
        }
        for entry in bodyweightHistory { try entry.validate() }
        func normalized(_ names: [String]) -> [String] {
            names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        }
        for names in [preferredExercises, avoidedExercises] {
            guard names.count <= 50, names.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 200 }),
                  Set(normalized(names)).count == names.count else {
                throw GymaError.invalid("Use up to 50 distinct exercise names, each at most 200 characters.")
            }
        }
        guard Set(normalized(preferredExercises)).isDisjoint(with: Set(normalized(avoidedExercises))) else {
            throw GymaError.invalid("An exercise cannot be both preferred and avoided.")
        }
    }
}

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

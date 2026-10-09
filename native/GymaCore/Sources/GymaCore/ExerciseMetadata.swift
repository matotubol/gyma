import Foundation

/// Granular training categories, independent of the six broad soreness regions.
public enum TrainingMuscle: String, Codable, CaseIterable, Sendable, Identifiable {
    case chest, lats, upperBack, lowerBack, quadriceps, hamstrings, glutes, calves
    case frontDelts, sideDelts, rearDelts, biceps, triceps, forearms, abdominals
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .upperBack: return "Upper back"
        case .lowerBack: return "Lower back"
        case .frontDelts: return "Front delts"
        case .sideDelts: return "Side delts"
        case .rearDelts: return "Rear delts"
        default: return rawValue.capitalized
        }
    }
}

public enum ExerciseMeasurement: String, Codable, Sendable { case repetitions, seconds }

public enum ExerciseLoadConvention: String, Codable, CaseIterable, Sendable, Identifiable {
    case unknown, totalExternalWeight, perDumbbell, machineStack, bodyweight
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .unknown: return "Not specified"
        case .totalExternalWeight: return "Total external weight"
        case .perDumbbell: return "Weight per dumbbell"
        case .machineStack: return "Displayed machine weight"
        case .bodyweight: return "Added weight for bodyweight exercise"
        }
    }
}

/// Direct and secondary involvement are catalog estimates, not measured stimulus or fractional sets.
public struct ExerciseMetadata: Codable, Sendable, Equatable {
    public var primaryMuscles: [TrainingMuscle]
    public var secondaryMuscles: [TrainingMuscle]
    public var equipment: AthleteEquipment?
    public var measurement: ExerciseMeasurement
    public var loadConvention: ExerciseLoadConvention
    public init(primaryMuscles: [TrainingMuscle], secondaryMuscles: [TrainingMuscle] = [], equipment: AthleteEquipment? = nil, measurement: ExerciseMeasurement = .repetitions, loadConvention: ExerciseLoadConvention = .unknown) {
        self.primaryMuscles = primaryMuscles; self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment; self.measurement = measurement; self.loadConvention = loadConvention
    }
    public func validate() throws {
        guard !primaryMuscles.isEmpty, Set(primaryMuscles).count == primaryMuscles.count,
              Set(secondaryMuscles).count == secondaryMuscles.count,
              Set(primaryMuscles).isDisjoint(with: secondaryMuscles) else {
            throw GymaError.invalid("Exercise muscle metadata needs distinct direct and secondary muscles.")
        }
    }
}

public extension ExerciseDefinition {
    /// Custom exercises without explicit metadata stay unknown instead of assigning all muscles in a broad region.
    var trainingMetadata: ExerciseMetadata? {
        if let metadata { return metadata }
        switch id {
        case "bench_press", "incline_bench": return .init(primaryMuscles: [.chest], secondaryMuscles: [.frontDelts, .triceps], equipment: .barbell, loadConvention: .totalExternalWeight)
        case "dumbbell_press": return .init(primaryMuscles: [.chest], secondaryMuscles: [.frontDelts, .triceps], equipment: .dumbbells)
        case "chest_fly": return .init(primaryMuscles: [.chest])
        case "chest_press": return .init(primaryMuscles: [.chest], secondaryMuscles: [.frontDelts, .triceps], equipment: .machines)
        case "dips": return .init(primaryMuscles: [.chest, .triceps], secondaryMuscles: [.frontDelts], equipment: .bodyweight)
        case "deadlift": return .init(primaryMuscles: [.glutes, .hamstrings], secondaryMuscles: [.lowerBack, .upperBack, .quadriceps], equipment: .barbell, loadConvention: .totalExternalWeight)
        case "lat_pulldown": return .init(primaryMuscles: [.lats], secondaryMuscles: [.biceps, .upperBack], equipment: .cables)
        case "pull_ups": return .init(primaryMuscles: [.lats], secondaryMuscles: [.biceps, .upperBack], equipment: .pullUpBar)
        case "seated_row": return .init(primaryMuscles: [.upperBack, .lats], secondaryMuscles: [.biceps, .rearDelts], equipment: .cables)
        case "barbell_row": return .init(primaryMuscles: [.upperBack, .lats], secondaryMuscles: [.biceps, .rearDelts, .lowerBack], equipment: .barbell, loadConvention: .totalExternalWeight)
        case "squat": return .init(primaryMuscles: [.quadriceps, .glutes], secondaryMuscles: [.lowerBack], equipment: .barbell, loadConvention: .totalExternalWeight)
        case "leg_press": return .init(primaryMuscles: [.quadriceps, .glutes], equipment: .machines)
        case "leg_extension": return .init(primaryMuscles: [.quadriceps], equipment: .machines)
        case "leg_curl": return .init(primaryMuscles: [.hamstrings], equipment: .machines)
        case "lunges": return .init(primaryMuscles: [.quadriceps, .glutes])
        case "calf_raises": return .init(primaryMuscles: [.calves])
        case "hip_thrust": return .init(primaryMuscles: [.glutes])
        case "shoulder_press": return .init(primaryMuscles: [.frontDelts], secondaryMuscles: [.sideDelts, .triceps])
        case "lateral_raise": return .init(primaryMuscles: [.sideDelts])
        case "rear_delt_fly": return .init(primaryMuscles: [.rearDelts], secondaryMuscles: [.upperBack])
        case "biceps_curl": return .init(primaryMuscles: [.biceps], secondaryMuscles: [.forearms])
        case "hammer_curl": return .init(primaryMuscles: [.biceps, .forearms], equipment: .dumbbells)
        case "triceps_pushdown": return .init(primaryMuscles: [.triceps], equipment: .cables)
        case "skull_crushers": return .init(primaryMuscles: [.triceps])
        case "crunches": return .init(primaryMuscles: [.abdominals], equipment: .bodyweight)
        case "plank": return .init(primaryMuscles: [.abdominals], equipment: .bodyweight, measurement: .seconds)
        case "cable_crunch": return .init(primaryMuscles: [.abdominals], equipment: .cables)
        default: return nil
        }
    }
}

import Foundation

public enum ExerciseCatalog {
    /// Stable exercise identities used by both device apps and native backups.
    public static let builtIn: [ExerciseDefinition] = [
        .init(id: "bench_press", name: "Bench press", muscle: .chest),
        .init(id: "incline_bench", name: "Incline bench press", muscle: .chest),
        .init(id: "dumbbell_press", name: "Dumbbell press", muscle: .chest),
        .init(id: "chest_fly", name: "Chest fly", muscle: .chest, iconKey: "gymnastics"),
        .init(id: "chest_press", name: "Chest press machine", muscle: .chest, iconKey: "body"),
        .init(id: "dips", name: "Dips", muscle: .chest, iconKey: "gymnastics"),
        .init(id: "deadlift", name: "Deadlift", muscle: .back),
        .init(id: "lat_pulldown", name: "Lat pulldown", muscle: .back, iconKey: "gymnastics"),
        .init(id: "pull_ups", name: "Pull-ups", muscle: .back, iconKey: "gymnastics"),
        .init(id: "seated_row", name: "Seated row", muscle: .back, iconKey: "row"),
        .init(id: "barbell_row", name: "Barbell row", muscle: .back),
        .init(id: "squat", name: "Squat", muscle: .legs),
        .init(id: "leg_press", name: "Leg press", muscle: .legs, iconKey: "legs"),
        .init(id: "leg_extension", name: "Leg extension", muscle: .legs, iconKey: "legs"),
        .init(id: "leg_curl", name: "Leg curl", muscle: .legs, iconKey: "legs"),
        .init(id: "lunges", name: "Lunges", muscle: .legs, iconKey: "walk"),
        .init(id: "calf_raises", name: "Calf raises", muscle: .legs, iconKey: "stairs"),
        .init(id: "hip_thrust", name: "Hip thrust", muscle: .legs),
        .init(id: "shoulder_press", name: "Shoulder press", muscle: .shoulders),
        .init(id: "lateral_raise", name: "Lateral raise", muscle: .shoulders, iconKey: "body"),
        .init(id: "rear_delt_fly", name: "Rear delt fly", muscle: .shoulders, iconKey: "body"),
        .init(id: "biceps_curl", name: "Biceps curl", muscle: .arms, iconKey: "arm"),
        .init(id: "hammer_curl", name: "Hammer curl", muscle: .arms, iconKey: "arm"),
        .init(id: "triceps_pushdown", name: "Triceps pushdown", muscle: .arms, iconKey: "arm"),
        .init(id: "skull_crushers", name: "Skull crushers", muscle: .arms),
        .init(id: "crunches", name: "Crunches", muscle: .core, iconKey: "core"),
        .init(id: "plank", name: "Plank", muscle: .core, iconKey: "core"),
        .init(id: "cable_crunch", name: "Cable crunch", muscle: .core, iconKey: "core")
    ]
}

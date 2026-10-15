import XCTest
@testable import GymaCore

final class AthleteProfileTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var profile: AthleteProfile {
        AthleteProfile(primaryGoal: .muscleGain, secondaryGoals: [.strength], goalNotes: "Stronger upper body",
                       experience: .intermediate, heightCM: 182,
                       bodyweightHistory: [.init(id: "new", recordedAt: now, kg: 83.5),
                                           .init(id: "old", recordedAt: now.addingTimeInterval(-86400), kg: 84)],
                       daysPerWeek: 4, usualSessionMinutes: 55, scheduleNotes: "Alternating night shifts",
                       equipment: [.barbell, .dumbbells, .cables],
                       loadIncrements: [.init(equipment: .barbell, incrementKg: 2.5),
                                        .init(equipment: .dumbbells, incrementKg: 2)],
                       equipmentNotes: "Cable stacks differ by station", preferredExercises: ["Cable row"],
                       avoidedExercises: ["Upright row"], ongoingLimitations: "Avoid overhead loading",
                       updatedAt: now)
    }

    func testProfileAndDatedBodyweightsSurviveBackupRoundTrip() throws {
        var state = GymaState()
        try state.saveAthleteProfile(profile, now: now)
        let restored = try NativeBackup.decode(NativeBackup.encode(state))
        XCTAssertEqual(restored.athleteProfile, profile)
        XCTAssertEqual(restored.athleteProfile?.latestBodyweight?.id, "new")
        XCTAssertEqual(restored.athleteProfile?.bodyweightHistory.last?.recordedAt, now.addingTimeInterval(-86400))
        XCTAssertEqual(restored.revision, 1)
        try restored.validate()
    }

    func testLegacyStateWithoutProfileStillDecodes() throws {
        let original = GymaState()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "athleteProfile")
        let restored = try JSONDecoder().decode(GymaState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.athleteProfile)
        XCTAssertEqual(restored.storeID, original.storeID)
        try restored.validate()
    }

    func testUnspecifiedValuesStayUnknown() throws {
        let value = AthleteProfile(updatedAt: now)
        try value.validate()
        XCTAssertEqual(value.primaryGoal, .unspecified)
        XCTAssertEqual(value.experience, .unspecified)
        XCTAssertNil(value.heightCM)
        XCTAssertNil(value.latestBodyweight)
        XCTAssertTrue(value.equipment.isEmpty)
        XCTAssertTrue(value.loadIncrements.isEmpty)
    }

    func testRejectsNonFiniteMeasurementsAndOutOfBoundsAvailability() throws {
        for height in [49.9, 300.1, Double.infinity, Double.nan] {
            var value = profile; value.heightCM = height
            XCTAssertThrowsError(try value.validate())
        }
        for kg in [19.9, 500.1, Double.infinity, Double.nan] {
            var value = profile; value.bodyweightHistory[0].kg = kg
            XCTAssertThrowsError(try value.validate())
        }
        for days in [0, 8] {
            var value = profile; value.daysPerWeek = days
            XCTAssertThrowsError(try value.validate())
        }
        for minutes in [9, 241] {
            var value = profile; value.usualSessionMinutes = minutes
            XCTAssertThrowsError(try value.validate())
        }
        var value = profile
        value.heightCM = nil
        value.bodyweightHistory = []
        try value.validate()
    }

    func testRejectsContradictoryGoalsPreferencesAndLoadIncrements() throws {
        let mutations: [(inout AthleteProfile) -> Void] = [
            { $0.secondaryGoals = [.muscleGain] },
            { $0.secondaryGoals = [.strength, .strength] },
            { $0.secondaryGoals = [.unspecified] },
            { $0.primaryGoal = .unspecified },
            { $0.preferredExercises = ["Cable row", " cable ROW "] },
            { $0.avoidedExercises = [" cable ROW "] },
            { $0.preferredExercises = [" "] },
            { $0.equipment = [.barbell, .barbell] },
            { $0.loadIncrements = [.init(equipment: .machines, incrementKg: 5)] },
            { $0.loadIncrements = [.init(equipment: .barbell, incrementKg: 0)] },
            { $0.loadIncrements = [.init(equipment: .barbell, incrementKg: .nan)] },
            { $0.loadIncrements.append(.init(equipment: .barbell, incrementKg: 1)) },
            { $0.equipment.append(.bodyweight); $0.loadIncrements.append(.init(equipment: .bodyweight, incrementKg: 2)) }
        ]
        for mutation in mutations {
            var value = profile
            mutation(&value)
            XCTAssertThrowsError(try value.validate())
        }
    }

    func testRejectsMalformedHistoryAndOversizedNotes() throws {
        let mutations: [(inout AthleteProfile) -> Void] = [
            { $0.bodyweightHistory.append($0.bodyweightHistory[0]) },
            { $0.bodyweightHistory[0].id = "" },
            { $0.bodyweightHistory[0].recordedAt = .distantFuture },
            { $0.updatedAt = .distantPast },
            { $0.goalNotes = String(repeating: "x", count: 2_001) },
            { $0.ongoingLimitations = String(repeating: "x", count: 2_001) },
            { $0.preferredExercises = [String(repeating: "x", count: 201)] }
        ]
        for mutation in mutations {
            var value = profile
            mutation(&value)
            XCTAssertThrowsError(try value.validate())
        }
    }

    func testSaveIsAtomicAndClearKeepsWorkoutHistory() throws {
        var state = GymaState()
        state.workouts = [.init(id: "history", start: now.addingTimeInterval(-3600), end: now)]
        try state.saveAthleteProfile(profile, now: now)
        let saved = state
        var invalid = profile; invalid.daysPerWeek = 0
        XCTAssertThrowsError(try state.saveAthleteProfile(invalid, now: now))
        XCTAssertEqual(state, saved)
        state.clearAthleteProfile()
        XCTAssertNil(state.athleteProfile)
        XCTAssertEqual(state.workouts, saved.workouts)
        XCTAssertEqual(state.revision, saved.revision + 1)
        let revision = state.revision
        state.clearAthleteProfile()
        XCTAssertEqual(state.revision, revision)
    }

    func testProfileEditsRequireAcceptedWorkoutToBeReviewedAgain() throws {
        var state = GymaState()
        let checkIn = SessionCheckIn(shift: .off, energy: .good)
        let plan = WorkoutPlan(id: "plan", title: "Strength", exercises: [
            .init(exerciseID: "bench_press", target: .init(sets: 3, repsMin: 8, repsMax: 10))
        ], checkIn: checkIn, createdAt: now)
        try state.saveCoachConversation(.init(checkIn: checkIn, plan: plan))
        try state.acceptCoachPlan(planID: "plan", now: now)
        try state.saveAthleteProfile(profile, now: now)
        XCTAssertNil(state.coachConversation?.plan?.acceptedAt)
        XCTAssertEqual(state.coachConversation?.plan?.id, "plan")
        try state.acceptCoachPlan(planID: "plan", now: now)
        state.clearAthleteProfile()
        XCTAssertNil(state.coachConversation?.plan?.acceptedAt)
    }

    func testWatchSnapshotDoesNotExposeProfileDetails() throws {
        var state = GymaState()
        try state.saveAthleteProfile(profile, now: now)
        let text = String(decoding: try JSONEncoder().encode(CompanionSnapshot(state: state)), as: UTF8.self)
        XCTAssertFalse(text.contains("athleteProfile"))
        XCTAssertFalse(text.contains(profile.ongoingLimitations))
        XCTAssertFalse(text.contains(profile.scheduleNotes))
    }
}

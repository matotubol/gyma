import XCTest
@testable import GymaCore

final class TrainingProgramTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var target: ExerciseTarget { .init(sets: 2, repsMin: 8, repsMax: 10, loadKg: 60, restSeconds: 90, targetEffort: .challenging) }
    private func program(target override: ExerciseTarget? = nil) -> TrainingProgram {
        .init(id: "program", title: "My program", goal: "Build strength", sessions: [
            .init(id: "a", title: "A", exercises: [.init(exerciseID: "bench_press", target: override ?? target)]),
            .init(id: "b", title: "B", exercises: [.init(exerciseID: "squat", target: target)])
        ], createdAt: now.addingTimeInterval(-60 * 86400), updatedAt: now.addingTimeInterval(-60 * 86400))
    }
    private func completed(id: String, daysAgo: Double, reps: Int = 10, effort: SetEffort? = .challenging, target override: ExerciseTarget? = nil) -> Workout {
        let date = now.addingTimeInterval(-daysAgo * 86400)
        return .init(id: id, start: date.addingTimeInterval(-1800), end: date, exercises: [
            .init(exerciseID: "bench_press", sets: [
                .init(id: "\(id)-1", kg: 60, reps: reps, effort: effort, isWarmup: false),
                .init(id: "\(id)-2", kg: 60, reps: reps, effort: effort, isWarmup: false)
            ], target: override ?? target)
        ], programID: "program", programSessionID: "a", programRevision: 1)
    }
    private func recommendation(_ plan: TrainingProgram, _ history: [Workout]) throws -> NextTargetRecommendation {
        try XCTUnwrap(plan.recommendations(for: plan.sessions[0], history: history, now: now).first)
    }

    func testRotationUsesLinkedCompletionsAndNeverCalendarCatchup() throws {
        let plan = program()
        XCTAssertEqual(plan.nextSession(history: [], now: now)?.id, "a")
        let old = completed(id: "old", daysAgo: 40)
        var unlinked = completed(id: "unlinked", daysAgo: 1); unlinked.programID = nil; unlinked.programSessionID = nil; unlinked.programRevision = nil
        var active = completed(id: "active", daysAgo: 0); active.programSessionID = "b"; active.end = nil
        var future = completed(id: "future", daysAgo: -1); future.programSessionID = "b"
        XCTAssertEqual(plan.nextSession(history: [future, unlinked, active, old], now: now)?.id, "b")
        var b = completed(id: "b", daysAgo: 0); b.programSessionID = "b"
        XCTAssertEqual(plan.nextSession(history: [b, old], now: now)?.id, "a")
    }

    func testFinishingWithoutKnownWorkingSetsDoesNotConsumeSession() throws {
        let plan = program()
        var empty = completed(id: "empty", daysAgo: 1)
        empty.exercises[0].sets = []
        XCTAssertEqual(plan.nextSession(history: [empty], now: now)?.id, "a")
        empty.exercises[0].sets = [.init(kg: 20, reps: 8, isWarmup: true), .init(kg: 20, reps: 8)]
        XCTAssertEqual(plan.nextSession(history: [empty], now: now)?.id, "a")
        empty.exercises[0].sets.append(.init(kg: 60, reps: 8, isWarmup: false))
        XCTAssertEqual(plan.nextSession(history: [empty], now: now)?.id, "b")
    }

    func testDoubleProgressionRequiresTwoComparableSuccessesAndIsIdempotent() throws {
        let plan = program()
        let latest = completed(id: "latest", daysAgo: 1)
        let previous = completed(id: "previous", daysAgo: 5)
        XCTAssertEqual(try recommendation(plan, [latest]).action, .repeatTarget)
        let result = try recommendation(plan, [previous, latest])
        XCTAssertEqual(result.action, .increaseLoad)
        XCTAssertEqual(result.target.loadKg, 62.5)
        XCTAssertEqual(result.evidenceWorkoutIDs, ["latest", "previous"])
        XCTAssertEqual(result, try recommendation(plan, [latest, previous]))
        XCTAssertEqual(try recommendation(plan, [completed(id: "lower", daysAgo: 0, reps: 9), latest]).action, .addReps)
    }

    func testProgressionRetainsLatestPrescribedLoadAfterAnIncrease() throws {
        let plan = program()
        var advancedTarget = target; advancedTarget.loadKg = 62.5
        var advanced = completed(id: "advanced", daysAgo: 0, reps: 8, target: advancedTarget)
        for index in advanced.exercises[0].sets.indices { advanced.exercises[0].sets[index].kg = 62.5 }
        let result = try recommendation(plan, [completed(id: "older", daysAgo: 5), advanced])
        XCTAssertEqual(result.action, .addReps)
        XCTAssertEqual(result.target.loadKg, 62.5)
    }

    func testUnknownEffortAndClassificationNeverQualifyAndWarmupsDoNotCount() throws {
        let plan = program()
        let previous = completed(id: "previous", daysAgo: 5)
        let unknownEffort = completed(id: "unknown", daysAgo: 1, effort: nil)
        XCTAssertEqual(try recommendation(plan, [previous, unknownEffort]).action, .needsEffort)
        var unknownType = completed(id: "type", daysAgo: 1)
        unknownType.exercises[0].sets.append(.init(kg: 20, reps: 8))
        XCTAssertEqual(try recommendation(plan, [previous, unknownType]).action, .needsEffort)
        var warmup = completed(id: "warmup", daysAgo: 1)
        warmup.exercises[0].sets.insert(.init(kg: 20, reps: 5, isWarmup: true), at: 0)
        XCTAssertEqual(try recommendation(plan, [previous, warmup]).action, .increaseLoad)
        var unspecified = target; unspecified.targetEffort = nil
        XCTAssertEqual(try recommendation(program(target: unspecified), [completed(id: "no-target", daysAgo: 1, target: unspecified)]).action, .needsEffort)
    }

    func testUnknownEffortBreaksSuccessStreakRatherThanBeingSkipped() throws {
        let plan = program()
        let history = [completed(id: "old", daysAgo: 9), completed(id: "unknown", daysAgo: 5, effort: nil), completed(id: "latest", daysAgo: 1)]
        let result = try recommendation(plan, history)
        XCTAssertEqual(result.action, .repeatTarget)
        XCTAssertEqual(result.evidenceWorkoutIDs, ["latest"])
    }

    func testLongGapPainPoorEnergyAndUnexpectedEffortRequireReview() throws {
        let plan = program()
        let old = completed(id: "old", daysAgo: 35)
        XCTAssertEqual(try recommendation(plan, [old]).action, .review)
        XCTAssertNil(try recommendation(plan, [old]).target.loadKg)
        let previous = completed(id: "previous", daysAgo: 5)
        var recent = completed(id: "recent", daysAgo: 1)
        recent.checkIn = .init(shift: .off, energy: .good, painNote: "Shoulder uncomfortable")
        XCTAssertEqual(try recommendation(plan, [previous, recent]).action, .review)
        recent.checkIn = nil; recent.energy = .poor
        XCTAssertEqual(try recommendation(plan, [previous, recent]).action, .review)
        XCTAssertEqual(try recommendation(plan, [previous, completed(id: "hard", daysAgo: 1, effort: .limit)]).action, .review)
    }

    func testInitialOpenLoadUsesObservedWorkingLoadWithoutInventingEffort() throws {
        var openTarget = target; openTarget.loadKg = nil
        let plan = program(target: openTarget)
        let recent = completed(id: "recent", daysAgo: 1, target: openTarget)
        let previous = completed(id: "previous", daysAgo: 5, target: openTarget)
        XCTAssertEqual(try recommendation(plan, [recent]).target.loadKg, 60)
        XCTAssertEqual(try recommendation(plan, [recent, previous]).target.loadKg, 62.5)
        XCTAssertEqual(try recommendation(plan, [recent, previous]).action, .increaseLoad)
        let unknown = completed(id: "unknown", daysAgo: 1, effort: nil, target: openTarget)
        XCTAssertNil(try recommendation(plan, [unknown]).target.loadKg)
    }

    func testUnchangedPrescriptionPreservesEvidenceAcrossRevisions() throws {
        var plan = program(); plan.revision = 2; plan.rationale = "New wording"
        let records = [completed(id: "latest", daysAgo: 1), completed(id: "older", daysAgo: 5)]
        XCTAssertEqual(try recommendation(plan, records).action, .increaseLoad)
        plan.sessions[0].exercises[0].target?.loadKg = 70
        XCTAssertEqual(try recommendation(plan, records).action, .review)
        XCTAssertEqual(try recommendation(plan, records).target.loadKg, 70)
    }

    func testRuleOnlyRevisionKeepsProgressedLoadUsingArchivedTemplate() throws {
        let previous = program()
        var updated = previous; updated.revision = 2; updated.progressionRule.loadIncrementKg = 1
        var progressedTarget = target; progressedTarget.loadKg = 65
        var recorded = completed(id: "progressed", daysAgo: 1, reps: 9, target: progressedTarget)
        for index in recorded.exercises[0].sets.indices { recorded.exercises[0].sets[index].kg = 65 }
        let result = try XCTUnwrap(updated.recommendations(for: updated.sessions[0], history: [recorded], now: now, priorPrograms: [previous]).first)
        XCTAssertEqual(result.action, .addReps)
        XCTAssertEqual(result.target.loadKg, 65)
        updated.sessions[0].exercises[0].target?.loadKg = 50
        let changed = try XCTUnwrap(updated.recommendations(for: updated.sessions[0], history: [recorded], now: now, priorPrograms: [previous]).first)
        XCTAssertEqual(changed.action, .review)
        XCTAssertEqual(changed.target.loadKg, 50)
    }

    func testAmbiguousMachineNeedsAnExplicitExerciseIncrement() throws {
        var plan = program()
        plan.sessions[0].exercises[0].exerciseID = "chest_press"
        var records = [completed(id: "latest", daysAgo: 1), completed(id: "older", daysAgo: 5)]
        for index in records.indices { records[index].exercises[0].exerciseID = "chest_press" }
        XCTAssertEqual(try recommendation(plan, records).action, .review)
        plan.progressionRule.exerciseIncrements["chest_press"] = 5
        XCTAssertEqual(try recommendation(plan, records).target.loadKg, 65)
    }

    func testOversizedAvailableIncrementRequiresReviewWithoutRaisingLoad() throws {
        var smallTarget = target; smallTarget.loadKg = 10
        var plan = program(target: smallTarget)
        plan.progressionRule.exerciseIncrements["bench_press"] = 100
        var records = [completed(id: "latest", daysAgo: 1, target: smallTarget), completed(id: "older", daysAgo: 5, target: smallTarget)]
        for workoutIndex in records.indices {
            for setIndex in records[workoutIndex].exercises[0].sets.indices {
                records[workoutIndex].exercises[0].sets[setIndex].kg = 10
            }
        }
        let oversized = try recommendation(plan, records)
        XCTAssertEqual(oversized.action, .review)
        XCTAssertEqual(oversized.target.loadKg, 10)
        XCTAssertTrue(oversized.reason.contains("too large"))
        XCTAssertTrue(oversized.reason.contains("product rule"))
        plan.progressionRule.exerciseIncrements["bench_press"] = 2.5
        let available = try recommendation(plan, records)
        XCTAssertEqual(available.action, .increaseLoad)
        XCTAssertEqual(available.target.loadKg, 12.5)
    }

    func testNextExercisesIncludeTheReasonAndValidationRejectsUnsupportedPlans() throws {
        let plan = program()
        let next = try XCTUnwrap(plan.nextExercises(history: [], now: now).first)
        XCTAssertTrue(next.target?.reason.contains("record effort") == true)
        XCTAssertNoThrow(try plan.validate(catalog: ExerciseCatalog.builtIn))
        var invalid = plan; invalid.sessions[0].exercises[0].exerciseID = "plank"
        XCTAssertThrowsError(try invalid.validate(catalog: ExerciseCatalog.builtIn))
        invalid = plan; invalid.progressionRule.successfulExposuresRequired = 0
        XCTAssertThrowsError(try invalid.validate(catalog: ExerciseCatalog.builtIn))
        invalid = plan; invalid.progressionRule.exerciseIncrements["unplanned"] = 2.5
        XCTAssertThrowsError(try invalid.validate(catalog: ExerciseCatalog.builtIn))
        invalid = plan; invalid.sessions.append(invalid.sessions[0])
        XCTAssertThrowsError(try invalid.validate(catalog: ExerciseCatalog.builtIn))
        XCTAssertEqual(try JSONDecoder().decode(TrainingProgram.self, from: JSONEncoder().encode(plan)), plan)
    }

    func testWorkoutLinksAreAllOrNothingAndLegacyTargetsRemainUnknown() throws {
        var workout = completed(id: "linked", daysAgo: 1)
        XCTAssertNoThrow(try workout.validate())
        workout.programRevision = nil
        XCTAssertThrowsError(try workout.validate())
        let legacy = Data(#"{"sets":2,"repsMin":8,"repsMax":10,"loadKg":60,"restSeconds":90,"reason":""}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(ExerciseTarget.self, from: legacy).targetEffort)
    }
}

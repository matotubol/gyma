import XCTest
@testable import GymaCore

final class RecordsTests: XCTestCase {
    private let exerciseId = String(repeating: "a", count: 32)

    private func session(history: [ExerciseHistory], sets: [(kg: Double, reps: Int)]) throws -> WorkoutSession {
        let setsJSON = sets.enumerated().map { index, set in
            """
            {"id":"\(String(format: "%032ld", index + 1))","exercisePosition":0,"setNumber":\(index + 1),"status":"completed",
             "startedAt":"2026-10-27T10:0\(index):00.000Z","completedAt":"2026-10-27T10:0\(index):30.000Z",
             "actualKg":\(set.kg),"actualReps":\(set.reps),"recordedManually":false}
            """
        }.joined(separator: ",")
        let historyJSON = String(decoding: try JSONEncoder().encode(history), as: UTF8.self)
        let json = """
        {"id":"\(String(repeating: "b", count: 32))","date":"2026-10-27","planVersion":1,"version":3,"status":"active",
         "startedAt":"2026-10-27T10:00:00.000Z","completedAt":null,
         "exercises":[{"entryId":"\(String(repeating: "c", count: 32))","position":0,"exerciseId":"\(exerciseId)","name":"Back Squat",
                       "equipment":"barbell","brand":null,"plannedSets":3,"plannedReps":8,"plannedKg":80}],
         "sets":[\(setsJSON)],"history":\(historyJSON)}
        """
        return try JSONDecoder().decode(WorkoutSession.self, from: Data(json.utf8))
    }

    private func history(last: [LiftedSet], best: [LiftedSet], volume: Double = 1000) -> ExerciseHistory {
        ExerciseHistory(exerciseId: exerciseId, lastDate: "2026-10-20", lastSets: last, bestRepsByKg: best, bestVolume: volume)
    }

    func testFormatsKilograms() {
        XCTAssertEqual(formatKg(82.5), "82.5")
        XCTAssertEqual(formatKg(80), "80")
        XCTAssertEqual(formatKg(0.25), "0.25")
        XCTAssertEqual(formatKg(70.10000000001), "70.1")
        XCTAssertEqual(formatSet(LiftedSet(kg: 60, reps: 8)), "60 × 8")
    }

    func testEstimatedMax() {
        XCTAssertEqual(e1rm(100, 1), 100)
        XCTAssertEqual(e1rm(100, 0), 0)
        XCTAssertEqual(e1rm(90, 3), 99, accuracy: 0.0001)
    }

    func testHeavierSetIsWeightRecordOnlyOnce() throws {
        let past = history(last: [LiftedSet(kg: 80, reps: 8)], best: [LiftedSet(kg: 80, reps: 8)])
        let workout = try session(history: [past], sets: [(85, 5), (85, 5)])
        let analysis = analyseWorkout(workout)
        let first = try XCTUnwrap(analysis.records[workout.sets[0].id])
        XCTAssertTrue(first.kinds.contains(.weight))
        XCTAssertEqual(first.previousKg, 80)
        XCTAssertNil(analysis.records[workout.sets[1].id], "Repeating today's best is not a new record")
    }

    func testFirstTimeExerciseOnlySetsBaseline() throws {
        let workout = try session(history: [], sets: [(60, 10)])
        XCTAssertTrue(analyseWorkout(workout).records.isEmpty)
    }

    func testRepsForRecord() {
        let baseline = Baseline(bestKg: 80, bestE1rm: e1rm(80, 8), bestVolume: 1000,
                                repsByKg: [LiftedSet(kg: 80, reps: 8), LiftedSet(kg: 70, reps: 10)], sessionVolume: 0)
        XCTAssertEqual(repsForRecord(baseline, kg: 82.5), .any)
        XCTAssertEqual(repsForRecord(baseline, kg: 80), .reps(9))
        XCTAssertNil(repsForRecord(nil, kg: 80))
    }

    func testPlanPushesAfterHittingTargetReps() throws {
        let past = history(last: [LiftedSet(kg: 80, reps: 8), LiftedSet(kg: 80, reps: 8)], best: [LiftedSet(kg: 80, reps: 8)])
        let plan = try XCTUnwrap(planKg(past, reps: 8, equipment: .barbell))
        XCTAssertEqual(plan.recommend, .push)
        XCTAssertEqual(plan.repeatKg, 80)
        XCTAssertEqual(plan.pushKg, 82.5)
        XCTAssertEqual(plan.recommendedKg, 82.5)
    }

    func testPlanRepeatsWhenSlightlyShort() throws {
        let past = history(last: [LiftedSet(kg: 40, reps: 10), LiftedSet(kg: 40, reps: 8)], best: [LiftedSet(kg: 40, reps: 10)])
        let plan = try XCTUnwrap(planKg(past, reps: 10, equipment: .machine))
        XCTAssertEqual(plan.recommend, .repeatWeight)
        XCTAssertEqual(plan.pushKg, 45)
        XCTAssertEqual(plan.reason, "Last time 10 · 8 reps at 40 kg. Own all 10 first.")
    }

    func testJudgeKg() throws {
        let past = history(last: [LiftedSet(kg: 80, reps: 8)], best: [LiftedSet(kg: 80, reps: 8)])
        let plan = try XCTUnwrap(planKg(past, reps: 8, equipment: .barbell))
        XCTAssertEqual(judgeKg(plan, kg: 85, reps: 8)?.tone, .pr)
        XCTAssertEqual(judgeKg(plan, kg: 80, reps: 8)?.tone, .same)
        XCTAssertEqual(judgeKg(plan, kg: 75, reps: 8)?.title, "−5 kg vs last time")
        XCTAssertNil(judgeKg(plan, kg: 0, reps: 8))
    }

    func testPickMatchesWebHash() {
        // JS: hash = (hash * 31 + charCode) | 0 over "abc" = 96354.
        XCTAssertEqual(pick(["a", "b", "c", "d", "e", "f", "g"], seed: "abc"), ["a", "b", "c", "d", "e", "f", "g"][96354 % 7])
    }
}

import XCTest
@testable import GymaCore

final class CalendarCoachAvailabilityTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return value
    }
    private func date(_ day: Int, month: Int = 10, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private var plan: TrainingCalendarPlan { .defaultPlan(now: date(10), timeZone: calendar.timeZone) }
    private func context(now: Date, history: [Workout] = []) throws -> String {
        try CoachContext.text(profile: nil, program: nil, history: history, catalog: ExerciseCatalog.builtIn,
                              now: now, trainingCalendar: plan)
    }

    func testCoachDistinguishesPreviewTrainingRecoveryCompletionAndExpiredBlock() throws {
        let before = try context(now: date(10))
        XCTAssertTrue(before.contains("BLOCK NOT STARTED. The block begins 2026-10-13"))
        XCTAssertTrue(before.contains("Future sessions are previews"))
        XCTAssertTrue(before.contains("Discussing or saving a program is allowed before the block begins"))
        XCTAssertTrue(try context(now: date(13)).contains("TRAINING DAY. Today's workout may start"))
        XCTAssertTrue(try context(now: date(15)).contains("RECOVERY DAY"))
        let completed = Workout(start: date(13, hour: 9), end: date(13, hour: 10), exercises: [
            .init(exerciseID: "bench_press", sets: [.init(kg: 60, reps: 8, effort: .challenging, isWarmup: false)])
        ])
        XCTAssertTrue(try context(now: date(13), history: [completed]).contains("TODAY ALREADY RECORDED"))
        var active = completed
        active.end = nil
        XCTAssertTrue(try context(now: date(14), history: [active]).contains("WORKOUT IN PROGRESS"))
        XCTAssertTrue(try context(now: plan.reviewDate).contains("BLOCK COMPLETE"))
    }

    func testBothCoachAPIsReceiveEarlyBaselineOutsideRecentFourExposures() throws {
        let history: [Workout] = (0..<6).map { index in
            let start = date(index + 1, month: 8)
            return .init(id: "exposure-\(index)", start: start, end: start.addingTimeInterval(1800), exercises: [
                .init(exerciseID: "bench_press", sets: [.init(kg: 40 + Double(index) * 2.5, reps: 8, effort: .challenging, isWarmup: false)])
            ])
        }
        let conversation = CoachConversation(checkIn: .init(shift: .off, energy: .good),
                                             messages: [.init(role: .user, content: "Compare my progress since I started.")])
        var selected = try XCTUnwrap(history.last)
        selected.coachConversation = .init(messages: [.init(role: .user, content: "Compare my first and latest working sets.")])
        let bodies = try [
            CoachAPI.requestBody(conversation: conversation, catalog: ExerciseCatalog.builtIn, history: history,
                                 now: date(10), trainingCalendar: plan),
            WorkoutCoachAPI.requestBody(workout: selected, storeID: "store", revision: 1, restTimer: nil,
                                        catalog: ExerciseCatalog.builtIn, history: history, now: date(10), trainingCalendar: plan)
        ]
        for body in bodies {
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let text = try XCTUnwrap((json["input"] as? [[String: String]])?.first?["content"])
            XCTAssertTrue(text.contains("BLOCK NOT STARTED"))
            let prefix = "First and latest working exposures across all retained calendar blocks, for these relevant exercises: "
            let line = try XCTUnwrap(text.components(separatedBy: "\n").first { $0.hasPrefix(prefix) })
            let comparisons = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.dropFirst(prefix.count).utf8)) as? [[String: Any]])
            let comparison = try XCTUnwrap(comparisons.first)
            XCTAssertEqual(comparison["completedExposureCount"] as? Int, 6)
            XCTAssertEqual(comparison["topWorkingLoadChangeKg"] as? Double, 12.5)
            let first = try XCTUnwrap(comparison["first"] as? [String: Any])
            let latest = try XCTUnwrap(comparison["latest"] as? [String: Any])
            XCTAssertEqual(first["workoutID"] as? String, "exposure-0")
            XCTAssertEqual(first["topWorkingLoadKg"] as? Double, 40)
            XCTAssertEqual(latest["workoutID"] as? String, "exposure-5")
            XCTAssertEqual(latest["topWorkingLoadKg"] as? Double, 52.5)
            XCTAssertTrue(text.contains("Load differences alone do not establish improvement"))
            XCTAssertTrue(text.contains("Do not invent a specific eight-week or block-to-block result"))
        }
    }
}

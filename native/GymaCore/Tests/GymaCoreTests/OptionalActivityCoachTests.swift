import XCTest
@testable import GymaCore

final class OptionalActivityCoachTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return value
    }
    private func date(_ day: Int, month: Int = 10, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private var plan: TrainingCalendarPlan {
        var value = TrainingCalendarPlan(startDate: date(13), cycleAnchorDate: date(17), timeZone: calendar.timeZone)
        value.dayOverrides = [.init(dayOffset: 0, isTraining: true), .init(dayOffset: 2, isTraining: false)]
        value.activities = [
            .init(dayOffset: 0, kind: .inclineWalking, durationMinutes: 20, isCompleted: true),
            .init(dayOffset: 1, kind: .stretching, durationMinutes: 10, isCompleted: false),
            .init(dayOffset: 3, kind: .abs, durationMinutes: 8, isCompleted: false)
        ]
        return value
    }
    private var program: TrainingProgram {
        let target = ExerciseTarget(sets: 2, repsMin: 8, repsMax: 10)
        return .init(id: "upper-lower", title: "Upper / lower", goal: "Strength", sessions: [
            .init(id: "upper", title: "Upper", exercises: [.init(exerciseID: "bench_press", target: target)]),
            .init(id: "lower", title: "Lower", exercises: [.init(exerciseID: "squat", target: target)])
        ], createdAt: date(10), updatedAt: date(10))
    }
    private func requestBodies(trainingCalendar: TrainingCalendarPlan?, trainingCalendarHistory: [TrainingCalendarPlan] = [],
                               now: Date? = nil) throws -> [[String: Any]] {
        let observation = now ?? date(14)
        let conversation = CoachConversation(checkIn: .init(shift: .off, energy: .good),
                                             messages: [.init(role: .user, content: "Can I walk or stretch on a rest day?")])
        let active = Workout(id: "active", start: observation,
                             coachConversation: .init(messages: [.init(role: .user, content: "Can I do abs tomorrow?")]),
                             exercises: [.init(exerciseID: "bench_press")])
        let requests = try [
            CoachAPI.requestBody(conversation: conversation, catalog: ExerciseCatalog.builtIn, history: [],
                                 program: program, now: observation, trainingCalendar: trainingCalendar, trainingCalendarHistory: trainingCalendarHistory),
            CoachAPI.requestBody(conversation: .programPlanning(existingProgram: program), catalog: ExerciseCatalog.builtIn,
                                 history: [], program: program, now: observation, trainingCalendar: trainingCalendar, trainingCalendarHistory: trainingCalendarHistory),
            WorkoutCoachAPI.requestBody(workout: active, storeID: "store", revision: 1, restTimer: nil,
                                        catalog: ExerciseCatalog.builtIn, history: [], now: observation,
                                        program: program, trainingCalendar: trainingCalendar, trainingCalendarHistory: trainingCalendarHistory)
        ]
        return try requests.map { try XCTUnwrap(JSONSerialization.jsonObject(with: $0) as? [String: Any]) }
    }

    func testEveryCoachModeReceivesIndependentStartAndShiftDatesWithRealActivityUnits() throws {
        for body in try requestBodies(trainingCalendar: plan) {
            let context = try XCTUnwrap((body["input"] as? [[String: String]])?.first?["content"])
            XCTAssertTrue(context.contains("Training block starts 2026-10-13; first morning shift anchor is 2026-10-17"))
            XCTAssertTrue(context.contains("Start-day shift: Off, cycle day 7"))
            XCTAssertTrue(context.contains("2026-10-13 through 2026-12-07; review on 2026-12-08"))
            XCTAssertTrue(context.contains("2026-10-13: inclineWalking: reported completed, 20 minutes"))
            XCTAssertTrue(context.contains("2026-10-14: stretching: planned only, 10 minutes"))
            XCTAssertTrue(context.contains("2026-10-16: abs: planned only, 8 minutes"))
            XCTAssertTrue(context.contains("2026-10-14: Off, Upper"), "Optional completion must not consume a strength session")
            XCTAssertTrue(context.contains("2026-10-16: Off, Lower"))

            let prefix = "User-confirmed eight-week training calendar: "
            let savedLine = try XCTUnwrap(context.components(separatedBy: "\n").first { $0.hasPrefix(prefix) })
            let savedData = Data(savedLine.dropFirst(prefix.count).utf8)
            let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: savedData) as? [String: Any])
            let activities = try XCTUnwrap(saved["activities"] as? [[String: Any]])
            XCTAssertEqual(activities.count, 3)
            XCTAssertEqual(activities[0]["kind"] as? String, "inclineWalking")
            XCTAssertEqual(activities[0]["durationMinutes"] as? Int, 20)
            XCTAssertEqual(activities[0]["isCompleted"] as? Bool, true)
            XCTAssertEqual(activities[1]["isCompleted"] as? Bool, false)
            for activity in activities {
                XCTAssertNil(activity["reps"])
                XCTAssertNil(activity["loadKg"])
            }
        }
    }

    func testActivityAdviceGuardrailsReachAllCoachModesEvenWithoutCalendar() throws {
        for trainingCalendar in [plan, nil] as [TrainingCalendarPlan?] {
            for body in try requestBodies(trainingCalendar: trainingCalendar) {
                let instructions = try XCTUnwrap(body["instructions"] as? String)
                for rule in ["Optional activity never advances the upper/lower rotation",
                             "comfortable full-sentence conversation", "stretching gentle and comfortable, never painful",
                             "prioritize sleep", "at least one full recovery day", "soreness, poor sleep and pain",
                             "Never encode walking or stretching minutes", "live-workout activity-only advice uses change:null",
                             "programSessionID:null"] {
                    XCTAssertTrue(instructions.contains(rule), "Missing optional-activity rule: \(rule)")
                }
            }
        }
    }

    func testEmptyCalendarActivitiesDoNotInventCompletionOrOptionalDefaults() throws {
        var value = plan
        value.activities = []
        let context = try CoachContext.text(profile: nil, program: program, history: [], catalog: ExerciseCatalog.builtIn,
                                            now: date(14), trainingCalendar: value)
        XCTAssertTrue(context.contains("None saved. Do not assume optional activity was planned or completed."))
        XCTAssertFalse(context.contains("reported completed"))
    }

    private func archivedActivities(in context: String) throws -> [[String: Any]] {
        let prefix = "Recent reported-completed optional activities from archived blocks (past seven local dates, latest 14 records): "
        let line = try XCTUnwrap(context.components(separatedBy: "\n").first { $0.hasPrefix(prefix) })
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.dropFirst(prefix.count).utf8)) as? [[String: Any]])
    }

    func testArchivedAbsAtBlockBoundaryReachAllCoachModesWithoutOldPlansOrFutureCompletions() throws {
        // Midnight December 8 in Amsterdam is still December 7 UTC. Keep the local activity date intact.
        let observation = date(8, month: 12, hour: 0)
        var archived = TrainingCalendarPlan(startDate: date(13), cycleAnchorDate: date(17), timeZone: calendar.timeZone)
        archived.activities = [
            .init(dayOffset: 55, kind: .abs, durationMinutes: 8, isCompleted: true),
            .init(dayOffset: 54, kind: .inclineWalking, durationMinutes: 20, isCompleted: true),
            .init(dayOffset: 53, kind: .stretching, durationMinutes: 10, isCompleted: false),
            .init(dayOffset: 0, kind: .inclineWalking, durationMinutes: 30, isCompleted: true)
        ]
        var future = TrainingCalendarPlan(startDate: date(9, month: 12), cycleAnchorDate: date(17), timeZone: calendar.timeZone)
        future.activities = [.init(dayOffset: 0, kind: .abs, durationMinutes: 15, isCompleted: true)]
        let current = TrainingCalendarPlan(startDate: observation, cycleAnchorDate: date(17), timeZone: calendar.timeZone)
        for body in try requestBodies(trainingCalendar: current, trainingCalendarHistory: [archived, future], now: observation) {
            let context = try XCTUnwrap((body["input"] as? [[String: String]])?.first?["content"])
            let activities = try archivedActivities(in: context)
            XCTAssertEqual(activities.count, 2)
            XCTAssertEqual(activities[0]["localDate"] as? String, "2026-12-07")
            XCTAssertEqual(activities[0]["timeZoneIdentifier"] as? String, "Europe/Amsterdam")
            XCTAssertEqual(activities[0]["kind"] as? String, "abs")
            XCTAssertEqual(activities[0]["durationMinutes"] as? Int, 8)
            XCTAssertEqual(activities[1]["localDate"] as? String, "2026-12-06")
            XCTAssertEqual(activities[1]["kind"] as? String, "inclineWalking")
            for activity in activities {
                XCTAssertEqual(Set(activity.keys), Set(["localDate", "timeZoneIdentifier", "kind", "durationMinutes"]))
            }
        }
    }

    func testArchivedActivityContextIsLimitedToFourteenRecentCompletions() throws {
        var archived = TrainingCalendarPlan(startDate: date(13), cycleAnchorDate: date(17), timeZone: calendar.timeZone)
        for offset in 50...55 {
            archived.activities += [
                .init(dayOffset: offset, kind: .inclineWalking, isCompleted: true),
                .init(dayOffset: offset, kind: .stretching, isCompleted: true)
            ]
            if offset.isMultiple(of: 2) { archived.activities.append(.init(dayOffset: offset, kind: .abs, isCompleted: true)) }
        }
        let context = try CoachContext.text(profile: nil, program: nil, history: [], catalog: ExerciseCatalog.builtIn,
                                            now: date(8, month: 12), trainingCalendarHistory: [archived])
        let activities = try archivedActivities(in: context)
        XCTAssertEqual(activities.count, 14)
        XCTAssertEqual(activities.first?["localDate"] as? String, "2026-12-07")
        XCTAssertEqual(archived.activities.count, 15, "Context bounding must not discard saved activity")
    }
}

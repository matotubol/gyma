import Foundation

/// App-owned evidence and calculations. The language model explains these; it does not manufacture them.
public enum CoachContext {
    /// Shared by planning and live coaching so optional activity never becomes fabricated strength data.
    public static let optionalActivityGuidance = """
    Optional activities are user-chosen additions on individual calendar dates: incline treadmill walking, gentle stretching, or abs. A strength rest day may include one of these without becoming a rotating strength session. Discuss optional activity without creating or revising an unrelated strength plan. Planned activity is not completed activity; a completion marker is a user report, not measured sets or wearable evidence. Optional activity never advances the upper/lower rotation. Never claim to schedule, complete or save activity through chat.
    On recovery days, keep incline treadmill walking easy enough for comfortable full-sentence conversation; adjust speed, incline and duration to current comfort and fatigue. Do not assume a particular gradient, speed or duration is easy for this person. Keep stretching gentle and comfortable, never painful. After night shifts, prioritize sleep before deciding whether to train; being off work does not prove readiness.
    Abs are resistance training, not an automatic daily recovery activity. Leave at least one full recovery day between hard sessions for the same muscles, including direct ab work in strength workouts. Consider recent and upcoming direct ab work, soreness, poor sleep and pain before suggesting optional abs; reduce or skip work when recovery is doubtful and never train through pain. A calendar abs duration is a time budget, not sets, repetitions, load, intensity or proof of recovery. Do not infer hard or easy intensity from an activity completion marker.
    The structured strength schemas support repetition-based exercises only. Never encode walking or stretching minutes, distance, speed, incline or timed holds as repetitions or kilograms. Keep walking/stretching advice in message text and direct the user to calendar activity controls to save it. Use plan:null and program:null for activity-only advice unless a strength proposal is explicitly requested; live-workout activity-only advice uses change:null. Only in daily workout planning, a requested standalone repetition-based abs workout can use supported catalog exercises with programSessionID:null; do not attach it to the next upper/lower session merely to log optional abs. Such a strength workout still follows today's saved-calendar start eligibility. On recovery days, use optional Calendar activity controls for abs; do not offer a strength workout start. Recurring-program planning must still return plan:null; live coaching can only propose supported changes to the existing workout.
    Recovery reference: https://www.mayoclinic.org/healthy-lifestyle/fitness/basics/strength-training/hlv-20049447 . Talking effort reference: https://www.cdc.gov/physical-activity-basics/measuring/ . Easy recovery activity and adjustable activity time budgets are conservative product guidance, not a personalized medical prescription.
    """

    public static let principles = """
    Training principles, reviewed 2026-10-09: use a repeatable program matched to goals, equipment, preferences and available time. More volume and training to failure are not automatically better. ACSM 2026: https://acsm.org/resistance-training-guidelines-update-2026/ . Repetition and load progression are both viable: https://pubmed.ncbi.nlm.nih.gov/36199287/ . Near-failure training can build muscle without requiring failure on every set: https://pubmed.ncbi.nlm.nih.gov/38393985/ . These population findings are starting principles, not proof of an individual's optimal dose. Progression thresholds and session-duration estimates in this app are transparent product heuristics. Do not infer injury risk, medical diagnoses, exact recovery percentages or causation from correlations. Preserve unknown effort and unclassified sets. Pain differs from soreness. A normal wearable reading cannot establish muscular recovery. Stable profile facts are confirmed by the user; dated check-ins and workout feedback are temporary context, never permanent facts. Never claim to have saved a new fact or changed the profile through chat.
    """

    public static func text(profile: AthleteProfile?, program: TrainingProgram?, history: [Workout],
                            catalog: [ExerciseDefinition], reviews: [WorkoutReview] = [], feedback: [WorkoutFeedback] = [],
                            relevantExerciseIDs: [String] = [], now: Date = Date(), priorPrograms: [TrainingProgram] = [], trainingCalendar: TrainingCalendarPlan? = nil,
                            trainingCalendarHistory: [TrainingCalendarPlan] = []) throws -> String {
        try profile?.validate()
        try program?.validate(catalog: catalog)
        try trainingCalendar?.validate()
        for archived in trainingCalendarHistory { try archived.validate() }
        var boundedProfile = profile
        boundedProfile?.bodyweightHistory = Array((profile?.bodyweightHistory ?? []).sorted { $0.recordedAt > $1.recordedAt }.prefix(90))
        let requested = relevantExerciseIDs.isEmpty ? (program?.nextSession(history: history, now: now)?.exercises.map(\.exerciseID) ?? []) : relevantExerciseIDs
        let completed = history.filter { $0.end.map { $0 <= now } == true }.sorted { $0.start > $1.start }
        var seen = Set<String>()
        let candidates = requested + completed.flatMap { $0.exercises.map(\.exerciseID) }
        let relevant = Array(candidates.filter { seen.insert($0).inserted }.prefix(12))
        let analytics = TrainingAnalytics.make(workouts: history, catalog: catalog, now: now, relevantExerciseIDs: relevant)
        let comparisons = relevant.compactMap { id -> ExerciseProgressComparison? in
            guard let exercise = catalog.first(where: { $0.id == id }) else { return nil }
            return ExerciseProgressComparison.make(exercise: exercise, workouts: history, now: now)
        }
        let completedIDs = Set(history.filter { !$0.isActive }.map(\.id))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
        return """
        Observation date: \(try json(now))
        Confirmed athlete profile (bodyweight limited to latest 90 measurements): \(try json(boundedProfile))
        Accepted program: \(try json(program))
        \(try calendarContext(trainingCalendar, program: program, history: history, now: now))
        Recent reported-completed optional activities from archived blocks (past seven local dates, latest 14 records): \(try json(recentArchivedActivities(trainingCalendarHistory, now: now)))
        Archived activity dates use each record's saved time zone. They inform recent recovery; they are not the current schedule. Completion does not establish intensity, measured performance or readiness.
        Next rotating session: \(try json(program?.nextSession(history: history, now: now)))
        Deterministic next-session targets before today's readiness/time adjustments: \(try json(program.flatMap { p in p.nextSession(history: history, now: now).map { p.recommendations(for: $0, history: history, now: now, catalog: catalog, priorPrograms: priorPrograms) } }))
        Exercise equipment, direct and secondary muscle metadata: \(try json(catalog.map { CatalogContext(id: $0.id, metadata: $0.trainingMetadata) }))
        Computed full-history analytics, relevant exposures and missing-data coverage: \(try json(analytics))
        First and latest working exposures across all retained calendar blocks, for these relevant exercises: \(try json(comparisons))
        These comparisons retain early baseline results even when they are outside the recent-session detail below. A single exposure is not a trend. Load differences alone do not establish improvement: compare repetitions, working-set counts, recorded effort, equipment and load convention. Working-set samples are limited to ten per exposure; totals include all classified working sets. Missing effort stays unknown. Calendar rollover does not reset workout history or these comparisons. Do not invent a specific eight-week or block-to-block result when its dates or intermediate sessions are not in this context.
        Actual sets for relevant exercises (latest four exposures per exercise, latest ten sets per exposure): \(try json(relevant.map { id in
            RelevantExerciseRecords(exerciseID: id, exposures: Array(completed.compactMap { workout in
                workout.exercises.first(where: { $0.exerciseID == id && !$0.sets.isEmpty }).map { entry in
                    RelevantRecord(workoutID: workout.id, date: workout.start, target: entry.target, sets: Array(entry.sets.suffix(10)), totalLoggedSets: entry.sets.count)
                }
            }.prefix(4)))
        }))
        Latest saved workout reviews: \(try json(Array(reviews.filter { completedIDs.contains($0.workoutID) }.sorted { $0.createdAt > $1.createdAt }.prefix(4))))
        Dated workout feedback, not permanent restrictions: \(try json(Array(feedback.filter { completedIDs.contains($0.workoutID) }.sorted { $0.recordedAt > $1.recordedAt }.prefix(6))))
        Reviews capture the evidence at finish time. Newer pain/discomfort feedback takes precedence over earlier progression proposals and needs discussion before increasing demands.
        \(principles)
        """
    }

    private static func recentArchivedActivities(_ plans: [TrainingCalendarPlan], now: Date) -> [ArchivedActivity] {
        var records: [(date: Date, activity: ArchivedActivity)] = []
        for plan in plans {
            let today = plan.calendar.startOfDay(for: now)
            guard let earliest = plan.calendar.date(byAdding: .day, value: -6, to: today) else { continue }
            let formatter = DateFormatter()
            formatter.calendar = plan.calendar; formatter.timeZone = plan.calendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
            for activity in plan.activities where activity.isCompleted {
                guard let date = plan.date(at: activity.dayOffset), date >= earliest, date <= today, date <= now else { continue }
                records.append((date, ArchivedActivity(localDate: formatter.string(from: date), timeZoneIdentifier: plan.timeZoneIdentifier,
                                                       kind: activity.kind, durationMinutes: activity.durationMinutes)))
            }
        }
        return records.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            if $0.activity.timeZoneIdentifier != $1.activity.timeZoneIdentifier {
                return $0.activity.timeZoneIdentifier < $1.activity.timeZoneIdentifier
            }
            return $0.activity.kind.rawValue < $1.activity.kind.rawValue
        }.prefix(14).map { $0.activity }
    }

    private static func calendarContext(_ plan: TrainingCalendarPlan?, program: TrainingProgram?, history: [Workout], now: Date) throws -> String {
        guard let plan else { return "No saved training calendar. Ask about scheduling preferences when needed." }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let saved = String(decoding: try encoder.encode(plan), as: UTF8.self)
        let formatter = DateFormatter()
        formatter.calendar = plan.calendar; formatter.timeZone = plan.calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let entries = plan.entries(program: program, history: history, now: now)
        let upcoming = entries
            .filter { $0.date >= plan.calendar.startOfDay(for: now) && $0.isTraining && $0.workouts.isEmpty }
            .map { "\(formatter.string(from: $0.date)): \($0.shift.label), \($0.session?.title ?? "training slot; no saved session")" }
            .joined(separator: "\n")
        let activities = entries.filter { !$0.activities.isEmpty }.map { entry in
            let details = entry.activities.map { activity in
                "\(activity.kind.rawValue): \(activity.isCompleted ? "reported completed" : "planned only"), \(activity.durationMinutes) minutes (time budget)"
            }.joined(separator: "; ")
            return "\(formatter.string(from: entry.date)): \(details)"
        }.joined(separator: "\n")
        var calendarState = GymaState()
        calendarState.trainingCalendar = plan
        calendarState.workouts = history
        let availability: String
        switch calendarState.dailyTrainingStatus(now: now) {
        case .beforeStart(let start):
            availability = "BLOCK NOT STARTED. The block begins \(formatter.string(from: start)); no strength workout can start today. Future sessions are previews."
        case .recoveryDay:
            availability = "RECOVERY DAY. Optional activities may be planned or completed, but no strength workout can start today."
        case .completedToday:
            availability = "TODAY ALREADY RECORDED. Review the saved workout; do not offer the next rotating session as ready today."
        case .blockComplete:
            availability = "BLOCK COMPLETE. Review history and save a new calendar block before starting another strength workout."
        case .activeWorkout:
            availability = "WORKOUT IN PROGRESS. The existing workout can be resumed, including after midnight; no new workout can start."
        case .trainingDay:
            availability = "TRAINING DAY. Today's workout may start after readiness and plan review. Future sessions remain previews."
        case .noCalendar, .unavailable:
            availability = "Check the saved training calendar before offering a workout start."
        }
        return """
        User-confirmed eight-week training calendar: \(saved)
        Shift cycle: 2 mornings, 2 afternoons, 2 nights, 4 days off; cycle day 1 is the saved first morning date. Scheduled baseline: \(plan.trainingCycleDays.count) sessions per 10 days, NOT per week. Date exceptions are explicit user choices.
        Training block starts \(formatter.string(from: plan.startDate)); first morning shift anchor is \(formatter.string(from: plan.cycleAnchorDate)). These dates are independent: the block can begin on days off before the first morning shift. Start-day shift: \(plan.shift(on: plan.startDate).label), cycle day \(plan.cycleDay(on: plan.startDate)).
        Calendar dates in \(plan.timeZoneIdentifier): \(formatter.string(from: plan.startDate)) through \(formatter.string(from: plan.lastDate)); review on \(formatter.string(from: plan.reviewDate)). Block has ended: \(now >= plan.reviewDate).
        Today's calendar availability: \(availability)
        Discussing or saving a program is allowed before the block begins and on recovery days. Do not tell the user a future session is ready to start today. A draft dated today cannot override the calendar. The user can explicitly adjust dates in Calendar; chat does not reschedule or start workouts.
        Upper/lower preference: \(plan.prefersUpperLower ? "Yes. When creating or revising a program, propose alternating upper/lower sessions in continuous order across cycles, subject to profile constraints and user review. Do not silently replace an existing program." : "Follow the saved program and discuss the user's preferred split.")
        Upcoming projected sessions, assuming future planned sessions are completed:
        \(upcoming.isEmpty ? "None remaining in this block." : upcoming)
        Optional activity by local calendar date, separate from strength sessions:
        \(activities.isEmpty ? "None saved. Do not assume optional activity was planned or completed." : activities)
        While the block is current, the confirmed calendar takes precedence over the profile's approximate days-per-week field. An expired block is historical, not a new schedule. The calendar does not prove recovery or completion. Missed dates never add catch-up volume or advance the actual program. Only logged, linked completed training advances rotation; future labels may shift after missed or extra sessions. Keep the program's useful exercises stable while progressing from observed performance. The eight-week review date does not require new exercises, a deload or an automatic increase in workload. You may discuss changes, but calendar edits must be made explicitly in the app; never claim to have saved dates or workouts through chat.
        """
    }

    private struct CatalogContext: Encodable { let id: String; let metadata: ExerciseMetadata? }
    private struct ArchivedActivity: Encodable {
        let localDate: String; let timeZoneIdentifier: String; let kind: CalendarActivityKind; let durationMinutes: Int
    }
    private struct RelevantExerciseRecords: Encodable { let exerciseID: String; let exposures: [RelevantRecord] }
    private struct RelevantRecord: Encodable { let workoutID: String; let date: Date; let target: ExerciseTarget?; let sets: [WorkSet]; let totalLoggedSets: Int }
}

public enum CoachingConstraints {
    public static func validate(exercises: [WorkoutExercise], profile: AthleteProfile?, catalog: [ExerciseDefinition]) throws {
        let excluded = Set((profile?.avoidedExercises ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        for entry in exercises {
            guard let definition = catalog.first(where: { $0.id == entry.exerciseID }), definition.trainingMetadata?.measurement != .seconds else {
                throw GymaError.invalid("Choose a supported repetition-based exercise from your library.")
            }
            guard !excluded.contains(definition.id.lowercased()), !excluded.contains(definition.name.lowercased()) else {
                throw GymaError.invalid("\(definition.name) is in your profile's avoided exercises. Ask the coach for a substitution.")
            }
            if let profile, !profile.equipment.isEmpty, let required = definition.trainingMetadata?.equipment,
               required != .bodyweight, !profile.equipment.contains(required) {
                throw GymaError.invalid("\(definition.name) requires \(required.label.lowercased()), which is not selected in your profile. Choose a compatible exercise or update your equipment.")
            }
        }
    }
}

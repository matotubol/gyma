import Foundation

public struct TrainingCalendarOverride: Codable, Sendable, Equatable {
    public var dayOffset: Int
    public var isTraining: Bool

    public init(dayOffset: Int, isTraining: Bool) {
        self.dayOffset = dayOffset
        self.isTraining = isTraining
    }
}

public struct TrainingCalendarDay: Sendable, Equatable, Identifiable {
    public var id: Int { dayOffset }
    public var dayOffset: Int
    public var date: Date
    public var cycleDay: Int
    public var shift: Shift
    public var isTraining: Bool
    /// A projection of the existing program template, never a completed workout or a load prediction.
    public var session: ProgramSession?
    public var workouts: [Workout]
    public var activities: [CalendarActivity]
}

/// A fixed eight-week block, anchored to a repeating 2 morning / 2 afternoon / 2 night / 4 off cycle.
/// Dates use the saved planning time zone even when the device later changes time zone.
public struct TrainingCalendarPlan: Codable, Sendable, Equatable {
    public static let dayCount = 56
    public var startDate: Date
    public var cycleAnchorDate: Date
    public var timeZoneIdentifier: String
    public var trainingCycleDays: [Int]
    public var dayOverrides: [TrainingCalendarOverride]
    public var prefersUpperLower: Bool
    public var activities: [CalendarActivity]

    public init(startDate: Date, cycleAnchorDate: Date, trainingCycleDays: [Int] = [2, 5, 8, 9, 10], timeZone: TimeZone = .current, prefersUpperLower: Bool = true) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.startDate = Self.supportedDate(startDate) ? calendar.startOfDay(for: startDate) : startDate
        self.cycleAnchorDate = Self.supportedDate(cycleAnchorDate) ? calendar.startOfDay(for: cycleAnchorDate) : cycleAnchorDate
        self.timeZoneIdentifier = timeZone.identifier
        self.trainingCycleDays = trainingCycleDays.sorted()
        self.dayOverrides = []
        self.prefersUpperLower = prefersUpperLower
        self.activities = []
    }

    private enum CodingKeys: String, CodingKey {
        case startDate, cycleAnchorDate, timeZoneIdentifier, trainingCycleDays, dayOverrides, prefersUpperLower, activities
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        startDate = try values.decode(Date.self, forKey: .startDate)
        cycleAnchorDate = try values.decode(Date.self, forKey: .cycleAnchorDate)
        timeZoneIdentifier = try values.decode(String.self, forKey: .timeZoneIdentifier)
        trainingCycleDays = try values.decode([Int].self, forKey: .trainingCycleDays)
        dayOverrides = try values.decode([TrainingCalendarOverride].self, forKey: .dayOverrides)
        prefersUpperLower = try values.decode(Bool.self, forKey: .prefersUpperLower)
        // Existing backups predate optional activities and keep their exact saved schedule.
        activities = try values.decodeIfPresent([CalendarActivity].self, forKey: .activities) ?? []
    }

    /// Fresh setup only: October 13 is the first off day after nights; the first morning
    /// remains October 17. Never apply this factory over an already saved calendar.
    public static func defaultPlan(now: Date = Date(), timeZone: TimeZone = .current) -> Self {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let opening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13))!
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17))!
        let today = Self.supportedDate(now) ? calendar.startOfDay(for: now) : opening
        var plan = Self(startDate: max(today, opening), cycleAnchorDate: anchor, timeZone: timeZone)
        // Start after sleep on the 13th, then train on the 14th and 16th with a recovery day between.
        if let offset = plan.dayOffset(for: opening) { plan.setOverride(at: offset, isTraining: true) }
        if let recovery = calendar.date(byAdding: .day, value: 2, to: opening), let offset = plan.dayOffset(for: recovery) {
            plan.setOverride(at: offset, isTraining: false)
        }
        return plan
    }

    /// Rebuild setup without silently moving or dropping the user's individual dates.
    public func reconfigured(startDate: Date, cycleAnchorDate: Date, trainingCycleDays: [Int], prefersUpperLower: Bool) throws -> Self {
        try validate()
        var result = Self(startDate: startDate, cycleAnchorDate: cycleAnchorDate, trainingCycleDays: trainingCycleDays,
                          timeZone: calendar.timeZone, prefersUpperLower: prefersUpperLower)
        // A later, non-overlapping block is fresh; the state layer archives this entire block.
        if result.startDate >= reviewDate {
            try result.validate()
            return result
        }
        if activities.contains(where: \.isCompleted), result.startDate != self.startDate {
            throw GymaError.invalid("The block start cannot change after an optional activity is completed.")
        }
        for override in dayOverrides {
            guard let date = date(at: override.dayOffset), let offset = result.dayOffset(for: date) else {
                throw GymaError.invalid("That block would discard a saved training-date change. Keep that date inside the block.")
            }
            result.setOverride(at: offset, isTraining: override.isTraining)
        }
        for activity in activities {
            guard let date = date(at: activity.dayOffset), let offset = result.dayOffset(for: date) else {
                throw GymaError.invalid("That block would discard a saved optional activity. Keep that date inside the block.")
            }
            var moved = activity
            moved.dayOffset = offset
            result.activities.append(moved)
        }
        try result.validate()
        return result
    }

    public var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0) ?? .current
        return value
    }

    public var dates: [Date] { (0..<Self.dayCount).compactMap { date(at: $0) } }
    public var lastDate: Date { date(at: Self.dayCount - 1) ?? safeStartDate }
    /// The review is due after all 56 days; it does not reset the program or automatically replace this block.
    public var reviewDate: Date {
        calendar.date(byAdding: .day, value: Self.dayCount, to: safeStartDate) ?? lastDate
    }

    public func validate() throws {
        guard Self.supportedDate(startDate), Self.supportedDate(cycleAnchorDate),
              TimeZone(identifier: timeZoneIdentifier) != nil,
              (1...10).contains(trainingCycleDays.count),
              trainingCycleDays.allSatisfy({ (1...10).contains($0) }),
              Set(trainingCycleDays).count == trainingCycleDays.count,
              dayOverrides.count <= Self.dayCount,
              dayOverrides.allSatisfy({ (0..<Self.dayCount).contains($0.dayOffset) }),
              Set(dayOverrides.map(\.dayOffset)).count == dayOverrides.count,
              activities.count <= Self.dayCount * CalendarActivityKind.allCases.count,
              Set(activities.map(\.id)).count == activities.count,
              dates.count == Self.dayCount, Self.supportedDate(reviewDate) else {
            throw GymaError.invalid("A training calendar needs a valid eight-week block, time zone, and unique cycle days from 1 to 10.")
        }
        for activity in activities { try activity.validate() }
        let absDays = Set(activities.filter { $0.kind == .abs }.map(\.dayOffset))
        guard !absDays.contains(where: { absDays.contains($0 + 1) }) else {
            throw GymaError.invalid("Leave at least one day between direct ab sessions, including planned or completed abs.")
        }
    }

    public func date(at offset: Int) -> Date? {
        guard (0..<Self.dayCount).contains(offset), Self.supportedDate(startDate),
              TimeZone(identifier: timeZoneIdentifier) != nil else { return nil }
        return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: startDate))
    }

    public func dayOffset(for date: Date) -> Int? {
        guard Self.supportedDate(date), Self.supportedDate(startDate),
              TimeZone(identifier: timeZoneIdentifier) != nil,
              let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: calendar.startOfDay(for: date)).day,
              (0..<Self.dayCount).contains(offset) else { return nil }
        return offset
    }

    /// One-based shift-cycle day, also defined before the anchor and outside this eight-week block.
    public func cycleDay(on date: Date) -> Int {
        guard Self.supportedDate(date), Self.supportedDate(cycleAnchorDate),
              let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: cycleAnchorDate), to: calendar.startOfDay(for: date)).day else { return 1 }
        return ((offset % 10) + 10) % 10 + 1
    }

    public func shift(on date: Date) -> Shift {
        switch cycleDay(on: date) {
        case 1, 2: return .morning
        case 3, 4: return .afternoon
        case 5, 6: return .night
        default: return .off
        }
    }

    public func isTrainingDay(on date: Date) -> Bool {
        guard let offset = dayOffset(for: date) else { return false }
        return dayOverrides.first(where: { $0.dayOffset == offset })?.isTraining ?? trainingCycleDays.contains(cycleDay(on: date))
    }

    public func activities(on date: Date) -> [CalendarActivity] {
        guard let offset = dayOffset(for: date) else { return [] }
        return activities.filter { $0.dayOffset == offset }.sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    public mutating func setActivity(on date: Date, kind: CalendarActivityKind, isPlanned: Bool, durationMinutes: Int? = nil, now: Date = Date()) throws {
        try validate()
        let offset = try editableOffset(for: date, now: now)
        let existing = activities.first { $0.dayOffset == offset && $0.kind == kind }
        var candidate = self
        if isPlanned {
            let activity = CalendarActivity(dayOffset: offset, kind: kind,
                                            durationMinutes: durationMinutes ?? existing?.durationMinutes,
                                            isCompleted: existing?.isCompleted ?? false)
            guard existing?.isCompleted != true || activity == existing else {
                throw GymaError.invalid("Undo today's activity completion before changing its duration.")
            }
            candidate.activities.removeAll { $0.dayOffset == offset && $0.kind == kind }
            candidate.activities.append(activity)
        } else {
            guard existing?.isCompleted != true else {
                throw GymaError.invalid("Undo today's activity completion before removing it.")
            }
            candidate.activities.removeAll { $0.dayOffset == offset && $0.kind == kind }
        }
        candidate.activities.sort { $0.dayOffset == $1.dayOffset ? $0.kind.rawValue < $1.kind.rawValue : $0.dayOffset < $1.dayOffset }
        try candidate.validate()
        self = candidate
    }

    /// Completion and undo are deliberately limited to today; future plans are not history.
    public mutating func setActivityCompleted(on date: Date, kind: CalendarActivityKind, isCompleted: Bool, now: Date = Date()) throws {
        try validate()
        let offset = try editableOffset(for: date, now: now)
        guard calendar.isDate(date, inSameDayAs: now),
              let index = activities.firstIndex(where: { $0.dayOffset == offset && $0.kind == kind }) else {
            throw GymaError.invalid("Only a planned activity for today can be marked done or undone.")
        }
        activities[index].isCompleted = isCompleted
    }

    public mutating func setTrainingDay(on date: Date, isTraining: Bool, now: Date = Date()) throws {
        try validate()
        let offset = try editableOffset(for: date, now: now)
        setOverride(at: offset, isTraining: isTraining)
    }

    /// Both dates are checked before mutation, so a rejected move preserves the entire plan.
    /// The state layer additionally protects dates with recorded workouts.
    public mutating func moveTrainingDay(from source: Date, to destination: Date, now: Date = Date()) throws {
        try validate()
        let sourceOffset = try editableOffset(for: source, now: now)
        let destinationOffset = try editableOffset(for: destination, now: now)
        guard sourceOffset != destinationOffset, isTrainingDay(on: source), !isTrainingDay(on: destination) else {
            throw GymaError.invalid("Move a planned training day to a different rest day within this block.")
        }
        setOverride(at: sourceOffset, isTraining: false)
        setOverride(at: destinationOffset, isTraining: true)
    }

    /// Actual workouts are grouped by their start date regardless of their program or planned slot.
    /// Past missed slots never consume a session. Today's recorded workout suppresses a duplicate
    /// projection; only completed, linked working sets advance TrainingProgram.nextSession.
    /// An active workout therefore keeps its session pending until it is completed.
    public func entries(program: TrainingProgram?, history: [Workout], now: Date = Date()) -> [TrainingCalendarDay] {
        guard (try? validate()) != nil, Self.supportedDate(now) else { return [] }
        let today = calendar.startOfDay(for: now)
        var recorded: [Int: [Workout]] = [:]
        for workout in history where workout.start <= now {
            if let offset = dayOffset(for: workout.start) { recorded[offset, default: []].append(workout) }
        }
        let sessions = program?.sessions ?? []
        let nextID = program?.nextSession(history: history, now: now)?.id
        var nextIndex = nextID.flatMap { id in sessions.firstIndex(where: { $0.id == id }) }

        return dates.enumerated().map { offset, date in
            let actual = (recorded[offset] ?? []).sorted {
                $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start
            }
            let training = isTrainingDay(on: date)
            var session: ProgramSession?
            if date >= today, training, actual.isEmpty, let index = nextIndex, !sessions.isEmpty {
                session = sessions[index]
                nextIndex = (index + 1) % sessions.count
            }
            return TrainingCalendarDay(dayOffset: offset, date: date, cycleDay: cycleDay(on: date), shift: shift(on: date), isTraining: training, session: session, workouts: actual, activities: activities(on: date))
        }
    }

    private var safeStartDate: Date {
        Self.supportedDate(startDate) ? calendar.startOfDay(for: startDate) : Date(timeIntervalSince1970: 0)
    }

    private static func supportedDate(_ date: Date) -> Bool {
        (-2_208_988_800.0...4_102_444_800.0).contains(date.timeIntervalSince1970)
    }

    private func editableOffset(for date: Date, now: Date) throws -> Int {
        guard Self.supportedDate(now), let offset = dayOffset(for: date),
              calendar.startOfDay(for: date) >= calendar.startOfDay(for: now) else {
            throw GymaError.invalid("Only today or a future date inside this eight-week block can be edited.")
        }
        return offset
    }

    private mutating func setOverride(at offset: Int, isTraining: Bool) {
        guard let date = date(at: offset) else { return }
        dayOverrides.removeAll { $0.dayOffset == offset }
        if isTraining != trainingCycleDays.contains(cycleDay(on: date)) {
            dayOverrides.append(.init(dayOffset: offset, isTraining: isTraining))
        }
        dayOverrides.sort { $0.dayOffset < $1.dayOffset }
    }
}

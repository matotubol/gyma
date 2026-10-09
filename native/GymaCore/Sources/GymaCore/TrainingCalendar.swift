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

    public init(startDate: Date, cycleAnchorDate: Date, trainingCycleDays: [Int] = [2, 5, 8, 9, 10], timeZone: TimeZone = .current, prefersUpperLower: Bool = true) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.startDate = Self.supportedDate(startDate) ? calendar.startOfDay(for: startDate) : startDate
        self.cycleAnchorDate = Self.supportedDate(cycleAnchorDate) ? calendar.startOfDay(for: cycleAnchorDate) : cycleAnchorDate
        self.timeZoneIdentifier = timeZone.identifier
        self.trainingCycleDays = trainingCycleDays.sorted()
        self.dayOverrides = []
        self.prefersUpperLower = prefersUpperLower
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
              dates.count == Self.dayCount, Self.supportedDate(reviewDate) else {
            throw GymaError.invalid("A training calendar needs a valid eight-week block, time zone, and unique cycle days from 1 to 10.")
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
            return TrainingCalendarDay(dayOffset: offset, date: date, cycleDay: cycleDay(on: date), shift: shift(on: date), isTraining: training, session: session, workouts: actual)
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

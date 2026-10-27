import Foundation

/// Civil `YYYY-MM-DD` date keys in the device's calendar, never converted to UTC instants.
/// Port of gym-web/web/src/calendar.ts.
public enum CivilDate {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    public static func key(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1)
    }

    public static var today: String { key(Date()) }

    /// Midday on the given date, so formatting never slips to a neighbouring day.
    public static func parse(_ key: String) -> Date {
        let numbers = key.split(separator: "-").compactMap { Int($0) }
        let components = DateComponents(year: numbers.count > 0 ? numbers[0] : 2026, month: numbers.count > 1 ? numbers[1] : 1,
                                        day: numbers.count > 2 ? numbers[2] : 1, hour: 12)
        return calendar.date(from: components) ?? Date()
    }

    public static func isValid(_ key: String) -> Bool {
        key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil && self.key(parse(key)) == key
    }

    public static func month(of key: String) -> String { String(key.prefix(7)) }

    public static func shift(day key: String, by offset: Int) -> String {
        Self.key(calendar.date(byAdding: .day, value: offset, to: parse(key)) ?? parse(key))
    }

    public static func shift(month: String, by offset: Int) -> String {
        let first = parse(month + "-01")
        return String(Self.key(calendar.date(byAdding: .month, value: offset, to: first) ?? first).prefix(7))
    }

    /// Whole weeks (Monday first) covering the month, including neighbouring days.
    public static func cells(month: String) -> [String] {
        let first = parse(month + "-01")
        let weekday = calendar.component(.weekday, from: first) // 1 = Sunday
        let offset = (weekday + 5) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let count = Int((Double(offset + daysInMonth) / 7).rounded(.up)) * 7
        let start = calendar.date(byAdding: .day, value: -offset, to: first) ?? first
        return (0..<count).map { key(calendar.date(byAdding: .day, value: $0, to: start) ?? start) }
    }
}

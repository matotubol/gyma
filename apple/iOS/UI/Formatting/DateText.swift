import Foundation
import GymaCore

/// British date labels, matching the web client's `en-GB` formatting.
enum DateText {
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = format
        return formatter
    }

    private static let fullFormatter = formatter("EEEE d MMMM yyyy")
    private static let shortDayFormatter = formatter("EEE d MMM")
    private static let dayMonthFormatter = formatter("d MMM")
    private static let longFormatter = formatter("d MMM yyyy")
    private static let monthFormatter = formatter("MMMM yyyy")
    private static let weekdayFormatter = formatter("EEEE")

    /// "Tuesday 27 October 2026"
    static func full(_ key: String) -> String { fullFormatter.string(from: CivilDate.parse(key)) }
    /// "Tue 27 Oct"
    static func shortDay(_ key: String) -> String { shortDayFormatter.string(from: CivilDate.parse(key)) }
    /// "27 Oct"
    static func dayMonth(_ key: String) -> String { dayMonthFormatter.string(from: CivilDate.parse(key)) }
    /// "27 Oct 2026"
    static func long(_ key: String) -> String { longFormatter.string(from: CivilDate.parse(key)) }
    /// "October 2026"
    static func month(_ month: String) -> String { monthFormatter.string(from: CivilDate.parse(month + "-01")) }
    /// "Tuesday"
    static func weekday(_ key: String) -> String { weekdayFormatter.string(from: CivilDate.parse(key)) }
}

extension LibraryExercise {
    /// "Matrix · Machine"
    var detail: String { [brand?.rawValue, equipment.label].compactMap { $0 }.joined(separator: " · ") }
}

extension Optional where Wrapped == DayKind {
    var label: String {
        switch self {
        case .some(.training): "Training"
        case .some(.rest): "Rest"
        case .none: "Unplanned"
        }
    }
}

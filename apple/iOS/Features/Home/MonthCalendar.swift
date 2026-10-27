import SwiftUI
import UIKit
import GymaCore

/// The system calendar (`UICalendarView`) with a dot under training and rest days.
struct MonthCalendar: UIViewRepresentable {
    let selected: String
    let month: String
    let days: [String: CalendarDay]
    let onSelect: (String) -> Void
    let onMonthChange: (String) -> Void

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday, as on the web
        calendar.timeZone = .current
        return calendar
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = Self.calendar
        view.fontDesign = .rounded
        view.delegate = context.coordinator
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        selection.selectedDate = Self.components(selected)
        view.selectionBehavior = selection
        view.visibleDateComponents = Self.components(month + "-01")
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        context.coordinator.shownDays = days
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if let selection = view.selectionBehavior as? UICalendarSelectionSingleDate,
           Self.key(selection.selectedDate) != selected {
            selection.setSelected(Self.components(selected), animated: true)
        }
        if Self.monthKey(view.visibleDateComponents) != month {
            view.setVisibleDateComponents(Self.components(month + "-01"), animated: true)
        }
        let changed = Set(days.keys).union(coordinator.shownDays.keys).filter { days[$0]?.kind != coordinator.shownDays[$0]?.kind }
        coordinator.shownDays = days
        if !changed.isEmpty {
            view.reloadDecorations(forDateComponents: changed.map(Self.components), animated: true)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context: Context) -> CGSize? {
        let width = proposal.width ?? 360
        let fitted = uiView.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                    withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        return CGSize(width: width, height: fitted.height)
    }

    static func components(_ key: String) -> DateComponents {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        return DateComponents(calendar: calendar, year: parts.first, month: parts.count > 1 ? parts[1] : nil, day: parts.count > 2 ? parts[2] : nil)
    }

    static func key(_ components: DateComponents?) -> String? {
        guard let year = components?.year, let month = components?.month, let day = components?.day else { return nil }
        return String(format: "%04ld-%02ld-%02ld", year, month, day)
    }

    static func monthKey(_ components: DateComponents) -> String? {
        guard let year = components.year, let month = components.month else { return nil }
        return String(format: "%04ld-%02ld", year, month)
    }

    @MainActor
    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: MonthCalendar
        var shownDays: [String: CalendarDay] = [:]

        init(_ parent: MonthCalendar) { self.parent = parent }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let key = MonthCalendar.key(dateComponents), let kind = parent.days[key]?.kind else { return nil }
            return .default(color: kind == .training ? .systemGreen : .systemBlue, size: .medium)
        }

        func calendarView(_ calendarView: UICalendarView, didChangeVisibleDateComponentsFrom previousDateComponents: DateComponents) {
            if let month = MonthCalendar.monthKey(calendarView.visibleDateComponents) { parent.onMonthChange(month) }
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            if let key = MonthCalendar.key(dateComponents) { parent.onSelect(key) }
        }
    }
}

import SwiftUI
import GymaCore

/// A compact Monday-first week using the same date keys and selection as the system month calendar.
struct WeekCalendar: View {
    let selected: String
    let days: [String: CalendarDay]
    let onSelect: (String) -> Void

    private var week: [String] {
        let cells = CivilDate.cells(month: CivilDate.month(of: selected))
        guard let index = cells.firstIndex(of: selected) else { return [] }
        let start = index / 7 * 7
        return Array(cells[start..<(start + 7)])
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(week, id: \.self) { key in
                Button { onSelect(key) } label: {
                    VStack(spacing: 5) {
                        Text(CivilDate.parse(key), format: .dateTime.weekday(.narrow))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(CivilDate.parse(key), format: .dateTime.day())
                            .font(.body.weight(key == selected ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(key == selected ? Color.white : Color.primary)
                            .frame(width: 32, height: 32)
                            .background(key == selected ? Color.accentColor : Color.clear, in: Circle())
                            .overlay {
                                if key == CivilDate.today && key != selected {
                                    Circle().strokeBorder(Color.accentColor, lineWidth: 1)
                                }
                            }
                        Circle()
                            .fill(days[key]?.kind.tint ?? Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(DateText.full(key) + (key == CivilDate.today ? ", Today" : ""))
                .accessibilityAddTraits(key == selected ? .isSelected : [])
            }
        }
    }
}

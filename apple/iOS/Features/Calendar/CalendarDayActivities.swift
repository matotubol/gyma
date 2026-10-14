import Foundation
import SwiftUI
import GymaCore

struct CalendarDayActivities: View {
    @EnvironmentObject private var model: GymaAppModel
    @State private var error: String?
    let day: TrainingCalendarDay
    let plan: TrainingCalendarPlan
    let now: Date

    private var canEdit: Bool {
        day.date >= plan.calendar.startOfDay(for: now)
    }

    private var isToday: Bool { plan.calendar.isDate(day.date, inSameDayAs: now) }

    private var availableKinds: [CalendarActivityKind] {
        CalendarActivityKind.allCases.filter { kind in !day.activities.contains(where: { $0.kind == kind }) }
    }

    var body: some View {
        Section {
            if day.activities.isEmpty {
                Text("No optional activities planned.").foregroundStyle(.secondary)
            }
            ForEach(day.activities) { activity in activityRow(activity) }
            if canEdit && !availableKinds.isEmpty {
                Menu {
                    ForEach(availableKinds) { kind in
                        Button(kind.title, systemImage: calendarActivitySymbol(kind)) {
                            updateActivity { try $0.setCalendarActivity(on: day.date, kind: kind, isPlanned: true, now: Date()) }
                        }
                    }
                } label: {
                    Label("Add an optional activity", systemImage: "plus.circle")
                }.disabled(model.storageBlocked)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        } header: { Text("Optional activities") } footer: {
            Text("Add these on strength or recovery days when you feel recovered. Walking and stretching can stay easy; hard abs sessions need recovery too. Activities do not advance your strength program. Mark them done on the day; past dates stay unchanged.")
        }
    }

    private func activityRow(_ activity: CalendarActivity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(activity.kind.title, systemImage: calendarActivitySymbol(activity.kind)).font(.headline)
                Spacer()
                if activity.isCompleted {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(GymaStyle.accent)
                        .accessibilityLabel("Completed")
                }
            }
            if canEdit && !activity.isCompleted {
                Stepper(value: Binding(get: { activity.durationMinutes }, set: { minutes in
                    updateActivity {
                        try $0.setCalendarActivity(on: day.date, kind: activity.kind, isPlanned: true, durationMinutes: minutes, now: Date())
                    }
                }), in: activity.kind.durationRange, step: 5) {
                    Text("\(activity.durationMinutes) min").font(.subheadline)
                }
                .accessibilityLabel("\(activity.kind.title) duration")
                .disabled(model.storageBlocked)
            } else {
                Text("\(activity.durationMinutes) min · \(activity.isCompleted ? "Completed" : "Planned")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text(activity.kind.guidance).font(.caption).foregroundStyle(.secondary)
            if canEdit {
                HStack {
                    if isToday {
                        Button(activity.isCompleted ? "Undo completion" : "Mark done", systemImage: activity.isCompleted ? "arrow.uturn.backward" : "checkmark") {
                            updateActivity {
                                try $0.setCalendarActivityCompleted(on: day.date, kind: activity.kind, isCompleted: !activity.isCompleted, now: Date())
                            }
                        }
                        .disabled(model.storageBlocked)
                    }
                    Spacer()
                    if !activity.isCompleted {
                        Button("Remove", role: .destructive) {
                            updateActivity {
                                try $0.setCalendarActivity(on: day.date, kind: activity.kind, isPlanned: false, now: Date())
                            }
                        }
                        .disabled(model.storageBlocked)
                    }
                }.font(.subheadline).buttonStyle(.borderless)
            }
        }.padding(.vertical, 5)
    }

    private func updateActivity(_ mutation: (inout GymaState) throws -> Void) {
        error = model.update(mutation) ? nil : model.errorMessage
    }
}

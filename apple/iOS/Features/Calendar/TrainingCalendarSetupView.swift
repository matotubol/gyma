import Foundation
import SwiftUI
import GymaCore

struct TrainingCalendarSetupView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let existing: TrainingCalendarPlan?
    @State private var startDate: Date
    @State private var cycleAnchorDate: Date
    @State private var trainingDays: Set<Int>
    @State private var prefersUpperLower: Bool
    @State private var openingScheduleRequested = false
    @State private var error: String?
    private let timeZone: TimeZone
    private let basePlan: TrainingCalendarPlan

    init(existing: TrainingCalendarPlan?) {
        self.existing = existing
        let zone = existing.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? TimeZone(identifier: "Europe/Amsterdam") ?? .current
        timeZone = zone
        let plan = existing ?? TrainingCalendarPlan.defaultPlan(now: Date(), timeZone: zone)
        basePlan = plan
        _startDate = State(initialValue: plan.startDate)
        _cycleAnchorDate = State(initialValue: plan.cycleAnchorDate)
        _trainingDays = State(initialValue: Set(plan.trainingCycleDays))
        _prefersUpperLower = State(initialValue: plan.prefersUpperLower)
    }

    private var preview: TrainingCalendarPlan {
        (try? configuredPlan()) ?? TrainingCalendarPlan(startDate: startDate, cycleAnchorDate: cycleAnchorDate, trainingCycleDays: trainingDays.sorted(), timeZone: timeZone, prefersUpperLower: prefersUpperLower)
    }

    private var openingStartDate: Date {
        basePlan.calendar.date(from: DateComponents(year: 2026, month: 10, day: 13)) ?? basePlan.startDate
    }

    private var firstMorningDate: Date {
        basePlan.calendar.date(from: DateComponents(year: 2026, month: 10, day: 17)) ?? basePlan.cycleAnchorDate
    }

    private var configurationError: String? {
        do { _ = try configuredPlan(); return nil }
        catch { return error.localizedDescription }
    }

    private func configuredPlan() throws -> TrainingCalendarPlan {
        var plan: TrainingCalendarPlan
        if existing != nil {
            plan = try basePlan.reconfigured(startDate: startDate, cycleAnchorDate: cycleAnchorDate, trainingCycleDays: trainingDays.sorted(), prefersUpperLower: prefersUpperLower)
        } else {
            plan = TrainingCalendarPlan(startDate: startDate, cycleAnchorDate: cycleAnchorDate, trainingCycleDays: trainingDays.sorted(), timeZone: timeZone, prefersUpperLower: prefersUpperLower)
            if plan.cycleAnchorDate == firstMorningDate {
                for override in basePlan.dayOverrides {
                    if let date = basePlan.date(at: override.dayOffset), let offset = plan.dayOffset(for: date) {
                        plan.dayOverrides.append(.init(dayOffset: offset, isTraining: override.isTraining))
                    }
                }
            }
            try plan.validate()
        }
        if openingScheduleRequested, plan.startDate == openingStartDate, plan.cycleAnchorDate == firstMorningDate {
            try plan.setTrainingDay(on: openingStartDate, isTraining: true, now: Date())
            if let recoveryDate = plan.calendar.date(byAdding: .day, value: 2, to: openingStartDate) {
                try plan.setTrainingDay(on: recoveryDate, isTraining: false, now: Date())
            }
        }
        return plan
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Block starts", selection: $startDate, displayedComponents: .date)
                    DatePicker("First morning shift", selection: $cycleAnchorDate, displayedComponents: .date)
                    Text("Eight weeks: \(calendarRange(preview))\nReview: \(calendarDate(preview.reviewDate, plan: preview, template: "d MMMM yyyy"))")
                        .font(.caption).foregroundStyle(.secondary)
                    if existing != nil, basePlan.calendar.startOfDay(for: Date()) <= openingStartDate {
                        Button("Start on 13 October") {
                            startDate = openingStartDate
                            cycleAnchorDate = firstMorningDate
                            openingScheduleRequested = true
                            error = nil
                        }.disabled(model.storageBlocked || model.state.activeWorkout != nil)
                    }
                } header: { Text("Your dates") } footer: {
                    Text("The block can start before your first morning shift. That shift anchors the repeating 10-day cycle. Dates stay in \(timeZone.identifier).")
                }
                if preview.startDate == openingStartDate, preview.cycleAnchorDate == firstMorningDate {
                    Section("Your first days off") {
                        ForEach(Array(preview.entries(program: nil, history: []).prefix(4))) { day in
                            LabeledContent(calendarDate(day.date, plan: preview, template: "EEE d MMM"), value: day.isTraining ? "Strength" : "Recovery")
                        }
                        Text("On 13 October, sleep after your final night shift before training. Check your energy and soreness; move the session if you need more recovery.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(1...10, id: \.self) { day in
                        Toggle(isOn: Binding(get: { trainingDays.contains(day) }, set: { enabled in
                            if enabled { trainingDays.insert(day) } else { trainingDays.remove(day) }
                        })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Day \(day) · \(calendarCycleLabel(day))")
                                if [2, 5, 8, 9, 10].contains(day) {
                                    Text(calendarTrainingTiming(day)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.tint(GymaStyle.accent)
                    }
                } header: { Text("Training days · \(trainingDays.count) of 10 selected") } footer: {
                    Text("Choose 1–10 training days per cycle to fit your schedule. Individual dates can be moved or changed to recovery after saving. Saved program sessions continue across cycles.")
                }
                Section {
                    Toggle("Prefer alternating upper/lower", isOn: $prefersUpperLower)
                } footer: {
                    Text("Your coach uses this preference when discussing your program. Saving this calendar keeps your current exercises and session order.")
                }
                if existing != nil {
                    Section {
                        Text(startDate > basePlan.lastDate
                             ? "This starts a new eight-week block. Your previous calendar and optional activity records will stay in calendar history."
                             : "Individual date changes and optional activities keep their calendar dates when the block start changes. A change that would leave any of them outside the block must be resolved first. Recorded training and completed activities are kept.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let configurationError { Section { Text(configurationError).foregroundStyle(.red) } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button(existing == nil ? "Create calendar" : "Save calendar") { save() }
                        .disabled(configurationError != nil || model.storageBlocked || model.state.activeWorkout != nil)
                } footer: {
                    Text("The calendar reserves training dates. It does not start workouts or replace your program at the end of eight weeks. Changing the calendar clears an unstarted draft. Check in again before training.")
                }
            }
            .environment(\.timeZone, timeZone)
            .environment(\.calendar, preview.calendar)
            .navigationTitle(existing == nil ? "Plan eight weeks" : "Calendar settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() {
        do {
            let plan = try configuredPlan()
            if model.update({ try $0.saveTrainingCalendar(plan, now: Date()) }) { dismiss() }
            else { error = model.errorMessage }
        } catch { self.error = error.localizedDescription }
    }
}

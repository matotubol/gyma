import SwiftUI
import GymaCore

/// A fresh, explicit check-in is saved with the session that is about to start.
struct WorkoutReadinessView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let plan: WorkoutPlan
    let onStarted: (String) -> Void
    @State private var energy: Energy
    @State private var soreness: [Muscle: Soreness]
    @State private var error: String?

    init(plan: WorkoutPlan, onStarted: @escaping (String) -> Void) {
        self.plan = plan; self.onStarted = onStarted
        _energy = State(initialValue: plan.checkIn.energy)
        _soreness = State(initialValue: Dictionary(uniqueKeysWithValues:
            Muscle.allCases.map { ($0, plan.checkIn.soreness(for: $0)) }))
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Form {
                    let today = DailyTrainingPresentation(state: model.state, now: context.date)
                    let canStart = model.state.canStartAcceptedPlan(plan, now: context.date)
                    Section {
                        Text(plan.title).font(.title2.bold())
                        Text("How do you feel right now? This check-in is saved with today's sets, weights and rest.")
                            .foregroundStyle(.secondary)
                    }
                    Section("Energy") {
                        Picker("Energy", selection: $energy) {
                            ForEach(Energy.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                        }
                    }
                    Section("Muscle soreness") { SorenessFields(soreness: $soreness) }
                    if let error { Section { Text(error).foregroundStyle(.orange) } }
                    if !canStart {
                        Section {
                            Text(today.status.allowsWorkoutStart
                                 ? "This saved workout is dated \(today.date(plan.scheduledDate)). Return to Overview to review today's available session."
                                 : today.message).foregroundStyle(.orange)
                        }
                    }
                    Section {
                        Button {
                            guard model.state.canStartAcceptedPlan(plan) else {
                                error = "This workout is no longer available for today. Return to Overview to review your calendar."
                                return
                            }
                            let readiness = WorkoutReadiness(energy: energy, soreness: soreness, recordedAt: Date())
                            if let id = model.startCoachPlan(plan.id, readiness: readiness) { onStarted(id) }
                            else { error = model.errorMessage ?? "The plan changed. Return to Overview and review it again." }
                        } label: {
                            Label("Start workout", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canAcceptCoachPlan || !canStart)
                    }
                }
            }
            .navigationTitle("Before you start").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: model.state.activeWorkout?.id) { _, id in if id != nil { dismiss() } }
        }
    }
}

struct SorenessFields: View {
    @Binding var soreness: [Muscle: Soreness]

    var body: some View {
        ForEach(Muscle.allCases) { muscle in
            Picker(muscle.label, selection: Binding(
                get: { soreness[muscle] ?? Soreness.none },
                set: { soreness[muscle] = $0 }
            )) {
                ForEach(Soreness.allCases) { level in Text(level.label).tag(level) }
            }
        }
    }
}

struct WorkoutReadinessSummary: View {
    let readiness: WorkoutReadiness

    var body: some View {
        LabeledContent("Energy", value: readiness.energy.label)
        ForEach(Muscle.allCases) { muscle in
            LabeledContent(muscle.label, value: (readiness.soreness[muscle] ?? Soreness.none).label)
        }
        Text("Recorded \(readiness.recordedAt.formatted(date: .omitted, time: .shortened)) before starting")
            .font(.caption).foregroundStyle(.secondary)
    }
}

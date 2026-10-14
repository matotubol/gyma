import GymaCore
import SwiftUI

struct WatchReadyContext: Identifiable {
    let id = UUID()
    let storeID: String
    let revision: Int
    let plan: ReadyWorkoutPlan
}

@MainActor
struct WatchReadinessView: View {
    @EnvironmentObject private var connectivity: WorkoutConnectivity
    @Environment(\.dismiss) private var dismiss
    let context: WatchReadyContext
    @State private var energy: Energy
    @State private var soreness: [Muscle: Soreness]
    @State private var error: String?

    init(context: WatchReadyContext) {
        self.context = context
        _energy = State(initialValue: context.plan.energy)
        _soreness = State(initialValue: Dictionary(uniqueKeysWithValues: Muscle.allCases.map {
            ($0, context.plan.soreness[$0] ?? Soreness.none)
        }))
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Form {
                    Section {
                        Text(context.plan.title).font(.headline)
                        Text("Confirm how you feel today before starting.")
                            .font(.caption2).foregroundStyle(.secondary)
                        if context.plan.programID != nil {
                            Text("Saved program; today’s targets adapt to this check-in. These are default selections: change them to how you feel now.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Section("Energy") {
                        Picker("Energy", selection: $energy) {
                            ForEach(Energy.allCases) { value in Text(value.label).tag(value) }
                        }
                    }
                    Section("Muscle soreness") {
                        ForEach(Muscle.allCases) { muscle in
                            Picker(muscle.label, selection: Binding<Soreness>(
                                get: { soreness[muscle] ?? Soreness.none },
                                set: { soreness[muscle] = $0 }
                            )) {
                                ForEach(Soreness.allCases) { value in Text(value.label).tag(value) }
                            }
                        }
                    }
                    if let reason = unavailableReason(at: timeline.date) {
                        Text(reason).font(.caption2).foregroundStyle(.orange)
                    }
                    Button("Confirm & Start") { confirmStart() }
                        .font(.headline).buttonStyle(WatchPrimaryButtonStyle())
                        .disabled(unavailableReason(at: timeline.date) != nil)
                }
            }
            .navigationTitle("Readiness")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Workout not started", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func unavailableReason(at now: Date) -> String? {
        guard let snapshot = connectivity.snapshot, snapshot.storeID == context.storeID,
              snapshot.revision == context.revision, snapshot.readyPlan == context.plan,
              snapshot.activeWorkout == nil else {
            return "The plan changed on iPhone. Close this screen and review today’s workout."
        }
        guard context.plan.isAvailable(at: now), Calendar.current.isDate(context.plan.scheduledFor, inSameDayAs: now) else {
            return "This workout is no longer scheduled for today. Review your plan on iPhone."
        }
        guard connectivity.canStartAcceptedPlan(context.plan.id, at: now) else {
            return "Waiting for the previous change to be confirmed."
        }
        return nil
    }

    private func confirmStart() {
        do {
            if let reason = unavailableReason(at: Date()) { throw GymaError.stale(reason) }
            let readiness = WorkoutReadiness(energy: energy, soreness: soreness, recordedAt: Date())
            try connectivity.submit(.startAcceptedPlan(planID: context.plan.id, readiness: readiness),
                                    expectedWorkoutID: context.plan.id, basedOnRevision: context.revision,
                                    expectedStoreID: context.storeID)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

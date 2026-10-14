import GymaCore
import SwiftUI

@MainActor
struct WatchWorkoutSettings: View {
    @EnvironmentObject private var connectivity: WorkoutConnectivity
    @EnvironmentObject private var notifications: WatchRestNotifications
    @EnvironmentObject private var runtime: WatchWorkoutRuntime
    let storageError: String?
    let draft: WatchSetDraft?
    let isDraftCurrent: Bool
    let canChangeWorkout: Bool
    let discardDraft: () -> Void
    let finishWorkout: () -> Void
    let chooseExercise: () -> Void
    let cancelSet: () -> Void
    let skipSet: () -> Void
    let skipExercise: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if connectivity.snapshot?.activeWorkout != nil {
                    Section("Workout") {
                        Button("Exercise menu", systemImage: "list.bullet", action: chooseExercise)
                    }
                }
                if let draft, isDraftCurrent, draft.phase != .submitting {
                    Section("Current exercise") {
                        Text(connectivity.snapshot?.catalog.first { $0.id == draft.exerciseID }?.name ?? draft.exerciseID)
                            .font(.headline)
                        if draft.phase == .performing || draft.phase == .review {
                            Button("Cancel unsaved set", role: .destructive, action: cancelSet)
                                .disabled(!canChangeWorkout)
                        }
                        if let exercise = connectivity.snapshot?.activeWorkout?.exercises.first(where: { $0.exerciseID == draft.exerciseID }),
                           !exercise.isTargetResolved {
                            if exercise.target != nil {
                                Button("Skip planned set", action: skipSet)
                                    .disabled(!canChangeWorkout || draft.isWarmupSet)
                            }
                            Button("Stop this exercise", role: .destructive, action: skipExercise)
                                .disabled(!canChangeWorkout)
                            Text("Skipped sets are kept separate from completed sets.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if let draft, !isDraftCurrent, draft.phase != .submitting {
                    Section("Saved Watch draft") {
                        Text(connectivity.snapshot?.catalog.first { $0.id == draft.exerciseID }?.name ?? draft.exerciseID)
                            .font(.headline)
                        Text("\(draft.actualKg.formatted()) kg × \(draft.actualReps)")
                        Text("This draft no longer matches the current workout. Review your workout on iPhone before discarding it.")
                            .font(.caption2)
                        Button("Use current workout", action: discardDraft)
                            .disabled(connectivity.pendingCommand != nil || connectivity.snapshot == nil || storageError != nil)
                    }
                }
                if let pending = connectivity.pendingCommand {
                    Section("Saved change") {
                        Text(pending.action.watchDescription).font(.headline)
                        Text("Saved on this Watch, waiting for iPhone confirmation. Open Gyma on iPhone if this takes a while.")
                            .font(.caption2)
                        if case let .logSet(_, set) = pending.action {
                            Text("\(set.kg.formatted()) kg × \(set.reps)")
                        }
                        if case let .startAcceptedPlan(_, readiness) = pending.action {
                            readinessDetails(readiness)
                        }
                    }
                }
                if let receipt = connectivity.lastAcknowledgement, receipt.status == .rejected {
                    Section("Change not saved") {
                        Text(receipt.message ?? "Review the current workout before retrying. Your draft is preserved.")
                            .font(.caption2).foregroundStyle(.orange)
                        if let command = connectivity.rejectedCommand, case let .logSet(_, set) = command.action {
                            Text("Not saved: \(set.kg.formatted()) kg × \(set.reps)")
                        }
                        if let command = connectivity.rejectedCommand,
                           case let .startAcceptedPlan(_, readiness) = command.action {
                            readinessDetails(readiness)
                        }
                    }
                }
                if let command = connectivity.quarantinedCommand {
                    Section("Earlier change needs review") {
                        Text("This change was not applied after your iPhone data changed. Review the earlier workout on iPhone.")
                            .font(.caption2).foregroundStyle(.orange)
                        if case let .logSet(_, set) = command.action {
                            Text("Not saved: \(set.kg.formatted()) kg × \(set.reps)")
                        }
                        if case let .startAcceptedPlan(_, readiness) = command.action {
                            readinessDetails(readiness)
                        }
                    }
                }
                if let error = storageError ?? connectivity.lastError {
                    Section("Action needed") { Text(error).font(.caption2).foregroundStyle(.orange) }
                }
                Section("Rest alerts") {
                    Toggle("Rest vibration", isOn: Binding(
                        get: { notifications.enabled },
                        set: { value in Task { await notifications.setEnabled(value) } }
                    ))
                    Button(notifications.isTestingHaptic ? "Stop vibration" : "Test vibration") { notifications.testHaptic() }
                    if let message = notifications.message {
                        Text(message).font(.caption2).foregroundStyle(.orange)
                    }
                    if let message = runtime.message {
                        Text(message).font(.caption2).foregroundStyle(.orange)
                    }
                }
                if connectivity.snapshot?.activeWorkout != nil {
                    Button("Finish workout early", role: .destructive, action: finishWorkout)
                        .disabled(!canChangeWorkout)
                }
            }
            .navigationTitle("Options")
            .onDisappear { notifications.stopHapticPreview() }
        }
    }

    private func readinessDetails(_ readiness: WorkoutReadiness) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Energy: \(readiness.energy.label)").font(.caption)
            ForEach(Muscle.allCases) { muscle in
                Text("\(muscle.label): \(readiness.soreness(for: muscle).label)").font(.caption2)
            }
        }
    }
}

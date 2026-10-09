import GymaCore
import SwiftUI

@MainActor
struct WatchWorkoutView: View {
    @EnvironmentObject private var connectivity: WorkoutConnectivity
    @EnvironmentObject private var notifications: WatchRestNotifications
    @State private var confirmFinish = false
    @State private var finishWorkoutID: String?
    @State private var finishRevision: Int?
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                if let workout = connectivity.snapshot?.activeWorkout {
                    Section {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(workout.planTitle ?? "Your workout")
                                .font(.headline)
                            HStack {
                                Text(workout.start, style: .timer)
                                Spacer()
                                Text(connectivity.snapshot?.isTruncated == true ? "\(workout.totalSets)+ shown" : "\(workout.totalSets) sets")
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                    }
                    if connectivity.snapshot?.isTruncated == true {
                        Text("Showing the first 12 exercises and the latest 20 sets per exercise. See your complete workout on iPhone.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let timer = connectivity.snapshot?.restTimer,
                       timer.workoutID == workout.id {
                        restSection(timer)
                    }
                    Section("Exercises") {
                        ForEach(workout.exercises) { exercise in
                            NavigationLink {
                                WatchExerciseView(workoutID: workout.id, exerciseID: exercise.exerciseID)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exerciseName(exercise.exerciseID))
                                    if let target = exercise.target {
                                        Text(target.watchSummary)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("\(exercise.sets.filter { $0.isWarmup == false }.count) working sets logged")
                                        .font(.caption2)
                                        .foregroundStyle(.mint)
                                }
                            }
                        }
                    }
                    Button("Finish workout", role: .destructive) {
                        finishWorkoutID = workout.id
                        finishRevision = connectivity.snapshot?.revision
                        confirmFinish = true
                    }
                        .disabled(!connectivity.canSubmit)
                } else {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.largeTitle)
                                .foregroundStyle(.mint)
                            Text(connectivity.snapshot == nil ? "Connect your iPhone" : "Ready when you are")
                                .font(.headline)
                            Text("Open Gyma on your paired iPhone to start a workout. Your exercises will appear here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                }
                Section("Rest reminders") {
                    Toggle("Watch notifications", isOn: Binding(
                        get: { notifications.enabled },
                        set: { value in Task { await notifications.setEnabled(value) } }
                    ))
                    Text(notifications.message ?? "Delivery follows your Watch notification and Focus settings.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Gyma")
            .confirmationDialog("Finish this workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Finish workout", role: .destructive) {
                    do {
                        try connectivity.submit(.finishWorkout, expectedWorkoutID: finishWorkoutID,
                                                basedOnRevision: finishRevision)
                    } catch { localError = error.localizedDescription }
                }
                Button("Keep training", role: .cancel) {}
            } message: {
                Text("Your iPhone will save the workout when it receives this request.")
            }
            .alert("Could not queue the change", isPresented: Binding(
                get: { localError != nil }, set: { if !$0 { localError = nil } }
            )) {
                Button("OK", role: .cancel) { localError = nil }
            } message: { Text(localError ?? "") }
        }
    }

    private var connectionSection: some View {
        Section {
            Label(connectivity.connectionStatus,
                  systemImage: connectivity.isReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                .font(.caption2)
                .foregroundStyle(connectivity.isReachable ? Color.mint : Color.orange)
            if let pending = connectivity.pendingCommand {
                Label("\(pending.action.watchDescription) pending", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                Text("Saved on this Watch. Waiting for your iPhone to confirm before your next change.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let receipt = connectivity.lastAcknowledgement, receipt.status == .rejected {
                Label("Change wasn’t applied", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Text(receipt.message ?? "The workout changed on your iPhone. Review the current workout and try again.")
                    .font(.caption2)
                if let command = connectivity.rejectedCommand, case let .logSet(_, set) = command.action {
                    Text("Not saved on iPhone: \(set.kg.formatted()) kg × \(set.reps)")
                        .font(.caption2)
                }
            }
            if let command = connectivity.quarantinedCommand {
                Label("Earlier change needs review", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Text("Your iPhone data was replaced. This Watch saved an unconfirmed \(command.action.watchDescription.lowercased()) from the previous workout; it was not applied to the new data.")
                    .font(.caption2)
                if case let .logSet(_, set) = command.action {
                    Text("\(set.kg.formatted()) kg × \(set.reps) · \(set.isWarmup == true ? "Warm-up" : "Working set")")
                        .font(.caption2)
                }
            }
            if let error = connectivity.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
            if let snapshot = connectivity.snapshot {
                HStack {
                    Text("Last update")
                    Spacer()
                    Text(snapshot.generatedAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Button(connectivity.pendingCommand == nil ? "Refresh" : "Retry sync", systemImage: "arrow.clockwise") {
                connectivity.refresh()
            }
            .font(.caption)
        }
    }

    private func restSection(_ timer: RestTimer) -> some View {
        Section("Rest · \(exerciseName(timer.exerciseID))") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = Int(ceil(timer.remaining(at: context.date)))
                Text(remaining > 0 ? String(format: "%d:%02d", remaining / 60, remaining % 60) : "Ready for your next set")
                    .font(remaining > 0 ? .title2.monospacedDigit() : .headline)
                    .foregroundStyle(.mint)
            }
            HStack {
                Button("+30 sec") { submit(.extendRest(timerID: timer.id, seconds: 30)) }
                Button("Skip") { submit(.skipRest(timerID: timer.id)) }
            }
            .disabled(!connectivity.canSubmit)
        }
    }

    private func exerciseName(_ id: String) -> String {
        connectivity.snapshot?.catalog.first { $0.id == id }?.name ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func submit(_ action: WatchAction) {
        do { try connectivity.submit(action) }
        catch { localError = error.localizedDescription }
    }
}

@MainActor
private struct WatchExerciseView: View {
    @EnvironmentObject private var connectivity: WorkoutConnectivity
    let workoutID: String
    let exerciseID: String
    @State private var showLogger = false

    private var exercise: WorkoutExercise? {
        guard connectivity.snapshot?.activeWorkout?.id == workoutID else { return nil }
        return connectivity.snapshot?.activeWorkout?.exercises.first { $0.exerciseID == exerciseID }
    }
    private var name: String {
        connectivity.snapshot?.catalog.first { $0.id == exerciseID }?.name ?? "Exercise"
    }

    var body: some View {
        List {
            if let exercise {
                if let target = exercise.target {
                    Section("Target") {
                        Text(target.watchSummary).font(.headline)
                        Text("\(target.restSeconds) sec rest after working sets")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Button("Log set", systemImage: "plus.circle.fill") { showLogger = true }
                    .disabled(!connectivity.canSubmit)
                if connectivity.pendingCommand != nil {
                    Text("Waiting for iPhone confirmation…").font(.caption).foregroundStyle(.orange)
                }
                Section("Completed sets") {
                    if exercise.sets.isEmpty {
                        Text("No sets logged yet").foregroundStyle(.secondary)
                    }
                    ForEach(exercise.sets) { set in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(set.kg.formatted()) kg × \(set.reps)").font(.headline)
                            Text(set.isWarmup == true ? "Warm-up" : (set.effort?.label ?? "Logged set"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("This workout has changed. Return to Gyma to see the latest session.")
                    .font(.caption)
            }
        }
        .navigationTitle(name)
        .sheet(isPresented: $showLogger) {
            if let exercise {
                WatchSetLogger(workoutID: workoutID, revision: connectivity.snapshot?.revision ?? 0, exercise: exercise)
            }
        }
    }
}

@MainActor
private struct WatchSetLogger: View {
    @EnvironmentObject private var connectivity: WorkoutConnectivity
    @Environment(\.dismiss) private var dismiss
    let workoutID: String
    @State private var revision: Int
    let exercise: WorkoutExercise
    @State private var kg: Double
    @State private var reps: Int
    @State private var warmup = false
    @State private var effort: SetEffort?
    @State private var error: String?

    init(workoutID: String, revision: Int, exercise: WorkoutExercise) {
        self.workoutID = workoutID
        _revision = State(initialValue: revision)
        self.exercise = exercise
        let recent = exercise.sets.last { $0.isWarmup == false }
        _kg = State(initialValue: min(1000, max(0, exercise.target?.loadKg ?? recent?.kg ?? 0)))
        _reps = State(initialValue: min(100, max(1, exercise.target?.repsMin ?? recent?.reps ?? 8)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Set details") {
                    Picker("Load (kg)", selection: $kg) {
                        if kg.truncatingRemainder(dividingBy: 0.5) != 0 {
                            Text(kg.formatted()).tag(kg)
                        }
                        ForEach(0...2000, id: \.self) { halfKg in
                            Text((Double(halfKg) / 2).formatted()).tag(Double(halfKg) / 2)
                        }
                    }
                    if exercise.target?.loadKg == nil && !exercise.sets.contains(where: { $0.isWarmup == false }) {
                        Text("Choose a comfortable load. Use 0 kg for bodyweight.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Picker("Reps", selection: $reps) {
                        ForEach(1...100, id: \.self) { count in Text("\(count)").tag(count) }
                    }
                    Toggle("Warm-up", isOn: $warmup)
                    Picker("Effort", selection: $effort) {
                        Text("Not recorded").tag(Optional<SetEffort>.none)
                        ForEach(SetEffort.allCases) { value in Text(value.label).tag(Optional(value)) }
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                Button(connectivity.isReachable ? "Log set" : "Queue set") {
                    guard connectivity.snapshot?.activeWorkout?.id == workoutID else {
                        error = "This workout has ended or changed on your iPhone."
                        return
                    }
                    do {
                        try connectivity.submit(.logSet(exerciseID: exercise.exerciseID,
                                                       set: WorkSet(kg: kg, reps: reps, effort: effort, isWarmup: warmup)),
                                                expectedWorkoutID: workoutID, basedOnRevision: revision)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .disabled(!connectivity.canSubmit)
            }
            .navigationTitle("Log set")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private extension ExerciseTarget {
    var watchSummary: String {
        let reps = repsMin == repsMax ? "\(repsMin)" : "\(repsMin)–\(repsMax)"
        let load = loadKg.map { " · \($0.formatted()) kg" } ?? ""
        return "\(sets) × \(reps) reps\(load)"
    }
}

private extension WatchAction {
    var watchDescription: String {
        switch self {
        case .logSet: return "Set"
        case .skipRest: return "Skip rest"
        case .extendRest: return "Extend rest"
        case .finishWorkout: return "Finish workout"
        }
    }
}

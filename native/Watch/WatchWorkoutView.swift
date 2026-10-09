import GymaCore
import SwiftUI

@MainActor
struct WatchWorkoutView: View {
    @EnvironmentObject private var connectivity: WorkoutConnectivity
    @EnvironmentObject private var notifications: WatchRestNotifications
    @AppStorage("watchStartedExercise") private var startedExerciseKey = ""
    @State private var showLogger = false
    @State private var confirmFinish = false
    @State private var finishWorkoutID: String?
    @State private var finishRevision: Int?
    @State private var localError: String?
    @State private var pendingExerciseStart: (commandID: String, exerciseKey: String)?
    @State private var pendingRestTimer: RestTimer?

    private var displayedRestTimer: RestTimer? {
        if let timer = connectivity.snapshot?.restTimer { return timer }
        if let pending = connectivity.pendingCommand, case let .skipRest(timerID) = pending.action,
           pendingRestTimer?.id == timerID { return pendingRestTimer }
        return nil
    }

    var body: some View {
        NavigationStack {
            List {
                actionStatus
                if let workout = connectivity.snapshot?.activeWorkout {
                    workoutHeader(workout)
                    if let timer = displayedRestTimer, timer.workoutID == workout.id {
                        restSection(timer, workout: workout)
                    } else if let exercise = workout.nextExercise {
                        exerciseSection(exercise, workout: workout)
                    } else if hasHiddenExercises(workout) {
                        Text("Continue on iPhone to see the rest of this workout.")
                            .font(.caption)
                    } else {
                        Section {
                            Label("Workout complete", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.mint)
                            Text("All planned sets are logged.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Finish workout") { prepareFinish(workout) }
                                .disabled(!connectivity.canSubmit)
                        }
                    }
                } else {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.largeTitle).foregroundStyle(.mint)
                            Text("Your next workout")
                                .font(.headline)
                            Text("Create and accept a workout in Gyma on iPhone to begin.")
                                .font(.caption).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                }
            }
            .navigationTitle("Gyma")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        WatchWorkoutSettings {
                            if let workout = connectivity.snapshot?.activeWorkout { prepareFinish(workout) }
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Workout settings")
                }
            }
            .sheet(isPresented: $showLogger) {
                if let workout = connectivity.snapshot?.activeWorkout, let exercise = workout.nextExercise {
                    WatchSetLogger(workoutID: workout.id, revision: connectivity.snapshot?.revision ?? 0,
                                   exercise: exercise, name: exerciseName(exercise.exerciseID))
                }
            }
            .onChange(of: connectivity.pendingCommand?.id) { _, commandID in
                if commandID == nil { pendingRestTimer = nil }
                guard commandID == nil, let pendingExerciseStart,
                      let receipt = connectivity.lastAcknowledgement,
                      receipt.commandID == pendingExerciseStart.commandID else { return }
                if receipt.status == .applied || (receipt.status == .duplicate && receipt.originalStatus == .applied) {
                    startedExerciseKey = pendingExerciseStart.exerciseKey
                }
                self.pendingExerciseStart = nil
            }
            .onChange(of: connectivity.snapshot?.activeWorkout?.id) { _, _ in showLogger = false }
            .onChange(of: connectivity.snapshot?.activeWorkout?.nextExercise?.exerciseID) { _, _ in showLogger = false }
            .onChange(of: connectivity.snapshot?.restTimer?.id) { _, timerID in
                if timerID != nil { showLogger = false }
            }
            .confirmationDialog("Finish this workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Finish workout", role: .destructive) {
                    do {
                        try connectivity.submit(.finishWorkout, expectedWorkoutID: finishWorkoutID,
                                                basedOnRevision: finishRevision)
                    } catch { localError = error.localizedDescription }
                }
                Button("Keep training", role: .cancel) {}
            } message: {
                Text("Your completed sets will be saved on your iPhone.")
            }
            .alert("Could not save the change", isPresented: Binding(
                get: { localError != nil }, set: { if !$0 { localError = nil } }
            )) {
                Button("OK", role: .cancel) { localError = nil }
            } message: { Text(localError ?? "") }
        }
    }

    private func workoutHeader(_ workout: Workout) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.planTitle ?? "Your workout").font(.headline)
                HStack {
                    Text(workout.start, style: .timer)
                    Spacer()
                    Text("\(workout.exercises.filter(\.isTargetComplete).count)/\(connectivity.snapshot?.totalExerciseCount ?? workout.exercises.count) exercises")
                }
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    private func exerciseSection(_ exercise: WorkoutExercise, workout: Workout) -> some View {
        let hasStarted = startedExerciseKey == exerciseKey(exercise, workout: workout)
        return Section(hasStarted ? "Current exercise" : (workout.totalSets == 0 ? "First exercise" : "Next exercise")) {
            Text(exerciseName(exercise.exerciseID)).font(.title3.bold())
            if let target = exercise.target {
                Text(target.watchSummary).font(.headline)
                Text("\(target.restSeconds) sec rest · \(exercise.workingSetCount)/\(target.sets) sets done")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Set targets on iPhone to follow this workout.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if hasStarted {
                Text("Set \(exercise.workingSetCount + 1)").font(.headline).foregroundStyle(.mint)
                Button("Log completed set", systemImage: "checkmark.circle.fill") { showLogger = true }
                    .disabled(!connectivity.canSubmit)
                if let set = exercise.sets.last(where: { $0.isWarmup == false }) {
                    Text("Last set: \(set.kg.formatted()) kg × \(set.reps)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let rest = workout.restHistory?.last {
                    Text("Last rest: \(watchDuration(Int(min(86400, max(0, rest.elapsedSeconds)))))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Button(workout.totalSets == 0 ? "Start exercise" : "Start next exercise", systemImage: "play.fill") {
                    startedExerciseKey = exerciseKey(exercise, workout: workout)
                }
                .disabled(!connectivity.canSubmit)
            }
        }
    }

    private func restSection(_ timer: RestTimer, workout: Workout) -> some View {
        let next = workout.nextExercise
        let sameExercise = next?.exerciseID == timer.exerciseID
        return Section("Rest") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let date = restDisplayDate(timerID: timer.id, now: context.date)
                let remaining = Int(ceil(timer.remaining(at: date)))
                let elapsed = Int(max(0, min(86400, date.timeIntervalSince(timer.startedAt))))
                let overtime = Int(max(0, min(86400, date.timeIntervalSince(timer.endsAt))))
                VStack(alignment: .leading, spacing: 4) {
                    Text(remaining > 0 ? watchDuration(remaining) : "Ready")
                        .font(.largeTitle.monospacedDigit().bold()).foregroundStyle(.mint)
                    Text("Rested \(watchDuration(elapsed))")
                        .font(.caption.monospacedDigit())
                    if remaining == 0 {
                        Text("\(watchDuration(overtime)) past target")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if let next {
                Text(exerciseName(next.exerciseID)).font(.headline)
                if let target = next.target {
                    Text("Set \(next.workingSetCount + 1) of \(target.sets) · \(target.watchReps) reps")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button(next == nil ? "End rest" : (sameExercise ? "Start next set" : "Start next exercise"), systemImage: "play.fill") {
                do {
                    try connectivity.submit(.skipRest(timerID: timer.id))
                    pendingRestTimer = timer
                    if let next, let commandID = connectivity.pendingCommand?.id {
                        pendingExerciseStart = (commandID, exerciseKey(next, workout: workout))
                    }
                } catch { localError = error.localizedDescription }
            }
            .disabled(!connectivity.canSubmit)
            Text("Tap when you start to record your actual rest.")
                .font(.caption2).foregroundStyle(.secondary)
            if !notifications.hasChosenAlerts {
                Button("Enable rest alerts", systemImage: "bell.badge") {
                    Task { await notifications.setEnabled(true) }
                }
                Text("Get a tap when your rest is over.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if let message = notifications.message {
                Text(message).font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var actionStatus: some View {
        if connectivity.pendingCommand != nil || connectivity.lastAcknowledgement?.status == .rejected ||
            connectivity.quarantinedCommand != nil || connectivity.lastError != nil {
            Section {
                if let pending = connectivity.pendingCommand {
                    Label("\(pending.action.watchDescription)…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                    Text("Saved on this Watch. Open Gyma on iPhone to confirm if this takes a while.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let receipt = connectivity.lastAcknowledgement, receipt.status == .rejected {
                    Label("Change wasn’t saved", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                    Text(receipt.message ?? "Review the workout and try again.").font(.caption2)
                    if let command = connectivity.rejectedCommand, case let .logSet(_, set) = command.action {
                        Text("Not saved: \(set.kg.formatted()) kg × \(set.reps)").font(.caption2)
                    }
                }
                if let command = connectivity.quarantinedCommand {
                    Label("Earlier change needs review", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                    Text("iPhone data was replaced. Review the previous workout in Gyma before logging this change again.")
                        .font(.caption2)
                    if case let .logSet(_, set) = command.action {
                        Text("Not saved: \(set.kg.formatted()) kg × \(set.reps)").font(.caption2)
                    }
                }
                if let error = connectivity.lastError {
                    Text(error).font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }

    private func prepareFinish(_ workout: Workout) {
        finishWorkoutID = workout.id
        finishRevision = connectivity.snapshot?.revision
        confirmFinish = true
    }

    private func hasHiddenExercises(_ workout: Workout) -> Bool {
        if let total = connectivity.snapshot?.totalExerciseCount { return total > workout.exercises.count }
        return connectivity.snapshot?.isTruncated == true
    }

    private func restDisplayDate(timerID: String, now: Date) -> Date {
        if let pending = connectivity.pendingCommand, case let .skipRest(pendingTimerID) = pending.action,
           pendingTimerID == timerID {
            return pending.createdAt
        }
        return now
    }

    private func exerciseKey(_ exercise: WorkoutExercise, workout: Workout) -> String {
        "\(connectivity.snapshot?.storeID ?? "")/\(workout.id)/\(exercise.exerciseID)"
    }

    private func exerciseName(_ id: String) -> String {
        connectivity.snapshot?.catalog.first { $0.id == id }?.name ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

@MainActor
private struct WatchWorkoutSettings: View {
    @EnvironmentObject private var connectivity: WorkoutConnectivity
    @EnvironmentObject private var notifications: WatchRestNotifications
    @Environment(\.dismiss) private var dismiss
    let finishWorkout: () -> Void

    var body: some View {
        Form {
            Section("Rest alerts") {
                Toggle("Rest alerts", isOn: Binding(
                    get: { notifications.enabled },
                    set: { value in Task { await notifications.setEnabled(value) } }
                ))
                Text(notifications.message ?? "A tap when rest ends while Gyma is open. Background reminders follow your Watch notification and Focus settings.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if connectivity.snapshot?.activeWorkout != nil {
                Section {
                    Button("Finish workout early", role: .destructive) {
                        dismiss()
                        finishWorkout()
                    }
                    .disabled(!connectivity.canSubmit)
                }
            }
        }
        .navigationTitle("Settings")
    }
}

@MainActor
private struct WatchSetLogger: View {
    @EnvironmentObject private var connectivity: WorkoutConnectivity
    @Environment(\.dismiss) private var dismiss
    let workoutID: String
    @State private var revision: Int
    let exercise: WorkoutExercise
    let name: String
    @State private var kg: Double
    @State private var reps: Int
    @State private var error: String?

    init(workoutID: String, revision: Int, exercise: WorkoutExercise, name: String) {
        self.workoutID = workoutID
        _revision = State(initialValue: revision)
        self.exercise = exercise
        self.name = name
        let recent = exercise.sets.last { $0.isWarmup == false }
        _kg = State(initialValue: min(1000, max(0, recent?.kg ?? exercise.target?.loadKg ?? 0)))
        _reps = State(initialValue: min(100, max(1, exercise.target?.repsMin ?? recent?.reps ?? 8)))
    }

    private var canLog: Bool {
        connectivity.canSubmit && connectivity.snapshot?.restTimer == nil &&
        connectivity.snapshot?.activeWorkout?.id == workoutID &&
        connectivity.snapshot?.activeWorkout?.nextExercise?.exerciseID == exercise.exerciseID
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Set \(exercise.workingSetCount + 1)") {
                    Text(name).font(.headline)
                    if let target = exercise.target {
                        Text("Planned: \(target.watchReps) reps" + (target.loadKg.map { " · \($0.formatted()) kg" } ?? ""))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Picker("Actual kg", selection: $kg) {
                        if kg.truncatingRemainder(dividingBy: 0.5) != 0 {
                            Text(kg.formatted()).tag(kg)
                        }
                        ForEach(0...2000, id: \.self) { halfKg in
                            Text((Double(halfKg) / 2).formatted()).tag(Double(halfKg) / 2)
                        }
                    }
                    if exercise.target?.loadKg == nil && !exercise.sets.contains(where: { $0.isWarmup == false }) {
                        Text("Choose your load. Use 0 kg for bodyweight.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Picker("Actual reps", selection: $reps) {
                        ForEach(1...100, id: \.self) { count in Text("\(count)").tag(count) }
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                Button("Save set") {
                    guard canLog else {
                        error = "This workout changed. Close this screen and review your current exercise."
                        return
                    }
                    do {
                        try connectivity.submit(.logSet(exerciseID: exercise.exerciseID,
                                                       set: WorkSet(kg: kg, reps: reps, isWarmup: false)),
                                                expectedWorkoutID: workoutID, basedOnRevision: revision)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .disabled(!canLog)
            }
            .navigationTitle("Completed set")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private func watchDuration(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}

private extension ExerciseTarget {
    var watchReps: String { repsMin == repsMax ? "\(repsMin)" : "\(repsMin)–\(repsMax)" }
    var watchSummary: String {
        let load = loadKg.map { " · \($0.formatted()) kg" } ?? ""
        return "\(sets) × \(watchReps) reps\(load)"
    }
}

private extension WatchAction {
    var watchDescription: String {
        switch self {
        case .logSet: return "Saving set"
        case .skipRest: return "Saving rest"
        case .extendRest: return "Updating rest"
        case .finishWorkout: return "Finishing workout"
        }
    }
}

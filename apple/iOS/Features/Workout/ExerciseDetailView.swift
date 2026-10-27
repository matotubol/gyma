import SwiftUI
import GymaCore

/// One exercise of a started workout: its sets, then start and log the next one.
struct ExerciseDetailView: View {
    let position: Int

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var kg = ""
    @State private var reps = ""
    @State private var draftDirty = false
    @State private var pendingStart: String?
    @State private var editor: RunnerEditor?
    @State private var confirmCancel = false

    private var session: WorkoutSession? { model.session }
    private var exercise: SessionExercise? { session?.exercise(at: position) }

    var body: some View {
        Group {
            if let session, let exercise {
                content(session, exercise)
            } else {
                ContentUnavailableView("Not in This Workout", systemImage: "dumbbell",
                                       description: Text("This exercise was removed or the workout changed."))
            }
        }
        .onChange(of: draftKey, initial: true) { resetDraft() }
        .onChange(of: isDone) { wasDone, nowDone in
            // Finishing the last planned set returns to the list to choose what's next.
            if !wasDone, nowDone, session?.status == .active, session?.activeSet == nil { dismiss() }
        }
        .sheet(item: $editor) { editor in
            WorkoutEditorSheet(editor: editor).environmentObject(model)
        }
    }

    private func content(_ session: WorkoutSession, _ exercise: SessionExercise) -> some View {
        let analysis = analyseWorkout(session)
        let recorded = session.recordedSets(at: position)
        let completedCount = session.completedSets(at: position).count
        let done = session.isDone(exercise)
        let active = session.activeSet
        let upcoming = active?.setNumber ?? session.nextSetNumber(at: position)
        let training = session.status == .active && !done
        let history = session.history(for: exercise.exerciseId)
        let total = max(exercise.plannedSets, recorded.map(\.setNumber).max() ?? 0)
        let locked = model.busy || model.workoutNeedsReload

        return List {
            Section {
                LabeledContent("Target", value: "\(exercise.plannedSets) × \(exercise.plannedReps) @ \(formatKg(exercise.plannedKg)) kg")
                if let history {
                    LabeledContent("Last · \(DateText.dayMonth(history.lastDate))") {
                        Text(history.lastSets.map(formatSet).joined(separator: " · ")).monospacedDigit()
                    }
                } else {
                    Label("First time. Today sets your baseline.", systemImage: "sparkles")
                }
            } header: {
                Text(exercise.library.detail)
            }

            Section("Sets") {
                ForEach(1...max(total, 1), id: \.self) { number in
                    setRow(number, set: recorded.first { $0.setNumber == number }, records: analysis.records,
                           next: training && active == nil && number == upcoming, plannedReps: exercise.plannedReps, locked: locked)
                }
            }

            if active != nil || training {
                Section {
                    ValueStepper(title: "Weight", text: draftBinding($kg), step: kgStep(exercise.equipment), unit: "kg", decimal: true, prominent: true)
                    ValueStepper(title: "Reps", text: draftBinding($reps), step: 1, range: 0...1000, prominent: true)
                } header: {
                    Text(active != nil ? "Set \(upcoming) · running" : "Set \(upcoming)")
                } footer: {
                    hint(history: history, upcoming: upcoming, baseline: analysis.baselines[exercise.exerciseId])
                }
                .disabled(locked)

                Section {
                    if let active {
                        Button { logActiveSet(session, active) } label: {
                            Text(model.busy ? "Saving…" : "Log Set \(active.setNumber)").frame(maxWidth: .infinity)
                        }
                        .prominentRow()
                        .disabled(locked)
                    } else {
                        Button { startSet(session) } label: {
                            Text(model.busy ? "Starting…" : "Start Set \(upcoming)").frame(maxWidth: .infinity)
                        }
                        .prominentRow()
                        .disabled(locked)
                    }
                }
                if let active {
                    Section {
                        Button("Cancel Set", role: .destructive) {
                            if draftDirty { confirmCancel = true } else { cancelSet(session, active) }
                        }
                        .disabled(locked)
                        .confirmationDialog("Cancel this set without recording it?", isPresented: $confirmCancel, titleVisibility: .visible) {
                            Button("Cancel Set", role: .destructive) { cancelSet(session, active) }
                        }
                    }
                }
            } else if !done {
                Section {
                    Button("Log Completed Set", systemImage: "plus") { editor = .logSet(position) }
                        .disabled(locked || completedCount >= 100)
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        // A running set keeps its exercise open.
        .navigationBarBackButtonHidden(active != nil)
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .refreshable { await model.reloadSession() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit Exercise", systemImage: "pencil") { editor = .editExercise(position) }
                    Button("Log Completed Set", systemImage: "checkmark.circle") { editor = .logSet(position) }
                        .disabled(completedCount >= 100)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(active != nil || locked)
                .accessibilityLabel("Exercise actions")
            }
        }
    }

    @ViewBuilder
    private func setRow(_ number: Int, set: PerformedSet?, records: [String: SetRecord], next: Bool, plannedReps: Int, locked: Bool) -> some View {
        if let set, set.status == .completed {
            let record = records[set.id] != nil
            Button { editor = .editSet(set.id) } label: {
                HStack {
                    Image(systemName: record ? "star.fill" : "checkmark.circle.fill")
                        .foregroundStyle(record ? Theme.pr : Color.green)
                    Text("Set \(number)").foregroundStyle(Color.primary)
                    if set.recordedManually { Text("logged").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Text("\(formatKg(set.actualKg ?? 0)) kg × \(set.actualReps ?? 0)")
                        .monospacedDigit()
                        .foregroundStyle(record ? Theme.pr : Color.primary)
                }
            }
            .disabled(locked)
            .swipeActions {
                Button("Delete", systemImage: "trash", role: .destructive) { removeSet(set) }
            }
            .accessibilityHint("Edit set")
        } else if let set, set.status == .active {
            HStack {
                Image(systemName: "timer").foregroundStyle(.tint)
                Text("Set \(number)")
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(clock(since: set.startedAt, now: context.date)).monospacedDigit().foregroundStyle(.tint)
                }
            }
            .fontWeight(.semibold)
        } else {
            HStack {
                Image(systemName: next ? "arrow.right.circle" : "circle").foregroundStyle(next ? Color.accentColor : Color.secondary)
                Text("Set \(number)").foregroundStyle(next ? Color.primary : Color.secondary)
                Spacer()
                Text(next ? "Next" : "× \(plannedReps)").foregroundStyle(.secondary)
            }
        }
    }

    /// "Last time set 2: 80 × 8" and "9 reps at 80 kg is a PR".
    @ViewBuilder
    private func hint(history: ExerciseHistory?, upcoming: Int, baseline: Baseline?) -> some View {
        let lastTime = history.flatMap { $0.lastSets.indices.contains(upcoming - 1) ? $0.lastSets[upcoming - 1] : nil }
        let chosenKg = parseNumber(kg) ?? .nan
        let target = repsForRecord(baseline, kg: chosenKg)
        VStack(alignment: .leading, spacing: 4) {
            if let lastTime { Text("Last time set \(upcoming): \(formatSet(lastTime))") }
            if let target {
                Label(target == .any ? "Any rep at \(formatKg(chosenKg)) kg is a PR" : "\(targetReps(target)) reps at \(formatKg(chosenKg)) kg is a PR",
                      systemImage: "star.fill")
                    .foregroundStyle(Theme.pr)
            }
        }
        .monospacedDigit()
    }

    private func targetReps(_ target: RecordTarget) -> Int {
        if case .reps(let count) = target { return count }
        return 1
    }

    // MARK: Drafts

    private var isDone: Bool { session.flatMap { session in exercise.map(session.isDone) } ?? false }

    private var draftKey: String { "\(session?.activeSet?.id ?? "")|\(exercise?.entryId ?? "")" }

    /// Typing marks the draft dirty; prefilling does not.
    private func draftBinding(_ binding: Binding<String>) -> Binding<String> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = $0; draftDirty = true })
    }

    /// Prefill with the last completed set of this exercise, else its targets.
    private func resetDraft() {
        guard let session, let exercise else { return }
        let last = session.completedSets(at: position).last
        kg = formatKg(last?.actualKg ?? exercise.plannedKg)
        reps = String(last?.actualReps ?? exercise.plannedReps)
        draftDirty = false
    }

    private func clock(since start: String, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(parseTimestamp(start) ?? now)))
        return String(format: "%02ld:%02ld", seconds / 60, seconds % 60)
    }

    // MARK: Actions

    private func startSet(_ session: WorkoutSession) {
        if pendingStart == nil { pendingStart = newEntityID() }
        guard let setId = pendingStart else { return }
        Haptics.tap()
        Task {
            if await model.perform("Set started", { api in
                try await api.startSet(date: session.date, setId: setId, position: position, version: session.version)
            }) != nil { pendingStart = nil }
        }
    }

    private func logActiveSet(_ session: WorkoutSession, _ active: PerformedSet) {
        guard let load = parseNumber(kg), (0...10000).contains(load), let count = parseCount(reps, in: 0...1000) else {
            model.workoutError = "Enter kg between 0 and 10000 and whole reps between 0 and 1000."
            return
        }
        Task {
            await model.perform("Set saved", celebrateSet: active.id) { api in
                try await api.confirmSet(date: session.date, setId: active.id, kg: load, reps: count, version: session.version)
            }
        }
    }

    private func cancelSet(_ session: WorkoutSession, _ active: PerformedSet) {
        Task {
            await model.perform("Set cancelled") { api in
                try await api.cancelSet(date: session.date, setId: active.id, version: session.version)
            }
        }
    }

    private func removeSet(_ set: PerformedSet) {
        guard let session else { return }
        Task {
            await model.perform("Set removed") { api in
                try await api.removeSet(date: session.date, setId: set.id, version: session.version)
            }
        }
    }
}

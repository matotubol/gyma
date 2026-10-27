import SwiftUI
import GymaCore

/// Runs one date's workout: choose an exercise, start each set, confirm actual kg and reps.
/// Port of gym-web's WorkoutRunner. The server session in `AppModel` is the only workout state;
/// this view keeps focus, typed values and open editors.
struct WorkoutRunnerView: View {
    let plan: WorkoutPlan

    @EnvironmentObject private var model: AppModel
    @State private var position: Int?
    @State private var kg = ""
    @State private var reps = ""
    @State private var draftDirty = false
    @State private var error: String?
    @State private var needsReload = false
    @State private var editor: RunnerEditor?
    @State private var celebration: ShownCelebration?
    @State private var pendingStart: PendingStart?
    @State private var confirm: ConfirmRequest?

    private var session: WorkoutSession? { model.session }
    private var disabled: Bool { model.busy || needsReload }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error {
                    ErrorBanner(message: error, actionTitle: needsReload || session == nil ? "Reload progress" : nil, action: reload)
                }
                if let session {
                    topline(session)
                    if let exercise = focused(session) {
                        FocusedExerciseCard(
                            session: session, exercise: exercise,
                            kg: Binding(get: { kg }, set: { kg = $0; draftDirty = true }),
                            reps: Binding(get: { reps }, set: { reps = $0; draftDirty = true }),
                            disabled: disabled, busy: model.busy,
                            onStartSet: { startSet(session, exercise) },
                            onLogSet: { logActiveSet(session) },
                            onCancelSet: { cancelActiveSet(session) },
                            onLogCompleted: { editor = .logSet },
                            onEditSet: { editor = .editSet($0) },
                            onShowExercises: showExercises)
                    } else {
                        chooser(session)
                    }
                } else {
                    ready
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .refreshable { await model.reloadSession() }
        .overlay(alignment: .top) {
            if let celebration {
                RecordToast(celebration: celebration.value) { self.celebration = nil }
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: celebration.key) {
                        try? await Task.sleep(for: .seconds(celebration.value.monster ? 6 : 4.5))
                        if self.celebration?.key == celebration.key { withAnimation { self.celebration = nil } }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: celebration?.key)
        .onAppear { position = session?.nextFocus(current: nil) }
        .onChange(of: session) { old, next in follow(old, next) }
        .onChange(of: draftKey, initial: true) { resetDraft() }
        .sheet(item: $editor) { editor in
            editorSheet(editor).environmentObject(model)
        }
        .confirmationDialog(confirm?.title ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { request in
            Button(request.actionTitle, role: request.destructive ? .destructive : nil) { request.action() }
        }
    }

    // MARK: Not started

    private var ready: some View {
        let trainable = plan.kind == .training && !plan.exercises.isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            Text(DateText.dayMonth(plan.date)).font(.caption).foregroundStyle(Theme.muted)
            Text(trainable ? "Ready to train" : "Plan your workout").font(.title.weight(.semibold))
            Text("\(plan.exercises.count) \(plan.exercises.count == 1 ? "exercise" : "exercises") planned")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            if !plan.exercises.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(plan.exercises.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Divider().overlay(Theme.line) }
                        HStack {
                            Text(item.name).font(.subheadline)
                            Spacer()
                            Text("\(item.sets) × \(item.reps) · \(formatKg(item.plannedKg)) kg")
                                .font(.caption).monospacedDigit().foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 10)
                    }
                }
                .card(padding: 12)
            }
            if trainable {
                Button {
                    Task { await perform("Workout started") { api in try await api.startSession(date: plan.date, planVersion: plan.version) } }
                } label: {
                    Text(model.busy ? "Starting…" : "Start workout")
                }
                .buttonStyle(.primary)
                .disabled(model.busy || error != nil)
            }
            if plan.exercises.isEmpty {
                Button("Open day plan") { model.planEditorOpen = true }.buttonStyle(.primary).disabled(model.busy)
            } else {
                Button("Open day plan") { model.planEditorOpen = true }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .disabled(model.busy)
            }
        }
        .padding(.top, 8)
    }

    // MARK: Header and chooser

    private func topline(_ session: WorkoutSession) -> some View {
        let done = session.exercises.filter(session.isDone).count
        let exercise = focused(session)
        let active = session.activeSet
        return HStack {
            if exercise != nil {
                Button(action: showExercises) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.caption.weight(.semibold))
                        Text("Exercises").font(.subheadline.weight(.semibold))
                        Text("\(done)/\(session.exercises.count)").font(.caption).foregroundStyle(Theme.faint)
                    }
                }
                .foregroundStyle(Theme.muted)
                .disabled(disabled || active != nil)
            } else {
                HStack(spacing: 4) {
                    Text("Exercises").font(.subheadline.weight(.semibold))
                    Text("\(done)/\(session.exercises.count)").font(.caption).foregroundStyle(Theme.faint)
                }
            }
            Spacer()
            Menu {
                Button { editor = .addExercise } label: { Label("Add exercise", systemImage: "plus") }
                if let exercise, active == nil {
                    Button { editor = .editExercise(exercise.position) } label: { Label("Edit exercise", systemImage: "pencil") }
                    Button { editor = .logSet } label: { Label("Log completed set", systemImage: "checkmark.circle") }
                        .disabled(session.completedSets(at: exercise.position).count >= 100)
                }
                if session.status == .active, active == nil, session.completedSetCount > 0 {
                    Button { finish(session) } label: { Label("Finish workout", systemImage: "flag.checkered") }
                }
                if session.status == .completed {
                    Button {
                        Task { await perform("Workout reopened", focus: exercise?.position) { api in try await api.reopen(date: session.date, version: session.version) } }
                    } label: { Label("Reopen workout", systemImage: "arrow.uturn.backward") }
                }
                Button("Edit day plan") { model.planEditorOpen = true }
            } label: {
                Image(systemName: "ellipsis").frame(width: 40, height: 36).contentShape(Rectangle())
            }
            .accessibilityLabel("Workout actions")
            .disabled(disabled)
        }
        .padding(.top, 4)
    }

    private func chooser(_ session: WorkoutSession) -> some View {
        let pending = session.exercises.filter { !session.isDone($0) }
        let done = session.exercises.filter(session.isDone)
        let records = recordPositions(session)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if session.status == .completed {
                    Text("WORKOUT COMPLETED").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.done)
                }
                Text(pending.isEmpty ? "All exercises done" : "Choose an exercise").font(.title2.weight(.semibold))
            }
            if !pending.isEmpty {
                ExerciseQueue(session: session, items: pending, records: records, done: false, disabled: disabled, onChoose: choose)
            }
            if !done.isEmpty {
                DisclosureGroup {
                    ExerciseQueue(session: session, items: done, records: records, done: true, disabled: disabled, onChoose: choose)
                        .padding(.top, 8)
                } label: {
                    HStack {
                        Text("✓ Done").foregroundStyle(Theme.done)
                        Spacer()
                        Text("\(done.count) \(done.count == 1 ? "exercise" : "exercises")").foregroundStyle(Theme.muted)
                    }
                    .font(.subheadline)
                }
                .tint(Theme.muted)
            }
            if pending.isEmpty, session.status == .active, session.completedSetCount > 0 {
                Button { finish(session) } label: { Text(model.busy ? "Saving…" : "Finish workout") }
                    .buttonStyle(.primary)
                    .disabled(disabled)
            }
            Button { editor = .addExercise } label: { Label("Add exercise", systemImage: "plus") }
                .buttonStyle(.dashed)
                .disabled(disabled)
        }
    }

    // MARK: Focus and drafts

    private func focused(_ session: WorkoutSession) -> SessionExercise? {
        session.exercise(at: session.activeSet?.exercisePosition ?? position ?? -1)
    }

    private var draftKey: String {
        guard let session else { return "" }
        return "\(session.activeSet?.id ?? "")|\(focused(session)?.position ?? -1)"
    }

    /// Prefill with the last completed set of this exercise, else its targets.
    private func resetDraft() {
        guard let session, let exercise = focused(session) else { return }
        let last = session.completedSets(at: exercise.position).last
        kg = formatKg(last?.actualKg ?? exercise.plannedKg)
        reps = String(last?.actualReps ?? exercise.plannedReps)
        draftDirty = false
    }

    /// Keeps focus valid when the session is reloaded or changed elsewhere.
    private func follow(_ old: WorkoutSession?, _ next: WorkoutSession?) {
        guard let next else { position = nil; return }
        if old?.id != next.id { position = next.nextFocus(current: nil); return }
        if let active = next.activeSet { position = active.exercisePosition }
        else if let current = position, next.exercise(at: current) == nil { position = nil }
    }

    private func choose(_ next: Int) {
        guard session?.activeSet == nil, !disabled else { return }
        position = next
    }

    private func showExercises() {
        guard session?.activeSet == nil, !disabled else { return }
        position = nil
    }

    private func recordPositions(_ session: WorkoutSession) -> Set<Int> {
        let records = analyseWorkout(session).records
        return Set(session.sets.filter { records[$0.id] != nil }.map(\.exercisePosition))
    }

    // MARK: Actions

    /// Runs a workout change. Returns nil on success, otherwise a message for the caller to show.
    @discardableResult
    private func perform(_ message: String, focus: Int? = nil, focusEntry: String? = nil, celebrateSet: String? = nil,
                         editing: Bool = false, _ operation: (GymAPI) async throws -> WorkoutSession) async -> String? {
        error = nil
        switch await model.mutateSession(operation) {
        case .success(let next):
            let preferred = focusEntry.flatMap { id in next.exercises.first { $0.entryId == id }?.position } ?? focus
            position = next.nextFocus(current: position, preferred: preferred)
            needsReload = false
            pendingStart = nil
            if !editing { draftDirty = false }
            if let setId = celebrateSet, let record = analyseWorkout(next).records[setId] {
                let copy = celebrate(record, seed: setId)
                celebration = ShownCelebration(key: setId, value: copy)
                Haptics.record(monster: copy.monster)
                UIAccessibility.post(notification: .announcement, argument: "\(copy.title) \(copy.detail)")
            } else {
                if celebrateSet != nil { Haptics.success() }
                UIAccessibility.post(notification: .announcement, argument: message)
            }
            return nil
        case .failure(.conflict):
            needsReload = true
            let text = "This workout changed or the action is no longer available. Your entries are still here. Reload progress before continuing."
            error = text
            return text
        case .failure(.unauthorized):
            return "Your access key no longer works. Sign in again."
        case .failure(.failed):
            let text = "Couldn’t save workout progress. Your entries are still here; retry the same action."
            error = text
            return text
        }
    }

    private func startSet(_ session: WorkoutSession, _ exercise: SessionExercise) {
        if pendingStart?.position != exercise.position { pendingStart = PendingStart(position: exercise.position, id: newEntityID()) }
        guard let setId = pendingStart?.id else { return }
        Haptics.tap()
        Task { await perform("Set started") { api in try await api.startSet(date: session.date, setId: setId, position: exercise.position, version: session.version) } }
    }

    private func logActiveSet(_ session: WorkoutSession) {
        guard let active = session.activeSet else { return }
        guard let kgValue = parseNumber(kg), (0...10000).contains(kgValue), let repsValue = parseCount(reps, in: 0...1000) else {
            error = "Enter kg between 0 and 10000 and whole reps between 0 and 1000."
            return
        }
        Task {
            await perform("Set saved", celebrateSet: active.id) { api in
                try await api.confirmSet(date: session.date, setId: active.id, kg: kgValue, reps: repsValue, version: session.version)
            }
        }
    }

    private func cancelActiveSet(_ session: WorkoutSession) {
        guard let active = session.activeSet else { return }
        let cancel: () -> Void = {
            Task { await perform("Set cancelled") { api in try await api.cancelSet(date: session.date, setId: active.id, version: session.version) } }
        }
        if draftDirty {
            confirm = ConfirmRequest(title: "Cancel this set without recording its kg and reps?", actionTitle: "Cancel set", action: cancel)
        } else {
            cancel()
        }
    }

    private func finish(_ session: WorkoutSession) {
        let run: () -> Void = {
            Task { await perform("Workout completed") { api in try await api.finish(date: session.date, version: session.version) } }
        }
        let remaining = session.plannedSetCount - session.completedSetCount
        if remaining > 0 {
            confirm = ConfirmRequest(title: "Finish this workout with \(remaining) planned \(remaining == 1 ? "set" : "sets") unfinished?",
                                     actionTitle: "Finish workout", destructive: false, action: run)
        } else {
            run()
        }
    }

    private func reload() {
        if session == nil && needsReload { model.loadDay() } else { Task { await model.reloadSession() } }
        error = nil; needsReload = false; draftDirty = false
        editor = nil
        resetDraft()
    }

    // MARK: Editors

    @ViewBuilder
    private func editorSheet(_ editor: RunnerEditor) -> some View {
        if let session {
            switch editor {
            case .addExercise:
                WorkoutExerciseEditor(date: session.date, initial: nil, minimumSets: 1, recordedSets: 0,
                                      onSave: { targets, entryId, _ in
                                          await perform("Exercise added to this workout", focusEntry: entryId, editing: true) { api in
                                              try await api.addExercise(date: session.date, entryId: entryId, targets: targets, version: session.version)
                                          }
                                      }, onRemove: nil)
            case .editExercise(let position):
                let initial = session.exercise(at: position)
                WorkoutExerciseEditor(date: session.date, initial: initial,
                                      minimumSets: max(1, session.recordedSets(at: position).map(\.setNumber).max() ?? 1),
                                      recordedSets: session.completedSets(at: position).count,
                                      onSave: { targets, _, reassign in
                                          await perform("Workout exercise updated", focus: position, editing: true) { api in
                                              try await api.editExercise(date: session.date, position: position, targets: targets, allowReassign: reassign, version: session.version)
                                          }
                                      }, onRemove: {
                                          await perform("Exercise removed from this workout", editing: true) { api in
                                              try await api.removeExercise(date: session.date, position: position, version: session.version)
                                          }
                                      })
            case .logSet:
                if let exercise = focused(session) {
                    WorkoutSetEditor(initial: nil, exercise: exercise, onSave: { kg, reps, setId in
                        await perform("Completed set logged", focus: exercise.position, celebrateSet: setId, editing: true) { api in
                            try await api.logSet(date: session.date, setId: setId, position: exercise.position, kg: kg, reps: reps, version: session.version)
                        }
                    }, onRemove: nil)
                }
            case .editSet(let setId):
                if let set = session.sets.first(where: { $0.id == setId }), let exercise = session.exercise(at: set.exercisePosition) {
                    WorkoutSetEditor(initial: set, exercise: exercise, onSave: { kg, reps, _ in
                        await perform("Recorded set corrected", focus: exercise.position, editing: true) { api in
                            try await api.editSet(date: session.date, setId: setId, kg: kg, reps: reps, version: session.version)
                        }
                    }, onRemove: {
                        await perform("Recorded set removed", focus: exercise.position, editing: true) { api in
                            try await api.removeSet(date: session.date, setId: setId, version: session.version)
                        }
                    })
                }
            }
        }
    }
}

// MARK: - Supporting types

enum RunnerEditor: Identifiable, Hashable {
    case addExercise
    case editExercise(Int)
    case logSet
    case editSet(String)

    var id: String {
        switch self {
        case .addExercise: "add"
        case .editExercise(let position): "exercise-\(position)"
        case .logSet: "log"
        case .editSet(let id): "set-\(id)"
        }
    }
}

private struct PendingStart: Equatable { let position: Int; let id: String }

private struct ShownCelebration: Equatable { let key: String; let value: Celebration }

struct ConfirmRequest {
    let title: String
    let actionTitle: String
    var destructive = true
    let action: () -> Void
}

private struct ExerciseQueue: View {
    let session: WorkoutSession
    let items: [SessionExercise]
    let records: Set<Int>
    let done: Bool
    let disabled: Bool
    let onChoose: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.entryId) { index, item in
                if index > 0 { Divider().overlay(Theme.line) }
                Button { onChoose(item.position) } label: {
                    HStack(spacing: 12) {
                        if done {
                            Image(systemName: "checkmark").font(.caption.weight(.semibold)).foregroundStyle(Theme.done).frame(width: 18)
                        } else {
                            Text(String(format: "%02ld", (session.exercises.firstIndex(of: item) ?? 0) + 1))
                                .font(.system(size: 10)).monospacedDigit().foregroundStyle(Theme.muted).frame(width: 18)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                                if records.contains(item.position) { PRChip() }
                            }
                            let count = session.completedSets(at: item.position).count
                            Text(done ? "\(count) sets logged · \(item.library.detail)" : "\(item.library.detail) · \(count)/\(item.plannedSets) sets")
                                .font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
            }
        }
        .background(done ? Theme.surface.opacity(0.5) : Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

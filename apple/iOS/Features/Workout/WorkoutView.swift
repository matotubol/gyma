import SwiftUI
import GymaCore

/// The Workout tab: the selected day's exercises. Each exercise opens as its own screen.
struct WorkoutView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editor: RunnerEditor?
    @State private var confirm: ConfirmRequest?

    var body: some View {
        NavigationStack(path: $model.workoutPath) {
            content
                .navigationTitle(model.selectedDate == CivilDate.today ? "Today" : DateText.shortDay(model.selectedDate))
                .toolbar { toolbar }
                .navigationDestination(for: Int.self) { ExerciseDetailView(position: $0) }
        }
        .sheet(item: $editor) { editor in
            WorkoutEditorSheet(editor: editor) { position in model.workoutPath = [position] }
                .environmentObject(model)
        }
        .confirmationDialog(confirm?.title ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { request in
            Button(request.actionTitle, role: request.destructive ? .destructive : nil) { request.action() }
        }
        .alert("Couldn’t Save", isPresented: Binding(get: { model.workoutError != nil }, set: { if !$0 { model.workoutError = nil } })) {
            if model.workoutNeedsReload {
                Button("Reload") { Task { await model.reloadSession() } }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.workoutError ?? "")
        }
        // A running set always owns focus.
        .onChange(of: model.session?.activeSet?.exercisePosition, initial: true) { _, position in
            if let position, model.workoutPath != [position] { model.workoutPath = [position] }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let plan = model.dayPlan {
            if let session = model.session {
                SessionList(session: session, editor: $editor, confirm: $confirm)
            } else {
                ReadyList(plan: plan)
            }
        } else if let error = model.dayError {
            ContentUnavailableView {
                Label("Couldn’t Load This Day", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { model.loadDay() }
            }
        } else {
            ProgressView()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button { model.select(CivilDate.shift(day: model.selectedDate, by: -1)) } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous day")
            Button { model.select(CivilDate.shift(day: model.selectedDate, by: 1)) } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next day")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.selectedDate != CivilDate.today {
                Button("Today") { model.select(CivilDate.today) }
            }
            Menu {
                if let session = model.session {
                    Button("Add Exercise", systemImage: "plus") { editor = .addExercise }
                    if session.status == .active, session.activeSet == nil, session.completedSetCount > 0 {
                        Button("Finish Workout", systemImage: "flag.checkered") { confirm = finishRequest(session) }
                    }
                    if session.status == .completed {
                        Button("Reopen Workout", systemImage: "arrow.uturn.backward") {
                            Task { await model.perform("Workout reopened") { api in try await api.reopen(date: session.date, version: session.version) } }
                        }
                    }
                }
                Button("Edit Day Plan", systemImage: "list.bullet.clipboard") { model.planEditorOpen = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Workout actions")
        }
    }

    private func finishRequest(_ session: WorkoutSession) -> ConfirmRequest {
        let remaining = session.plannedSetCount - session.completedSetCount
        return ConfirmRequest(
            title: remaining > 0 ? "Finish with \(remaining) planned \(remaining == 1 ? "set" : "sets") unfinished?" : "Finish this workout?",
            actionTitle: "Finish Workout", destructive: false) {
                Task { await model.perform("Workout completed") { api in try await api.finish(date: session.date, version: session.version) } }
            }
    }
}

// MARK: - Not started

private struct ReadyList: View {
    let plan: WorkoutPlan
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if plan.exercises.isEmpty {
            ContentUnavailableView {
                Label(plan.kind == .rest ? "Rest Day" : "Nothing Planned", systemImage: plan.kind == .rest ? "bed.double" : "calendar.badge.plus")
            } description: {
                Text(plan.kind == .rest ? "Recover well." : "Plan exercises for this day to start a workout.")
            } actions: {
                Button("Plan This Day") { model.planEditorOpen = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy)
            }
        } else {
            List {
                Section {
                    ForEach(Array(plan.exercises.enumerated()), id: \.offset) { _, item in
                        LabeledContent {
                            Text("\(item.sets) × \(item.reps) · \(formatKg(item.plannedKg)) kg").monospacedDigit()
                        } label: {
                            Text(item.name)
                            Text(item.library.detail)
                        }
                    }
                } header: {
                    Text("\(plan.exercises.count) \(plan.exercises.count == 1 ? "exercise" : "exercises") planned")
                }
                Section {
                    Button {
                        Task { await model.perform("Workout started") { api in try await api.startSession(date: plan.date, planVersion: plan.version) } }
                    } label: {
                        Text(model.busy ? "Starting…" : "Start Workout").frame(maxWidth: .infinity)
                    }
                    .prominentRow()
                    .disabled(model.busy || plan.kind != .training)
                }
                Section {
                    Button("Edit Day Plan", systemImage: "pencil") { model.planEditorOpen = true }
                        .disabled(model.busy)
                }
            }
            .refreshable { await model.refresh() }
        }
    }
}

// MARK: - Started

private struct SessionList: View {
    let session: WorkoutSession
    @Binding var editor: RunnerEditor?
    @Binding var confirm: ConfirmRequest?
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let pending = session.exercises.filter { !session.isDone($0) }
        let done = session.exercises.filter(session.isDone)
        let records = recordPositions()
        let running = session.activeSet?.exercisePosition
        List {
            if model.workoutNeedsReload {
                Section {
                    Button("Reload Workout", systemImage: "arrow.clockwise") { Task { await model.reloadSession() } }
                } footer: {
                    Text("This workout changed elsewhere.")
                }
            }
            if session.status == .completed {
                Section {
                    Label("Workout completed", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }
            if !pending.isEmpty {
                Section("To Do") {
                    ForEach(pending) { row($0, records: records, running: running, done: false) }
                }
            }
            if !done.isEmpty {
                Section("Done") {
                    ForEach(done) { row($0, records: records, running: running, done: true) }
                }
            }
            Section {
                if pending.isEmpty, session.status == .active, session.completedSetCount > 0 {
                    Button {
                        Task { await model.perform("Workout completed") { api in try await api.finish(date: session.date, version: session.version) } }
                    } label: {
                        Text(model.busy ? "Saving…" : "Finish Workout").frame(maxWidth: .infinity)
                    }
                    .prominentRow()
                    .disabled(model.busy)
                }
            }
            Section {
                Button("Add Exercise", systemImage: "plus") { editor = .addExercise }
                    .disabled(model.busy || running != nil)
            }
        }
        .refreshable { await model.reloadSession() }
    }

    private func row(_ item: SessionExercise, records: Set<Int>, running: Int?, done: Bool) -> some View {
        let count = session.completedSets(at: item.position).count
        return NavigationLink(value: item.position) {
            HStack(spacing: 12) {
                Image(systemName: running == item.position ? "timer" : done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(running == item.position ? Color.accentColor : done ? Color.green : Color.secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(item.name)
                        if records.contains(item.position) {
                            Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.pr).accessibilityLabel("Personal record")
                        }
                    }
                    Text("\(item.library.detail) · \(count)/\(item.plannedSets) sets")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(running != nil && running != item.position)
        .swipeActions {
            Button("Remove", systemImage: "trash", role: .destructive) { confirm = removeRequest(item, count: count) }
            Button("Edit", systemImage: "pencil") { editor = .editExercise(item.position) }
        }
    }

    private func removeRequest(_ item: SessionExercise, count: Int) -> ConfirmRequest {
        ConfirmRequest(title: "Remove \(item.name)\(count > 0 ? " and its \(count) recorded \(count == 1 ? "set" : "sets")" : "") from this workout?",
                       actionTitle: "Remove Exercise") {
            Task {
                await model.perform("Exercise removed") { api in
                    try await api.removeExercise(date: session.date, position: item.position, version: session.version)
                }
            }
        }
    }

    private func recordPositions() -> Set<Int> {
        let records = analyseWorkout(session).records
        return Set(session.sets.filter { records[$0.id] != nil }.map(\.exercisePosition))
    }
}

struct ConfirmRequest {
    let title: String
    let actionTitle: String
    var destructive = true
    let action: () -> Void
}

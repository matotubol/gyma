import SwiftUI
import GymaCore

/// Edits the selected date's day type and ordered exercises, saved atomically with its version.
struct DayPlanEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var base: WorkoutPlan?
    @State private var kind: DayKind?
    @State private var rows: [DraftRow] = []
    @State private var original: [DraftRow] = []
    @State private var path: [UUID] = []
    @State private var saving = false
    @State private var conflict = false
    @State private var error: String?
    @State private var picking = false
    @State private var pendingKind: KindChoice?
    @State private var confirmDiscard = false

    private var dirty: Bool { base != nil && (kind != base?.kind || rows != original) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let base {
                    form(base)
                } else if let error = model.dayError {
                    ContentUnavailableView {
                        Label("Couldn’t Load Plan", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { model.loadDay() }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Day Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if dirty { confirmDiscard = true } else { dismiss() } }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("Save", action: save)
                            .disabled(!dirty || conflict || model.busy || rows.contains { $0.exercise == nil })
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    if base != nil, !rows.isEmpty { EditButton() }
                    Spacer()
                    Text(summary).font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let index = rows.firstIndex(where: { $0.id == id }), let base {
                    PlanRowEditor(row: $rows[index], date: base.date)
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
            }
            .confirmationDialog("Remove this day’s exercises?", isPresented: Binding(
                get: { pendingKind != nil }, set: { if !$0 { pendingKind = nil } }), titleVisibility: .visible, presenting: pendingKind) { choice in
                Button("Remove Exercises", role: .destructive) { rows = []; kind = choice.kind }
            } message: { choice in
                Text("A \(choice.title.lowercased()) day has no exercises. Save to apply.")
            }
            .sheet(isPresented: $picking) {
                ExercisePickerSheet { chosen in
                    let row = DraftRow(exercise: chosen, autoKg: true)
                    rows.append(row)
                    kind = .training
                    path = [row.id]
                }
                .environmentObject(model)
            }
        }
        .interactiveDismissDisabled(dirty || saving)
        .onAppear(perform: resetFromModel)
        .onChange(of: model.plan) { if base == nil || !dirty { resetFromModel() } }
    }

    private func form(_ base: WorkoutPlan) -> some View {
        List {
            if let error {
                Section {
                    Text(error).foregroundStyle(.red)
                    if conflict { Button("Reload Plan", systemImage: "arrow.clockwise", action: reloadPlan) }
                }
            }

            Section {
                Picker("Day Type", selection: kindChoice) {
                    ForEach(KindChoice.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                if model.session != nil {
                    Text("This day has a started workout. To change recorded sets, use the workout.")
                }
            }

            Section {
                ForEach(rows) { row in
                    NavigationLink(value: row.id) { PlanRowLabel(row: row) }
                }
                .onDelete { rows.remove(atOffsets: $0) }
                .onMove { rows.move(fromOffsets: $0, toOffset: $1) }
                Button("Add Exercise", systemImage: "plus") { picking = true }
                    .disabled(rows.count >= 100)
            } header: {
                Text("Exercises")
            } footer: {
                Text("Kilograms per set. Use 0 for bodyweight.")
            }
        }
        .disabled(saving || model.busy)
    }

    private var summary: String {
        let sets = rows.reduce(0) { $0 + (Int($1.sets) ?? 0) }
        return "\(rows.count) \(rows.count == 1 ? "exercise" : "exercises") · \(sets) sets"
    }

    private var kindChoice: Binding<KindChoice> {
        Binding(get: { KindChoice(kind) }, set: { choice in
            guard choice.kind != kind else { return }
            if choice != .training && !rows.isEmpty { pendingKind = choice } else { kind = choice.kind }
        })
    }

    private func resetFromModel() {
        guard let plan = model.plan, plan.date == model.selectedDate, model.isDayReady else { return }
        base = plan
        kind = plan.kind
        rows = plan.exercises.map { DraftRow(exercise: $0.library, sets: String($0.sets), reps: String($0.reps), kg: formatKg($0.plannedKg)) }
        original = rows
        path = []
        conflict = false; error = nil
    }

    private func reloadPlan() {
        base = nil; conflict = false; error = nil
        model.loadDay()
    }

    private func save() {
        guard let base, !saving else { return }
        var inputs: [PlannedExerciseInput] = []
        for (index, row) in rows.enumerated() {
            guard let exercise = row.exercise, let values = row.values else {
                error = "Check exercise \(index + 1): sets 1–100, reps 1–1000 and 0–10000 kg."
                return
            }
            inputs.append(PlannedExerciseInput(exerciseId: exercise.id, sets: values.sets, reps: values.reps, plannedKg: values.kg))
        }
        saving = true; error = nil
        Task {
            switch await model.savePlan(date: base.date, kind: kind, expectedVersion: base.version, exercises: inputs) {
            case .saved:
                original = rows
                self.base = model.dayPlan
                Haptics.success()
                dismiss()
            case .conflict:
                conflict = true
                error = "This plan changed elsewhere. Your edits are still here; reload the saved plan before editing again."
            case .failed:
                error = "Couldn’t save. Your edits are still here; try again."
            }
            saving = false
        }
    }
}

// MARK: - Rows

struct DraftRow: Identifiable, Equatable {
    let id = UUID()
    var exercise: LibraryExercise?
    var sets = "3"
    var reps = "10"
    var kg = "0"
    var autoKg = false

    var values: (sets: Int, reps: Int, kg: Double)? {
        guard let sets = parseCount(sets, in: 1...100), let reps = parseCount(reps, in: 1...1000),
              let kg = parseNumber(kg), (0...10000).contains(kg) else { return nil }
        return (sets, reps, kg)
    }

    static func == (lhs: DraftRow, rhs: DraftRow) -> Bool {
        lhs.id == rhs.id && lhs.exercise == rhs.exercise && lhs.sets == rhs.sets && lhs.reps == rhs.reps && lhs.kg == rhs.kg
    }
}

private struct PlanRowLabel: View {
    let row: DraftRow

    var body: some View {
        LabeledContent {
            if let values = row.values {
                Text("\(values.sets) × \(values.reps)\(values.kg > 0 ? " · \(formatKg(values.kg)) kg" : "")").monospacedDigit()
            } else {
                Label("Check values", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        } label: {
            Text(row.exercise?.name ?? "Choose exercise")
            if let exercise = row.exercise { Text(exercise.detail) }
        }
    }
}

/// One planned exercise: library reference, sets, reps and load with a suggestion.
private struct PlanRowEditor: View {
    @Binding var row: DraftRow
    let date: String

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    ExercisePickerList { exercise in
                        row.exercise = exercise
                        row.autoKg = (parseNumber(row.kg) ?? 0) == 0
                    }
                } label: {
                    LabeledContent("Exercise") {
                        Text(row.exercise?.name ?? "Choose").foregroundStyle(row.exercise == nil ? Color.accentColor : Color.secondary)
                    }
                }
            } footer: {
                if let exercise = row.exercise { Text(exercise.detail) }
            }

            Section("Targets") {
                ValueStepper(title: "Sets", text: $row.sets, step: 1, range: 1...100)
                ValueStepper(title: "Reps per set", text: $row.reps, step: 1, range: 1...1000)
                ValueStepper(title: "Weight", text: $row.kg, step: row.exercise.map { kgStep($0.equipment) } ?? 2.5, unit: "kg", decimal: true)
            }

            if let exercise = row.exercise {
                KgSuggestSection(exercise: exercise, before: date, reps: row.reps, kg: row.kg, autoFill: row.autoKg) { row.kg = $0 }
                    .id(exercise.id)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .navigationTitle(row.exercise?.name ?? "Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum KindChoice: CaseIterable, Identifiable {
    case unplanned, training, rest

    init(_ kind: DayKind?) {
        switch kind {
        case .some(.training): self = .training
        case .some(.rest): self = .rest
        case .none: self = .unplanned
        }
    }

    var id: Self { self }
    var kind: DayKind? {
        switch self {
        case .unplanned: nil
        case .training: .training
        case .rest: .rest
        }
    }
    var title: String { kind.label }
}

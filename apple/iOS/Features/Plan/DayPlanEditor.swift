import SwiftUI
import GymaCore

/// Edits the selected date's day type and ordered exercises, saved atomically with its version.
struct DayPlanEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var base: WorkoutPlan?
    @State private var kind: DayKind?
    @State private var rows: [DraftRow] = []
    @State private var dirty = false
    @State private var saving = false
    @State private var conflict = false
    @State private var error: String?
    @State private var pickerRow: PickerTarget?
    @State private var pendingKind: KindChoice?
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            Group {
                if let base {
                    editor(base)
                } else if let error = model.dayError {
                    ErrorBanner(message: error, actionTitle: "Retry") { model.loadDay() }.padding(16)
                    Spacer()
                } else {
                    ProgressView("Loading plan…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Day plan").font(.headline)
                        Text(DateText.shortDay(base?.date ?? model.selectedDate)).font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if dirty { confirmDiscard = true } else { dismiss() } }
                        .disabled(saving)
                }
            }
            .keyboardDoneButton()
            .confirmationDialog("Discard unsaved changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
            }
            .confirmationDialog("Remove this day’s exercises and change the day type?", isPresented: Binding(
                get: { pendingKind != nil }, set: { if !$0 { pendingKind = nil } }), titleVisibility: .visible, presenting: pendingKind) { choice in
                Button("Remove exercises", role: .destructive) {
                    rows = []; kind = choice.kind; dirty = true
                }
            } message: { _ in
                Text("Save to apply.")
            }
            .sheet(item: $pickerRow) { target in
                ExercisePickerSheet { chosen in choose(chosen, for: target.id) }
                    .environmentObject(model)
            }
        }
        .interactiveDismissDisabled(dirty || saving)
        .onAppear(perform: resetFromModel)
        .onChange(of: model.plan) { if base == nil || !dirty { resetFromModel() } }
    }

    private func editor(_ base: WorkoutPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error {
                    ErrorBanner(message: error, actionTitle: conflict ? "Reload plan" : nil, action: reloadPlan)
                }
                if model.session != nil {
                    Text("This day has a started workout. Changes here update the day plan; edit recorded sets from the workout’s actions menu.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                Picker("Day type", selection: kindChoice) {
                    ForEach(KindChoice.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Spacer()
                    Text("\(rows.count) \(rows.count == 1 ? "exercise" : "exercises") · \(rows.reduce(0) { $0 + (Int($1.sets) ?? 0) }) sets")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                ForEach($rows) { $row in
                    DraftRowCard(row: $row, number: (rows.firstIndex { $0.id == row.id } ?? 0) + 1, date: base.date,
                                 onPickExercise: { pickerRow = PickerTarget(id: row.id) },
                                 onRemove: { rows.removeAll { $0.id == row.id }; dirty = true },
                                 onChange: { dirty = true })
                }

                Button {
                    let row = DraftRow()
                    rows.append(row)
                    kind = .training
                    dirty = true
                    pickerRow = PickerTarget(id: row.id)
                } label: {
                    Label("Add exercise", systemImage: "plus")
                }
                .buttonStyle(.dashed)
                .disabled(rows.count >= 100)

                Text("Kg per set. Use 0 for bodyweight.")
                    .font(.caption)
                    .foregroundStyle(Theme.faint)
            }
            .disabled(saving || model.busy)
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                HStack(spacing: 6) {
                    Text(saving ? "Saving…" : "Save plan")
                    if !saving { Image(systemName: "checkmark").font(.footnote.weight(.semibold)) }
                }
            }
            .buttonStyle(.primary)
            .disabled(saving || model.busy || !dirty || conflict || rows.contains { $0.exercise == nil })
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.canvas)
        }
    }

    private var kindChoice: Binding<KindChoice> {
        Binding(get: { KindChoice(kind) }, set: { choice in
            guard choice.kind != kind else { return }
            if choice != .training && !rows.isEmpty { pendingKind = choice; return }
            kind = choice.kind
            dirty = true
        })
    }

    private func resetFromModel() {
        guard let plan = model.plan, plan.date == model.selectedDate, model.isDayReady else { return }
        base = plan
        kind = plan.kind
        rows = plan.exercises.map { DraftRow(exercise: $0.library, sets: String($0.sets), reps: String($0.reps), kg: formatKg($0.plannedKg)) }
        dirty = false; conflict = false; error = nil
    }

    private func reloadPlan() {
        dirty = false; conflict = false; error = nil; base = nil
        model.loadDay()
    }

    private func choose(_ exercise: LibraryExercise, for id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].exercise = exercise
        rows[index].autoKg = (parseNumber(rows[index].kg) ?? 0) == 0
        dirty = true
    }

    private func save() {
        guard let base, !saving else { return }
        var inputs: [PlannedExerciseInput] = []
        for (index, row) in rows.enumerated() {
            guard let exercise = row.exercise else { error = "Choose a library exercise for each row before saving."; return }
            guard let sets = parseCount(row.sets, in: 1...100), let reps = parseCount(row.reps, in: 1...1000),
                  let kg = parseNumber(row.kg), (0...10000).contains(kg) else {
                error = "Check exercise \(index + 1): sets 1–100, reps 1–1000 and kg 0–10000."
                return
            }
            inputs.append(PlannedExerciseInput(exerciseId: exercise.id, sets: sets, reps: reps, plannedKg: kg))
        }
        saving = true; error = nil
        Task {
            switch await model.savePlan(date: base.date, kind: kind, expectedVersion: base.version, exercises: inputs) {
            case .saved:
                dirty = false
                Haptics.success()
                dismiss()
            case .conflict:
                conflict = true
                error = "This plan changed elsewhere. Your edits are still here. Reload the saved plan before editing again."
            case .failed:
                error = "Couldn’t save. Your edits are still here; please try again."
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
}

private struct PickerTarget: Identifiable { let id: UUID }

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

private struct DraftRowCard: View {
    @Binding var row: DraftRow
    let number: Int
    let date: String
    let onPickExercise: () -> Void
    let onRemove: () -> Void
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(String(format: "%02ld", number))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
                Button(action: onPickExercise) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.exercise?.name ?? "Choose exercise")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(row.exercise == nil ? Theme.muted : Theme.ink)
                            if let exercise = row.exercise {
                                Text(exercise.detail).font(.system(size: 11)).foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
                }
                .buttonStyle(.plain)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash").frame(width: 36, height: 36)
                }
                .foregroundStyle(Theme.muted)
                .accessibilityLabel("Remove exercise \(number)")
            }

            HStack(spacing: 10) {
                field("Sets", text: $row.sets, decimal: false)
                field("Reps / set", text: $row.reps, decimal: false)
                field("Planned kg", text: $row.kg, decimal: true)
            }

            if let exercise = row.exercise {
                KgSuggestView(exercise: exercise, before: date, reps: row.reps, kg: row.kg, autoFill: row.autoKg) { value in
                    row.kg = value
                    onChange()
                }
                .id(exercise.id)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
    }

    private func field(_ label: String, text: Binding<String>, decimal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.muted)
            TextField("0", text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .inputField()
                .onChange(of: text.wrappedValue) { onChange() }
        }
    }
}

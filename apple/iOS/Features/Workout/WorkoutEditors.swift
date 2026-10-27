import SwiftUI
import GymaCore

enum RunnerEditor: Identifiable, Hashable {
    case addExercise
    case editExercise(Int)
    case logSet(Int)
    case editSet(String)

    var id: String {
        switch self {
        case .addExercise: "add"
        case .editExercise(let position): "exercise-\(position)"
        case .logSet(let position): "log-\(position)"
        case .editSet(let id): "set-\(id)"
        }
    }
}

/// Builds the editor for a workout change against the current session.
struct WorkoutEditorSheet: View {
    let editor: RunnerEditor
    /// Called with the position of a newly added exercise.
    var onAdded: (Int) -> Void = { _ in }
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let session = model.session {
            switch editor {
            case .addExercise:
                WorkoutExerciseEditor(date: session.date, initial: nil, minimumSets: 1, recordedSets: 0, onSave: { targets, entryId, _ in
                    let error = await model.attempt("Exercise added") { api in
                        try await api.addExercise(date: session.date, entryId: entryId, targets: targets, version: session.version)
                    }
                    if error == nil, let added = model.session?.exercises.first(where: { $0.entryId == entryId }) { onAdded(added.position) }
                    return error
                }, onRemove: nil)
            case .editExercise(let position):
                if let initial = session.exercise(at: position) {
                    WorkoutExerciseEditor(date: session.date, initial: initial,
                                          minimumSets: max(1, session.recordedSets(at: position).map(\.setNumber).max() ?? 1),
                                          recordedSets: session.completedSets(at: position).count, onSave: { targets, _, reassign in
                        await model.attempt("Exercise updated") { api in
                            try await api.editExercise(date: session.date, position: position, targets: targets, allowReassign: reassign, version: session.version)
                        }
                    }, onRemove: {
                        await model.attempt("Exercise removed") { api in
                            try await api.removeExercise(date: session.date, position: position, version: session.version)
                        }
                    })
                }
            case .logSet(let position):
                if let exercise = session.exercise(at: position) {
                    WorkoutSetEditor(initial: nil, exercise: exercise, onSave: { kg, reps, setId in
                        await model.attempt("Completed set logged", celebrateSet: setId) { api in
                            try await api.logSet(date: session.date, setId: setId, position: position, kg: kg, reps: reps, version: session.version)
                        }
                    }, onRemove: nil)
                }
            case .editSet(let setId):
                if let set = session.sets.first(where: { $0.id == setId }), let exercise = session.exercise(at: set.exercisePosition) {
                    WorkoutSetEditor(initial: set, exercise: exercise, onSave: { kg, reps, _ in
                        await model.attempt("Set corrected") { api in
                            try await api.editSet(date: session.date, setId: setId, kg: kg, reps: reps, version: session.version)
                        }
                    }, onRemove: {
                        await model.attempt("Set removed") { api in
                            try await api.removeSet(date: session.date, setId: setId, version: session.version)
                        }
                    })
                }
            }
        }
    }
}

/// Add an exercise to a started workout, or change one's library reference and targets.
struct WorkoutExerciseEditor: View {
    let date: String
    let initial: SessionExercise?
    let minimumSets: Int
    /// Completed sets that move along when the exercise is changed.
    let recordedSets: Int
    /// Saves targets with the client entry ID and whether recorded sets may move. Returns an error message.
    let onSave: (ExerciseTargets, String, Bool) async -> String?
    let onRemove: (() async -> String?)?

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: LibraryExercise?
    @State private var sets = "3"
    @State private var reps = "10"
    @State private var kg = "0"
    @State private var autoKg = false
    @State private var entryId = newEntityID()
    @State private var saving = false
    @State private var error: String?
    @State private var confirmReassign = false
    @State private var confirmRemove = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ExercisePickerList { exercise in
                            chosen = exercise
                            autoKg = (parseNumber(kg) ?? 0) == 0
                        }
                    } label: {
                        LabeledContent("Exercise") {
                            Text(chosen?.name ?? "Choose").foregroundStyle(chosen == nil ? Color.accentColor : Color.secondary)
                        }
                    }
                } footer: {
                    if let chosen { Text(chosen.detail) }
                }

                Section("Targets") {
                    ValueStepper(title: "Sets", text: $sets, step: 1, range: Double(minimumSets)...100)
                    ValueStepper(title: "Reps", text: $reps, step: 1, range: 1...1000)
                    ValueStepper(title: "Weight", text: $kg, step: chosen.map { kgStep($0.equipment) } ?? 2.5, unit: "kg", decimal: true)
                }

                if let chosen {
                    KgSuggestSection(exercise: chosen, before: date, reps: reps, kg: kg, autoFill: autoKg) { kg = $0 }
                        .id(chosen.id)
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }

                if onRemove != nil {
                    Section {
                        Button("Remove Exercise", role: .destructive) { confirmRemove = true }
                    }
                }
            }
            .disabled(saving)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(initial == nil ? "Add Exercise" : "Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button(initial == nil ? "Add" : "Save", action: save).disabled(chosen == nil)
                    }
                }
            }
            .keyboardDoneButton()
            .confirmationDialog("Its \(recordedSets) recorded \(recordedSets == 1 ? "set moves" : "sets move") to the new exercise.",
                                isPresented: $confirmReassign, titleVisibility: .visible) {
                Button("Change Exercise") { submit(reassign: true) }
            }
            .confirmationDialog(removeTitle, isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove Exercise", role: .destructive) { remove() }
            }
        }
        .interactiveDismissDisabled(saving)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let initial {
                chosen = initial.library
                sets = String(initial.plannedSets); reps = String(initial.plannedReps); kg = formatKg(initial.plannedKg)
            }
        }
    }

    private var removeTitle: String {
        "Remove \(initial?.name ?? "this exercise")\(recordedSets > 0 ? " and its \(recordedSets) recorded \(recordedSets == 1 ? "set" : "sets")" : "")?"
    }

    private func save() {
        guard let chosen else { return }
        if let initial, initial.exerciseId != chosen.id, recordedSets > 0 { confirmReassign = true; return }
        submit(reassign: false)
    }

    private func submit(reassign: Bool) {
        guard let chosen else { return }
        guard let setCount = parseCount(sets, in: minimumSets...100), let repCount = parseCount(reps, in: 1...1000),
              let load = parseNumber(kg), (0...10000).contains(load) else {
            error = "Use \(minimumSets)–100 sets, 1–1000 reps and 0–10000 kg."
            return
        }
        saving = true; error = nil
        Task {
            error = await onSave(ExerciseTargets(exerciseId: chosen.id, plannedSets: setCount, plannedReps: repCount, plannedKg: load), entryId, reassign)
            saving = false
            if error == nil { dismiss() }
        }
    }

    private func remove() {
        guard let onRemove else { return }
        saving = true; error = nil
        Task {
            error = await onRemove()
            saving = false
            if error == nil { dismiss() }
        }
    }
}

/// Log a set performed without the timer, or correct or remove a recorded set.
struct WorkoutSetEditor: View {
    let initial: PerformedSet?
    let exercise: SessionExercise
    /// Saves kg, reps and the set ID. Returns an error message.
    let onSave: (Double, Int, String) async -> String?
    let onRemove: (() async -> String?)?

    @Environment(\.dismiss) private var dismiss
    @State private var kg = ""
    @State private var reps = ""
    @State private var setId = newEntityID()
    @State private var saving = false
    @State private var error: String?
    @State private var confirmRemove = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ValueStepper(title: "Weight", text: $kg, step: kgStep(exercise.equipment), unit: "kg", decimal: true)
                    ValueStepper(title: "Reps", text: $reps, step: 1, range: 0...1000)
                } header: {
                    Text(exercise.name)
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                    else if initial == nil { Text("A set you already performed. No timer needed.") }
                }
                if onRemove != nil {
                    Section {
                        Button("Delete Set", role: .destructive) { confirmRemove = true }
                    }
                }
            }
            .disabled(saving)
            .navigationTitle(initial.map { "Set \($0.setNumber)" } ?? "Log Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Save", action: save) }
                }
            }
            .keyboardDoneButton()
            .confirmationDialog("Remove this set from the workout and its totals?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Delete Set", role: .destructive) { remove() }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(saving)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            kg = formatKg(initial?.actualKg ?? exercise.plannedKg)
            reps = String(initial?.actualReps ?? exercise.plannedReps)
            if let initial { setId = initial.id }
        }
    }

    private func save() {
        guard let load = parseNumber(kg), (0...10000).contains(load), let count = parseCount(reps, in: 0...1000) else {
            error = "Enter kg between 0 and 10000 and whole reps between 0 and 1000."
            return
        }
        saving = true; error = nil
        Task {
            error = await onSave(load, count, setId)
            saving = false
            if error == nil { dismiss() }
        }
    }

    private func remove() {
        guard let onRemove else { return }
        saving = true; error = nil
        Task {
            error = await onRemove()
            saving = false
            if error == nil { dismiss() }
        }
    }
}

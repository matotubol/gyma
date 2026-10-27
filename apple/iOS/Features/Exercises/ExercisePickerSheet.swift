import SwiftUI
import GymaCore

/// The exercise library as a searchable list. Push it, or present it with `ExercisePickerSheet`.
struct ExercisePickerList: View {
    var allowCreate = true
    let onChoose: (LibraryExercise) -> Void

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [LibraryExercise] = []
    @State private var page = 0
    @State private var more = false
    @State private var loading = true
    @State private var error: String?
    @State private var retry = 0

    private static let pageSize = 20

    var body: some View {
        List {
            if allowCreate {
                Section {
                    NavigationLink {
                        CreateExerciseForm(initialName: query.trimmingCharacters(in: .whitespaces)) { choose($0) }
                    } label: {
                        Label("New exercise", systemImage: "plus")
                    }
                }
            }
            Section {
                ForEach(results) { exercise in
                    Button { choose(exercise) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name).foregroundStyle(Color.primary)
                            Text(exercise.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let error {
                    Button { retry += 1 } label: {
                        Label("\(error). Retry", systemImage: "arrow.clockwise")
                    }
                } else if results.isEmpty {
                    Text("No matching exercises").foregroundStyle(.secondary)
                } else if more {
                    Button("Show more") { page += 1 }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name, equipment or brand")
        .autocorrectionDisabled()
        .onChange(of: query) { page = 0; more = false }
        .task(id: "\(query)|\(page)|\(retry)") { await load() }
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        guard let api = model.api else { return }
        let page = page
        loading = true; error = nil
        try? await Task.sleep(for: .milliseconds(180)) // debounce typing
        guard !Task.isCancelled else { return }
        do {
            let rows = try await api.searchExercises(query.trimmingCharacters(in: .whitespaces), limit: Self.pageSize, offset: page * Self.pageSize)
            guard !Task.isCancelled else { return }
            results = page == 0 ? rows : results + rows
            more = rows.count == Self.pageSize
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "Couldn’t load"
        }
        loading = false
    }

    private func choose(_ exercise: LibraryExercise) {
        onChoose(exercise)
        dismiss()
    }
}

/// The library picker in its own navigation stack, for sheets.
struct ExercisePickerSheet: View {
    var allowCreate = true
    let onChoose: (LibraryExercise) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // The list dismisses this sheet itself after a choice.
            ExercisePickerList(allowCreate: allowCreate, onChoose: onChoose)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

private struct CreateExerciseForm: View {
    let initialName: String
    let onCreate: (LibraryExercise) -> Void

    @EnvironmentObject private var model: AppModel
    @State private var name = ""
    @State private var equipment: Equipment = .machine
    @State private var brand: Brand? = .matrix
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                Picker("Equipment", selection: $equipment) {
                    ForEach(Equipment.allCases, id: \.self) { item in
                        Text(item == .other ? "Other" : item.label).tag(item)
                    }
                }
                if equipment.hasBrand {
                    Picker("Brand", selection: $brand) {
                        Text("Unspecified").tag(Brand?.none)
                        ForEach(Brand.allCases, id: \.self) { item in
                            Text(item.rawValue).tag(Brand?.some(item))
                        }
                    }
                }
            } footer: {
                if let error { Text(error).foregroundStyle(.red) }
            }
        }
        .disabled(busy)
        .navigationTitle("New Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if busy { ProgressView() } else {
                    Button("Add", action: create).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { if name.isEmpty { name = initialName } }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard (1...120).contains(trimmed.count) else { error = "Use up to 120 characters."; return }
        guard let api = model.api else { return }
        busy = true; error = nil
        Task {
            do {
                onCreate(try await api.createExercise(CreateExercise(name: trimmed, equipment: equipment, brand: brand)))
            } catch {
                self.error = "Couldn’t create this exercise. Try again."
            }
            busy = false
        }
    }
}

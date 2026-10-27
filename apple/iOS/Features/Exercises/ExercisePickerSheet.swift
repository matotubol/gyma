import SwiftUI
import GymaCore

/// Search the shared exercise library, or create a definition, then return it.
struct ExercisePickerSheet: View {
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
    @State private var creating = false

    private static let pageSize = 20

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { exercise in
                    Button { choose(exercise) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name).foregroundStyle(Theme.ink)
                            Text(exercise.detail).font(.caption).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(Theme.surface)
                }

                Group {
                    if loading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if let error {
                        Button("\(error) Retry") { retry += 1 }.foregroundStyle(Theme.danger)
                    } else if results.isEmpty {
                        Text("No matching exercises.").foregroundStyle(Theme.muted)
                    } else if more {
                        Button("Show more") { page += 1 }
                    }
                    if allowCreate {
                        Button { creating = true } label: {
                            Label("Create exercise in library", systemImage: "plus")
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search name, equipment, brand…")
            .autocorrectionDisabled()
            .onChange(of: query) { page = 0; more = false }
            .task(id: "\(query)|\(page)|\(retry)") { await load() }
            .screenBackground()
            .navigationTitle("Choose exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(isPresented: $creating) {
                CreateExerciseForm(initialName: query.trimmingCharacters(in: .whitespaces), onCreate: choose)
            }
        }
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
            self.error = "Couldn’t load exercises."
        }
        loading = false
    }

    private func choose(_ exercise: LibraryExercise) {
        onChoose(exercise)
        dismiss()
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
                        Text("Unspecified / other").tag(Brand?.none)
                        ForEach(Brand.allCases, id: \.self) { item in
                            Text(item.rawValue).tag(Brand?.some(item))
                        }
                    }
                }
            }
            .listRowBackground(Theme.surface)

            if let error {
                Section { Text(error).foregroundStyle(Theme.danger) }.listRowBackground(Theme.dangerSurface)
            }

            Section {
                Button(action: create) {
                    Text(busy ? "Creating…" : "Create & select")
                }
                .buttonStyle(.primary)
                .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .disabled(busy)
        .screenBackground()
        .navigationTitle("New library exercise")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if name.isEmpty { name = initialName } }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard (1...120).contains(trimmed.count) else { error = "Enter an exercise name (up to 120 characters)."; return }
        guard let api = model.api else { return }
        busy = true; error = nil
        Task {
            do {
                onCreate(try await api.createExercise(CreateExercise(name: trimmed, equipment: equipment, brand: brand)))
            } catch {
                self.error = "Couldn’t create this exercise. Your entry is still here; try again."
            }
            busy = false
        }
    }
}

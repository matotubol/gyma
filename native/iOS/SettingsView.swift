import SwiftUI
import UniformTypeIdentifiers
import GymaCore

struct SettingsView: View {
    @EnvironmentObject private var model: GymaAppModel
    @ObservedObject private var connectivity = WorkoutConnectivity.shared
    @State private var exportPresented = false
    @State private var importPresented = false
    @State private var restorePresented = false
    @State private var document: BackupDocument?
    @State private var importedState: GymaState?
    @State private var apiKey = ""
    @State private var keyNotice: String?

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    AthleteProfileView()
                } label: {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                if let profile = model.state.athleteProfile {
                    Text("\(profile.primaryGoal.label) · \(profile.daysPerWeek) days per week · \(profile.usualSessionMinutes) min")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Save your goals, measurements, schedule and equipment for your coach.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                NavigationLink {
                    ExerciseLibraryView()
                } label: {
                    Label("Exercise library", systemImage: "dumbbell")
                }
            } header: { Text("About you") }

            Section {
                LabeledContent("Model", value: "GPT Luna")
                if model.hasCoachAPIKey {
                    Label("API key saved on this iPhone", systemImage: "checkmark.shield")
                        .foregroundStyle(GymaStyle.accent)
                }
                SecureField(model.hasCoachAPIKey ? "Replace OpenAI API key" : "OpenAI API key", text: $apiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .privacySensitive()
                Button(model.hasCoachAPIKey ? "Replace API key" : "Save API key", systemImage: "key") {
                    if model.saveCoachAPIKey(apiKey) {
                        apiKey = ""
                        keyNotice = "API key saved securely. Your coach is ready."
                    }
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.coachRequestInFlight)
                if model.hasCoachAPIKey {
                    Button("Remove API key", role: .destructive) {
                        model.removeCoachAPIKey()
                        apiKey = ""
                        keyNotice = model.hasCoachAPIKey ? nil : "API key removed from this iPhone."
                    }
                }
                if let keyNotice { Text(keyNotice).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("AI coach") } footer: {
                Text("Your key is stored in the iPhone Keychain and is excluded from backups and Watch sync. Your saved profile, program, messages, check-in and training summaries are sent to OpenAI when you use the coach. API usage is billed to your OpenAI account.")
            }

            Section {
                HStack(spacing: 14) {
                    Image(systemName: "applewatch").font(.largeTitle).foregroundStyle(GymaStyle.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Apple Watch").font(.headline)
                        Text(connectivity.connectionStatus).font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 5)
                LabeledContent("Live connection", value: connectivity.isReachable ? "Reachable" : "Background delivery")
                Button("Refresh connection", systemImage: "arrow.triangle.2.circlepath") { model.refresh() }
                if let error = connectivity.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
            } header: { Text("Companion") } footer: {
                Text("Pair your Apple Watch in the Watch app and open Gyma on both devices. Your iPhone keeps the saved workout; Watch actions are confirmed after they are saved. When disconnected, Watch actions wait for the iPhone.")
            }

            Section {
                Toggle("Automatic rest timer", isOn: Binding(get: { model.state.restEnabled }, set: { enabled in model.update { $0.setRestEnabled(enabled) } }))
                    .disabled(model.storageBlocked)
                Toggle("Rest notifications", isOn: Binding(get: { model.notificationEnabled }, set: { model.setNotificationEnabled($0) }))
                    .disabled(model.isRequestingNotifications || model.storageBlocked)
                if model.isRequestingNotifications { ProgressView("Requesting permission…") }
                if let settings = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open iPhone notification settings", destination: settings)
                }
            } header: { Text("Rest") } footer: {
                Text("The countdown uses a saved deadline so it continues while Gyma is in the background. Notifications are optional and use iPhone notification permissions.")
            }

            Section {
                Button(model.storageBlocked ? "Export original unreadable file" : "Export JSON backup", systemImage: "square.and.arrow.up") {
                    do {
                        document = BackupDocument(data: try model.exportData())
                        exportPresented = true
                    } catch { model.errorMessage = "The backup could not be exported. \(error.localizedDescription)" }
                }
                Button("Restore JSON backup", systemImage: "square.and.arrow.down") { importPresented = true }
                if model.storageBlocked {
                    Label("The original gyma-native.json is preserved. No workout changes will be saved until you restore valid data.", systemImage: "externaldrive.badge.exclamationmark")
                        .font(.subheadline).foregroundStyle(.orange)
                } else {
                    LabeledContent("Saved workouts", value: "\(model.state.workouts.count)")
                    LabeledContent("Deleted workouts", value: "\(model.state.deletedWorkouts.count)")
                    LabeledContent("Custom exercises", value: "\(model.state.customExercises.count)")
                }
            } header: { Text("Your data") } footer: {
                Text("JSON backups include your profile and bodyweight history, program, workout history, custom exercises, deleted workouts, and coach conversation and draft. API keys are excluded. Restoring replaces the current data and keeps a copy of the previous file in Gyma’s Documents folder, available through Files or Finder.")
            }

            if let notice = model.notice {
                Section {
                    Label(notice, systemImage: "checkmark.circle").font(.subheadline)
                    Button("Dismiss") { model.notice = nil }
                }
            }

            Section {
                LabeledContent("Version", value: version)
                LabeledContent("Units", value: "Kilograms")
                Text("Workouts live on your iPhone and sync with your paired Apple Watch. Export a backup to keep a separate copy.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } header: { Text("Gyma") }
        }
        .navigationTitle("Settings")
        .onAppear { model.refreshCoachCredentials() }
        .onDisappear { apiKey = "" }
        .fileExporter(isPresented: $exportPresented, document: document, contentType: .json,
                      defaultFilename: model.storageBlocked ? "gyma-original" : "gyma-backup") { result in
            switch result {
            case .success: model.notice = "Backup exported."
            case .failure(let error): model.errorMessage = "Export failed. \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $importPresented, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                importedState = try model.readImport(url)
                restorePresented = true
            } catch { model.errorMessage = "This backup could not be read. Your current data is unchanged. \(error.localizedDescription)" }
        }
        .confirmationDialog("Restore this backup?", isPresented: $restorePresented, titleVisibility: .visible) {
            Button("Replace current data", role: .destructive) {
                if let importedState { _ = model.restore(importedState) }
                importedState = nil
            }
            Button("Cancel", role: .cancel) { importedState = nil }
        } message: {
            if let importedState {
                Text("This backup contains \(importedState.workouts.count) workouts, \(importedState.deletedWorkouts.count) deleted workouts, and \(importedState.customExercises.count) custom exercises. Current data will be replaced after a recovery copy is saved.")
            }
        }
    }

    private var version: String {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(marketing) (\(build))"
    }
}

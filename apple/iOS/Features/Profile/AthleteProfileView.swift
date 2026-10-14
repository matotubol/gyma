import SwiftUI
import GymaCore

struct AthleteProfileView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var profile = AthleteProfile()
    @State private var height = ""
    @State private var newWeight = ""
    @State private var weightDate = Date()
    @State private var incrementText: [AthleteEquipment: String] = [:]
    @State private var preferred = ""
    @State private var avoided = ""
    @State private var loaded = false
    @State private var error: String?
    @State private var clearPresented = false

    var body: some View {
        Form {
            Section {
                Text("Your coach uses this saved profile whenever you ask for advice. Review the starting schedule values and leave unknown details blank.")
                if let saved = model.state.athleteProfile {
                    LabeledContent("Last saved", value: saved.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Changes are saved when you tap Save. Today's soreness, energy and pain belong in your session check-in.")
            }

            goalsSection
            scheduleSection
            measurementsSection
            equipmentSection
            preferencesSection

            Section {
                Text("Your saved profile, including any body measurements and limitations you enter, is sent to OpenAI with coach requests. It stays on your iPhone between requests and is included in JSON backups. Profile details are not sent to your Watch.")
                Text("The coach uses the facts you save here; its suggestions and training trends do not silently change this profile.")
            } header: { Text("What your coach knows") }

            if let error {
                Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
            }
            Section {
                Button("Save profile", systemImage: "checkmark") { save() }
                    .disabled(model.storageBlocked)
                if model.state.athleteProfile != nil {
                    Button("Delete profile and measurements", role: .destructive) { clearPresented = true }
                        .disabled(model.storageBlocked)
                }
            }
        }
        .navigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }.disabled(model.storageBlocked)
            }
        }
        .onAppear { load() }
        .onChange(of: profile.primaryGoal) { _, goal in
            profile.secondaryGoals.removeAll { $0 == goal || goal == .unspecified }
        }
        .confirmationDialog("Delete your saved profile?", isPresented: $clearPresented, titleVisibility: .visible) {
            Button("Delete profile and measurements", role: .destructive) {
                if model.update({ $0.clearAthleteProfile() }) {
                    model.notice = "Profile and bodyweight measurements deleted."
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes your profile and bodyweight history from current data. Past workouts, conversations and exported backups may still contain information you shared. Any accepted workout draft needs review again.")
        }
    }

    private var goalsSection: some View {
        Section {
            Picker("Main goal", selection: $profile.primaryGoal) {
                ForEach(AthleteGoal.allCases) { Text($0.label).tag($0) }
            }
            if profile.primaryGoal != .unspecified {
                DisclosureGroup("Other goals") {
                    ForEach(AthleteGoal.allCases.filter { $0 != .unspecified && $0 != profile.primaryGoal }) { goal in
                        Toggle(goal.label, isOn: Binding(get: { profile.secondaryGoals.contains(goal) }, set: { selected in
                            profile.secondaryGoals.removeAll { $0 == goal }
                            if selected { profile.secondaryGoals.append(goal) }
                        }))
                    }
                }
            }
            TextField("What would progress look like for you?", text: $profile.goalNotes, axis: .vertical)
                .lineLimit(2...5)
            Picker("Experience", selection: $profile.experience) {
                ForEach(TrainingExperience.allCases) { Text($0.label).tag($0) }
            }
        } header: { Text("Goals") } footer: {
            Text("Your main goal takes priority when goals compete. You can change these choices as your needs change.")
        }
    }

    private var scheduleSection: some View {
        Section {
            Stepper("\(profile.daysPerWeek) days per week", value: $profile.daysPerWeek, in: 1...7)
            Stepper("\(profile.usualSessionMinutes) minutes per session", value: $profile.usualSessionMinutes, in: 10...240, step: 5)
            TextField("Shift pattern, usual days or scheduling constraints", text: $profile.scheduleNotes, axis: .vertical)
                .lineLimit(2...5)
        } header: { Text("Your schedule") } footer: {
            Text("Save your usual availability here. A shorter session or a different shift today can go in your check-in.")
        }
    }

    private var measurementsSection: some View {
        Section {
            HStack {
                Text("Height")
                Spacer()
                TextField("Optional", text: $height).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                Text("cm").foregroundStyle(.secondary)
            }
            if let latest = profile.latestBodyweight {
                LabeledContent("Latest weight", value: "\(number(latest.kg)) kg")
                Text(latest.recordedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("New weight")
                Spacer()
                TextField("Optional", text: $newWeight).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                Text("kg").foregroundStyle(.secondary)
            }
            DatePicker("Measurement date", selection: $weightDate, in: ...Date(), displayedComponents: .date)
            Button("Add weight measurement", systemImage: "plus") { addWeight() }
                .disabled(newWeight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !profile.bodyweightHistory.isEmpty {
                DisclosureGroup("Weight history (\(profile.bodyweightHistory.count))") {
                    ForEach(Array(profile.bodyweightHistory.sorted { $0.recordedAt > $1.recordedAt }.prefix(30))) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(number(entry.kg)) kg")
                                Text(entry.recordedAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { profile.bodyweightHistory.removeAll { $0.id == entry.id } } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(number(entry.kg)) kg on \(entry.recordedAt.formatted(date: .abbreviated, time: .omitted))")
                        }
                    }
                    if profile.bodyweightHistory.count > 30 {
                        Text("Showing the latest 30 measurements. Older entries are kept in your profile and backup.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: { Text("Body measurements") } footer: {
            Text("Optional. Weight measurements keep their dates so trends can be assessed over time. Tap Save to keep additions or removals.")
        }
    }

    private var equipmentSection: some View {
        Section {
            ForEach(AthleteEquipment.allCases) { equipment in
                Toggle(equipment.label, isOn: Binding(get: { profile.equipment.contains(equipment) }, set: { selected in
                    profile.equipment.removeAll { $0 == equipment }
                    if selected { profile.equipment.append(equipment) }
                }))
                if profile.equipment.contains(equipment) && equipment.supportsLoadIncrement {
                    HStack {
                        Text("Smallest increase").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        TextField("Unknown", text: Binding(get: { incrementText[equipment] ?? "" }, set: { incrementText[equipment] = $0 }))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .accessibilityLabel("\(equipment.label) smallest increase in kilograms")
                        Text("kg").foregroundStyle(.secondary)
                    }
                }
            }
            TextField("Machine names, available weights or setup details", text: $profile.equipmentNotes, axis: .vertical)
                .lineLimit(2...5)
        } header: { Text("Available equipment") } footer: {
            Text("Select what you can use. No selection means unknown. Increases are total added weight for barbells and Smith machines, per dumbbell or kettlebell, and per stack for cables or machines. Use notes if machines differ.")
        }
    }

    private var preferencesSection: some View {
        Section {
            TextField("Exercises you like — one per line", text: $preferred, axis: .vertical).lineLimit(2...6)
            TextField("Exercises to avoid — one per line", text: $avoided, axis: .vertical).lineLimit(2...6)
            TextField("Ongoing limitations or instructions you have been given", text: $profile.ongoingLimitations, axis: .vertical)
                .lineLimit(2...6)
        } header: { Text("Preferences and limitations") } footer: {
            Text("Use specific exercise names where possible. Record lasting restrictions here; report new pain in the session check-in. The coach treats these as your reported limits, not a diagnosis.")
        }
    }

    private func load() {
        guard !loaded else { return }
        profile = model.state.athleteProfile ?? AthleteProfile()
        height = profile.heightCM.map(number) ?? ""
        preferred = profile.preferredExercises.joined(separator: "\n")
        avoided = profile.avoidedExercises.joined(separator: "\n")
        incrementText = Dictionary(uniqueKeysWithValues: profile.loadIncrements.map { ($0.equipment, number($0.incrementKg)) })
        loaded = true
    }

    private func addWeight() {
        do {
            guard let kg = parse(newWeight) else { throw GymaError.invalid("Enter a weight between 20 and 500 kg.") }
            let entry = BodyweightEntry(recordedAt: weightDate, kg: kg)
            try entry.validate()
            guard profile.bodyweightHistory.count < 10_000 else { throw GymaError.invalid("Bodyweight history is full. Remove an old entry first.") }
            profile.bodyweightHistory.append(entry)
            newWeight = ""
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        do {
            var next = profile
            let heightText = height.trimmingCharacters(in: .whitespacesAndNewlines)
            if heightText.isEmpty { next.heightCM = nil }
            else {
                guard let value = parse(heightText) else { throw GymaError.invalid("Enter height in cm, or leave it blank.") }
                next.heightCM = value
            }
            // A typed measurement must not be silently discarded if Save is tapped first.
            if !newWeight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let value = parse(newWeight) else { throw GymaError.invalid("Enter a valid weight or clear the new weight field.") }
                next.bodyweightHistory.append(.init(recordedAt: weightDate, kg: value))
            }
            next.loadIncrements = try next.equipment.filter(\.supportsLoadIncrement).compactMap { equipment in
                let text = (incrementText[equipment] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { return nil }
                guard let value = parse(text) else { throw GymaError.invalid("Enter a valid load increment for \(equipment.label), or leave it blank.") }
                return EquipmentLoadIncrement(equipment: equipment, incrementKg: value)
            }
            next.preferredExercises = exerciseNames(preferred)
            next.avoidedExercises = exerciseNames(avoided)
            try next.validate()
            if model.update({ try $0.saveAthleteProfile(next) }) {
                model.notice = "Profile saved. Your coach will use it with your next request."
                dismiss()
            } else { error = model.errorMessage }
        } catch { self.error = error.localizedDescription }
    }

    private func exerciseNames(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func parse(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")), value.isFinite else { return nil }
        return value
    }

    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
}

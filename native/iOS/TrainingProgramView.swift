import SwiftUI
import GymaCore

struct TrainingProgramView: View {
    @EnvironmentObject private var model: GymaAppModel
    @State private var checkingIn = false
    @State private var showingCoach = false
    @State private var archivePresented = false

    var body: some View {
        List {
            if let program = model.state.trainingProgram {
                Section {
                    Text(program.title).font(.title2.bold())
                    Text(program.goal)
                    if !program.rationale.isEmpty { Text(program.rationale).font(.subheadline).foregroundStyle(.secondary) }
                    Text("Version \(program.revision) · Updated \(program.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let next = program.nextSession(history: model.state.workouts) {
                    Section {
                        ForEach(program.recommendations(for: next, history: model.state.workouts, catalog: model.state.catalog, priorPrograms: model.state.programHistory ?? [])) { recommendation in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(model.name(for: recommendation.exerciseID)).font(.headline)
                                Text(programTargetDescription(recommendation.target)).font(.subheadline)
                                Text(recommendation.reason).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 3)
                        }
                        Button("Prepare next session", systemImage: "list.clipboard") { checkingIn = true }
                            .disabled(model.state.activeWorkout != nil || model.storageBlocked)
                    } header: { Text("Next session · \(next.title)") } footer: {
                        Text("Sessions repeat in order after you finish them. Missed days do not create extra work. Review today's readiness and targets before accepting.")
                    }
                }
                Section("Your recurring sessions") { ProgramSessionsContent(program: program) }
                Section {
                    Text("Reach the upper rep target at the intended effort for \(program.progressionRule.successfulExposuresRequired) comparable sessions before a load increase is proposed.")
                        .font(.subheadline)
                    NavigationLink("Edit progression rules") { ProgressionRuleView(program: program) }
                        .disabled(model.state.activeWorkout != nil || model.storageBlocked)
                    Button("Discuss program changes", systemImage: "bubble.left.and.bubble.right") {
                        if model.beginProgramReview() { showingCoach = true }
                    }.disabled(model.state.activeWorkout != nil || model.storageBlocked)
                } header: { Text("Progression") } footer: {
                    Text("Missing effort, changed prescriptions and long gaps require review. These rules are configurable starting points, not a measurement of your recovery.")
                }
                Section {
                    Button("Archive this program", role: .destructive) { archivePresented = true }
                        .disabled(model.state.activeWorkout != nil || model.storageBlocked)
                }
            } else {
                Section {
                    Text("A plan that remembers last time").font(.title2.bold())
                    Text("Save your goals, schedule and equipment in Profile, then discuss a recurring program with your coach.")
                    NavigationLink("Your profile") { AthleteProfileView() }
                    Button("Plan with coach", systemImage: "sparkles") { checkingIn = true }
                        .disabled(model.state.activeWorkout != nil || model.storageBlocked || !model.hasCoachAPIKey)
                }
            }
            if let history = model.state.programHistory, !history.isEmpty {
                Section("Previous program versions") {
                    ForEach(Array(history.reversed().enumerated()), id: \.offset) { _, program in
                        NavigationLink("\(program.title) · v\(program.revision)") { ArchivedProgramView(program: program) }
                    }
                }
            }
        }
        .navigationTitle("Your program")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $checkingIn) {
            CheckInView { checkingIn = false; showingCoach = true; model.requestCoachReply() }
        }
        .navigationDestination(isPresented: $showingCoach) { CoachView(onAccepted: { showingCoach = false }) }
        .confirmationDialog("Archive this program?", isPresented: $archivePresented, titleVisibility: .visible) {
            Button("Archive program", role: .destructive) { model.update { try $0.archiveTrainingProgram() } }
        } message: { Text("Your training and program versions are kept. You can restore a previous version or plan a new program.") }
    }
}

struct ProgramProposalCard: View {
    @EnvironmentObject private var model: GymaAppModel
    let program: TrainingProgram
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("PROGRAM PROPOSAL", systemImage: "calendar").font(.caption.bold()).foregroundStyle(GymaStyle.accent)
            Text(program.title).font(.title2.bold())
            Text(program.goal)
            if !program.rationale.isEmpty { Text(program.rationale).font(.subheadline).foregroundStyle(.secondary) }
            ProgramSessionsContent(program: program)
            Text("Default increment: \(program.progressionRule.loadIncrementKg.gymaNumber) kg after \(program.progressionRule.successfulExposuresRequired) successful comparable sessions. Equipment-specific increments take precedence.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Accepting saves the recurring program and prepares a session for you to review. It does not start a workout.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Accept program", systemImage: "checkmark") { _ = model.acceptCoachProgram(program.id) }
                .buttonStyle(.borderedProminent)
                .disabled(model.coachRequestInFlight || model.storageBlocked || model.state.activeWorkout != nil)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct ProgramSessionsContent: View {
    @EnvironmentObject private var model: GymaAppModel
    let program: TrainingProgram
    var body: some View {
        ForEach(program.sessions) { session in
            DisclosureGroup(session.title) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(session.exercises) { exercise in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.name(for: exercise.exerciseID)).font(.subheadline.bold())
                            if let target = exercise.target {
                                Text(programTargetDescription(target)).font(.caption).foregroundStyle(.secondary)
                                if !target.reason.isEmpty { Text(target.reason).font(.caption).foregroundStyle(.secondary) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.vertical, 8)
            }
        }
    }
}

private struct ProgressionRuleView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let program: TrainingProgram
    @State private var defaultIncrement: String
    @State private var exposures: Int
    @State private var increments: [String: String]
    @State private var error: String?

    init(program: TrainingProgram) {
        self.program = program
        _defaultIncrement = State(initialValue: program.progressionRule.loadIncrementKg.gymaNumber)
        _exposures = State(initialValue: program.progressionRule.successfulExposuresRequired)
        _increments = State(initialValue: program.progressionRule.exerciseIncrements.mapValues { $0.gymaNumber })
    }
    private var exerciseIDs: [String] { Array(Set(program.sessions.flatMap { $0.exercises.map(\.exerciseID) })).sorted() }
    var body: some View {
        Form {
            Section("When to increase") {
                Stepper("Successful exposures: \(exposures)", value: $exposures, in: 1...5)
                Text("All prescribed working sets must reach the upper rep target with recorded effort no harder than intended. Missing effort never counts as success.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Default increase in kg", text: $defaultIncrement).keyboardType(.decimalPad)
            }
            Section {
                ForEach(exerciseIDs, id: \.self) { id in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.name(for: id)).font(.subheadline)
                        TextField("Use default", text: Binding(get: { increments[id] ?? "" }, set: { increments[id] = $0 }))
                            .keyboardType(.decimalPad)
                    }
                }
            } header: { Text("Increase per exercise · kg") } footer: {
                Text("Use the smallest suitable increment your equipment supports. For dumbbells, use the amount per dumbbell. Unknown load conventions and machine stacks require an explicit exercise increment.")
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section {
                Button("Save rules") { save() }.disabled(model.storageBlocked || model.state.activeWorkout != nil)
            }
        }.navigationTitle("Progression rules").navigationBarTitleDisplayMode(.inline)
    }
    private func save() {
        guard model.state.trainingProgram == program else { error = "Your program changed. Reopen its rules before saving."; return }
        func number(_ text: String) -> Double? { Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")) }
        guard let step = number(defaultIncrement) else { error = "Enter a valid default increase in kilograms."; return }
        var overrides: [String: Double] = [:]
        for id in exerciseIDs {
            let text = (increments[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                guard let value = number(text) else { error = "Enter a valid increase for \(model.name(for: id))."; return }
                overrides[id] = value
            }
        }
        let rule = ProgressionRule(loadIncrementKg: step, successfulExposuresRequired: exposures, exerciseIncrements: overrides)
        if model.update({ try $0.updateProgressionRule(rule) }) { dismiss() }
        else { error = model.errorMessage }
    }
}

private struct ArchivedProgramView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let program: TrainingProgram
    var body: some View {
        List {
            Section { Text(program.goal); Text(program.rationale).foregroundStyle(.secondary) }
            Section("Sessions") { ProgramSessionsContent(program: program) }
            Section {
                Button("Restore this version") {
                    if model.update({ try $0.restoreProgramVersion(id: program.id, version: program.revision) }) { dismiss() }
                }.disabled(model.storageBlocked || model.state.activeWorkout != nil)
            } footer: { Text("Restoring creates a new program version. Completed training remains unchanged.") }
        }.navigationTitle("\(program.title) · v\(program.revision)").navigationBarTitleDisplayMode(.inline)
    }
}

private func programTargetDescription(_ target: ExerciseTarget) -> String {
    let load = target.loadKg.map { "\($0.gymaNumber) kg" } ?? "Choose a comfortable load"
    let effort = target.targetEffort.map { " · \($0.label)" } ?? " · effort target not set"
    return "\(target.sets) × \(target.repsMin)–\(target.repsMax) · \(load) · \(target.restSeconds)s rest\(effort)"
}

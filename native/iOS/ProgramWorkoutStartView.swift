import SwiftUI
import GymaCore

/// Collect today's readiness once, review the resulting session, then explicitly start it.
struct ProgramWorkoutStartView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let onStarted: (String) -> Void
    @State private var shift: Shift = .off
    @State private var energy: Energy = .good
    @State private var soreness = Soreness.allNone
    @State private var minutes = 45
    @State private var sleep = ""
    @State private var notes = ""
    @State private var recentTraining = ""
    @State private var pain = ""
    @State private var loadedDefaults = false
    @State private var preview: PreparedSession?
    @State private var error: String?
    @State private var coachPresented = false
    @State private var discussionFirstMessageID: String?

    private struct PreparedSession {
        let plan: WorkoutPlan
        let readiness: WorkoutReadiness
        let storeID: String
        let revision: Int
    }

    private var unavailable: Bool {
        model.storageBlocked || model.state.activeWorkout != nil || model.coachRequestInFlight
            || model.state.trainingProgram == nil
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Form {
                    if let preview { sessionPreview(preview, at: context.date) }
                    else { checkInFields }
                    if let error { Section { Text(error).foregroundStyle(.orange) } }
                }
            }
            .navigationTitle(preview == nil ? "Before you start" : "Review workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $coachPresented) {
                NavigationStack {
                    AnyView(CoachView(onAccepted: acceptCoachAdjustment))
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { coachPresented = false }
                            }
                        }
                }
            }
            .onAppear {
                guard !loadedDefaults else { return }
                loadedDefaults = true
                minutes = min(180, max(10, model.state.athleteProfile?.usualSessionMinutes ?? 45))
                if let calendar = model.state.trainingCalendar { shift = calendar.shift(on: Date()) }
            }
        }
    }

    @ViewBuilder
    private var checkInFields: some View {
        Section {
            Text("How are you arriving today?").font(.title2.bold())
            if let program = model.state.trainingProgram,
               let next = program.nextSession(history: model.state.workouts) {
                Text("Next: \(next.title)").font(.headline)
            }
            Text("Check in once for this workout. Review today's targets before accepting and starting.")
                .foregroundStyle(.secondary)
        }
        Section("Today") {
            Picker("Shift", selection: $shift) {
                ForEach(Shift.allCases) { Text($0.label).tag($0) }
            }
            Picker("Energy", selection: $energy) {
                ForEach(Energy.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }
            Stepper("Time available: \(minutes) min", value: $minutes, in: 10...180, step: 5)
            TextField("Sleep in hours (optional)", text: $sleep).keyboardType(.decimalPad)
        }
        Section {
            SorenessFields(soreness: $soreness)
        } header: { Text("Muscle soreness") } footer: {
            Text("Review every muscle group. These answers are saved with the workout you start.")
        }
        Section("Anything else today?") {
            TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(2...4)
            TextField("Recent training (optional)", text: $recentTraining, axis: .vertical).lineLimit(2...4)
            TextField("Pain or limitations (optional)", text: $pain, axis: .vertical).lineLimit(2...4)
        }
        Section {
            Button(action: preparePreview) {
                Label("Review workout", systemImage: "list.clipboard")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).disabled(unavailable)
        } footer: {
            Text("Your saved program and training history prepare today's session on your device. Your recurring program stays consistent.")
        }
    }

    @ViewBuilder
    private func sessionPreview(_ preview: PreparedSession, at now: Date) -> some View {
        let current = isCurrent(preview, at: now)
        let continuingDiscussion = canContinueDiscussion(preview, at: now)
        Section {
            Text(preview.plan.title).font(.title2.bold())
            Text("\(preview.plan.exercises.count) exercises · \(preview.plan.exercises.reduce(0) { $0 + ($1.target?.sets ?? 0) }) sets")
                .foregroundStyle(.secondary)
            Text("Review these targets, including any adjustments for today's readiness. Accepting starts this workout.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        Section("Your check-in") {
            LabeledContent("Energy", value: preview.readiness.energy.label)
            LabeledContent("Shift", value: preview.plan.checkIn.shift.label)
            LabeledContent("Available time", value: "\(preview.plan.checkIn.timeMinutes) min")
            if let hours = preview.plan.checkIn.sleepHours {
                LabeledContent("Sleep", value: "\(hours.gymaNumber) hours")
            }
            DisclosureGroup("Soreness and notes") {
                ForEach(Muscle.allCases) { muscle in
                    LabeledContent(muscle.label, value: preview.readiness.soreness(for: muscle).label)
                }
                if !preview.plan.checkIn.painNote.isEmpty { Text("Pain or limitations: \(preview.plan.checkIn.painNote)") }
                if !preview.plan.checkIn.notes.isEmpty { Text(preview.plan.checkIn.notes) }
                if !preview.plan.checkIn.recentTrainingNote.isEmpty { Text("Recent training: \(preview.plan.checkIn.recentTrainingNote)") }
            }
            Text("Checked at \(preview.readiness.recordedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            Button("Edit check-in") {
                self.preview = nil
                discussionFirstMessageID = nil
                error = nil
            }
        }
        Section("Today's exercises") {
            ForEach(preview.plan.exercises) { exercise in
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.name(for: exercise.exerciseID)).font(.headline)
                    if let target = exercise.target {
                        Text(targetDescription(target)).font(.subheadline)
                        if !target.reason.isEmpty {
                            Text(target.reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.vertical, 4)
            }
        }
        if !current {
            Section {
                if continuingDiscussion {
                    Text("Your daily coach discussion is saved. Continue it to review the coach's reply and accept the adjusted workout.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Your training information changed or this check-in is more than five minutes old. Review the workout again before starting.")
                        .foregroundStyle(.orange)
                }
                if canConfirmReadiness(preview, at: now) {
                    Text("Your coach-adjusted targets are kept. Review the check-in above and confirm it still describes how you feel now, or edit it if anything changed.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Confirm check-in still current") { confirmReadiness(preview) }
                        .disabled(unavailable)
                }
                Button("Review again", action: preparePreview).disabled(unavailable)
                Text("Review again rebuilds today's targets from your saved program using the answers in this form. It replaces any daily coach adjustments.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Section {
            if continuingDiscussion {
                Button("Continue discussion", systemImage: "bubble.left.and.bubble.right") {
                    guard canContinueDiscussion(preview, at: Date()) else {
                        error = "This workout discussion changed. Review today's session again."
                        return
                    }
                    error = nil
                    coachPresented = true
                }
                .disabled(model.storageBlocked || model.state.activeWorkout != nil)
            } else {
                Button("Ask coach to adjust", systemImage: "bubble.left.and.bubble.right") {
                    guard isCurrent(preview, at: Date()) else {
                        error = "Review today's check-in before asking for adjustments."
                        return
                    }
                    if model.discussProgramWorkout(plan: preview.plan, expectedStoreID: preview.storeID, expectedRevision: preview.revision) {
                        discussionFirstMessageID = model.state.coachConversation?.messages.first?.id
                        error = nil
                        coachPresented = true
                    } else {
                        error = model.errorMessage ?? "The coach discussion could not be opened."
                    }
                }
                .disabled(unavailable || !current || !model.hasCoachAPIKey)
            }
        } footer: {
            Text("Discuss pain, soreness or changes before starting. Your existing check-in goes with this workout discussion; your saved program stays unchanged.")
        }
        Section {
            Button {
                guard isCurrent(preview, at: Date()) else {
                    error = "Review this workout again before starting."
                    return
                }
                if let workoutID = model.startProgramWorkout(plan: preview.plan, readiness: preview.readiness,
                                                             expectedStoreID: preview.storeID, expectedRevision: preview.revision) {
                    onStarted(workoutID)
                } else {
                    error = model.errorMessage ?? "The session changed. Review the workout again."
                }
            } label: {
                Label("Accept & start", systemImage: "play.fill")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).disabled(unavailable || !current)
        }
    }

    private func isCurrent(_ preview: PreparedSession, at now: Date) -> Bool {
        let age = now.timeIntervalSince(preview.readiness.recordedAt)
        return preview.storeID == model.state.storeID && preview.revision == model.state.revision
            && age >= 0 && age <= 300 && preview.plan.isScheduledForToday(at: now)
    }

    private func matchesDiscussion(_ preview: PreparedSession, at now: Date) -> Bool {
        guard let discussionFirstMessageID,
              model.state.storeID == preview.storeID,
              let conversation = model.state.coachConversation,
              conversation.purpose == .workout, conversation.startedWorkoutID == nil,
              conversation.messages.first?.id == discussionFirstMessageID,
              conversation.checkIn == preview.plan.checkIn,
              preview.plan.programID != nil, preview.plan.isScheduledForToday(at: now) else { return false }
        return (try? model.state.validateProgramLink(preview.plan, now: now)) != nil
            && (try? model.state.validatePlanningContext(preview.plan)) != nil
    }

    private func canContinueDiscussion(_ preview: PreparedSession, at now: Date) -> Bool {
        guard matchesDiscussion(preview, at: now) else { return false }
        // Once its accepted targets are back in the preview, a new adjustment can start afresh.
        return model.state.coachConversation?.plan?.acceptedAt == nil || model.state.coachConversation?.plan != preview.plan
    }

    private func acceptCoachAdjustment() {
        coachPresented = false
        guard let previous = preview,
              matchesDiscussion(previous, at: Date()),
              let conversation = model.state.coachConversation, !conversation.isProgramPlanning,
              let plan = conversation.plan, plan.acceptedAt != nil,
              plan.checkIn == previous.plan.checkIn,
              plan.programID == previous.plan.programID,
              plan.programSessionID == previous.plan.programSessionID,
              plan.isScheduledForToday() else {
            error = "This discussion did not accept the same daily workout. Review today's session again before starting."
            return
        }
        do {
            try model.state.validateProgramLink(plan)
            try model.state.validatePlanningContext(plan)
            try plan.validate(catalog: model.state.catalog)
            preview = PreparedSession(plan: plan, readiness: previous.readiness,
                                      storeID: model.state.storeID, revision: model.state.revision)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func canConfirmReadiness(_ preview: PreparedSession, at now: Date) -> Bool {
        preview.plan.acceptedAt != nil && model.state.coachConversation?.plan == preview.plan
            && preview.storeID == model.state.storeID && preview.revision == model.state.revision
            && preview.plan.isScheduledForToday(at: now)
            && (try? model.state.validateProgramLink(preview.plan, now: now)) != nil
            && (try? model.state.validatePlanningContext(preview.plan)) != nil
    }

    private func confirmReadiness(_ previous: PreparedSession) {
        let now = Date()
        guard canConfirmReadiness(previous, at: now) else {
            error = "Your training information changed. Review today's workout again."
            return
        }
        // Only this explicit confirmation renews the timestamp; accepting AI targets does not.
        let readiness = WorkoutReadiness(energy: previous.readiness.energy, soreness: previous.readiness.soreness, recordedAt: now)
        preview = PreparedSession(plan: previous.plan, readiness: readiness, storeID: previous.storeID, revision: previous.revision)
        error = nil
    }

    private func preparePreview() {
        error = nil
        discussionFirstMessageID = nil
        let hours = sleep.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = Double(hours.replacingOccurrences(of: ",", with: "."))
        guard hours.isEmpty || value.map({ $0.isFinite && (0...24).contains($0) }) == true else {
            error = "Sleep must be between 0 and 24 hours."
            return
        }
        let checkIn = SessionCheckIn(shift: shift, energy: energy, timeMinutes: minutes,
                                    sleepHours: value, notes: notes, recentTrainingNote: recentTraining,
                                    painNote: pain, soreness: soreness)
        let readiness = WorkoutReadiness(energy: energy, soreness: soreness, recordedAt: Date())
        guard let plan = model.prepareProgramWorkout(checkIn: checkIn) else {
            error = model.errorMessage ?? "Your next session could not be prepared."
            return
        }
        preview = PreparedSession(plan: plan, readiness: readiness, storeID: model.state.storeID, revision: model.state.revision)
    }

    private func targetDescription(_ target: ExerciseTarget) -> String {
        let reps = target.repsMin == target.repsMax ? "\(target.repsMin)" : "\(target.repsMin)–\(target.repsMax)"
        let load = target.loadKg.map { "\($0.gymaNumber) kg" } ?? "Choose a comfortable load"
        let effort = target.targetEffort.map { " · \($0.label)" } ?? ""
        return "\(target.sets) × \(reps) · \(load) · \(target.restSeconds)s rest\(effort)"
    }
}

import SwiftUI
import UIKit
import GymaCore

struct WorkoutCoachView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let workoutID: String
    @State private var message = ""
    @FocusState private var composerFocused: Bool

    init(workoutID: String, initialQuestion: String? = nil) {
        self.workoutID = workoutID
        _message = State(initialValue: initialQuestion ?? "")
    }

    private var workout: Workout? { model.workout(workoutID) }
    private var inFlight: Bool { model.workoutCoachRequestWorkoutID == workoutID }
    private var canSend: Bool {
        workout != nil && model.hasCoachAPIKey && !model.storageBlocked && model.workoutCoachRequestWorkoutID == nil
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.count <= 16_000
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let workout {
                        DisclosureGroup("Workout details") { sessionCard(workout) }
                        if !model.hasCoachAPIKey { keySetup }
                        if let messages = workout.coachConversation?.messages, !messages.isEmpty {
                            ForEach(messages) { CoachMessageRow(message: $0) }
                        } else {
                            Text(workout.isActive ? "Ask to swap an exercise for today, use another machine first, skip a set, or adjust today's weights and technique."
                                 : "Discuss what went well, why a target was missed, and what to consider next time. Add workout feedback so the coach can use your explanation.")
                                .foregroundStyle(.secondary)
                        }
                        if inFlight {
                            ProgressView("Coach is reviewing your latest workout…")
                                .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let error = model.workoutCoachError(for: workoutID) {
                            Label(error, systemImage: "exclamationmark.bubble")
                                .font(.subheadline).foregroundStyle(.orange)
                        }
                        if workout.coachConversation?.messages.last?.role == .user, !inFlight {
                            Button(workout.isActive ? "Ask again with latest sets" : "Ask again with latest feedback", systemImage: "arrow.clockwise") {
                                model.requestWorkoutCoachReply(workoutID: workoutID)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!model.hasCoachAPIKey || model.storageBlocked)
                        }
                        if workout.isActive, let proposal = workout.coachConversation?.proposal { proposalCard(proposal, workout: workout) }
                    } else {
                        ContentUnavailableView("Workout unavailable", systemImage: "figure.strengthtraining.traditional",
                                               description: Text("Return to your workouts to open a saved session."))
                    }
                    Color.clear.frame(height: 1).id("workout-coach-bottom")
                }
                .padding(20)
            }
            .background(GymaStyle.background)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if workout != nil {
                    composer
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.bar)
                        .overlay(alignment: .top) { Divider() }
                }
            }
            .onChange(of: workout?.coachConversation?.messages.last?.id) { _, _ in
                withAnimation { proxy.scrollTo("workout-coach-bottom", anchor: .bottom) }
            }
            .onChange(of: inFlight) { _, _ in
                withAnimation { proxy.scrollTo("workout-coach-bottom", anchor: .bottom) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                if composerFocused { withAnimation { proxy.scrollTo("workout-coach-bottom", anchor: .bottom) } }
            }
            .onAppear { proxy.scrollTo("workout-coach-bottom", anchor: .bottom) }
        }
        .navigationTitle("Workout coach")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { composerFocused = false; dismiss() } label: { Label("Back", systemImage: "chevron.left") }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { composerFocused = false }
            }
        }
        .onAppear { model.refreshCoachCredentials() }
    }

    private func sessionCard(_ workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(workout.isActive ? "LIVE WORKOUT" : "WORKOUT REVIEW",
                  systemImage: workout.isActive ? "waveform.path.ecg" : "bubble.left.and.bubble.right")
                .font(.caption.weight(.bold)).foregroundStyle(GymaStyle.accent)
            Text(workout.title).font(.title2.bold())
            Text("\(workout.exercises.reduce(0) { $0 + $1.workingSetCount }) working sets logged · \(workout.exercises.count) exercises")
                .font(.subheadline).foregroundStyle(.secondary)
            if let next = workout.nextExercise, workout.isActive {
                Text("Current exercise: \(model.name(for: next.exerciseID))")
                    .font(.subheadline.weight(.medium))
            }
            if let readiness = workout.readiness {
                Text("\(readiness.energy.label) energy at the start")
                    .font(.subheadline)
                let sore = Muscle.allCases.filter { readiness.soreness(for: $0) != .none }
                if !sore.isEmpty {
                    Text(sore.map { "\($0.label): \((readiness.soreness[$0] ?? .none).label.lowercased())" }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No muscle soreness reported").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Readiness was not recorded for this workout.").font(.caption).foregroundStyle(.secondary)
            }
            Text(workout.isActive ? "The coach sees your latest saved sets and rest intervals when you send a message."
                                 : "Discuss the result and your next session. Completed sets and targets stay as recorded; this conversation is saved with the workout.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private var keySetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Connect your coach", systemImage: "key").font(.headline)
            Text("Add your OpenAI API key to use GPT-6.1 Sol.").font(.subheadline).foregroundStyle(.secondary)
            NavigationLink { SettingsView() } label: { Text("Open coach settings") }
                .buttonStyle(.bordered)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func proposalCard(_ change: WorkoutCoachChange, workout: Workout) -> some View {
        let original = workout.exercises.first { $0.exerciseID == change.exerciseID }
        let current = change.storeID == model.state.storeID && change.basedOnRevision == model.state.revision && workout.isActive
        return VStack(alignment: .leading, spacing: 16) {
            Label("SUGGESTED CHANGE", systemImage: "list.clipboard")
                .font(.caption.weight(.bold)).foregroundStyle(GymaStyle.accent)
            if let replacement = change.replacementExerciseID {
                Text("\(model.name(for: change.exerciseID)) → \(model.name(for: replacement))").font(.title3.bold())
            } else {
                Text(model.name(for: change.exerciseID)).font(.title3.bold())
            }
            switch change.effectiveAction {
            case .updateTarget:
                if let target = original?.target {
                    targetSummary(target, heading: "Current target", resolvedSets: original?.resolvedSetCount ?? 0)
                }
                targetSummary(change.target, heading: "Proposed target", resolvedSets: change.replacementExerciseID == nil ? (original?.resolvedSetCount ?? 0) : 0)
            case .selectExercise:
                Label("Do this exercise next", systemImage: "play.fill").font(.headline)
                Text("Other exercises stay available for later.").font(.subheadline)
            case .skipSet:
                Label("Skip one planned set", systemImage: "forward.end").font(.headline)
                Text("No reps or volume will be recorded for this set.").font(.subheadline)
            case .skipExercise:
                Label("Stop this exercise for today", systemImage: "stop.circle").font(.headline)
                Text("Skip the remaining planned sets and continue with another exercise.").font(.subheadline)
            }
            Text(change.reason).font(.subheadline).foregroundStyle(.secondary)
            Text(change.effectiveAction == .updateTarget && change.replacementExerciseID == nil
                 ? "For this workout only. Completed sets stay saved. Target changes apply to upcoming sets; an active rest timer keeps its current duration."
                 : "For this workout only. Completed sets stay saved under the original exercise. Switching or skipping ends the relevant rest timer and saves the elapsed rest.")
                .font(.caption).foregroundStyle(.secondary)
            if current {
                Button {
                    _ = model.applyWorkoutCoachChange(change, workoutID: workoutID)
                } label: {
                    Label("Apply change", systemImage: "checkmark").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canApplyWorkoutCoachChange(change, workoutID: workoutID))
            } else {
                Label("Your workout has changed since this suggestion.", systemImage: "arrow.clockwise")
                    .font(.subheadline).foregroundStyle(.orange)
                if workout.isActive {
                    Button("Ask coach to update") {
                        model.sendWorkoutCoachMessage("Please update your last suggested change using my latest workout and sets.", workoutID: workoutID)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.hasCoachAPIKey || model.storageBlocked || model.workoutCoachRequestWorkoutID != nil)
                }
            }
            if workout.isActive {
                Button("Keep workout as it is") { model.dismissWorkoutCoachChange(workoutID: workoutID) }
                    .font(.subheadline)
                    .disabled(model.storageBlocked || inFlight)
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func targetSummary(_ target: ExerciseTarget, heading: String, resolvedSets: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(heading).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            let reps = target.repsMin == target.repsMax ? "\(target.repsMin)" : "\(target.repsMin)–\(target.repsMax)"
            Text("\(target.sets) total sets × \(reps) reps · \(max(0, target.sets - resolvedSets)) sets remaining")
                .font(.subheadline.weight(.medium))
            Text("\(target.loadKg.map { "\($0.gymaNumber) kg" } ?? "Choose a comfortable load") · \(target.restSeconds)s rest")
                .font(.subheadline)
            if let effort = target.targetEffort {
                Text("Effort target: \(effort.label)").font(.subheadline)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(workout?.isActive == true ? "Swap for today, skip a set, another machine first…" : "What happened, what should I do next time…", text: $message, axis: .vertical)
                    .lineLimit(1...4).focused($composerFocused)
                    .disabled(inFlight || model.storageBlocked)
                Button {
                    if model.sendWorkoutCoachMessage(message, workoutID: workoutID) {
                        message = ""; composerFocused = false
                    }
                } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .accessibilityLabel("Send message to workout coach")
                    .disabled(!canSend)
            }
            .padding(14).background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 18))
            if !composerFocused {
                Text("Messages and relevant training data are sent to OpenAI. Review suggested changes before applying.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

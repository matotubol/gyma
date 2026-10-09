import SwiftUI
import GymaCore

struct CoachView: View {
    @EnvironmentObject private var model: GymaAppModel
    @State private var checkInPresented = false
    @State private var replacePresented = false
    @State private var message = ""
    @State private var activeWorkoutID: String?
    @State private var activePresented = false
    @FocusState private var composerFocused: Bool

    private var conversation: CoachConversation? { model.state.coachConversation }
    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && model.hasCoachAPIKey && !model.coachRequestInFlight && !model.storageBlocked
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let workout = model.state.activeWorkout {
                        activeSession(workout)
                    } else {
                        if !model.hasCoachAPIKey { keySetup }
                        if let conversation, conversation.startedWorkoutID == nil {
                            checkInSummary(conversation.checkIn)
                            ForEach(conversation.messages) { chatMessage($0) }
                            if model.coachRequestInFlight {
                                ProgressView("Your coach is thinking…")
                                    .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if let error = model.coachError {
                                Label(error, systemImage: "exclamationmark.bubble")
                                    .font(.subheadline).foregroundStyle(.orange)
                            }
                            if conversation.messages.last?.role == .user && !model.coachRequestInFlight {
                                Button(model.coachError == nil ? "Send to coach" : "Try again", systemImage: "arrow.clockwise") {
                                    model.requestCoachReply()
                                }
                                .buttonStyle(.bordered)
                                .disabled(!model.hasCoachAPIKey || model.storageBlocked)
                            }
                            if let plan = conversation.plan { planCard(plan) }
                            composer
                        } else {
                            introduction
                            if let previous = conversation {
                                DisclosureGroup("Previous conversation") {
                                    VStack(alignment: .leading, spacing: 18) {
                                        checkInSummary(previous.checkIn, heading: "PREVIOUS CHECK-IN")
                                        ForEach(previous.messages) { chatMessage($0) }
                                    }
                                    .padding(.top, 14)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id("coach-bottom")
                }
                .padding(20)
            }
            .background(GymaStyle.background)
            .onChange(of: conversation?.messages.last?.id) { _, _ in
                withAnimation { proxy.scrollTo("coach-bottom", anchor: .bottom) }
            }
        }
        .navigationTitle("Coach")
        .toolbar {
            if conversation != nil && conversation?.startedWorkoutID == nil && model.state.activeWorkout == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New check-in", systemImage: "plus") { replacePresented = true }
                        .disabled(model.storageBlocked)
                }
            }
        }
        .sheet(isPresented: $checkInPresented) {
            CheckInView {
                message = ""
                checkInPresented = false
                model.requestCoachReply()
            }
        }
        .confirmationDialog("Replace this coach conversation?", isPresented: $replacePresented, titleVisibility: .visible) {
            Button("New check-in", role: .destructive) { checkInPresented = true }
            Button("Keep conversation", role: .cancel) { }
        } message: {
            Text("Creating a new plan replaces this conversation and its workout draft. Your completed workouts are kept.")
        }
        .navigationDestination(isPresented: $activePresented) {
            if let activeWorkoutID { ActiveWorkoutView(workoutID: activeWorkoutID) }
        }
        .onAppear { model.refreshCoachCredentials() }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36, weight: .light)).foregroundStyle(GymaStyle.accent)
            Text("Build a session\nthat fits today.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Check in with your AI coach. Talk through the exercises, sets, reps, weights and rest times, then accept your workout when it feels right.")
                .foregroundStyle(.secondary)
            Text("Start it here on your iPhone. Your Watch will guide each exercise and log what you actually lift.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Check in", systemImage: "sparkles") { checkInPresented = true }
                .font(.headline).buttonStyle(.borderedProminent)
                .disabled(!model.hasCoachAPIKey || model.storageBlocked)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private var keySetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Connect your coach", systemImage: "key")
                .font(.headline)
            Text("Add your OpenAI API key to use GPT Luna.")
                .font(.subheadline).foregroundStyle(.secondary)
            NavigationLink { SettingsView() } label: { Text("Open coach settings") }
                .buttonStyle(.bordered)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func activeSession(_ workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Workout in progress", systemImage: "figure.strengthtraining.traditional")
                .font(.headline).foregroundStyle(GymaStyle.accent)
            Text(workout.title).font(.title2.bold())
            Text("Finish this session before creating your next workout with the coach.")
                .foregroundStyle(.secondary)
            Button("Resume workout", systemImage: "play.fill") {
                activeWorkoutID = workout.id
                activePresented = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func checkInSummary(_ checkIn: SessionCheckIn, heading: String = "TODAY’S CHECK-IN") -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(heading).font(.caption.weight(.bold)).foregroundStyle(GymaStyle.accent)
            Text("\(checkIn.energy.label) energy · \(checkIn.timeMinutes) min · \(checkIn.shift.label) shift")
                .font(.subheadline)
            if let hours = checkIn.sleepHours {
                Text("\(hours.gymaNumber) hours of sleep").font(.caption).foregroundStyle(.secondary)
            }
            if !checkIn.notes.isEmpty { Text(checkIn.notes).font(.subheadline).foregroundStyle(.secondary) }
            if !checkIn.recentTrainingNote.isEmpty {
                Text("Recent training: \(checkIn.recentTrainingNote)").font(.subheadline).foregroundStyle(.secondary)
            }
            if !checkIn.painNote.isEmpty {
                Text("Limitations: \(checkIn.painNote)").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func chatMessage(_ message: CoachMessage) -> some View {
        let isCoach = message.role == .assistant
        return VStack(alignment: .leading, spacing: 7) {
            Text(isCoach ? "GPT Luna" : "You")
                .font(.caption.weight(.semibold)).foregroundStyle(isCoach ? GymaStyle.accent : .secondary)
            Text(message.content).font(.body).textSelection(.enabled)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(isCoach ? GymaStyle.card : GymaStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
        .padding(isCoach ? .trailing : .leading, 18)
    }

    private func planCard(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Label(plan.acceptedAt == nil ? "WORKOUT DRAFT" : "ACCEPTED WORKOUT", systemImage: plan.acceptedAt == nil ? "list.clipboard" : "checkmark.seal")
                    .font(.caption.weight(.bold)).foregroundStyle(GymaStyle.accent)
                Text(plan.title).font(.title2.bold())
                Text("\(plan.exercises.count) exercises · \(plan.exercises.reduce(0) { $0 + ($1.target?.sets ?? 0) }) sets")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { index, exercise in
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    Text("\(index + 1). \(model.name(for: exercise.exerciseID))").font(.headline)
                    if let target = exercise.target {
                        Text("\(target.sets) sets × \(repDescription(target)) reps")
                            .font(.subheadline.weight(.medium))
                        HStack(alignment: .top) {
                            Label(target.loadKg.map { "\($0.gymaNumber) kg" } ?? "Choose a comfortable load", systemImage: "dumbbell")
                            Spacer(minLength: 8)
                            Label("\(target.restSeconds)s rest", systemImage: "timer")
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                        if !target.reason.isEmpty {
                            Text(target.reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Divider()
            Text("Your Watch will guide the accepted sets, reps and rest times. You can adjust the reps and kilograms you actually complete.")
                .font(.caption).foregroundStyle(.secondary)
            if plan.acceptedAt != nil {
                Label("Plan accepted", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(GymaStyle.accent)
                Button {
                    if let id = model.startCoachPlan(plan.id) {
                        activeWorkoutID = id
                        activePresented = true
                    }
                } label: {
                    Label("Start workout", systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).disabled(!model.canAcceptCoachPlan)
            } else {
                Button { model.acceptCoachPlan(plan.id) } label: {
                    Label("Accept workout plan", systemImage: "checkmark")
                        .font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).disabled(!model.canAcceptCoachPlan)
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func repDescription(_ target: ExerciseTarget) -> String {
        target.repsMin == target.repsMax ? "\(target.repsMin)" : "\(target.repsMin)–\(target.repsMax)"
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Talk it through").font(.headline)
            Text("Ask for a different exercise, load, number of sets or rest time.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("What would you like to change?", text: $message, axis: .vertical)
                    .lineLimit(2...6).focused($composerFocused)
                    .disabled(model.coachRequestInFlight || model.storageBlocked)
                Button {
                    if model.sendCoachMessage(message) {
                        message = ""
                        composerFocused = false
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .accessibilityLabel("Send message to coach")
                .disabled(!canSend)
            }
            .padding(14).background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 18))
            Text("Messages, check-in and recent workout summaries are sent to OpenAI. Any changes require you to accept the plan again.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

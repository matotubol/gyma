import SwiftUI
import GymaCore

struct CoachView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    var onAccepted: (() -> Void)? = nil
    @State private var workoutStartPresented = false
    @State private var activePresented = false
    @State private var selectedWorkoutID: String?
    @State private var replacePresented = false
    @State private var message = ""
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
                    HStack {
                        NavigationLink("Your profile", destination: AthleteProfileView())
                        Spacer()
                        NavigationLink("Your program", destination: TrainingProgramView())
                    }.font(.subheadline)
                    if model.state.activeWorkout != nil {
                        workoutInProgress
                    } else if let program = model.state.trainingProgram,
                              conversation?.isProgramPlanning == true,
                              conversation?.acceptedProgramID == program.id {
                        acceptedProgram(program)
                    } else if conversation?.startedWorkoutID == nil, let plan = conversation?.plan, plan.acceptedAt != nil {
                        acceptedPlan(plan)
                    } else {
                        if !model.hasCoachAPIKey { keySetup }
                        if let conversation, conversation.startedWorkoutID == nil {
                            if conversation.isProgramPlanning { programPlanningSummary }
                            else { checkInSummary(conversation.checkIn) }
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
                            if let program = conversation.proposedProgram { ProgramProposalCard(program: program) }
                            if let proposals = conversation.proposedExercises, !proposals.isEmpty {
                                exerciseProposalsCard(proposals)
                            }
                            composer
                        } else {
                            introduction
                            if let previous = conversation {
                                DisclosureGroup("Previous conversation") {
                                    VStack(alignment: .leading, spacing: 18) {
                                        if previous.isProgramPlanning { programPlanningSummary }
                                        else { checkInSummary(previous.checkIn, heading: "PREVIOUS CHECK-IN") }
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
                    Button("New program discussion", systemImage: "plus") { replacePresented = true }
                        .disabled(model.storageBlocked || model.coachRequestInFlight || !model.hasCoachAPIKey)
                }
            }
        }
        .sheet(isPresented: $workoutStartPresented) {
            ProgramWorkoutStartView { workoutID in
                workoutStartPresented = false
                selectedWorkoutID = workoutID
                activePresented = true
            }
        }
        .navigationDestination(isPresented: $activePresented) {
            if let selectedWorkoutID { ActiveWorkoutView(workoutID: selectedWorkoutID) }
        }
        .confirmationDialog("Replace this coach conversation?", isPresented: $replacePresented, titleVisibility: .visible) {
            Button("Start program discussion", role: .destructive) { beginProgramPlanning(replacingConversation: true) }
            Button("Keep conversation", role: .cancel) { }
        } message: {
            Text("This starts a new program discussion using your profile, calendar and training history. It replaces this conversation and any unaccepted proposal.")
        }
        .onAppear { model.refreshCoachCredentials() }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36, weight: .light)).foregroundStyle(GymaStyle.accent)
            Text("Training that\nbuilds on last time.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(model.state.trainingProgram == nil
                 ? "Set up your profile, then build a recurring program with your coach. Your goals, equipment and training history carry into every conversation."
                 : "Your saved program keeps your sessions consistent. Discuss longer-term changes with your coach, or start your next workout when you are ready to train.")
                .foregroundStyle(.secondary)
            Text("Plan the program now. Check in about energy, sleep and soreness once, when you start each workout.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Unsure what an exercise or machine is called? Describe how you use it. Your coach can suggest an exercise to review and save to your library.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button(model.state.trainingProgram == nil ? "Plan program with coach" : "Discuss program changes", systemImage: "sparkles") {
                if conversation != nil { replacePresented = true }
                else { beginProgramPlanning() }
            }
                .font(.headline).buttonStyle(.borderedProminent)
                .disabled(!model.hasCoachAPIKey || model.storageBlocked || model.coachRequestInFlight)
            if model.state.trainingProgram != nil {
                Button("Start next workout", systemImage: "play.fill") { workoutStartPresented = true }
                    .buttonStyle(.bordered).disabled(model.storageBlocked || model.coachRequestInFlight)
            }
            if let error = model.coachError { Text(error).font(.subheadline).foregroundStyle(.orange) }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private var keySetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Connect your coach", systemImage: "key")
                .font(.headline)
            Text("Add your OpenAI API key to use GPT-6.1 Sol.")
                .font(.subheadline).foregroundStyle(.secondary)
            NavigationLink { SettingsView() } label: { Text("Open coach settings") }
                .buttonStyle(.bordered)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private var workoutInProgress: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Planning is done", systemImage: "checkmark.circle")
                .font(.headline).foregroundStyle(GymaStyle.accent)
            Text("Your coach can help during your workout.").font(.title2.bold())
            Text("Open your workout from Overview and tap Ask coach for advice or exercise changes.")
                .foregroundStyle(.secondary)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func acceptedPlan(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Plan accepted", systemImage: "checkmark.seal.fill")
                .font(.headline).foregroundStyle(GymaStyle.accent)
            Text(plan.title).font(.title2.bold())
            Text("Your planning chat is closed. The workout is ready in Overview and, on its scheduled day, on your Watch.")
                .foregroundStyle(.secondary)
            Button("Done", action: closePlanning).buttonStyle(.borderedProminent)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func acceptedProgram(_ program: TrainingProgram) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Program saved", systemImage: "checkmark.seal.fill")
                .font(.headline).foregroundStyle(GymaStyle.accent)
            Text(program.title).font(.title2.bold())
            Text("Your recurring sessions are ready in your calendar. When you are ready to train, start your next workout from Overview and check in once for that day.")
                .foregroundStyle(.secondary)
            Button("Done", action: closePlanning).buttonStyle(.borderedProminent)
            Button("Discuss program changes", systemImage: "bubble.left.and.bubble.right") { replacePresented = true }
                .buttonStyle(.bordered)
                .disabled(!model.hasCoachAPIKey || model.storageBlocked || model.coachRequestInFlight)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private var programPlanningSummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("PROGRAM PLANNING", systemImage: "calendar")
                .font(.caption.weight(.bold)).foregroundStyle(GymaStyle.accent)
            if let calendar = model.state.trainingCalendar {
                Text("Eight weeks · \(calendar.startDate.formatted(date: .abbreviated, time: .omitted))–\(calendar.lastDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                Text("\(calendar.trainingCycleDays.count) sessions per 10-day shift cycle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let profile = model.state.athleteProfile {
                Text("\(profile.primaryGoal.label) · \(profile.experience.label)")
                    .font(.subheadline)
            }
            Text("Your coach uses your profile, schedule and training history to plan repeatable sessions. Daily readiness is checked when you start a workout.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func beginProgramPlanning(replacingConversation: Bool = false) {
        if model.beginProgramPlanning(replacingConversation: replacingConversation) {
            message = ""
            composerFocused = false
        }
    }

    private func closePlanning() {
        composerFocused = false
        if let onAccepted { onAccepted() }
        else { dismiss() }
    }

    private func checkInSummary(_ checkIn: SessionCheckIn, heading: String = "TODAY’S CHECK-IN") -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(heading).font(.caption.weight(.bold)).foregroundStyle(GymaStyle.accent)
            Text("\(checkIn.energy.label) energy · \(checkIn.timeMinutes) min · \(checkIn.shift.label) shift")
                .font(.subheadline)
            if let hours = checkIn.sleepHours {
                Text("\(hours.gymaNumber) hours of sleep").font(.caption).foregroundStyle(.secondary)
            }
            if checkIn.soreness != nil {
                let sore = Muscle.allCases.filter { checkIn.soreness(for: $0) != .none }
                Text(sore.isEmpty ? "Soreness: none" : sore.map { "\($0.label): \(checkIn.soreness(for: $0).label.lowercased())" }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
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
            Text(isCoach ? "GPT-6.1 Sol" : "You")
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
                        if let effort = target.targetEffort {
                            Text("Effort target: \(effort.label)").font(.caption).foregroundStyle(GymaStyle.accent)
                        }
                    }
                }
            }
            Divider()
            Text("Your Watch will guide the accepted sets, reps and rest times. You can adjust the reps and kilograms you actually complete.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                if model.acceptCoachPlan(plan.id) { closePlanning() }
            } label: {
                Label("Accept workout plan", systemImage: "checkmark")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).disabled(!model.canAcceptCoachPlan)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func repDescription(_ target: ExerciseTarget) -> String {
        target.repsMin == target.repsMax ? "\(target.repsMin)" : "\(target.repsMin)–\(target.repsMax)"
    }

    private func exerciseProposalsCard(_ proposals: [CoachExerciseProposal]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("EXERCISES TO REVIEW", systemImage: "dumbbell")
                .font(.caption.weight(.bold)).foregroundStyle(GymaStyle.accent)
            Text("Check these match your equipment and movement. Describe any corrections in the chat below before saving.")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(proposals) { proposal in
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    Text(proposal.exercise.name).font(.headline)
                    LabeledContent("Soreness region", value: proposal.exercise.muscle.label)
                    if let metadata = proposal.exercise.trainingMetadata {
                        LabeledContent("Main muscles", value: metadata.primaryMuscles.map(\.label).joined(separator: ", "))
                        LabeledContent("Secondary muscles", value: metadata.secondaryMuscles.isEmpty ? "None specified" : metadata.secondaryMuscles.map(\.label).joined(separator: ", "))
                        LabeledContent("Equipment", value: metadata.equipment?.label ?? "Not specified")
                        LabeledContent("How to log weight", value: metadata.loadConvention.label)
                        LabeledContent("Measurement", value: metadata.measurement == .seconds ? "Seconds" : "Repetitions")
                    } else {
                        Text("Muscle, equipment and weight details are not specified. Ask your coach to clarify these before saving.")
                            .foregroundStyle(.secondary)
                    }
                    Text(proposal.explanation).foregroundStyle(.secondary)
                }.font(.subheadline)
            }
            Text("Saving adds these exercises to your library so the coach can use them in your program. You will review the program separately.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                if model.acceptCoachExercises(proposals) { composerFocused = false }
            } label: {
                Label("Save exercises & continue", systemImage: "checkmark")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.storageBlocked || model.coachRequestInFlight || model.state.activeWorkout != nil ||
                      conversation?.proposedExercises != proposals || conversation?.messages.last?.role != .assistant)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Talk it through").font(.headline)
            Text(conversation?.isProgramPlanning == true
                 ? "Discuss your goals, recurring sessions, exercise choices and progression."
                 : "Ask for a different exercise, load, number of sets or rest time.")
                .font(.caption).foregroundStyle(.secondary)
            Text("You can describe unfamiliar machines in your own words. Your coach will ask for details when needed and show any new exercises for you to confirm.")
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
            Text("Messages, profile, program, relevant training history and feedback are sent to OpenAI when you ask the coach. Program and workout changes need your acceptance.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

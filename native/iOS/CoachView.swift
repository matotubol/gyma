import SwiftUI
import UIKit
import GymaCore

struct CoachView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    var onAccepted: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
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
                    }
                    if !model.hasCoachAPIKey { keySetup }
                    if let conversation, conversation.startedWorkoutID == nil {
                        if conversation.isProgramPlanning { programPlanningSummary }
                        else { checkInSummary(conversation.checkIn) }
                        if conversation.messages.isEmpty { conversationSuggestions }
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
                        if let proposal = model.coachAppChanges { appChangesCard(proposal) }
                        if let plan = conversation.plan {
                            if plan.acceptedAt == nil { planCard(plan) }
                            else { TimelineView(.periodic(from: .now, by: 30)) { context in acceptedPlan(plan, now: context.date) } }
                        }
                        if let program = conversation.proposedProgram { ProgramProposalCard(program: program) }
                        if let proposals = conversation.proposedExercises, !proposals.isEmpty {
                            exerciseProposalsCard(proposals)
                        }
                    } else {
                        TimelineView(.periodic(from: .now, by: 30)) { context in introduction(at: context.date) }
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
                    Color.clear.frame(height: 1).id("coach-bottom")
                }
                .padding(20)
            }
            .background(GymaStyle.background)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if conversation?.startedWorkoutID == nil, conversation != nil {
                    composer
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.bar)
                        .overlay(alignment: .top) { Divider() }
                }
            }
            .onChange(of: conversation?.messages.last?.id) { _, _ in
                withAnimation { proxy.scrollTo("coach-bottom", anchor: .bottom) }
            }
            .onChange(of: model.coachRequestInFlight) { _, _ in
                withAnimation { proxy.scrollTo("coach-bottom", anchor: .bottom) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                if composerFocused { withAnimation { proxy.scrollTo("coach-bottom", anchor: .bottom) } }
            }
            .onAppear { proxy.scrollTo("coach-bottom", anchor: .bottom) }
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    composerFocused = false
                    if let onClose { onClose() } else { dismiss() }
                } label: { Label("Back", systemImage: "chevron.left") }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { composerFocused = false }
            }
            if conversation != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New conversation", systemImage: "plus") { replacePresented = true }
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
            Button("Start new conversation", role: .destructive) { beginCoachDiscussion(replacingConversation: true) }
            Button("Keep conversation", role: .cancel) { }
        } message: {
            Text("Your profile, calendar and training history stay available. This replaces the current conversation and any unapplied proposal.")
        }
        .onAppear { model.refreshCoachCredentials() }
    }

    private func introduction(at now: Date) -> some View {
        let today = DailyTrainingPresentation(state: model.state, now: now)
        return VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36, weight: .light)).foregroundStyle(GymaStyle.accent)
            Text("Your training.\nYour coach can help.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Manage your program, change your cycle, add training days, rename exercises, adjust sets or review any recorded session. Your coach can look up the details and prepare the changes for you.")
                .foregroundStyle(.secondary)
            Text("Ask in your own words. Review the changes and apply them together here in the chat.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Unsure what an exercise or machine is called? Describe how you use it. Your coach can suggest an exercise to review and save to your library.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Talk to your coach", systemImage: "sparkles") {
                beginCoachDiscussion()
            }
                .font(.headline).buttonStyle(.borderedProminent)
                .disabled(!model.hasCoachAPIKey || model.storageBlocked || model.coachRequestInFlight)
            if model.state.trainingProgram != nil {
                if today.status.allowsWorkoutStart {
                    Button("Start today's workout", systemImage: "play.fill") {
                        guard model.state.dailyTrainingStatus().allowsWorkoutStart else { return }
                        workoutStartPresented = true
                    }
                    .buttonStyle(.bordered).disabled(model.storageBlocked || model.coachRequestInFlight)
                } else {
                    Text(today.message).font(.subheadline).foregroundStyle(.secondary)
                    NavigationLink("View calendar") { TrainingCalendarView() }.buttonStyle(.bordered)
                }
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
            Label("Workout in progress", systemImage: "figure.strengthtraining.traditional")
                .font(.headline).foregroundStyle(GymaStyle.accent)
            Text("Your coach is still available.").font(.title2.bold())
            Text("Discuss your program, schedule or training history here. For live exercise guidance, open your workout and tap Ask coach.")
                .foregroundStyle(.secondary)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func acceptedPlan(_ plan: WorkoutPlan, now: Date) -> some View {
        let today = DailyTrainingPresentation(state: model.state, now: now)
        return VStack(alignment: .leading, spacing: 14) {
            Label("Plan accepted", systemImage: "checkmark.seal.fill")
                .font(.headline).foregroundStyle(GymaStyle.accent)
            Text(plan.title).font(.title2.bold())
            Text(model.state.canStartAcceptedPlan(plan, now: now)
                 ? "Today's workout is available in Overview and on your Watch. You can keep talking to your coach below."
                 : "This workout is saved for \(today.date(plan.scheduledDate)); it can start on its scheduled training day. You can keep talking to your coach below.")
                .foregroundStyle(.secondary)
            if !today.status.allowsWorkoutStart { Text(today.message).font(.subheadline).foregroundStyle(.secondary) }
            Button("Done", action: closePlanning).buttonStyle(.borderedProminent)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private var programPlanningSummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("YOUR COACH", systemImage: "bubble.left.and.bubble.right")
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
            Text("Your coach can manage your program, calendar, exercise library and profile, and look up individual training days. Changes appear here for you to apply.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func beginCoachDiscussion(replacingConversation: Bool = false) {
        if model.beginCoachDiscussion(replacingConversation: replacingConversation) {
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

    private var conversationSuggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What would you like to work on?").font(.title3.bold())
            ForEach(["Review my program and training cycle", "Help me add an extra training day", "Review a specific workout", "Help me change an exercise or its sets"], id: \.self) { suggestion in
                Button(suggestion) {
                    message = suggestion
                    composerFocused = true
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func appChangesCard(_ proposal: CoachAppChangeProposal) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("CHANGES TO REVIEW", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.bold)).foregroundStyle(GymaStyle.accent)
            Text("Apply these changes together").font(.title2.bold())
            ForEach(Array(proposal.summaries.enumerated()), id: \.offset) { _, summary in
                Text(summary).font(.subheadline).textSelection(.enabled)
                Divider()
            }
            if !model.canApplyCoachAppChanges && !model.coachRequestInFlight {
                Text("Your data changed after this proposal. Ask the coach to refresh it before applying.")
                    .font(.subheadline).foregroundStyle(.orange)
                Button("Refresh changes", systemImage: "arrow.clockwise") {
                    _ = model.sendCoachMessage("Refresh your proposed app changes using my latest saved data. Keep my requested changes, look up anything that changed, and show an updated proposal.")
                }
                .buttonStyle(.bordered)
                .disabled(model.storageBlocked || !model.hasCoachAPIKey)
            }
            Button {
                if model.applyCoachAppChanges(proposal) { composerFocused = false }
            } label: {
                Label("Apply changes", systemImage: "checkmark")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canApplyCoachAppChanges)
            Button("Dismiss proposal") { model.discardCoachAppChanges() }
                .disabled(model.coachRequestInFlight || model.storageBlocked)
            Text("You can describe corrections in the chat before applying.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("What would you like to change?", text: $message, axis: .vertical)
                    .lineLimit(1...4).focused($composerFocused)
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
            if !composerFocused {
                Text("Messages and relevant training data are sent to OpenAI. Review suggested changes before applying.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

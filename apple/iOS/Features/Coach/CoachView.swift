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
                        else { CoachCheckInSummary(checkIn: conversation.checkIn) }
                        if conversation.messages.isEmpty { conversationSuggestions }
                        ForEach(conversation.messages) { CoachMessageRow(message: $0) }
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
                        if let proposal = model.coachAppChanges {
                            CoachAppChangesCard(proposal: proposal) { composerFocused = false }
                        }
                        if let plan = conversation.plan {
                            if plan.acceptedAt == nil { CoachWorkoutPlanCard(plan: plan, onAccepted: closePlanning) }
                            else { TimelineView(.periodic(from: .now, by: 30)) { context in acceptedPlan(plan, now: context.date) } }
                        }
                        if let program = conversation.proposedProgram { ProgramProposalCard(program: program) }
                        if let proposals = conversation.proposedExercises, !proposals.isEmpty {
                            CoachExerciseProposalsCard(proposals: proposals) { composerFocused = false }
                        }
                    } else {
                        TimelineView(.periodic(from: .now, by: 30)) { context in introduction(at: context.date) }
                        if let previous = conversation {
                            DisclosureGroup("Previous conversation") {
                                VStack(alignment: .leading, spacing: 18) {
                                    if previous.isProgramPlanning { programPlanningSummary }
                                    else { CoachCheckInSummary(checkIn: previous.checkIn, heading: "PREVIOUS CHECK-IN") }
                                    ForEach(previous.messages) { CoachMessageRow(message: $0) }
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

import SwiftUI
import GymaCore

@main
struct GymaApp: App {
    @StateObject private var model = GymaAppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(GymaStyle.accent)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refresh() }
                }
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var model: GymaAppModel
    @State private var selectedTab = "overview"

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { OverviewView() }
                .tabItem { Label("Overview", systemImage: "square.grid.2x2") }
                .tag("overview")
            NavigationStack { CoachView(onAccepted: { selectedTab = "overview" }) }
                .tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right") }
                .tag("coach")
            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag("history")
            NavigationStack { ProgressViewScreen() }
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
                .tag("progress")
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag("settings")
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.storageBlocked {
                Label("Saved data needs attention. Open Settings to recover it.", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.caption.weight(.medium))
                    .padding(12).frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.18))
            }
        }
        .alert("Gyma", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

struct OverviewView: View {
    @EnvironmentObject private var model: GymaAppModel
    @State private var coachPresented = false
    @State private var activePresented = false
    @State private var selectedWorkoutID: String?
    @State private var preparingPlan: WorkoutPlan?
    @State private var startingProgram = false

    private var acceptedPlan: WorkoutPlan? {
        guard model.state.activeWorkout == nil, let plan = model.state.coachConversation?.plan,
              plan.acceptedAt != nil else { return nil }
        return plan
    }

    private var thisWeek: [Workout] {
        let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date())
        return model.completedWorkouts.filter { interval?.contains($0.start) == true }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TimelineView(.periodic(from: .now, by: 30)) { context in hero(at: context.date) }
                TrainingCalendarOverviewCard()
                NavigationLink { TrainingProgramView() } label: {
                    HStack {
                        Image(systemName: "calendar").foregroundStyle(GymaStyle.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.state.trainingProgram?.title ?? "Build your training program").font(.headline)
                            Text(model.state.trainingProgram?.nextSession(history: model.state.workouts).map { "Next: \($0.title)" } ?? "Save a profile and a recurring plan")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }.padding(18).background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 20))
                }.foregroundStyle(.primary)
                HStack(spacing: 12) {
                    StatTile(value: "\(thisWeek.count)", label: "Workouts this week", symbol: "calendar")
                    StatTile(value: thisWeek.reduce(0) { $0 + $1.liftedVolume }.gymaNumber,
                             label: "Kilograms this week", symbol: "dumbbell")
                }
                if let timer = model.state.restTimer {
                    RestTimerCard(timer: timer)
                }
                SectionHeading(title: "Keep showing up", subtitle: "Your training, one session at a time.")
                if model.completedWorkouts.isEmpty {
                    EmptyState(title: "Your first session", message: "Build your recurring program with the coach. When you are ready to train, start a session and check how you feel that day. Your Watch guides you through each exercise.", symbol: "figure.strengthtraining.traditional")
                        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 22))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.completedWorkouts.prefix(3).enumerated()), id: \.element.id) { index, workout in
                            NavigationLink { WorkoutDetailView(workoutID: workout.id) } label: {
                                WorkoutSummaryRow(workout: workout).foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            if index < min(model.completedWorkouts.count, 3) - 1 { Divider().padding(.leading, 82) }
                        }
                    }
                    .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 22))
                }
                PairingInlineView(connectivity: model.connectivity)
            }
            .padding(20)
        }
        .background(GymaStyle.background)
        .navigationTitle("Gyma")
        .navigationDestination(isPresented: $coachPresented) { CoachView(onAccepted: { coachPresented = false }) }
        .navigationDestination(isPresented: $activePresented) {
            if let selectedWorkoutID { ActiveWorkoutView(workoutID: selectedWorkoutID) }
        }
        .sheet(item: $preparingPlan) { plan in
            WorkoutReadinessView(plan: plan) { workoutID in
                preparingPlan = nil
                selectedWorkoutID = workoutID
                activePresented = true
            }
        }
        .sheet(isPresented: $startingProgram) {
            ProgramWorkoutStartView { workoutID in
                startingProgram = false
                selectedWorkoutID = workoutID
                activePresented = true
            }
        }
    }

    private func hero(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(model.state.activeWorkout == nil ? "YOUR NEXT SESSION" : "SESSION IN PROGRESS", systemImage: "figure.strengthtraining.traditional")
                    .font(.caption.weight(.bold)).tracking(1)
                Spacer()
                Image(systemName: "arrow.up.right").font(.title3)
            }
            Text(model.state.activeWorkout != nil ? "Pick up where\nyou left off." : (acceptedPlan?.title ?? model.state.trainingProgram?.nextSession(history: model.state.workouts, now: now)?.title ?? "A little stronger.\nEvery session."))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            if let workout = model.state.activeWorkout {
                Text("\(workout.loggedSets) sets logged · Started \(workout.start.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
            } else if let plan = acceptedPlan {
                Text(plan.isScheduledForToday(at: now)
                     ? "Ready for today · \(plan.exercises.count) exercises. Check your energy and soreness before starting here or on Watch."
                     : "Scheduled for \(plan.scheduledDate.formatted(date: .abbreviated, time: .omitted)). Make a new plan for today.")
                    .font(.subheadline)
            } else if model.state.trainingProgram != nil {
                Text("Your program is ready. Check today's energy, sleep and soreness when you start this session.")
                    .font(.subheadline)
            } else {
                Text(model.state.coachConversation?.plan == nil || model.state.coachConversation?.startedWorkoutID != nil
                     ? "Build a recurring program with your coach for your training calendar."
                     : "Your coach has a workout ready to review.").font(.subheadline)
            }
            Button {
                if let active = model.state.activeWorkout {
                    selectedWorkoutID = active.id
                    activePresented = true
                } else if let plan = acceptedPlan, plan.isScheduledForToday(at: now) {
                    preparingPlan = plan
                } else if model.state.trainingProgram != nil {
                    startingProgram = true
                } else {
                    if model.beginProgramPlanning() { coachPresented = true }
                }
            } label: {
                Label(model.state.activeWorkout != nil ? "Resume workout" : (acceptedPlan?.isScheduledForToday(at: now) == true || model.state.trainingProgram != nil ? "Start next workout" : (model.hasUnfinishedProgramPlanning ? "Continue planning" : "Plan program with coach")), systemImage: model.state.activeWorkout != nil || acceptedPlan?.isScheduledForToday(at: now) == true || model.state.trainingProgram != nil ? "play.fill" : "bubble.left.and.bubble.right")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(Color(red: 0.10, green: 0.30, blue: 0.19))
            .disabled(model.storageBlocked)
        }
        .padding(24)
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [Color(red: 0.12, green: 0.37, blue: 0.24), GymaStyle.accent], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
    }
}

private struct PairingInlineView: View {
    @ObservedObject var connectivity: WorkoutConnectivity
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "applewatch").font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your wrist, in sync").font(.subheadline.weight(.semibold))
                Text(connectivity.connectionStatus).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Circle().fill(connectivity.isReachable ? GymaStyle.accent : .secondary).frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }
}

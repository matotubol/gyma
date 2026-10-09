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

    var body: some View {
        TabView {
            NavigationStack { OverviewView() }
                .tabItem { Label("Overview", systemImage: "square.grid.2x2") }
            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            NavigationStack { ProgressViewScreen() }
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
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
    @State private var checkInPresented = false
    @State private var activePresented = false
    @State private var selectedWorkoutID: String?

    private var thisWeek: [Workout] {
        let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date())
        return model.completedWorkouts.filter { interval?.contains($0.start) == true }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
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
                    EmptyState(title: "Make a start", message: "Check in, choose an exercise, and log your first set. Your workout saves as you go.", symbol: "figure.strengthtraining.traditional")
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
        .sheet(isPresented: $checkInPresented) {
            CheckInView { id in
                selectedWorkoutID = id
                checkInPresented = false
                activePresented = true
            }
        }
        .navigationDestination(isPresented: $activePresented) {
            if let selectedWorkoutID { ActiveWorkoutView(workoutID: selectedWorkoutID) }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(model.state.activeWorkout == nil ? "YOUR NEXT SESSION" : "SESSION IN PROGRESS", systemImage: "figure.strengthtraining.traditional")
                    .font(.caption.weight(.bold)).tracking(1)
                Spacer()
                Image(systemName: "arrow.up.right").font(.title3)
            }
            Text(model.state.activeWorkout == nil ? "A little stronger.\nEvery session." : "Pick up where\nyou left off.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            if let workout = model.state.activeWorkout {
                Text("\(workout.loggedSets) sets logged · Started \(workout.start.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
            } else {
                Text("Take a moment to check in. Then make it count.").font(.subheadline)
            }
            Button {
                if let active = model.state.activeWorkout {
                    selectedWorkoutID = active.id
                    activePresented = true
                } else { checkInPresented = true }
            } label: {
                Label(model.state.activeWorkout == nil ? "Start workout" : "Resume workout", systemImage: "play.fill")
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

struct CheckInView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    var onStarted: (String) -> Void
    @State private var shift: Shift = .off
    @State private var energy: Energy = .good
    @State private var minutes = 45
    @State private var title = ""
    @State private var sleep = ""
    @State private var notes = ""
    @State private var pain = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("How are you arriving today?").font(.title2.bold())
                    Text("A quick check-in helps put every workout in context.").foregroundStyle(.secondary)
                }
                Section("Before you start") {
                    Picker("Shift", selection: $shift) { ForEach(Shift.allCases) { Text($0.label).tag($0) } }
                    Picker("Energy", selection: $energy) { ForEach(Energy.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) } }
                    Stepper("Time available: \(minutes) min", value: $minutes, in: 10...180, step: 5)
                    TextField("Sleep in hours (optional)", text: $sleep).keyboardType(.decimalPad)
                }
                Section("Session") {
                    TextField("Workout name (optional)", text: $title)
                    TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(2...4)
                    TextField("Pain or limitations (optional)", text: $pain, axis: .vertical).lineLimit(2...4)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button {
                        let hours = sleep.trimmingCharacters(in: .whitespaces)
                        let value = Double(hours.replacingOccurrences(of: ",", with: "."))
                        guard hours.isEmpty || (value != nil && value! >= 0 && value! <= 24) else {
                            error = "Sleep must be between 0 and 24 hours."
                            return
                        }
                        let checkIn = SessionCheckIn(shift: shift, energy: energy, timeMinutes: minutes,
                                                    sleepHours: value, notes: notes, painNote: pain)
                        if let id = model.start(checkIn: checkIn, title: title) { onStarted(id) }
                        else { error = model.errorMessage }
                    } label: {
                        Label("Start workout", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).padding(.vertical, 4)
                }
            }
            .navigationTitle("Check in").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

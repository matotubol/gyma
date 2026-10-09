import SwiftUI

@main
@MainActor
struct GymaWatchApp: App {
    @WKApplicationDelegateAdaptor(GymaWatchAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var connectivity: WorkoutConnectivity
    @StateObject private var restNotifications: WatchRestNotifications
    @StateObject private var workoutRuntime: WatchWorkoutRuntime

    init() {
        let connectivity = WorkoutConnectivity.shared
        let reminders = WatchRestNotifications.shared
        let runtime = WatchWorkoutRuntime.shared
        _connectivity = StateObject(wrappedValue: connectivity)
        _restNotifications = StateObject(wrappedValue: reminders)
        _workoutRuntime = StateObject(wrappedValue: runtime)
        runtime.observe(connectivity: connectivity, onRunningChange: { [weak reminders] running in
            reminders?.setWorkoutRunning(running)
        }, afterStartAttempt: { [weak reminders] in
            await reminders?.prepareForWorkout()
        })
        // App initialization also runs for background connectivity launches;
        // view tasks are not guaranteed to run before incoming messages arrive.
        reminders.updatePendingCommand(connectivity.pendingCommand)
        connectivity.configureWatch { [weak reminders, weak connectivity, weak runtime] snapshot in
            reminders?.updatePendingCommand(connectivity?.pendingCommand)
            reminders?.update(snapshot)
            runtime?.update(snapshot, pendingCommand: connectivity?.pendingCommand)
        }
    }

    var body: some Scene {
        WindowGroup {
            WatchWorkoutView()
                .environmentObject(connectivity)
                .environmentObject(restNotifications)
                .environmentObject(workoutRuntime)
                .tint(.mint)
                .onChange(of: connectivity.pendingCommand, initial: true) { _, command in
                    restNotifications.updatePendingCommand(command)
                }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            restNotifications.setAppActive(phase == .active)
            workoutRuntime.setAppActive(phase == .active)
            if phase == .active {
                connectivity.refresh()
            }
        }
        .backgroundTask(.watchConnectivity) {
            await connectivity.receiveBackgroundTransfers()
            await restNotifications.finishPendingScheduling()
        }
    }
}

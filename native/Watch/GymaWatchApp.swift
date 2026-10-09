import SwiftUI

@main
@MainActor
struct GymaWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var connectivity: WorkoutConnectivity
    @StateObject private var restNotifications: WatchRestNotifications

    init() {
        let connectivity = WorkoutConnectivity.shared
        let reminders = WatchRestNotifications.shared
        _connectivity = StateObject(wrappedValue: connectivity)
        _restNotifications = StateObject(wrappedValue: reminders)
        // App initialization also runs for background connectivity launches;
        // view tasks are not guaranteed to run before incoming messages arrive.
        reminders.updatePendingCommand(connectivity.pendingCommand)
        connectivity.configureWatch { [weak reminders, weak connectivity] snapshot in
            reminders?.updatePendingCommand(connectivity?.pendingCommand)
            reminders?.update(snapshot)
        }
    }

    var body: some Scene {
        WindowGroup {
            WatchWorkoutView()
                .environmentObject(connectivity)
                .environmentObject(restNotifications)
                .tint(.mint)
                .onChange(of: connectivity.pendingCommand, initial: true) { _, command in
                    restNotifications.updatePendingCommand(command)
                }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            restNotifications.setAppActive(phase == .active)
            if phase == .active { connectivity.refresh() }
        }
        .backgroundTask(.watchConnectivity) {
            await connectivity.receiveBackgroundTransfers()
            await restNotifications.finishPendingScheduling()
        }
    }
}

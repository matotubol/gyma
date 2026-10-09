import SwiftUI

@main
@MainActor
struct GymaWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var connectivity: WorkoutConnectivity
    @StateObject private var restNotifications: WatchRestNotifications

    init() {
        let connectivity = WorkoutConnectivity.shared
        let reminders = WatchRestNotifications()
        _connectivity = StateObject(wrappedValue: connectivity)
        _restNotifications = StateObject(wrappedValue: reminders)
        // App initialization also runs for background connectivity launches;
        // view tasks are not guaranteed to run before incoming messages arrive.
        connectivity.configureWatch { [weak reminders] snapshot in
            reminders?.update(snapshot)
        }
    }

    var body: some Scene {
        WindowGroup {
            WatchWorkoutView()
                .environmentObject(connectivity)
                .environmentObject(restNotifications)
                .tint(.mint)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { connectivity.refresh() }
        }
        .backgroundTask(.watchConnectivity) {
            await connectivity.receiveBackgroundTransfers()
            await restNotifications.finishPendingScheduling()
        }
    }
}

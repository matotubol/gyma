import SwiftUI

@main
struct GymaApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    // Pick up changes made in the browser while the app was in the background.
                    if phase == .active, model.auth == .ready, !model.busy, !model.planEditorOpen { model.reloadAll() }
                }
        }
    }
}

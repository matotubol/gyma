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
            NavigationStack { CoachView(onAccepted: { selectedTab = "overview" }, onClose: { selectedTab = "overview" }) }
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

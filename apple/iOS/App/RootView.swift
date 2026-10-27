import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.auth {
        case .checking:
            ProgressView("Opening your workouts…")
        case .guest:
            SignInView()
        case .ready:
            MainTabs()
        }
    }
}

private struct MainTabs: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.tab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "calendar") }
                .tag(AppModel.Tab.home)
            WorkoutView()
                .tabItem { Label("Workout", systemImage: "dumbbell.fill") }
                .tag(AppModel.Tab.workout)
            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
                .tag(AppModel.Tab.progress)
        }
        .sheet(isPresented: $model.planEditorOpen) {
            DayPlanEditor().environmentObject(model)
        }
        .overlay(alignment: .top) {
            if let celebration = model.celebration {
                RecordToast(celebration: celebration.value) { model.celebration = nil }
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: celebration.key) {
                        try? await Task.sleep(for: .seconds(celebration.value.monster ? 6 : 4.5))
                        if model.celebration?.key == celebration.key { model.celebration = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: model.celebration?.key)
    }
}

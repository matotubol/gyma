import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.auth {
            case .checking:
                ProgressView("Opening your workouts…")
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.canvas.ignoresSafeArea())
            case .guest:
                SignInView()
            case .ready:
                MainTabs()
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}

private struct MainTabs: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.tab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppModel.Tab.home)
            WorkoutView()
                .tabItem { Label("Workout", systemImage: "dumbbell") }
                .tag(AppModel.Tab.workout)
            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppModel.Tab.progress)
        }
        .sheet(isPresented: $model.planEditorOpen) {
            DayPlanEditor().environmentObject(model)
        }
    }
}

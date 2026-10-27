import SwiftUI
import GymaCore

/// The Workout tab: steps between days and runs the selected day's workout.
struct WorkoutView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if let plan = model.dayPlan {
                    WorkoutRunnerView(plan: plan)
                        .id(plan.date)
                } else if let error = model.dayError {
                    VStack {
                        ErrorBanner(message: error, actionTitle: "Retry") { model.loadDay() }
                        Spacer()
                    }
                    .padding(16)
                } else {
                    ProgressView("Loading workout…")
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Workout").font(.headline)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    DaySwitcher()
                }
            }
        }
    }
}

private struct DaySwitcher: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let date = model.selectedDate
        let today = CivilDate.today
        HStack(spacing: 2) {
            if date != today {
                Button("Today") { model.select(today) }
                    .font(.caption.weight(.semibold))
                    .padding(.trailing, 4)
            }
            Button { model.select(CivilDate.shift(day: date, by: -1)) } label: {
                Image(systemName: "chevron.left").font(.footnote.weight(.semibold))
            }
            .accessibilityLabel("Previous day")
            Text(DateText.shortDay(date))
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
                .frame(minWidth: 76)
            Button { model.select(CivilDate.shift(day: date, by: 1)) } label: {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
            }
            .accessibilityLabel("Next day")
        }
        .disabled(model.busy)
    }
}

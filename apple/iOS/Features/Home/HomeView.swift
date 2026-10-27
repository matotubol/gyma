import SwiftUI
import GymaCore

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MonthCalendar(selected: model.selectedDate, month: model.month,
                                  days: model.loadedMonth == model.month ? model.days : [:],
                                  onSelect: { model.select($0) }, onMonthChange: { model.showMonth($0) })
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                } footer: {
                    HStack(spacing: 16) {
                        Label("Training", systemImage: "circle.fill").foregroundStyle(Theme.training)
                        Label("Rest", systemImage: "circle.fill").foregroundStyle(Theme.rest)
                        if model.monthLoading { ProgressView().controlSize(.mini) }
                        if let error = model.monthError {
                            Button("\(error) Retry") { model.loadMonth() }.font(.footnote)
                        }
                    }
                    .labelStyle(LegendLabelStyle())
                }

                DaySection()
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if model.selectedDate != CivilDate.today {
                        Button("Today") { model.select(CivilDate.today) }.disabled(model.busy)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmSignOut = true }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Account")
                }
            }
            .confirmationDialog("Sign out of this iPhone?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { model.signOut() }
            }
        }
    }
}

private struct LegendLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 6))
            configuration.title.foregroundStyle(.secondary)
        }
        .font(.footnote)
    }
}

private struct DaySection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let date = model.selectedDate
        Section {
            if let error = model.dayError {
                Button("Retry", systemImage: "arrow.clockwise") { model.loadDay() }
                    .badge(Text(error))
            } else if let plan = model.dayPlan {
                LabeledContent("Day") {
                    Text(plan.kind.label).foregroundStyle(plan.kind.tint)
                }
                ForEach(Array(plan.exercises.enumerated()), id: \.offset) { _, item in
                    LabeledContent {
                        Text("\(item.sets) × \(item.reps)\(item.plannedKg > 0 ? " · \(formatKg(item.plannedKg)) kg" : "")").monospacedDigit()
                    } label: {
                        Text(item.name)
                        Text(item.library.detail)
                    }
                }
                if plan.exercises.isEmpty {
                    Text(plan.kind == .rest ? "Rest day. Recover well." : "Nothing planned yet.").foregroundStyle(.secondary)
                    Button("Plan This Day", systemImage: "plus") { model.planEditorOpen = true }
                        .disabled(model.busy)
                } else {
                    Button {
                        model.tab = .workout
                    } label: {
                        Label(model.session?.status == .active ? "Continue Workout" : model.session?.status == .completed ? "View Workout" : "Go to Workout",
                              systemImage: model.session?.status == .completed ? "checkmark.circle" : "figure.strengthtraining.traditional")
                    }
                    if model.session == nil {
                        Button("Edit Plan", systemImage: "pencil") { model.planEditorOpen = true }
                            .disabled(model.busy)
                    }
                }
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        } header: {
            Text(date == CivilDate.today ? "Today · \(DateText.full(date))" : DateText.full(date))
        }
    }
}

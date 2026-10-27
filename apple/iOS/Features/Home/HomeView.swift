import SwiftUI
import GymaCore

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    CalendarCard()
                    SelectedDayCard()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable { await model.refresh() }
            .screenBackground()
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { confirmSignOut = true } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                    .accessibilityLabel("Sign out")
                    .disabled(model.busy)
                }
            }
            .confirmationDialog("Sign out of this iPhone?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { model.signOut() }
            }
        }
    }
}

// MARK: - Calendar

private struct CalendarCard: View {
    @EnvironmentObject private var model: AppModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let today = CivilDate.today
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                Text(DateText.month(model.month))
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.leading, 8)
                Spacer()
                Button("Today") { model.select(today) }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .disabled(model.busy)
                monthButton("chevron.left", offset: -1, label: "Previous month")
                monthButton("chevron.right", offset: 1, label: "Next month")
            }

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .padding(.bottom, 4)
                }
                ForEach(CivilDate.cells(month: model.month), id: \.self) { key in
                    DateCell(key: key, today: today)
                }
            }
            .opacity(model.monthLoading ? 0.5 : 1)

            HStack(spacing: 16) {
                legend("Training", color: Theme.training)
                legend("Rest", color: Theme.rest)
                if model.monthLoading { Text("Loading…") }
            }
            .font(.system(size: 10))
            .foregroundStyle(Theme.muted)
            .frame(minHeight: 28)

            if let error = model.monthError {
                ErrorBanner(message: error, actionTitle: "Retry") { model.loadMonth() }
            }
        }
        .card(padding: 8)
    }

    private func monthButton(_ symbol: String, offset: Int, label: String) -> some View {
        Button { model.showMonth(by: offset) } label: {
            Image(systemName: symbol).frame(width: 40, height: 40)
        }
        .foregroundStyle(Theme.muted)
        .accessibilityLabel(label)
    }

    private func legend(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
    }
}

private struct DateCell: View {
    @EnvironmentObject private var model: AppModel
    let key: String
    let today: String

    var body: some View {
        let inMonth = key.hasPrefix(model.month)
        let selected = key == model.selectedDate
        let day = model.loadedMonth == model.month ? model.days[key] : nil
        Button { model.tap(key) } label: {
            VStack(spacing: 3) {
                Text(String(Int(key.suffix(2)) ?? 0))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                Circle()
                    .fill(dotColor(day?.kind, selected: selected))
                    .frame(width: 4, height: 4)
            }
            .foregroundStyle(selected ? Theme.canvas : !inMonth ? Theme.faint : key == today ? Theme.accent : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(selected ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!inMonth || model.busy)
        .accessibilityLabel("\(DateText.full(key)), \(day?.kind.label ?? "Unplanned")\(day.map { $0.exerciseCount > 0 ? ", \($0.exerciseCount) exercises" : "" } ?? "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dotColor(_ kind: DayKind?, selected: Bool) -> Color {
        switch kind {
        case .some(.training): selected ? Theme.canvas : Theme.training
        case .some(.rest): selected ? Theme.canvas : Theme.rest
        case .none: .clear
        }
    }
}

// MARK: - Selected day

private struct SelectedDayCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let date = model.selectedDate
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(date == CivilDate.today ? "Today" : DateText.weekday(date))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    Text(DateText.long(date))
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                KindPill(kind: model.dayPlan?.kind, loading: model.dayPlan == nil)
            }

            if let error = model.dayError {
                ErrorBanner(message: error, actionTitle: "Retry") { model.loadDay() }
            } else if let plan = model.dayPlan {
                if plan.exercises.isEmpty {
                    Text(plan.kind == .rest ? "Rest day. Recover well." : "Nothing planned yet.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(plan.exercises.enumerated()), id: \.offset) { index, item in
                            if index > 0 { Divider().overlay(Theme.line) }
                            PlannedRow(item: item)
                        }
                    }
                }
                actions(plan)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .card()
    }

    @ViewBuilder
    private func actions(_ plan: WorkoutPlan) -> some View {
        if plan.exercises.isEmpty {
            Button { model.planEditorOpen = true } label: {
                Label("Plan this day", systemImage: "plus")
            }
            .buttonStyle(.primary)
            .disabled(model.busy)
        } else {
            Button { model.tab = .workout } label: {
                HStack(spacing: 6) {
                    Text(model.session?.status == .active ? "Continue workout" : model.session?.status == .completed ? "View workout" : "Go to workout")
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                }
            }
            .buttonStyle(.primary)
            if model.session == nil {
                Button("Edit plan") { model.planEditorOpen = true }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .disabled(model.busy)
            }
        }
    }
}

private struct PlannedRow: View {
    let item: PlannedExercise

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline.weight(.medium))
                Text(item.library.detail).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Text("\(item.sets) × \(item.reps)\(item.plannedKg > 0 ? " · \(formatKg(item.plannedKg)) kg" : "")")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Theme.muted)
        }
        .frame(minHeight: 48)
    }
}

struct KindPill: View {
    let kind: DayKind?
    var loading = false

    var body: some View {
        switch (loading, kind) {
        case (true, _): Pill(text: "…", foreground: Theme.muted, background: Theme.raised)
        case (false, .some(.training)): Pill(text: "Training", foreground: Theme.training, background: Theme.accentDim)
        case (false, .some(.rest)): Pill(text: "Rest", foreground: Theme.rest, background: Theme.rest.opacity(0.16))
        case (false, .none): Pill(text: "Unplanned", foreground: Theme.muted, background: Theme.raised)
        }
    }
}

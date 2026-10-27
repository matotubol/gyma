import SwiftUI
import GymaCore

/// Form section: last time, a "same / heavier" kg pick and a verdict on the chosen weight.
struct KgSuggestSection: View {
    let exercise: LibraryExercise
    let before: String
    let reps: String
    let kg: String
    var autoFill = false
    let onPick: (String) -> Void

    private enum Load { case loading, firstTime, failed, loaded(ExerciseHistory) }

    @EnvironmentObject private var model: AppModel
    @State private var load: Load = .loading
    @State private var filled = false

    var body: some View {
        Section {
            switch load {
            case .loading:
                HStack { Text("Checking last time…").foregroundStyle(.secondary); Spacer(); ProgressView() }
            case .failed:
                Text("Couldn’t load your history.").foregroundStyle(.secondary)
            case .firstTime:
                Label("First time. Today sets your baseline.", systemImage: "sparkles")
            case .loaded(let history):
                loaded(history)
            }
        } header: {
            Text("Suggestion")
        } footer: {
            if case .loaded(let history) = load, let plan = plan(history) { Text(plan.reason) }
        }
        .task(id: exercise.id + before) { await fetch() }
    }

    @ViewBuilder
    private func loaded(_ history: ExerciseHistory) -> some View {
        LabeledContent("Last · \(DateText.dayMonth(history.lastDate))") {
            Text(history.lastSets.map(formatSet).joined(separator: " · ")).monospacedDigit()
        }
        if let plan = plan(history) {
            choice(plan, target: plan.repeatKg, push: false)
            choice(plan, target: plan.pushKg, push: true)
            if let verdict = judgeKg(plan, kg: parseNumber(kg) ?? .nan, reps: Int(reps) ?? 0), verdict.tone != .same {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verdict.title).fontWeight(.semibold)
                        Text(verdict.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: icon(verdict.tone)).foregroundStyle(color(verdict.tone))
                        .symbolEffect(.bounce, value: verdict.title)
                }
            }
        }
    }

    private func choice(_ plan: KgPlan, target: Double, push: Bool) -> some View {
        Button { onPick(formatKg(target)) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(push ? "Add \(formatKg(roundKg(target - plan.repeatKg))) kg" : "Same weight").foregroundStyle(Color.primary)
                    if (plan.recommend == .push) == push {
                        Text("Recommended").font(.caption).foregroundStyle(.tint)
                    }
                }
                Spacer()
                Text("\(formatKg(target)) kg").monospacedDigit().foregroundStyle(.secondary)
                Image(systemName: "checkmark").foregroundStyle(.tint).opacity(parseNumber(kg) == target ? 1 : 0)
            }
        }
    }

    private func plan(_ history: ExerciseHistory) -> KgPlan? {
        planKg(history, reps: Int(reps) ?? 0, equipment: exercise.equipment)
    }

    private func icon(_ tone: KgVerdict.Tone) -> String {
        switch tone {
        case .pr: "flame.fill"
        case .up: "arrow.up.circle.fill"
        case .same: "equal.circle.fill"
        case .down: "arrow.down.circle.fill"
        }
    }

    private func color(_ tone: KgVerdict.Tone) -> Color {
        switch tone {
        case .pr: Theme.pr
        case .up: .green
        case .same, .down: .secondary
        }
    }

    private func fetch() async {
        load = .loading
        guard let api = model.api else { load = .failed; return }
        do {
            guard let history = try await api.history(exerciseId: exercise.id, before: before) else { load = .firstTime; return }
            guard !Task.isCancelled else { return }
            load = .loaded(history)
            // A freshly chosen exercise with no load yet gets the recommended weight once.
            if autoFill, !filled, (parseNumber(kg) ?? 0) == 0, let plan = plan(history) {
                filled = true
                onPick(formatKg(plan.recommendedKg))
            }
        } catch {
            if !Task.isCancelled { load = .failed }
        }
    }
}

import SwiftUI
import GymaCore

/// Last time + a "same / heavier" pick for a planned load, and a live verdict on the chosen kg.
struct KgSuggestView: View {
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
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: exercise.id + before) { await fetch() }
    }

    @ViewBuilder
    private var content: some View {
        switch load {
        case .loading:
            Text("Checking last time…").font(.caption).foregroundStyle(Theme.faint)
        case .failed:
            EmptyView()
        case .firstTime:
            Label("First time. Today sets your baseline.", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        case .loaded(let history):
            loaded(history)
        }
    }

    private func loaded(_ history: ExerciseHistory) -> some View {
        let plan = planKg(history, reps: Int(reps) ?? 0, equipment: exercise.equipment)
        let chosenKg = parseNumber(kg) ?? .nan
        let verdict = plan.flatMap { judgeKg($0, kg: chosenKg, reps: Int(reps) ?? 0) }
        return VStack(alignment: .leading, spacing: 8) {
            (Text("Last · \(DateText.dayMonth(history.lastDate))  ").foregroundColor(Theme.muted)
             + Text(history.lastSets.map(formatSet).joined(separator: " · ")))
                .font(.caption)
                .monospacedDigit()
            if let plan {
                HStack(spacing: 8) {
                    chip(plan, target: plan.repeatKg, push: false, chosenKg: chosenKg)
                    chip(plan, target: plan.pushKg, push: true, chosenKg: chosenKg)
                }
                Text(plan.reason).font(.caption).foregroundStyle(Theme.muted)
            }
            if let verdict, verdict.tone != .same {
                VerdictRow(verdict: verdict)
            }
        }
    }

    private func chip(_ plan: KgPlan, target: Double, push: Bool, chosenKg: Double) -> some View {
        let chosen = chosenKg == target
        let recommended = (plan.recommend == .push) == push
        return Button { onPick(formatKg(target)) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if push {
                        Image(systemName: "arrow.up").font(.system(size: 10, weight: .bold))
                        Text("+\(formatKg(roundKg(target - plan.repeatKg))) kg")
                    } else {
                        Text("Same")
                    }
                    if recommended {
                        Text("Pick")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(push ? Theme.accent : Theme.muted)
                (Text(formatKg(target)).font(.system(size: 17, weight: .semibold)) + Text(" kg").font(.system(size: 11)))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(chosen ? Theme.accentDim : Theme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(chosen ? Theme.accent : Theme.line))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func fetch() async {
        load = .loading
        guard let api = model.api else { load = .failed; return }
        do {
            guard let history = try await api.history(exerciseId: exercise.id, before: before) else { load = .firstTime; return }
            guard !Task.isCancelled else { return }
            load = .loaded(history)
            // A freshly chosen exercise with no load yet gets the recommended weight once.
            if autoFill, !filled, (parseNumber(kg) ?? 0) == 0,
               let plan = planKg(history, reps: Int(reps) ?? 0, equipment: exercise.equipment) {
                filled = true
                onPick(formatKg(plan.recommendedKg))
            }
        } catch {
            if !Task.isCancelled { load = .failed }
        }
    }
}

private struct VerdictRow: View {
    let verdict: KgVerdict

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: verdict.tone == .pr ? 18 : 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.15), in: Circle())
                .symbolEffect(.bounce, value: verdict.title)
            VStack(alignment: .leading, spacing: 1) {
                Text(verdict.title).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                Text(verdict.detail).font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(verdict.tone == .pr ? Theme.prSurface : Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var icon: String {
        switch verdict.tone {
        case .pr: "flame.fill"
        case .up: "arrow.up"
        case .same: "equal"
        case .down: "arrow.down"
        }
    }

    private var color: Color {
        switch verdict.tone {
        case .pr: Theme.pr
        case .up: Theme.accent
        case .same, .down: Theme.muted
        }
    }
}

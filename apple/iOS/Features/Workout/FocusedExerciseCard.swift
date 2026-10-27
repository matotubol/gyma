import SwiftUI
import GymaCore

/// One exercise at a time: its sets as tiles, then start / log the current set.
struct FocusedExerciseCard: View {
    let session: WorkoutSession
    let exercise: SessionExercise
    @Binding var kg: String
    @Binding var reps: String
    let disabled: Bool
    let busy: Bool
    let onStartSet: () -> Void
    let onLogSet: () -> Void
    let onCancelSet: () -> Void
    let onLogCompleted: () -> Void
    let onEditSet: (String) -> Void
    let onShowExercises: () -> Void

    var body: some View {
        let analysis = analyseWorkout(session)
        let recorded = session.recordedSets(at: exercise.position)
        let completed = session.completedSets(at: exercise.position)
        let done = session.isDone(exercise)
        let active = session.activeSet
        let upcoming = active?.setNumber ?? session.nextSetNumber(at: exercise.position)
        let training = session.status == .active && !done
        let history = session.history(for: exercise.exerciseId)

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(exercise.library.detail.uppercased())
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    if done {
                        Text("✓ Done")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.done)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.doneSurface, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                Text(exercise.name).font(.system(size: 24, weight: .semibold))
                Text("Target \(exercise.plannedSets) × \(exercise.plannedReps) @ \(formatKg(exercise.plannedKg)) kg")
                    .font(.caption).monospacedDigit().foregroundStyle(Theme.muted)
                Group {
                    if let history {
                        Text("Last · \(DateText.dayMonth(history.lastDate))  ").foregroundColor(Theme.muted)
                            + Text(history.lastSets.map(formatSet).joined(separator: " · ")).foregroundColor(Theme.ink.opacity(0.85))
                    } else {
                        Text("First time · today sets your baseline").foregroundColor(Theme.muted)
                    }
                }
                .font(.caption)
                .monospacedDigit()
            }

            SetTiles(planned: exercise.plannedSets, plannedReps: exercise.plannedReps, recorded: recorded,
                     records: analysis.records, upcoming: training ? upcoming : nil, disabled: disabled, onEditSet: onEditSet)

            if let active {
                HStack(spacing: 10) {
                    NumberStepper(label: "kg", value: $kg, step: kgStep(exercise.equipment), decimal: true, large: true)
                    NumberStepper(label: "reps", value: $reps, step: 1, range: 0...1000, large: true)
                }
                .disabled(disabled)
                hint(history: history, upcoming: upcoming, baseline: analysis.baselines[exercise.exerciseId])
                Button(action: onLogSet) { Text(busy ? "Saving…" : "Log set \(active.setNumber)") }
                    .buttonStyle(.primary)
                    .disabled(disabled)
                Button("Cancel set", action: onCancelSet)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .disabled(disabled)
            } else if training {
                hint(history: history, upcoming: upcoming, baseline: analysis.baselines[exercise.exerciseId])
                Button(action: onStartSet) { Text(busy ? "Starting…" : "Start set \(upcoming)") }
                    .buttonStyle(.primary)
                    .disabled(disabled)
            } else if !done {
                Button("Log completed set", action: onLogCompleted)
                    .buttonStyle(.primary)
                    .disabled(disabled || completed.count >= 100)
            } else {
                Button("Choose next exercise", action: onShowExercises)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
                    .disabled(disabled)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line.opacity(0.6)))
    }

    /// "Last time set 2: 80 × 8" and "★ 9 reps at 80 kg = PR".
    @ViewBuilder
    private func hint(history: ExerciseHistory?, upcoming: Int, baseline: Baseline?) -> some View {
        let lastTime = history.flatMap { $0.lastSets.indices.contains(upcoming - 1) ? $0.lastSets[upcoming - 1] : nil }
        let chosenKg = parseNumber(kg) ?? .nan
        let target = repsForRecord(baseline, kg: chosenKg)
        if lastTime != nil || target != nil {
            HStack(spacing: 8) {
                if let lastTime {
                    (Text("Last time set \(upcoming): ").foregroundColor(Theme.muted) + Text(formatSet(lastTime)).bold())
                }
                Spacer(minLength: 0)
                if let target {
                    Text(target == .any ? "★ Any rep at \(formatKg(chosenKg)) kg = PR" : "★ \(targetReps(target)) reps at \(formatKg(chosenKg)) kg = PR")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.pr)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.prSurface, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .font(.caption)
            .monospacedDigit()
        }
    }

    private func targetReps(_ target: RecordTarget) -> Int {
        if case .reps(let count) = target { return count }
        return 1
    }
}

private struct SetTiles: View {
    let planned: Int
    let plannedReps: Int
    let recorded: [PerformedSet]
    let records: [String: SetRecord]
    let upcoming: Int?
    let disabled: Bool
    let onEditSet: (String) -> Void

    var body: some View {
        let total = max(planned, recorded.map(\.setNumber).max() ?? 0)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(1...max(total, 1), id: \.self) { number in
                    tile(number, set: recorded.first { $0.setNumber == number })
                        .frame(width: 62, height: 64)
                }
            }
            .padding(.vertical, 1)
        }
    }

    @ViewBuilder
    private func tile(_ number: Int, set: PerformedSet?) -> some View {
        if let set, set.status == .completed {
            let record = records[set.id] != nil
            Button { onEditSet(set.id) } label: {
                VStack(spacing: 2) {
                    Text("\(number)\(record ? " ★" : " ✓")").font(.system(size: 10, weight: .medium))
                    (Text(formatKg(set.actualKg ?? 0)).font(.system(size: 16, weight: .semibold))
                     + Text("×\(set.actualReps ?? 0)").font(.system(size: 11)))
                        .monospacedDigit()
                }
                .foregroundStyle(record ? Theme.pr : Theme.done)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(record ? Theme.prSurface : Theme.doneSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(record ? Theme.pr.opacity(0.5) : .clear))
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .accessibilityLabel("Set \(number): \(formatKg(set.actualKg ?? 0)) kg × \(set.actualReps ?? 0) reps\(record ? ", personal record" : "")\(set.recordedManually ? ", logged afterwards" : ""). Edit set")
        } else if let set, set.status == .active {
            VStack(spacing: 2) {
                Text("\(number)").font(.system(size: 10, weight: .medium))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(clock(since: set.startedAt, now: context.date)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                }
            }
            .foregroundStyle(Theme.canvas)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel("Set \(number) running")
        } else {
            let next = number == upcoming
            VStack(spacing: 2) {
                Text("\(number)").font(.system(size: 10, weight: .medium))
                Text(next ? "Next" : "×\(plannedReps)").font(.system(size: next ? 12 : 11, weight: next ? .semibold : .regular))
            }
            .foregroundStyle(next ? Theme.accent : Theme.faint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(next ? Theme.accent.opacity(0.7) : Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }

    private func clock(since start: String, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(parseTimestamp(start) ?? now)))
        return String(format: "%02ld:%02ld", seconds / 60, seconds % 60)
    }
}

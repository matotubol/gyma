import SwiftUI
import Charts
import GymaCore

/// Charts one library exercise's heaviest set, most reps or volume per workout date.
struct ProgressScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var exercise: LibraryExercise?
    @State private var data: ExerciseProgress?
    @State private var loading = false
    @State private var error: String?
    @State private var retry = 0
    @State private var metric: Metric?
    @State private var selectedDate: String?
    @State private var showAll = false
    @State private var picking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    exerciseButton
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: "\(exercise?.id ?? "")|\(model.historyRevision)|\(retry)") { await load() }
            .sheet(isPresented: $picking) {
                ExercisePickerSheet(allowCreate: false) { chosen in
                    exercise = chosen
                    data = nil; metric = nil; selectedDate = nil; showAll = false
                }
                .environmentObject(model)
            }
        }
    }

    private var exerciseButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Exercise").font(.caption).foregroundStyle(Theme.muted)
            Button { picking = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise?.name ?? "Choose exercise").font(.subheadline.weight(.semibold))
                            .foregroundStyle(exercise == nil ? Theme.muted : Theme.ink)
                        if let exercise { Text(exercise.detail).font(.caption).foregroundStyle(Theme.muted) }
                    }
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var content: some View {
        let sessions = data?.exercise.id == exercise?.id ? data?.sessions ?? [] : []
        if let exercise {
            if loading && sessions.isEmpty {
                ProgressView("Loading progress…").frame(maxWidth: .infinity).padding(.vertical, 32)
            } else if let error {
                ErrorBanner(message: error, actionTitle: "Retry") { retry += 1 }
            } else if sessions.isEmpty {
                EmptyProgress(title: "No recorded sets yet", text: "Log a set of \(exercise.name) in a workout to start tracking it here.")
            } else {
                charts(exercise, sessions)
            }
        } else {
            EmptyProgress(title: "See your progress", text: "Your recorded sets will build a picture of how your weight, reps and volume change.", icon: true)
        }
    }

    @ViewBuilder
    private func charts(_ exercise: LibraryExercise, _ sessions: [ExerciseProgressPoint]) -> some View {
        let metric = self.metric ?? (sessions.contains { $0.bestKg > 0 } ? .bestKg : .maxReps)
        let best = sessions.map(metric.value).max() ?? 0
        let records = recordDates(sessions, metric)
        let latest = sessions.last
        let previous = sessions.count > 1 ? sessions[sessions.count - 2] : nil
        let delta = latest.flatMap { latest in previous.map { roundKg(metric.value(latest) - metric.value($0)) } }
        let selected = sessions.first { $0.date == selectedDate } ?? latest

        Picker("Metric", selection: Binding(get: { metric }, set: { self.metric = $0 })) {
            ForEach(Metric.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)

        HStack(spacing: 0) {
            stat("Best \(metric.label.lowercased())", value: formatNumber(best), unit: metric.unit)
            Divider().overlay(Theme.line)
            stat("Latest vs previous", value: delta.map { "\($0 > 0 ? "+" : "")\(formatNumber($0))" } ?? "—",
                 unit: delta == nil ? "First session" : metric.unit, positive: (delta ?? 0) > 0)
        }
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(metric.label) over time").font(.subheadline.weight(.semibold))
                Spacer()
                Group {
                    if !records.isEmpty {
                        Text("★ \(records.count) \(records.count == 1 ? "PR" : "PRs")").foregroundColor(Theme.pr).bold() + Text(" · ")
                    }
                    Text("\(sessions.count) \(sessions.count == 1 ? "session" : "sessions")")
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            }
            Text(metric.explanation).font(.caption).foregroundStyle(Theme.muted)

            ProgressChart(sessions: sessions, metric: metric, best: best, records: records, selectedDate: selected?.date) { selectedDate = $0 }
                .frame(height: 190)

            if let selected {
                Divider().overlay(Theme.line)
                HStack {
                    Text("\(DateText.long(selected.date)) · \(selected.sets) \(selected.sets == 1 ? "set" : "sets")")
                        .font(.caption).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("\(formatNumber(metric.value(selected))) \(metric.unit)")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent).monospacedDigit()
                }
            }
            if sessions.count == 1 {
                Text("Your first session is the starting point. Log another to see a trend.").font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .card(padding: 14)

        VStack(alignment: .leading, spacing: 0) {
            Text("Recent sessions").font(.subheadline.weight(.semibold)).padding(.bottom, 8)
            ForEach(Array(sessions.reversed().prefix(showAll ? 100 : 8))) { session in
                Button { model.open(session.date) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DateText.long(session.date)).font(.subheadline).foregroundStyle(Theme.ink)
                            Text("\(session.sets) \(session.sets == 1 ? "set" : "sets") · \(formatNumber(session.volume)) kg volume")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 6) {
                                if records.contains(session.date) { PRChip() }
                                Text(session.bestKg > 0 ? "\(formatNumber(session.bestKg)) kg × \(session.bestReps)" : "\(session.maxReps) reps")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).monospacedDigit()
                            }
                            Text(session.bestKg > 0 ? "Heaviest set" : "Most reps").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens that day’s workout")
                Divider().overlay(Theme.line)
            }
            if sessions.count > 8 {
                Button(showAll ? "Show fewer sessions" : "Show all \(sessions.count) sessions") { showAll.toggle() }
                    .font(.caption.weight(.semibold))
                    .padding(.top, 10)
            }
        }
        .padding(.top, 8)
    }

    private func stat(_ title: String, value: String, unit: String, positive: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.muted)
            (Text(value).font(.system(size: 20, weight: .semibold)).foregroundColor(positive ? Theme.accent : Theme.ink)
             + Text(" \(unit)").font(.system(size: 11)).foregroundColor(Theme.muted))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Sessions that beat every earlier session on the metric (the first one only sets the baseline).
    private func recordDates(_ sessions: [ExerciseProgressPoint], _ metric: Metric) -> Set<String> {
        var best = -Double.infinity
        var dates = Set<String>()
        for (index, point) in sessions.enumerated() {
            let value = metric.value(point)
            if index > 0 && value > best { dates.insert(point.date) }
            best = max(best, value)
        }
        return dates
    }

    private func load() async {
        guard let exercise, let api = model.api else { return }
        loading = true; error = nil
        do {
            let result = try await api.progress(exerciseId: exercise.id)
            guard !Task.isCancelled, result.exercise.id == self.exercise?.id else { return }
            data = result
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "Couldn’t load exercise progress. Please try again."
        }
        loading = false
    }
}

enum Metric: String, CaseIterable, Identifiable {
    case bestKg, maxReps, volume

    var id: Self { self }
    var label: String {
        switch self {
        case .bestKg: "Weight"
        case .maxReps: "Reps"
        case .volume: "Volume"
        }
    }
    var unit: String { self == .maxReps ? "reps" : "kg" }
    var explanation: String {
        switch self {
        case .bestKg: "Heaviest set with at least one completed rep per day."
        case .maxReps: "Most reps in a single set per day."
        case .volume: "Total kg lifted (weight × reps) across all sets per day."
        }
    }
    func value(_ point: ExerciseProgressPoint) -> Double {
        switch self {
        case .bestKg: point.bestKg
        case .maxReps: Double(point.maxReps)
        case .volume: point.volume
        }
    }
}

private struct ProgressChart: View {
    let sessions: [ExerciseProgressPoint]
    let metric: Metric
    let best: Double
    let records: Set<String>
    let selectedDate: String?
    let onSelect: (String) -> Void
    @State private var rawSelection: Date?

    var body: some View {
        Chart {
            ForEach(sessions) { point in
                LineMark(x: .value("Date", CivilDate.parse(point.date)), y: .value(metric.label, metric.value(point)))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            ForEach(sessions) { point in
                let record = records.contains(point.date)
                let selected = point.date == selectedDate
                PointMark(x: .value("Date", CivilDate.parse(point.date)), y: .value(metric.label, metric.value(point)))
                    .foregroundStyle(record ? Theme.pr : Theme.accent)
                    .symbolSize(selected ? 110 : record ? 70 : 30)
            }
        }
        .chartYScale(domain: 0...max(best, 1))
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, best / 2, best]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 4])).foregroundStyle(Theme.line)
                AxisValueLabel {
                    if let number = value.as(Double.self) { Text(formatNumber(number)).font(.system(size: 10)).foregroundStyle(Theme.muted) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.muted)
            }
        }
        .chartXSelection(value: $rawSelection)
        .onChange(of: rawSelection) { _, date in
            guard let date, let nearest = sessions.min(by: {
                abs(CivilDate.parse($0.date).timeIntervalSince(date)) < abs(CivilDate.parse($1.date).timeIntervalSince(date))
            }) else { return }
            if nearest.date != selectedDate { onSelect(nearest.date); Haptics.tap() }
        }
        .accessibilityLabel("\(metric.label) by workout date")
    }
}

private struct EmptyProgress: View {
    let title: String
    let text: String
    var icon = false

    var body: some View {
        VStack(spacing: 10) {
            if icon {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 60, height: 60)
                    .background(Theme.accentDim, in: Circle())
            }
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 16)
    }
}

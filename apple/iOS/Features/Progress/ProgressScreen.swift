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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ExercisePickerList(allowCreate: false) { chosen in
                            exercise = chosen
                            data = nil; metric = nil; selectedDate = nil; showAll = false
                        }
                    } label: {
                        LabeledContent("Exercise") {
                            Text(exercise?.name ?? "Choose").foregroundStyle(exercise == nil ? Color.accentColor : Color.secondary)
                        }
                    }
                } footer: {
                    if let exercise { Text(exercise.detail) }
                }
                content
            }
            .refreshable { retry += 1 }
            .navigationTitle("Progress")
            .task(id: "\(exercise?.id ?? "")|\(model.historyRevision)|\(retry)") { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        let sessions = data?.exercise.id == exercise?.id ? data?.sessions ?? [] : []
        if let exercise {
            if loading && sessions.isEmpty {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Try Again") { retry += 1 }
                }
            } else if sessions.isEmpty {
                Section {
                    ContentUnavailableView("No Recorded Sets", systemImage: "tray",
                                           description: Text("Log a set of \(exercise.name) in a workout to start tracking it."))
                }
            } else {
                charts(sessions)
            }
        } else {
            Section {
                ContentUnavailableView("See Your Progress", systemImage: "chart.xyaxis.line",
                                       description: Text("Choose an exercise to chart how your weight, reps and volume change."))
            }
        }
    }

    @ViewBuilder
    private func charts(_ sessions: [ExerciseProgressPoint]) -> some View {
        let metric = self.metric ?? (sessions.contains { $0.bestKg > 0 } ? .bestKg : .maxReps)
        let best = sessions.map(metric.value).max() ?? 0
        let records = recordDates(sessions, metric)
        let latest = sessions.last
        let previous = sessions.count > 1 ? sessions[sessions.count - 2] : nil
        let delta = latest.flatMap { latest in previous.map { roundKg(metric.value(latest) - metric.value($0)) } }
        let selected = sessions.first { $0.date == selectedDate } ?? latest

        Section {
            Picker("Metric", selection: Binding(get: { metric }, set: { self.metric = $0 })) {
                ForEach(Metric.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }

        Section {
            LabeledContent("Best \(metric.label.lowercased())", value: "\(formatNumber(best)) \(metric.unit)")
            LabeledContent("Latest vs previous") {
                if let delta {
                    Text("\(delta > 0 ? "+" : "")\(formatNumber(delta)) \(metric.unit)")
                        .foregroundStyle(delta > 0 ? Color.green : Color.secondary)
                } else {
                    Text("First session")
                }
            }
            LabeledContent("Personal records", value: "\(records.count)")
        }
        .monospacedDigit()

        Section {
            ProgressChart(sessions: sessions, metric: metric, best: best, records: records, selectedDate: selected?.date) { selectedDate = $0 }
                .frame(height: 200)
                .padding(.vertical, 8)
            if let selected {
                LabeledContent("\(DateText.long(selected.date)) · \(selected.sets) \(selected.sets == 1 ? "set" : "sets")",
                               value: "\(formatNumber(metric.value(selected))) \(metric.unit)")
                    .monospacedDigit()
            }
        } header: {
            Text("\(metric.label) over time")
        } footer: {
            Text(sessions.count == 1 ? "\(metric.explanation) Log another session to see a trend." : metric.explanation)
        }

        Section("Recent Sessions") {
            ForEach(Array(sessions.reversed().prefix(showAll ? 100 : 8))) { session in
                Button { model.open(session.date) } label: {
                    LabeledContent {
                        HStack(spacing: 4) {
                            if records.contains(session.date) { Image(systemName: "star.fill").foregroundStyle(Theme.pr) }
                            Text(session.bestKg > 0 ? "\(formatNumber(session.bestKg)) kg × \(session.bestReps)" : "\(session.maxReps) reps")
                                .monospacedDigit()
                        }
                    } label: {
                        Text(DateText.long(session.date)).foregroundStyle(Color.primary)
                        Text("\(session.sets) \(session.sets == 1 ? "set" : "sets") · \(formatNumber(session.volume)) kg volume")
                    }
                }
                .accessibilityHint("Opens that day’s workout")
            }
            if sessions.count > 8 {
                Button(showAll ? "Show Fewer" : "Show All \(sessions.count)") { showAll.toggle() }
            }
        }
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
            self.error = "Couldn’t load progress."
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
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)
            }
            ForEach(sessions) { point in
                let record = records.contains(point.date)
                PointMark(x: .value("Date", CivilDate.parse(point.date)), y: .value(metric.label, metric.value(point)))
                    .foregroundStyle(record ? Theme.pr : Color.accentColor)
                    .symbolSize(point.date == selectedDate ? 120 : record ? 70 : 30)
            }
            if let selectedDate {
                RuleMark(x: .value("Selected", CivilDate.parse(selectedDate)))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: 0...max(best, 1))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
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

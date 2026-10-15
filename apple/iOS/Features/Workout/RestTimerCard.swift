import SwiftUI
import GymaCore

struct RestTimerCard: View {
    @EnvironmentObject private var model: GymaAppModel
    let timer: RestTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(ceil(timer.remaining(at: context.date))))
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(seconds > 0 ? "Take a breath" : "Ready when you are", systemImage: "timer")
                            .font(.headline)
                        Text(model.name(for: timer.exerciseID)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityLabel("\(seconds) seconds remaining")
                }
                HStack {
                    Button { model.update { try $0.extendRest(timerID: timer.id) } } label: {
                        Label("30 seconds", systemImage: "plus")
                    }.buttonStyle(.bordered)
                    Spacer()
                    Button("Start next set") { model.update { try $0.skipRest(timerID: timer.id) } }
                        .buttonStyle(.borderedProminent)
                }
                Text("Rested \(Int(max(0, min(86400, context.date.timeIntervalSince(timer.startedAt))))) sec · Tap when you actually start your next set.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(18)
            .background(GymaStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

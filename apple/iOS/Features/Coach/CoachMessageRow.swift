import SwiftUI
import GymaCore

struct CoachMessageRow: View {
    let message: CoachMessage

    var body: some View {
        let isCoach = message.role == .assistant
        return VStack(alignment: .leading, spacing: 7) {
            Text(isCoach ? "GPT-6.1 Sol" : "You")
                .font(.caption.weight(.semibold)).foregroundStyle(isCoach ? GymaStyle.accent : .secondary)
            Text(message.content).font(.body).textSelection(.enabled)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(isCoach ? GymaStyle.card : GymaStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
        .padding(isCoach ? .trailing : .leading, 18)
    }
}

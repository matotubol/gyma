import SwiftUI
import GymaCore

struct CoachAppChangesCard: View {
    @EnvironmentObject private var model: GymaAppModel
    let proposal: CoachAppChangeProposal
    var onApplied: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("CHANGES TO REVIEW", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.bold)).foregroundStyle(GymaStyle.accent)
            Text("Apply these changes together").font(.title2.bold())
            ForEach(Array(proposal.summaries.enumerated()), id: \.offset) { _, summary in
                Text(summary).font(.subheadline).textSelection(.enabled)
                Divider()
            }
            if !model.canApplyCoachAppChanges && !model.coachRequestInFlight {
                Text("Your data changed after this proposal. Ask the coach to refresh it before applying.")
                    .font(.subheadline).foregroundStyle(.orange)
                Button("Refresh changes", systemImage: "arrow.clockwise") {
                    _ = model.sendCoachMessage("Refresh your proposed app changes using my latest saved data. Keep my requested changes, look up anything that changed, and show an updated proposal.")
                }
                .buttonStyle(.bordered)
                .disabled(model.storageBlocked || !model.hasCoachAPIKey)
            }
            Button {
                if model.applyCoachAppChanges(proposal) { onApplied() }
            } label: {
                Label("Apply changes", systemImage: "checkmark")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canApplyCoachAppChanges)
            Button("Dismiss proposal") { model.discardCoachAppChanges() }
                .disabled(model.coachRequestInFlight || model.storageBlocked)
            Text("You can describe corrections in the chat before applying.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

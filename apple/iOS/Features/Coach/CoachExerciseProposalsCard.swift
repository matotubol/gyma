import SwiftUI
import GymaCore

struct CoachExerciseProposalsCard: View {
    @EnvironmentObject private var model: GymaAppModel
    let proposals: [CoachExerciseProposal]
    var onSaved: () -> Void

    private var conversation: CoachConversation? { model.state.coachConversation }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("EXERCISES TO REVIEW", systemImage: "dumbbell")
                .font(.caption.weight(.bold)).foregroundStyle(GymaStyle.accent)
            Text("Check these match your equipment and movement. Describe any corrections in the chat below before saving.")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(proposals) { proposal in
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    Text(proposal.exercise.name).font(.headline)
                    LabeledContent("Soreness region", value: proposal.exercise.muscle.label)
                    if let metadata = proposal.exercise.trainingMetadata {
                        LabeledContent("Main muscles", value: metadata.primaryMuscles.map(\.label).joined(separator: ", "))
                        LabeledContent("Secondary muscles", value: metadata.secondaryMuscles.isEmpty ? "None specified" : metadata.secondaryMuscles.map(\.label).joined(separator: ", "))
                        LabeledContent("Equipment", value: metadata.equipment?.label ?? "Not specified")
                        LabeledContent("How to log weight", value: metadata.loadConvention.label)
                        LabeledContent("Measurement", value: metadata.measurement == .seconds ? "Seconds" : "Repetitions")
                    } else {
                        Text("Muscle, equipment and weight details are not specified. Ask your coach to clarify these before saving.")
                            .foregroundStyle(.secondary)
                    }
                    Text(proposal.explanation).foregroundStyle(.secondary)
                }.font(.subheadline)
            }
            Text("Saving adds these exercises to your library so the coach can use them in your program. You will review the program separately.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                if model.acceptCoachExercises(proposals) { onSaved() }
            } label: {
                Label("Save exercises & continue", systemImage: "checkmark")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.storageBlocked || model.coachRequestInFlight || model.state.activeWorkout != nil ||
                      conversation?.proposedExercises != proposals || conversation?.messages.last?.role != .assistant)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

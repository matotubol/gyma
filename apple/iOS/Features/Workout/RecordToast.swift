import SwiftUI
import GymaCore

/// Celebrates a personal record. The big ones are loud.
struct RecordToast: View {
    let celebration: Celebration
    let onDismiss: () -> Void
    @State private var popped = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: celebration.monster ? "flame.fill" : "trophy.fill")
                .font(.title2)
                .foregroundStyle(celebration.monster ? Color.white : Theme.pr)
                .frame(width: 44, height: 44)
                .background(celebration.monster ? Theme.pr : Theme.pr.opacity(0.18), in: Circle())
                .scaleEffect(popped ? 1 : 0.4)
                .symbolEffect(.bounce, value: popped)
            VStack(alignment: .leading, spacing: 2) {
                Text(celebration.title).font(.headline)
                Text(celebration.detail).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        .onTapGesture(perform: onDismiss)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { popped = true } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Dismiss")
    }
}

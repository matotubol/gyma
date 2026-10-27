import SwiftUI
import GymaCore

/// Celebrates a personal record. The big ones are loud.
struct RecordToast: View {
    let celebration: Celebration
    let onDismiss: () -> Void
    @State private var popped = false

    var body: some View {
        let monster = celebration.monster
        HStack(spacing: 12) {
            ZStack {
                Circle().fill((monster ? Theme.canvas : Theme.pr).opacity(0.15))
                Image(systemName: monster ? "flame.fill" : "trophy.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .scaleEffect(popped ? 1 : 0.4)
                    .symbolEffect(.bounce, value: popped)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(celebration.title).font(.system(size: 15, weight: .bold))
                Text(celebration.detail).font(.caption).monospacedDigit().opacity(0.85)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.caption.weight(.semibold)).frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .opacity(0.7)
            .accessibilityLabel("Dismiss")
        }
        .foregroundStyle(monster ? Theme.canvas : Theme.pr)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(monster ? Theme.pr : Theme.prSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.pr.opacity(monster ? 1 : 0.4)))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { popped = true } }
        .accessibilityElement(children: .combine)
    }
}

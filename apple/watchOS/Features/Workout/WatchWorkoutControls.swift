import SwiftUI

struct WatchWorkoutButton: View {
    let title: String
    let symbol: String
    let subtitle: String?
    let action: () -> Void

    init(_ title: String, symbol: String, subtitle: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.subtitle = subtitle
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Label(title, systemImage: symbol).font(.headline)
                if let subtitle { Text(subtitle).font(.caption2) }
            }
        }
        .buttonStyle(WatchPrimaryButtonStyle())
    }
}

struct WatchWorkoutEyebrow: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.2).foregroundStyle(.mint)
    }
}

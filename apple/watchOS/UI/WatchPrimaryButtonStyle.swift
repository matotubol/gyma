import SwiftUI

struct WatchPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isEnabled ? Color.mint : Color.white.opacity(0.12), in: Capsule())
            .foregroundStyle(isEnabled ? Color.black : Color.gray)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

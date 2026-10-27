import UIKit

@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }

    /// A personal record. The big ones get a longer burst.
    static func record(monster: Bool) {
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        heavy.prepare()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let beats: [Double] = monster ? [0.12, 0.24, 0.42] : [0.14]
        for delay in beats {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { heavy.impactOccurred() }
        }
    }
}

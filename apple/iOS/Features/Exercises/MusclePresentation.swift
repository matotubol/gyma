import SwiftUI
import GymaCore

extension Muscle {
    var tint: Color {
        switch self {
        case .chest: return .red
        case .back: return .blue
        case .legs: return .green
        case .shoulders: return .orange
        case .arms: return .purple
        case .core: return .teal
        }
    }
}

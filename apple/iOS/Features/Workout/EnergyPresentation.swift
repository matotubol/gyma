import GymaCore

extension Energy {
    var symbol: String {
        switch self {
        case .great: return "flame.fill"
        case .good: return "sun.max.fill"
        case .medium: return "cloud.sun.fill"
        case .poor: return "moon.fill"
        }
    }
}

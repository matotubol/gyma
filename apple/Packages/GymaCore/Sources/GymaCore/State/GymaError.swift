import Foundation

public enum GymaError: Error, LocalizedError, Equatable {
    case invalid(String)
    case stale(String)
    public var errorDescription: String? { switch self { case .invalid(let message), .stale(let message): return message } }
}

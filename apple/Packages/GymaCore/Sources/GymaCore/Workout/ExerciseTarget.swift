import Foundation

public struct ExerciseTarget: Codable, Sendable, Equatable {
    public var sets: Int
    public var repsMin: Int
    public var repsMax: Int
    public var loadKg: Double?
    public var restSeconds: Int
    public var reason: String
    public var targetEffort: SetEffort?
    public init(sets: Int, repsMin: Int, repsMax: Int, loadKg: Double? = nil, restSeconds: Int = 90, reason: String = "", targetEffort: SetEffort? = nil) {
        self.sets = sets; self.repsMin = repsMin; self.repsMax = repsMax; self.loadKg = loadKg; self.restSeconds = restSeconds; self.reason = reason; self.targetEffort = targetEffort
    }
    public func validate() throws {
        guard (1...10).contains(sets), (1...50).contains(repsMin), repsMax >= repsMin, repsMax <= 50,
              (15...600).contains(restSeconds), reason.count <= 2000, loadKg.map({ $0.isFinite && (0...1000).contains($0) }) ?? true else {
            throw GymaError.invalid("Invalid exercise target.")
        }
    }
}

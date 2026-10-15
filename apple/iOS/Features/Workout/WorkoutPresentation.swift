import Foundation
import GymaCore

extension Workout {
    var title: String { planTitle?.isEmpty == false ? planTitle! : "Workout" }
    func minutes(at date: Date = Date()) -> Int { Int(duration(at: date) / 60) }
}

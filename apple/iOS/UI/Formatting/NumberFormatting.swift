import Foundation

extension Double {
    var gymaNumber: String { formatted(.number.precision(.fractionLength(0...1))) }
}

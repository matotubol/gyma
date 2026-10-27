import Foundation

/// Reads a typed number, accepting a decimal comma from regional keyboards.
func parseNumber(_ text: String) -> Double? {
    Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
}

/// Reads a whole number within bounds, or nil.
func parseCount(_ text: String, in range: ClosedRange<Int>) -> Int? {
    guard let value = Int(text.trimmingCharacters(in: .whitespaces)), range.contains(value) else { return nil }
    return value
}

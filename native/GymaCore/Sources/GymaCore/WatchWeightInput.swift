import Foundation

/// Weight entry uses an ungrouped decimal, independently of the device locale.
public enum WatchWeightInput {
    public static func parse(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 512 else { return nil }
        var digits = 0
        var separators = 0
        for byte in value.utf8 {
            switch byte {
            case 48...57: digits += 1
            case 44, 46: separators += 1
            default: return nil
            }
        }
        guard digits > 0, separators <= 1,
              let number = Double(value.replacingOccurrences(of: ",", with: ".")),
              number.isFinite, (0...1000).contains(number) else { return nil }
        // Do not silently turn an unrepresentably small positive entry into bodyweight.
        if number == 0 && value.utf8.contains(where: { (49...57).contains($0) }) { return nil }
        return number
    }

    /// Returns an empty string for unsupported values. Expand the exponent in
    /// Swift's round-trip representation so existing fractional weights stay exact.
    public static func text(for value: Double) -> String {
        guard value.isFinite, (0...1000).contains(value) else { return "" }
        if value == 0 { return "0" }
        let representation = String(value)
        let exponentParts = representation.lowercased().split(separator: "e")
        guard exponentParts.count == 2, let exponent = Int(exponentParts[1]) else {
            return representation.hasSuffix(".0") ? String(representation.dropLast(2)) : representation
        }
        let mantissa = exponentParts[0].split(separator: ".", omittingEmptySubsequences: false)
        let digits = mantissa.joined()
        let decimalPosition = mantissa[0].count + exponent
        if decimalPosition <= 0 { return "0." + String(repeating: "0", count: -decimalPosition) + digits }
        if decimalPosition >= digits.count { return digits + String(repeating: "0", count: decimalPosition - digits.count) }
        let separator = digits.index(digits.startIndex, offsetBy: decimalPosition)
        return String(digits[..<separator]) + "." + String(digits[separator...])
    }
}

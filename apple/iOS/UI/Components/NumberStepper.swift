import SwiftUI
import GymaCore

/// A number field with − / + buttons, so a set can be adjusted without opening the keyboard.
struct NumberStepper: View {
    let label: String
    @Binding var value: String
    let step: Double
    var range: ClosedRange<Double> = 0...10000
    var decimal = false
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 0) {
                bumpButton("minus", direction: -1)
                    .disabled((parseNumber(value) ?? range.lowerBound) <= range.lowerBound)
                TextField("0", text: $value)
                    .keyboardType(decimal ? .decimalPad : .numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: large ? 28 : 20, weight: .semibold))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                bumpButton("plus", direction: 1)
                    .disabled((parseNumber(value) ?? range.lowerBound) >= range.upperBound)
            }
            .frame(height: large ? 64 : 48)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
        }
    }

    private func bumpButton(_ symbol: String, direction: Double) -> some View {
        Button {
            let current = parseNumber(value) ?? range.lowerBound
            let next = min(range.upperBound, max(range.lowerBound, current + direction * step))
            value = formatKg(roundKg(next))
            Haptics.tap()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: large ? 20 : 16, weight: .medium))
                .frame(width: 48)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.muted)
        .accessibilityLabel("\(label) \(direction > 0 ? "plus" : "minus") \(formatKg(step))")
    }
}

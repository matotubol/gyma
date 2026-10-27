import SwiftUI
import GymaCore

/// A form row with an editable number and a system stepper.
struct ValueStepper: View {
    let title: String
    @Binding var text: String
    let step: Double
    var range: ClosedRange<Double> = 0...10000
    var unit: String?
    var decimal = false
    var prominent = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            TextField("0", text: $text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .font(prominent ? .title2.weight(.semibold) : .body)
                .monospacedDigit()
                .frame(maxWidth: prominent ? 110 : 80)
            if let unit { Text(unit).foregroundStyle(.secondary) }
            Stepper(title, value: number, in: range, step: step)
                .labelsHidden()
                .fixedSize()
        }
    }

    private var number: Binding<Double> {
        Binding(
            get: { min(range.upperBound, max(range.lowerBound, parseNumber(text) ?? range.lowerBound)) },
            set: { text = formatKg(roundKg($0)) })
    }
}

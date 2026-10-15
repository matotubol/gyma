import SwiftUI

struct StatTile: View {
    let value: String
    let label: String
    var symbol: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !symbol.isEmpty {
                Image(systemName: symbol).foregroundStyle(GymaStyle.accent).font(.title3)
            }
            Text(value).font(.title2.bold()).monospacedDigit().minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

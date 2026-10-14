import SwiftUI

@MainActor
struct WatchRepsControl: View {
    let title: String
    let height: CGFloat
    @Binding var reps: Int

    var body: some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                adjustmentButton(-1, symbol: "minus")
                Text("\(reps)")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Reps")
                    .accessibilityValue("\(reps)")
                adjustmentButton(1, symbol: "plus")
            }
        }
    }

    private func adjustmentButton(_ delta: Int, symbol: String) -> some View {
        Button { reps = min(100, max(1, reps + delta)) } label: {
            Image(systemName: symbol).font(.title3.bold())
                .frame(width: 44, height: height)
                .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).foregroundStyle(.mint)
        .disabled(delta > 0 ? reps >= 100 : reps <= 1)
        .accessibilityLabel(delta > 0 ? "Increase reps" : "Decrease reps")
    }
}

enum WatchValueField: String, Identifiable {
    case preparedKg, expectedReps
    var id: String { rawValue }
    var title: String { self == .expectedReps ? "Expected reps" : "Set weight" }
}

@MainActor
struct WatchWeightReview: View {
    let height: CGFloat
    @Binding var kg: Double
    let isEnabled: Bool
    let confirm: (Double) -> Void

    var body: some View {
        VStack(spacing: 4) {
            WatchWeightPicker(kg: $kg, height: height).disabled(!isEnabled)
            Button { confirm(kg) } label: {
                Label("Confirm Weight", systemImage: "checkmark").font(.headline)
            }
            .buttonStyle(WatchPrimaryButtonStyle())
            .disabled(!isEnabled)
        }
    }
}

@MainActor
private struct WatchWeightPicker: View {
    @Binding var kg: Double
    let height: CGFloat
    @State private var originalKg: Double
    @FocusState private var focused: Bool

    init(kg: Binding<Double>, height: CGFloat) {
        _kg = kg; self.height = height
        _originalKg = State(initialValue: kg.wrappedValue)
    }

    private var values: [Double] {
        var values = (0...2000).map { Double($0) / 2 }
        // Keep an existing fractional load selectable without rounding it.
        if originalKg.truncatingRemainder(dividingBy: 0.5) != 0 {
            values.append(originalKg)
            values.sort()
        }
        return values
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("KG · turn Crown").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Picker("Kilograms", selection: $kg) {
                ForEach(values, id: \.self) { value in
                    Text(value.formatted(.number.grouping(.never)))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.65)
                        .tag(value)
                }
            }
            .pickerStyle(.wheel).labelsHidden().frame(height: height).focused($focused)
        }
        .onAppear { focused = true }
    }
}

@MainActor
struct WatchValueEditor: View {
    @Environment(\.dismiss) private var dismiss
    let field: WatchValueField
    @State private var kg: Double
    @State private var reps: Int
    @State private var error: String?
    let save: (Double, Int) throws -> Void

    init(field: WatchValueField, kg: Double, reps: Int, save: @escaping (Double, Int) throws -> Void) {
        self.field = field; _kg = State(initialValue: kg)
        _reps = State(initialValue: reps); self.save = save
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 8) {
                    if field == .expectedReps {
                        WatchRepsControl(title: "REPS", height: 64, reps: $reps)
                    } else {
                        WatchWeightPicker(kg: $kg, height: max(50, min(104, geometry.size.height - 72)))
                    }
                    Button(field == .expectedReps ? "Confirm Reps" : "Confirm Weight") {
                        do { try save(kg, reps); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                    .font(.headline).buttonStyle(WatchPrimaryButtonStyle())
                }
                .padding(.horizontal, 6)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
            }
            .navigationTitle(field.title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Could not save the change", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}

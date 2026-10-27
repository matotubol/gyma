import SwiftUI
import GymaCore

/// Semantic colours on top of the system palette. The app tint is the AccentColor asset.
enum Theme {
    static let pr = Color.orange
    static let training = Color.green
    static let rest = Color.blue
}

extension View {
    /// A "Done" key above number pads, which have no return key.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }

    /// A prominent button row inside a List or Form. Give its label `.frame(maxWidth: .infinity)`.
    func prominentRow() -> some View {
        buttonStyle(.borderedProminent)
            .controlSize(.large)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }
}

extension Optional where Wrapped == DayKind {
    var tint: Color {
        switch self {
        case .some(.training): Theme.training
        case .some(.rest): Theme.rest
        case .none: .secondary
        }
    }
}

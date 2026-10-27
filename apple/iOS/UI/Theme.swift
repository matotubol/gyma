import SwiftUI

/// gym-web's palette: a near-black base so colour only appears where it means something.
enum Theme {
    static let canvas = Color(hex: 0x0d0f0e)
    static let surface = Color(hex: 0x161918)
    static let raised = Color(hex: 0x1f2321)
    static let line = Color(hex: 0x2a2f2c)
    static let ink = Color(hex: 0xeef1ee)
    static let muted = Color(hex: 0x959e98)
    static let faint = Color(hex: 0x5d6560)
    /// Action: buttons, the current set, the active tab.
    static let accent = Color(hex: 0xb9e57a)
    static let accentDim = Color(hex: 0x24301c)
    /// Finished work: calm, so it never competes with what's next.
    static let done = Color(hex: 0x9fb4a5)
    static let doneSurface = Color(hex: 0x1c2420)
    /// Personal records and rewards.
    static let pr = Color(hex: 0xf4c64e)
    static let prSurface = Color(hex: 0x2c2513)
    static let training = Color(hex: 0x9ccc65)
    static let rest = Color(hex: 0x7f98bf)
    static let danger = Color(hex: 0xffb4a8)
    static let dangerSurface = Color(hex: 0x34201f)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

/// Rounded surface used for every card.
struct Card: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(Card(padding: padding)) }

    /// Dark canvas behind a scrolling screen.
    func screenBackground() -> some View {
        background(Theme.canvas.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.canvas)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

struct DashedButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(configuration.isPressed ? Theme.accentDim : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var primary: PrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == DashedButtonStyle { static var dashed: DashedButtonStyle { .init() } }

/// Inline error banner with an optional action.
struct ErrorBanner: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(message).frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.caption.weight(.semibold))
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.danger)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.dangerSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .tint(Theme.danger)
    }
}

/// Text field on a dark well with a hairline border.
struct InputField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
            .foregroundStyle(Theme.ink)
    }
}

extension View {
    func inputField() -> some View { modifier(InputField()) }

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
}

/// Small rounded label, e.g. the day kind or a PR marker.
struct Pill: View {
    let text: String
    var foreground: Color
    var background: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(background, in: Capsule())
    }
}

struct PRChip: View {
    var body: some View {
        Text("PR")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Theme.pr)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Theme.prSurface, in: RoundedRectangle(cornerRadius: 4))
    }
}

import SwiftUI

/// Colours and controls from the A1 mockup. Each colour has the mockup's light and dark value.
enum Theme {
    static let ink       = dynamic(light: 0x171a1f, dark: 0xeceff3)
    static let mute      = dynamic(light: 0x667080, dark: 0x8d97a6)
    // Tracks and dividers are see-through so the glass behind them shows (the mockup's solid greys were for a flat card).
    static let line      = dynamic(light: 0x000000, dark: 0xffffff, alpha: 0.12)
    static let fill      = dynamic(light: 0x000000, dark: 0xffffff, alpha: 0.09)
    static let accent    = dynamic(light: 0xe8590c, dark: 0xff7a2e)
    static let accentInk = dynamic(light: 0xffffff, dark: 0x1a0d03)
    static let good      = dynamic(light: 0x2f9e55, dark: 0x4cc073)
    static let danger    = Color(hex: 0xd92d20)

    static let width: CGFloat = 320
    static let corner: CGFloat = 14
    /// "More settings" fold: SwiftUI animates the rows and AppKit animates the window with this same duration and curve.
    static let foldDuration = 0.25
    static let fold = Animation.easeInOut(duration: foldDuration)

    private static func dynamic(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) {
            ($0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)).withAlphaComponent(alpha)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }
}

/// Segmented control: grey track, selected option filled with the accent.
/// One Tab stop for the whole control; ← and → move the selection.
struct Segments<T: Hashable>: View {
    let options: [(String, T)]
    let selection: T
    let onSelect: (T) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let on = options[i].1 == selection
                Text(options[i].0)
                    .font(.system(size: 11.5, weight: on ? .bold : .regular))
                    .foregroundStyle(on ? Theme.accentInk : Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(on ? Theme.accent : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(options[i].1) }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.fill))
        .focusable()
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
    }

    private func step(_ by: Int) -> KeyPress.Result {
        guard let i = options.firstIndex(where: { $0.1 == selection }) else { return .ignored }
        let j = min(max(i + by, 0), options.count - 1)
        if j != i { onSelect(options[j].1) }
        return .handled
    }
}

/// The mockup's switch: 36×21 track, 15 pt knob. Space toggles it when focused.
struct Switch: View {
    let isOn: Bool
    let onChange: (Bool) -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? Theme.accent : Theme.fill)
                .overlay(Capsule().stroke(isOn ? Theme.accent : Theme.line, lineWidth: 1))
            Circle().fill(isOn ? Theme.accentInk : Theme.mute).frame(width: 15, height: 15).padding(3)
        }
        .frame(width: 36, height: 21)
        .opacity(enabled ? 1 : 0.5)
        .contentShape(Capsule())
        .onTapGesture { onChange(!isOn) }
        .focusable()
        .onKeyPress(.space) { onChange(!isOn); return .handled }
    }
}

/// A label on the left, a switch on the right.
struct SwitchRow: View {
    let title: String
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Switch(isOn: isOn, onChange: onChange)
        }
    }
}

/// Full-width outlined button (Restore, Quit).
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(configuration.isPressed ? Theme.fill : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

struct BatteryGlyph: View {
    let percent: Int
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .stroke(Theme.mute, lineWidth: 1.5)
            .frame(width: 44, height: 10)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(percent <= 15 ? Theme.danger : Theme.good)
                    .frame(width: max(2, 39 * CGFloat(percent) / 100), height: 5)
                    .padding(.leading, 2.5)
            }
    }
}

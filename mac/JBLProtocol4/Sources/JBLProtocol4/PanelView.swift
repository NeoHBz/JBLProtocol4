import SwiftUI
import JBLKit

/// Layout A1 ("Fold-out"): daily controls on top, rarely used ones behind "More settings", power off in the footer.
struct PanelView: View {
    @EnvironmentObject var d: Device
    /// Reports the panel's natural height so the window can match it.
    var onHeight: (CGFloat) -> Void = { _ in }

    @State private var more = false
    @State private var armed = false
    @State private var armTask: Task<Void, Never>?
    @State private var balanceDraft = 0.0

    private var live: Bool { d.link == .ready }
    private func has(_ f: Product.Feature) -> Bool { Product.supports(f, pid: d.productID) }
    /// Noise modes the connected model lacks. Off is always there when any of the others is.
    private var noiseMissing: Set<NoiseMode> {
        Set([(NoiseMode.anc, Product.Feature.anc), (.ambient, .ambient), (.talkThru, .talkThru)].filter { !has($0.1) }.map(\.0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Segments(options: [("ANC", NoiseMode.anc), ("Ambient", .ambient), ("TalkThru", .talkThru), ("Off", .off)],
                     selection: d.noise, unavailable: noiseMissing, onSelect: d.setNoise)
                .available(noiseMissing.count < 3, live: live, model: d.productID)
            Divider().overlay(Theme.line)
            SwitchRow(title: "Voice Aware", isOn: d.voiceAware != nil) { d.setVoiceAware($0 ? .low : nil) }
                .available(has(.voiceAware), live: live, model: d.productID)
            if let level = d.voiceAware {
                Segments(options: [("Low", VoiceAwareLevel.low), ("Mid", .mid), ("High", .high)],
                         selection: level, onSelect: { d.setVoiceAware($0) })
                    .available(has(.voiceAware), live: live, model: d.productID)
            }
            SwitchRow(title: "Spatial Sound", isOn: d.spatial != nil) { d.setSpatial($0 ? .music : nil) }
                .available(has(.spatial), live: live, model: d.productID)
            if let mode = d.spatial {
                Segments(options: [("Music", SpatialMode.music), ("Movie", .movie), ("Game", .game)],
                         selection: mode, onSelect: { d.setSpatial($0) })
                    .available(has(.spatial), live: live, model: d.productID)
            }
            Divider().overlay(Theme.line)
            moreToggle
            if more { moreRows }
            footer
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Theme.ink)
        .padding(14)
        .frame(width: Theme.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: onHeight)
    }

    private var header: some View {
        HStack(spacing: 10) {
            productPicture
            VStack(alignment: .leading, spacing: 2) {
                Text(d.productID.flatMap(Product.name) ?? d.peripheralName ?? "JBL headphones").fontWeight(.bold)
                if let colour = d.colorID.flatMap(Product.colourName) {
                    Text(colour).font(.system(size: 11)).foregroundStyle(Theme.mute)
                }
            }
            Spacer()
            if live, let b = d.battery {
                HStack(spacing: 8) {
                    BatteryGlyph(percent: b)
                    Text("\(b)%").monospacedDigit()
                }
            }
        }
    }

    /// The model's photo in its reported colour; a headphones symbol when the build has no photos or the model has none.
    @ViewBuilder private var productPicture: some View {
        if let img = ProductImage.image(pid: d.productID, colorID: d.colorID) {
            Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .opacity(live ? 1 : 0.5)
        } else {
            Image(systemName: "headphones")
                .font(.system(size: 20))
                .foregroundStyle(Theme.mute)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.fill))
        }
    }

    private var moreToggle: some View {
        Button { withAnimation(Theme.fold) { more.toggle() } } label: {
            HStack {
                Text("More settings")
                Spacer()
                Text(more ? "−" : "+").monospaced()
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.mute)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    @ViewBuilder private var moreRows: some View {
        // Off also centres it: the slider has no marks, so an off-centre value kept from before would be hard to read later.
        SwitchRow(title: "Balance", isOn: d.balanceOn) { d.setBalance($0 ? d.balance : 0, on: $0) }
            .available(has(.balance), live: live, model: d.productID)
        if d.balanceOn {
            HStack {
                Text("L").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.mute)
                Slider(value: $balanceDraft, in: -16...16, step: 1) { editing in
                    if !editing { d.setBalance(Int(balanceDraft), on: true) }
                }
                .tint(Theme.accent)
                Text("R").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.mute)
            }
            .available(has(.balance), live: live, model: d.productID)
            .onAppear { balanceDraft = Double(d.balance) }
            .onChange(of: d.balance) { _, v in balanceDraft = Double(v) }
        }
        HStack {
            Text("Auto power off").foregroundStyle(live && has(.autoOff) ? Theme.ink : Theme.mute)
            Spacer()
            Picker("Auto power off", selection: Binding(get: { d.autoOff }, set: { d.setAutoOff($0) })) {
                Text("Off").tag(AutoOff.off)
                Text("30 min").tag(AutoOff.min30)
                Text("1 hour").tag(AutoOff.h1)
                Text("2 hours").tag(AutoOff.h2)
            }
            .labelsHidden().fixedSize()
        }
        .available(has(.autoOff), live: live, model: d.productID)
        SwitchRow(title: "Voice prompts", isOn: d.voicePrompts) { d.setVoicePrompts($0) }
            .available(has(.voicePrompts), live: live, model: d.productID)
        Button("Undo changes since app opened") { d.restoreLaunchState() }
            .buttonStyle(OutlineButtonStyle()).disabled(!d.canRestore)
            .help("Put back the settings the headphones had when this app opened")
        Button("Quit JBL Protocol4") { NSApp.terminate(nil) }
            .buttonStyle(OutlineButtonStyle()).keyboardShortcut("q")
        Text("Unofficial app. Not affiliated with or endorsed by JBL or Harman.")
            .font(.system(size: 10)).foregroundStyle(Theme.mute)
            .frame(maxWidth: .infinity).multilineTextAlignment(.center)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(d.lastError.map { "\(d.link.text) · \($0)" } ?? d.link.text)
                .lineLimit(1).truncationMode(.tail)
            Spacer()
            Button(action: powerTapped) {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(armed ? Color.white : Theme.mute)
                    .background(RoundedRectangle(cornerRadius: 7).fill(armed ? Theme.danger : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!live || !has(.powerOff))
            .opacity(has(.powerOff) ? 1 : 0.4)
            .help(!has(.powerOff) ? unavailableText(d.productID) : armed ? "Click again to power off" : "Power off")
            .accessibilityLabel(armed ? "Click again to power off" : "Power off")
        }
        .font(.system(size: 10))
        .foregroundStyle(Theme.mute)
    }

    /// Two clicks: the first arms the button (red) for 4 seconds, the second powers off.
    private func powerTapped() {
        armTask?.cancel()
        if armed {
            armed = false
            d.powerOff()
        } else {
            armed = true
            armTask = Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !Task.isCancelled { armed = false }
            }
        }
    }
}

private func unavailableText(_ pid: UInt16?) -> String {
    "Not available on the \(pid.flatMap(Product.name) ?? "connected model")"
}

private extension View {
    /// Greys out a control while disconnected, or always when the connected model does not have it (with a tooltip).
    func available(_ supported: Bool, live: Bool, model: UInt16?) -> some View {
        disabled(!live || !supported).help(supported ? "" : unavailableText(model))
    }
}

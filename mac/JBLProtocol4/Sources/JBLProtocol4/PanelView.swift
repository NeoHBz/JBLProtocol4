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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Segments(options: [("ANC", NoiseMode.anc), ("Ambient", .ambient), ("TalkThru", .talkThru), ("Off", .off)],
                     selection: d.noise, onSelect: d.setNoise)
                .disabled(!live)
            Divider().overlay(Theme.line)
            SwitchRow(title: "Voice Aware", isOn: d.voiceAware != nil) { d.setVoiceAware($0 ? .low : nil) }
                .disabled(!live)
            if let level = d.voiceAware {
                Segments(options: [("Low", VoiceAwareLevel.low), ("Mid", .mid), ("High", .high)],
                         selection: level, onSelect: { d.setVoiceAware($0) })
                    .disabled(!live)
            }
            SwitchRow(title: "Spatial Sound", isOn: d.spatial != nil) { d.setSpatial($0 ? .music : nil) }
                .disabled(!live)
            if let mode = d.spatial {
                Segments(options: [("Music", SpatialMode.music), ("Movie", .movie), ("Game", .game)],
                         selection: mode, onSelect: { d.setSpatial($0) })
                    .disabled(!live)
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
        HStack {
            Text("JBL Tune 780NC").fontWeight(.bold)
            Spacer()
            if live, let b = d.battery {
                HStack(spacing: 8) {
                    BatteryGlyph(percent: b)
                    Text("\(b)%").monospacedDigit()
                }
            }
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
        SwitchRow(title: "Balance", isOn: d.balanceOn) { d.setBalance(d.balance, on: $0) }
            .disabled(!live)
        if d.balanceOn {
            HStack {
                Text("L").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.mute)
                Slider(value: $balanceDraft, in: -16...16, step: 1) { editing in
                    if !editing { d.setBalance(Int(balanceDraft), on: true) }
                }
                .tint(Theme.accent)
                Text("R").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.mute)
            }
            .disabled(!live)
            .onAppear { balanceDraft = Double(d.balance) }
            .onChange(of: d.balance) { _, v in balanceDraft = Double(v) }
        }
        HStack {
            Text("Auto power off")
            Spacer()
            Picker("Auto power off", selection: Binding(get: { d.autoOff }, set: { d.setAutoOff($0) })) {
                Text("Off").tag(AutoOff.off)
                Text("30 min").tag(AutoOff.min30)
                Text("1 hour").tag(AutoOff.h1)
                Text("2 hours").tag(AutoOff.h2)
            }
            .labelsHidden().fixedSize()
        }
        .disabled(!live)
        SwitchRow(title: "Voice prompts", isOn: d.voicePrompts) { d.setVoicePrompts($0) }
            .disabled(!live)
        Button("Undo changes since app opened") { d.restoreLaunchState() }
            .buttonStyle(OutlineButtonStyle()).disabled(!d.canRestore)
            .help("Put back the settings the headphones had when this app opened")
        Button("Quit JBL Protocol4") { NSApp.terminate(nil) }
            .buttonStyle(OutlineButtonStyle()).keyboardShortcut("q")
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
            .disabled(!live)
            .help(armed ? "Click again to power off" : "Power off")
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

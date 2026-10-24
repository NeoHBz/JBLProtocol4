import SwiftUI
import JBLKit

/// Layout A1 ("Fold-out"): everyday controls on top, rarely used ones behind "More settings", power off in the footer.
struct PanelView: View {
    @EnvironmentObject var d: Device
    @AppStorage("moreExpanded") private var more = false
    @State private var armed = false
    @State private var armTask: Task<Void, Never>?
    @State private var balanceDraft = 0.0

    private var live: Bool { d.link == .ready }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            noisePicker
            Divider()
            voiceAwareSection
            spatialSection
            Divider()
            moreSection
            footer
        }
        .padding(14)
        .frame(width: 320)
        .disabled(false)
        .opacity(d.link == .poweredOff ? 0.6 : 1)
    }

    private var header: some View {
        HStack {
            Text("JBL Tune 780NC").fontWeight(.bold)
            Spacer()
            if live, let b = d.battery {
                HStack(spacing: 6) {
                    BatteryGlyph(percent: b)
                    Text("\(b)%").monospacedDigit()
                }
            }
        }
    }

    private func switchRow(_ title: String, _ on: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: on).toggleStyle(.switch).labelsHidden().tint(Theme.accent).disabled(!live)
        }
    }

    private var noisePicker: some View {
        Segments(selection: Binding(get: { d.noise }, set: { d.setNoise($0) }),
                 options: [("ANC", .anc), ("Ambient", .ambient), ("TalkThru", .talkThru), ("Off", .off)])
            .disabled(!live)
    }

    private var voiceAwareSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            switchRow("Voice Aware", Binding(get: { d.voiceAware != nil }, set: { d.setVoiceAware($0 ? .low : nil) }))
            if let level = d.voiceAware {
                Segments(selection: Binding(get: { level }, set: { d.setVoiceAware($0) }),
                         options: [("Low", .low), ("Mid", .mid), ("High", .high)])
                    .disabled(!live)
            }
        }
    }

    private var spatialSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            switchRow("Spatial Sound", Binding(get: { d.spatial != nil }, set: { d.setSpatial($0 ? .music : nil) }))
            if let mode = d.spatial {
                Segments(selection: Binding(get: { mode }, set: { d.setSpatial($0) }),
                         options: [("Music", .music), ("Movie", .movie), ("Game", .game)])
                    .disabled(!live)
            }
        }
    }

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.15)) { more.toggle() } } label: {
                HStack { Text("More settings").font(.system(size: 12)); Spacer(); Text(more ? "−" : "+").monospaced() }
                    .foregroundStyle(.secondary).contentShape(Rectangle())
            }.buttonStyle(.plain).focusable(false)
            if more {
                switchRow("Balance", Binding(get: { d.balanceOn }, set: { d.setBalance(d.balance, on: $0) }))
                if d.balanceOn {
                    HStack {
                        Text("L").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $balanceDraft, in: -16...16, step: 1) { editing in
                            if !editing { d.setBalance(Int(balanceDraft), on: true) }
                        }
                        Text("R").font(.caption).foregroundStyle(.secondary)
                    }
                    .disabled(!live)
                    .onAppear { balanceDraft = Double(d.balance) }
                    .onChange(of: d.balance) { balanceDraft = Double($0) }
                }
                HStack {
                    Text("Auto power off"); Spacer()
                    Picker("Auto power off", selection: Binding(get: { d.autoOff }, set: { d.setAutoOff($0) })) {
                        Text("Off").tag(AutoOff.off); Text("30 min").tag(AutoOff.min30)
                        Text("1 hour").tag(AutoOff.h1); Text("2 hours").tag(AutoOff.h2)
                    }.labelsHidden().fixedSize().disabled(!live)
                }
                switchRow("Voice prompts", Binding(get: { d.voicePrompts }, set: { d.setVoicePrompts($0) }))
                Button { d.restoreLaunchState() } label: {
                    Text("Restore launch state").font(.system(size: 12)).frame(maxWidth: .infinity).padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.18)))
                }.buttonStyle(.plain).disabled(!d.canRestore)
                Button { NSApplication.shared.terminate(nil) } label: {
                    Text("Quit JBL Control").font(.system(size: 12)).frame(maxWidth: .infinity).padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.18)))
                }.buttonStyle(.plain).keyboardShortcut("q")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(d.lastError.map { "\(d.link.text) · \($0)" } ?? d.link.text)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            Spacer()
            Button(action: powerTapped) {
                Image(systemName: "power").font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(armed ? Color.white : Color.secondary)
                    .background(RoundedRectangle(cornerRadius: 7).fill(armed ? Color.red : Color.clear))
            }
            .buttonStyle(.plain).disabled(!live)
            .help(armed ? "Click again to power off" : "Power off")
            .accessibilityLabel(armed ? "Click again to power off" : "Power off")
        }
    }

    private func powerTapped() {
        if armed {
            armTask?.cancel(); armed = false
            d.powerOff()
        } else {
            armed = true
            armTask?.cancel()
            armTask = Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !Task.isCancelled { armed = false }
            }
        }
    }
}

struct BatteryGlyph: View {
    let percent: Int
    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).stroke(Color.secondary, lineWidth: 1.5).frame(width: 44, height: 12)
            RoundedRectangle(cornerRadius: 1.5).fill(percent <= 15 ? Color.red : Color.green)
                .frame(width: max(2, 38 * CGFloat(percent) / 100), height: 7).padding(.leading, 3)
        }
    }
}

enum Theme {
    static let accent = Color(red: 1.0, green: 0.478, blue: 0.18)   // #ff7a2e, A1 dark accent
    static let accentInk = Color(red: 0.102, green: 0.051, blue: 0.012)
}

/// A1 segmented control: grey track, selected segment filled orange with bold dark text.
struct Segments<T: Hashable>: View {
    @Binding var selection: T
    let options: [(String, T)]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let on = options[i].1 == selection
                Button { selection = options[i].1 } label: {
                    Text(options[i].0)
                        .font(.system(size: 12, weight: on ? .bold : .regular))
                        .foregroundStyle(on ? Theme.accentInk : Color.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(on ? Theme.accent : Color.clear))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).focusable(false)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.1)))
    }
}

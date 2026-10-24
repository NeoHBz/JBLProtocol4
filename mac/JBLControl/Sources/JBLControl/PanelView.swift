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

    private var noisePicker: some View {
        Picker("Noise control", selection: Binding(get: { d.noise }, set: { d.setNoise($0) })) {
            Text("ANC").tag(NoiseMode.anc)
            Text("Ambient").tag(NoiseMode.ambient)
            Text("TalkThru").tag(NoiseMode.talkThru)
            Text("Off").tag(NoiseMode.off)
        }
        .pickerStyle(.segmented).labelsHidden().disabled(!live)
    }

    private var voiceAwareSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Voice Aware", isOn: Binding(get: { d.voiceAware != nil }, set: { d.setVoiceAware($0 ? .low : nil) }))
                .toggleStyle(.switch).disabled(!live)
            if let level = d.voiceAware {
                Picker("Voice Aware level", selection: Binding(get: { level }, set: { d.setVoiceAware($0) })) {
                    Text("Low").tag(VoiceAwareLevel.low); Text("Mid").tag(VoiceAwareLevel.mid); Text("High").tag(VoiceAwareLevel.high)
                }.pickerStyle(.segmented).labelsHidden().disabled(!live)
            }
        }
    }

    private var spatialSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Spatial Sound", isOn: Binding(get: { d.spatial != nil }, set: { d.setSpatial($0 ? .music : nil) }))
                .toggleStyle(.switch).disabled(!live)
            if let mode = d.spatial {
                Picker("Spatial mode", selection: Binding(get: { mode }, set: { d.setSpatial($0) })) {
                    Text("Music").tag(SpatialMode.music); Text("Movie").tag(SpatialMode.movie); Text("Game").tag(SpatialMode.game)
                }.pickerStyle(.segmented).labelsHidden().disabled(!live)
            }
        }
    }

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.15)) { more.toggle() } } label: {
                HStack { Text("More settings"); Spacer(); Text(more ? "−" : "+").monospaced() }
                    .foregroundStyle(.secondary).contentShape(Rectangle())
            }.buttonStyle(.plain).focusable(false)
            if more {
                Toggle("Balance", isOn: Binding(get: { d.balanceOn }, set: { d.setBalance(d.balance, on: $0) }))
                    .toggleStyle(.switch).disabled(!live)
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
                Toggle("Voice prompts", isOn: Binding(get: { d.voicePrompts }, set: { d.setVoicePrompts($0) }))
                    .toggleStyle(.switch).disabled(!live)
                Button("Restore launch state") { d.restoreLaunchState() }.disabled(!d.canRestore)
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
            RoundedRectangle(cornerRadius: 3).stroke(Color.secondary, lineWidth: 1.5).frame(width: 30, height: 12)
            RoundedRectangle(cornerRadius: 1.5).fill(percent <= 15 ? Color.red : Color.green)
                .frame(width: max(2, 24 * CGFloat(percent) / 100), height: 7).padding(.leading, 3)
        }
    }
}

import Foundation
@preconcurrency import CoreBluetooth
import JBLKit

enum LinkState: Equatable {
    case bluetoothOff, unauthorized, searching, connecting, handshaking, ready, poweredOff
    var text: String {
        switch self {
        case .bluetoothOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth access denied"
        case .searching: return "Searching for headphones"
        case .connecting, .handshaking: return "Connecting"
        case .ready: return "Connected over Bluetooth LE"
        case .poweredOff: return "Not connected"
        }
    }
}

/// Talks to the headphones. Every value shown in the UI comes from what the device reported (GET reply or state push),
/// never from what the UI asked for.
@MainActor
final class Device: NSObject, ObservableObject {
    @Published var link: LinkState = .searching
    @Published var battery: Int?
    @Published var noise: NoiseMode = .off
    @Published var voiceAware: VoiceAwareLevel?
    @Published var spatial: SpatialMode?
    @Published var balanceOn = false
    @Published var balance = 0
    @Published var autoOff: AutoOff = .off
    @Published var voicePrompts = false
    @Published var lastError: String?

    private nonisolated let serviceUUID = CBUUID(string: "65786365-6c70-6f69-6e74-2e636f6d0000")
    private nonisolated let writeUUID = CBUUID(string: "65786365-6c70-6f69-6e74-2e636f6d0002")
    private nonisolated let notifyUUID = CBUUID(string: "65786365-6c70-6f69-6e74-2e636f6d0001")
    private let deviceName = "JBL Tune 780NC"

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var pollTimer: Timer?
    private var intentionalPowerOff = false
    /// Raw values the device reported at the first full read of this app run, for "Undo changes since app opened".
    private var launch: [UInt16: Data] = [:]
    private var current: [UInt16: Data] = [:]
    private let stateTags: [UInt16] = [Tag.battery, Tag.anc, Tag.ambient, Tag.talkThru, Tag.voiceAware, Tag.balance,
                                       Tag.spatial, Tag.autoOff, Tag.voicePrompt, Tag.voicePromptLang]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: actions (each sends one verified frame, then asks the device to report the tag back)

    func setNoise(_ m: NoiseMode) { send(Commands.noise(m), reread: [Tag.anc, Tag.ambient, Tag.talkThru]) }
    func setVoiceAware(_ l: VoiceAwareLevel?) { send(Commands.voiceAware(l), reread: [Tag.voiceAware]) }
    func setSpatial(_ m: SpatialMode?) { send(Commands.spatial(m), reread: [Tag.spatial]) }
    func setBalance(_ v: Int, on: Bool) { send(Commands.balance(v, on: on), reread: [Tag.balance]) }
    func setAutoOff(_ a: AutoOff) { send(Commands.autoOff(a), reread: [Tag.autoOff]) }
    func setVoicePrompts(_ on: Bool) { send(Commands.voicePrompts(on), reread: [Tag.voicePrompt, Tag.voicePromptLang]) }

    func powerOff() {
        intentionalPowerOff = true
        send(Commands.powerOff, reread: [])
    }

    var canRestore: Bool { link == .ready && !launch.isEmpty }

    /// Writes back what the device reported when the app started: noise mode, Voice Aware, balance, Spatial,
    /// Auto Power Off and voice prompts.
    func restoreLaunchState() {
        guard canRestore else { return }
        let l = launch
        let aa = l[Tag.ambient]?.first == 0xFF, tt = l[Tag.talkThru]?.first == 0xFF, anc = l[Tag.anc]?.first == 0xFF
        let noiseFrame = Commands.noise(anc ? .anc : aa ? .ambient : tt ? .talkThru : .off)
        var frames = [noiseFrame]
        for group in [[Tag.voiceAware], [Tag.balance], [Tag.spatial], [Tag.autoOff], [Tag.voicePrompt, Tag.voicePromptLang]] {
            let tlvs = group.compactMap { t in l[t].map { TLV(t, $0) } }
            if tlvs.count == group.count, let f = try? Commands.raw(tlvs) { frames.append(f) }
        }
        for (i, f) in frames.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 * Double(i)) { [weak self] in self?.send(f, reread: []) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 * Double(frames.count) + 0.5) { [weak self] in self?.readState() }
    }

    // MARK: plumbing

    private func send(_ frame: Data, reread: [UInt16]) {
        guard link == .ready, let p = peripheral, let c = writeChar else { lastError = "Not connected"; return }
        p.writeValue(frame, for: c, type: .withResponse)
        if !reread.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.get(reread) }
        }
    }

    private func get(_ tags: [UInt16]) {
        guard let p = peripheral, let c = writeChar, link == .ready || link == .handshaking else { return }
        // One tag per GET, as the tested scripts did, so every reply is a single frame.
        for (i, t) in tags.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 * Double(i)) { p.writeValue(buildGet([t]), for: c, type: .withResponse) }
        }
    }

    private func readState() { get(stateTags) }

    private func handle(_ data: Data) {
        guard let f = try? Frame.parse(data), f.count == 1 else { return }
        if f.command == Cmd.set, data == ackFrame, link == .handshaking {
            link = .ready
            lastError = nil
            readState()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 * Double(stateTags.count) + 1.0) { [weak self] in
                guard let self, self.launch.isEmpty, self.link == .ready else { return }
                self.launch = self.current
            }
            pollTimer?.invalidate()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.get([Tag.battery]) }
            }
            return
        }
        guard f.command == Cmd.get || f.command == Cmd.notifyApp,
              let (status, tlvs) = try? parseStatusTLVs(f.payload), status == 0 else { return }
        for t in tlvs { apply(t.tag, t.value) }
    }

    private func apply(_ tag: UInt16, _ v: Data) {
        current[tag] = v
        switch tag {
        case Tag.battery: if let s = decodeSL1(v) { battery = s.level }
        case Tag.anc, Tag.ambient, Tag.talkThru:
            let on = v.first == 0xFF
            if tag == Tag.anc, on { noise = .anc }
            else if tag == Tag.ambient, on { noise = .ambient }
            else if tag == Tag.talkThru, on { noise = .talkThru }
            else if v.first == 0x7F, current[Tag.anc]?.first != 0xFF, current[Tag.ambient]?.first != 0xFF, current[Tag.talkThru]?.first != 0xFF { noise = .off }
        case Tag.voiceAware: if let s = decodeSL1(v) { voiceAware = s.on ? VoiceAwareLevel(rawValue: s.level) : nil }
        case Tag.spatial: if let s = decodeSL1(v) { spatial = s.on ? SpatialMode(level: s.level) : nil }
        case Tag.balance: if let s = decodeSL1(v) { balanceOn = s.on; balance = max(-16, min(16, s.level - 50)) }
        case Tag.autoOff:
            if let s = decodeSL2(v) { autoOff = s.on ? (AutoOff(rawValue: s.seconds) ?? .min30) : .off }
        case Tag.voicePrompt: if let s = decodeSL1(v) { voicePrompts = s.on }
        default: break
        }
    }

    private func startScan() {
        guard central.state == .poweredOn else { return }
        link = .searching
        if let id = UserDefaults.standard.string(forKey: "peripheralID").flatMap(UUID.init),
           let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(known); return
        }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func connect(_ p: CBPeripheral) {
        central.stopScan()
        peripheral = p; p.delegate = self
        link = .connecting
        central.connect(p)
    }
}

extension Device: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ c: CBCentralManager) {
        MainActor.assumeIsolated {
            switch c.state {
            case .poweredOn: startScan()
            case .poweredOff: link = .bluetoothOff
            case .unauthorized: link = .unauthorized
            default: break
            }
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        MainActor.assumeIsolated {
            let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name
            if name == deviceName { connect(p) }
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        MainActor.assumeIsolated {
            UserDefaults.standard.set(p.identifier.uuidString, forKey: "peripheralID")
            p.discoverServices([serviceUUID])
        }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { retryLater() }
    }

    nonisolated func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            pollTimer?.invalidate()
            writeChar = nil; notifyChar = nil
            if intentionalPowerOff { link = .poweredOff; intentionalPowerOff = false; battery = nil; launch = [:]; current = [:]; return }
            battery = nil; launch = [:]; current = [:]
            retryLater()
        }
    }

    @MainActor private func retryLater() {
        link = .searching
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.link != .ready else { return }
            self.startScan()
        }
    }
}

extension Device: CBPeripheralDelegate {
    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let s = p.services?.first(where: { $0.uuid == serviceUUID }) else { lastError = "Vendor service not found"; return }
            p.discoverCharacteristics([writeUUID, notifyUUID], for: s)
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        MainActor.assumeIsolated {
            writeChar = s.characteristics?.first { $0.uuid == writeUUID }
            notifyChar = s.characteristics?.first { $0.uuid == notifyUUID }
            guard let n = notifyChar, writeChar != nil else { lastError = "Characteristics not found"; return }
            link = .handshaking
            p.setNotifyValue(true, for: n)
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard ch.uuid == notifyUUID, ch.isNotifying, let w = writeChar else { return }
            // Handshake: HostType = 1. The device ignores everything else until it has been sent.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { p.writeValue(Commands.hostType, for: w, type: .withResponse) }
        }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == notifyUUID, let d = ch.value else { return }
        MainActor.assumeIsolated { handle(d) }
    }

    nonisolated func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        guard let error else { return }
        MainActor.assumeIsolated { lastError = error.localizedDescription }
    }
}

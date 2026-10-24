import Foundation

/// Frame encoder and parser for the JBL Tune 780NC "protocol4". Bytes only, never talks to a device.
/// Spec: notes/protocol.md. Mirrors proto/jbl_proto.py, which the tests below replay against captured frames.
public enum Cmd {
    public static let get: UInt16 = 0x0001
    public static let set: UInt16 = 0x0002
    public static let notifyApp: UInt16 = 0x0003
}

public enum Tag {
    public static let powerOff: UInt16 = 0x0011
    public static let battery: UInt16 = 0x000D
    public static let anc: UInt16 = 0x0018
    public static let ambient: UInt16 = 0x0019
    public static let talkThru: UInt16 = 0x001A
    public static let balance: UInt16 = 0x0015
    public static let voiceAware: UInt16 = 0x0023
    public static let spatial: UInt16 = 0x0022
    public static let autoOff: UInt16 = 0x0012
    public static let voicePrompt: UInt16 = 0x0C40
    public static let voicePromptLang: UInt16 = 0x0C41
    public static let hostType: UInt16 = 0x002F
}

/// Tags the app may ever SET. Everything else (firmware, factory reset, LE Audio, Auracast, EQ, Smart Audio & Video,
/// authentication, button mapping) is refused here, whatever the UI asks for.
public let writableTags: Set<UInt16> = [
    Tag.powerOff, Tag.anc, Tag.ambient, Tag.talkThru, Tag.balance, Tag.voiceAware, Tag.spatial,
    Tag.autoOff, Tag.voicePrompt, Tag.voicePromptLang, Tag.hostType,
]

public struct ProtocolError: Error, CustomStringConvertible {
    public let description: String
    init(_ d: String) { description = d }
}

public struct Frame: Equatable {
    public var identifier: UInt16 = 0xDD00
    public var command: UInt16
    public var count: UInt8 = 1
    public var index: UInt8 = 0
    public var payload: Data

    public init(command: UInt16, payload: Data) { self.command = command; self.payload = payload }
    init(identifier: UInt16, command: UInt16, count: UInt8, index: UInt8, payload: Data) {
        self.identifier = identifier; self.command = command; self.count = count; self.index = index; self.payload = payload
    }

    public func encode() -> Data {
        var d = Data()
        d.appendLE(identifier); d.appendLE(command); d.append(count); d.append(index); d.appendLE(UInt16(payload.count))
        d.append(payload)
        return d
    }

    public static func parse(_ data: Data) throws -> Frame {
        let b = [UInt8](data)
        guard b.count >= 8 else { throw ProtocolError("frame shorter than header") }
        let size = Int(b[6]) | Int(b[7]) << 8
        guard size == b.count - 8 else { throw ProtocolError("payload size \(size) does not match \(b.count - 8) bytes") }
        return Frame(identifier: UInt16(b[0]) | UInt16(b[1]) << 8, command: UInt16(b[2]) | UInt16(b[3]) << 8,
                     count: b[4], index: b[5], payload: Data(b[8...]))
    }
}

public struct TLV: Equatable {
    public var tag: UInt16
    public var value: Data
    public init(_ tag: UInt16, _ value: Data) { self.tag = tag; self.value = value }
    public init(_ tag: UInt16, byte: UInt8) { self.tag = tag; self.value = Data([byte]) }
}

public func parseTLVs(_ data: Data) throws -> [TLV] {
    let b = [UInt8](data)
    var out: [TLV] = [], i = 0
    while i < b.count {
        guard i + 4 <= b.count else { throw ProtocolError("truncated TLV header") }
        let tag = UInt16(b[i]) | UInt16(b[i + 1]) << 8
        let len = Int(b[i + 2]) | Int(b[i + 3]) << 8
        guard i + 4 + len <= b.count else { throw ProtocolError("truncated TLV value") }
        out.append(TLV(tag, Data(b[(i + 4)..<(i + 4 + len)])))
        i += 4 + len
    }
    return out
}

/// Replies and notifications: status u16 (0 = OK), then TLVs.
public func parseStatusTLVs(_ payload: Data) throws -> (status: UInt16, tlvs: [TLV]) {
    guard payload.count >= 2 else { throw ProtocolError("missing status") }
    let b = [UInt8](payload)
    return (UInt16(b[0]) | UInt16(b[1]) << 8, try parseTLVs(Data(b[2...])))
}

public func buildGet(_ tags: [UInt16]) -> Data {
    var p = Data()
    for t in tags { p.appendLE(t) }
    return Frame(command: Cmd.get, payload: p).encode()
}

public func buildSet(_ tlvs: [TLV]) throws -> Data {
    var p = Data()
    for t in tlvs {
        guard writableTags.contains(t.tag) else { throw ProtocolError(String(format: "tag 0x%04x is not a verified writable tag", t.tag)) }
        p.appendLE(t.tag); p.appendLE(UInt16(t.value.count)); p.append(t.value)
    }
    return Frame(command: Cmd.set, payload: p).encode()
}

public let ackFrame = Data([0x00, 0xdd, 0x02, 0x00, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00])

// MARK: value codecs

public func sl1(on: Bool, level: Int) -> UInt8 { (on ? 0x80 : 0) | UInt8(level & 0x7F) }
public func decodeSL1(_ v: Data) -> (on: Bool, level: Int)? { v.count == 1 ? (v[v.startIndex] & 0x80 != 0, Int(v[v.startIndex] & 0x7F)) : nil }
public func sl2(on: Bool, seconds: Int) -> Data { var d = Data(); d.appendLE(UInt16((on ? 0x8000 : 0) | (seconds & 0x7FFF))); return d }
public func decodeSL2(_ v: Data) -> (on: Bool, seconds: Int)? {
    guard v.count == 2 else { return nil }
    let x = Int(v[v.startIndex]) | Int(v[v.startIndex + 1]) << 8
    return (x & 0x8000 != 0, x & 0x7FFF)
}

public enum NoiseMode: String, CaseIterable { case anc, ambient, talkThru, off }
public enum SpatialMode: String, CaseIterable {
    case music, movie, game
    public var level: Int { switch self { case .music: 2; case .movie: 1; case .game: 3 } }
    public init?(level: Int) { guard let m = Self.allCases.first(where: { $0.level == level }) else { return nil }; self = m }
}
public enum VoiceAwareLevel: Int, CaseIterable { case low = 1, mid = 2, high = 3 }
public enum AutoOff: Int, CaseIterable { case off = 0, min30 = 1800, h1 = 3600, h2 = 7200 }

// MARK: command builders (each is byte-identical to a frame the phone sent in the capture)

public enum Commands {
    public static let hostType = try! buildSet([TLV(Tag.hostType, byte: 0x01)])
    public static let powerOff = try! buildSet([TLV(Tag.powerOff, Data([0x00, 0x00]))])

    public static func noise(_ m: NoiseMode) -> Data {
        switch m {
        case .anc: return try! buildSet([TLV(Tag.anc, byte: 0xFF)])
        case .ambient: return try! buildSet([TLV(Tag.ambient, byte: 0xFF)])
        case .talkThru: return try! buildSet([TLV(Tag.talkThru, byte: 0xFF)])
        case .off: return try! buildSet([TLV(Tag.anc, byte: 0x7F)])
        }
    }
    /// Off is `03`, as captured.
    public static func voiceAware(_ level: VoiceAwareLevel?) -> Data {
        try! buildSet([TLV(Tag.voiceAware, byte: level.map { sl1(on: true, level: $0.rawValue) } ?? 0x03)])
    }
    /// Off keeps the mode bits, `03`: the value the device itself reported while Spatial was off (Stage 6c baseline).
    public static func spatial(_ m: SpatialMode?) -> Data {
        try! buildSet([TLV(Tag.spatial, byte: m.map { sl1(on: true, level: $0.level) } ?? 0x03)])
    }
    /// value -16...16, stored as 50 + value.
    public static func balance(_ v: Int, on: Bool) -> Data {
        try! buildSet([TLV(Tag.balance, byte: sl1(on: on, level: 50 + max(-16, min(16, v))))])
    }
    /// Off is written as the captured "2 h, off" frame; the device keeps its own stored duration.
    public static func autoOff(_ a: AutoOff) -> Data {
        try! buildSet([TLV(Tag.autoOff, a == .off ? sl2(on: false, seconds: 7200) : sl2(on: true, seconds: a.rawValue))])
    }
    public static func voicePrompts(_ on: Bool) -> Data {
        try! buildSet([TLV(Tag.voicePrompt, byte: sl1(on: on, level: 0x7F)), TLV(Tag.voicePromptLang, byte: 0x01)])
    }
    /// Writes values back exactly as the device reported them (used by "Undo changes since app opened").
    public static func raw(_ tlvs: [TLV]) throws -> Data { try buildSet(tlvs) }
}

extension Data {
    mutating func appendLE(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8(v >> 8)) }
    public var hex: String { map { String(format: "%02x", $0) }.joined() }
    public init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var d = Data(), i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let b = UInt8(hex[i..<j], radix: 16) else { return nil }
            d.append(b); i = j
        }
        self = d
    }
}

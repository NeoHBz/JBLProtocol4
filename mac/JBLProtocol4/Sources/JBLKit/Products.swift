import Foundation

/// Model and colour, as the device reports them: ProductID (tag 0x0004) and ColorID (tag 0x0005).
/// Tables from the JBL app: `product_list.json` (notes/protocol.md section 11) and its colour enum (section 12).
public enum Product {
    /// ProductID is a little-endian u16: the 780NC sends `5f21` = 0x215f.
    public static func decodePID(_ v: Data) -> UInt16? {
        v.count == 2 ? UInt16(v[v.startIndex]) | UInt16(v[v.startIndex + 1]) << 8 : nil
    }

    public static func name(pid: UInt16) -> String? { names[pid] }

    /// Whether an advertised Bluetooth name is a Protocol4 model, e.g. "JBL Tune 780NC". Case-insensitive prefix, so
    /// a suffix some models add after the model name still matches.
    public static func isFamily(name: String) -> Bool {
        Set(names.values).contains { name.range(of: $0, options: [.caseInsensitive, .anchored]) != nil }
    }

    /// The JBL app's colour key, which is also the key its per-model image config uses (`Beige`, `GhostBlack`, ...).
    public static func colourKey(id: Int) -> String? { colours[id] }

    /// "GhostBlack" -> "Ghost Black".
    public static func colourName(id: Int) -> String? {
        colours[id].map { $0.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression) }
    }

    /// Controls the panel offers. Each maps to the JBL app's card for it, the one the 780NC uses.
    public enum Feature { case anc, ambient, talkThru, voiceAware, spatial, balance, autoOff, voicePrompts, powerOff }

    /// Whether the model has the control, by the JBL app's own per-model card list. An unknown model gets everything,
    /// as before models were told apart.
    public static func supports(_ f: Feature, pid: UInt16?) -> Bool {
        guard let pid, let s = features[pid] else { return true }
        return s.contains(f)
    }

    /// From each model's dash4 config `uiFeatures` (cards not marked `visible: false`) plus `isSupportConfig` in
    /// product_list.json: ANC, AA, TT, VoiceAwareCard, Spatial3DCard, LeftRightBalanceCard, AutoPowerOffCard,
    /// VoicePromptCard, DashBoardPowerOff. Look-alike cards (LeftRightBalance2Card, SpatialSoundWithHeadTrackCard,
    /// PowerSavingCard) do not count: their values may differ from what was verified on the 780NC.
    private static let features: [UInt16: Set<Feature>] = [
        0x2101: [.anc, .ambient, .talkThru, .voiceAware, .balance, .autoOff, .voicePrompts], // JBL Tour One M3
        0x2133: [.balance, .autoOff, .voicePrompts, .powerOff], // JBL Sense Lite
        0x2134: [.balance, .autoOff, .voicePrompts, .powerOff], // JBL Endurance Zone
        0x2135: [.voiceAware, .balance, .voicePrompts, .powerOff], // JBL Tune 135BT
        0x2136: [.voiceAware, .balance, .voicePrompts, .powerOff], // JBL Tune 235BT
        0x2152: [.balance, .autoOff, .voicePrompts], // JBL Soundgear Clips
        0x2154: [.balance, .autoOff, .voicePrompts], // JBL Junior Free
        0x214F: [.voiceAware, .balance, .autoOff, .voicePrompts], // JBL Endurance Run 3 Wireless
        0x2150: [.balance, .autoOff, .voicePrompts], // JBL Endurance Pace
        0x2151: [.voiceAware, .spatial, .balance, .voicePrompts], // JBL Endurance Peak 4
        0x2153: [.spatial, .balance, .autoOff, .voicePrompts, .powerOff], // JBL Sense Pro
        0x2162: [.voiceAware, .balance, .autoOff, .voicePrompts], // JBL Tune 530BT
        0x2189: [.voiceAware, .balance, .autoOff, .voicePrompts], // JBL Tune 530BT
        0x2163: [.voiceAware, .balance, .autoOff, .voicePrompts], // JBL Tune 730BT
        0x215E: [.anc, .ambient, .talkThru, .voiceAware, .spatial, .balance, .autoOff, .voicePrompts, .powerOff], // JBL Tune 680NC
        0x215F: [.anc, .ambient, .talkThru, .voiceAware, .spatial, .balance, .autoOff, .voicePrompts, .powerOff], // JBL Tune 780NC
        0x214B: [.powerOff], // JBL Smart Tx
        0x2160: [.anc, .ambient, .talkThru, .voiceAware, .spatial, .autoOff, .voicePrompts], // JBL Live 680NC
        0x2161: [.anc, .ambient, .talkThru, .voiceAware, .spatial, .autoOff, .voicePrompts], // JBL Live 780NC
        0x2179: [.anc, .ambient, .talkThru, .voiceAware, .spatial, .balance], // JBL Live Beam 4
        0x217B: [.anc, .ambient, .talkThru, .voiceAware, .spatial, .balance], // JBL Live Buds 4
        0x217D: [.anc, .ambient, .talkThru, .voiceAware, .spatial, .balance], // JBL Live Flex 4
        0x21A4: [.anc, .ambient, .talkThru, .voiceAware, .spatial, .balance, .autoOff, .voicePrompts, .powerOff], // JBL Tune 785NC
        0x2188: [.voiceAware, .balance, .autoOff, .voicePrompts], // JBL Tune 520BT2
        0x2194: [.voiceAware, .balance, .autoOff, .voicePrompts], // JBL Tune 535BT
        0x2195: [.voiceAware, .balance, .autoOff, .voicePrompts], // JBL Tune 735BT
        0x21B3: [.anc, .ambient, .talkThru, .voiceAware], // JBL Vibe Buds 3
        0x21B4: [.anc, .ambient, .talkThru, .voiceAware], // JBL Vibe Beam 3
        0x21B2: [.anc, .ambient, .talkThru, .voiceAware], // JBL Vibe Flex 3
        0x21AB: [.anc, .ambient, .talkThru, .voiceAware], // JBL Wave Buds 3
        0x21AC: [.anc, .ambient, .talkThru, .voiceAware], // JBL Wave Beam 3
        0x21AD: [.anc, .ambient, .talkThru, .voiceAware], // JBL Wave Flex 3
        0x21B7: [.anc, .ambient, .talkThru, .voiceAware, .spatial], // JBL Tune Buds 3
        0x21B8: [.anc, .ambient, .talkThru, .voiceAware, .spatial], // JBL Tune Beam 3
        0x21B9: [.anc, .ambient, .talkThru, .voiceAware, .spatial], // JBL Tune Beam 3
        0x21B6: [.anc, .ambient, .talkThru, .voiceAware, .spatial], // JBL Tune Flex 3
    ]

    private static let names: [UInt16: String] = [
        0x215E: "JBL Tune 680NC", 0x215F: "JBL Tune 780NC", 0x21A4: "JBL Tune 785NC",
        0x2160: "JBL Live 680NC", 0x2161: "JBL Live 780NC",
        0x2188: "JBL Tune 520BT2", 0x2162: "JBL Tune 530BT", 0x2189: "JBL Tune 530BT", 0x2194: "JBL Tune 535BT",
        0x2163: "JBL Tune 730BT", 0x2195: "JBL Tune 735BT",
        0x2101: "JBL Tour One M3", 0x2133: "JBL Sense Lite", 0x2134: "JBL Endurance Zone",
        0x2135: "JBL Tune 135BT", 0x2136: "JBL Tune 235BT",
        0x2179: "JBL Live Beam 4", 0x217B: "JBL Live Buds 4", 0x217D: "JBL Live Flex 4",
        0x21B6: "JBL Tune Flex 3", 0x21B7: "JBL Tune Buds 3", 0x21B8: "JBL Tune Beam 3", 0x21B9: "JBL Tune Beam 3",
        0x21B2: "JBL Vibe Flex 3", 0x21B3: "JBL Vibe Buds 3", 0x21B4: "JBL Vibe Beam 3",
        0x21AB: "JBL Wave Buds 3", 0x21AC: "JBL Wave Beam 3", 0x21AD: "JBL Wave Flex 3",
        0x2150: "JBL Endurance Pace", 0x2151: "JBL Endurance Peak 4", 0x214F: "JBL Endurance Run 3 Wireless",
        0x2154: "JBL Junior Free", 0x2153: "JBL Sense Pro", 0x2152: "JBL Soundgear Clips", 0x214B: "JBL Smart Tx",
    ]

    /// IDs are not contiguous: Teal is 37.
    private static let colours: [Int: String] = [
        0: "Black", 1: "White", 2: "Blue", 3: "Red", 4: "Green", 5: "Purple", 6: "GoldSilver", 7: "Silver", 8: "Grey",
        9: "Beige", 10: "Pink", 11: "Chrome", 12: "RoseGold", 13: "Coral", 14: "GhostBlack", 15: "GhostPurple",
        16: "GhostWhite", 17: "Mint", 18: "BlackTomorrowLand", 19: "Champagne", 20: "Brown", 21: "SquareBlack",
        22: "SquareWhite", 23: "SquareBrown", 24: "Yellow", 25: "Rose", 26: "Squad", 27: "Turquoise", 28: "PeachOrange",
        29: "BlackGray", 30: "BlackLime", 31: "Orange", 32: "Copper", 37: "Teal",
    ]
}

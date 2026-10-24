import Foundation

/// Model and colour, as the device reports them: ProductID (tag 0x0004) and ColorID (tag 0x0005).
/// Tables from the JBL app: `product_list.json` (notes/protocol.md section 11) and its colour enum (section 12).
public enum Product {
    /// ProductID is a little-endian u16: the 780NC sends `5f21` = 0x215f.
    public static func decodePID(_ v: Data) -> UInt16? {
        v.count == 2 ? UInt16(v[v.startIndex]) | UInt16(v[v.startIndex + 1]) << 8 : nil
    }

    public static func name(pid: UInt16) -> String? { names[pid] }

    /// The JBL app's colour key, which is also the key its per-model image config uses (`Beige`, `GhostBlack`, ...).
    public static func colourKey(id: Int) -> String? { colours[id] }

    /// "GhostBlack" -> "Ghost Black".
    public static func colourName(id: Int) -> String? {
        colours[id].map { $0.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression) }
    }

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

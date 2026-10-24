import XCTest
@testable import JBLKit

/// Every expected frame below is byte-identical to a write the phone made in the capture (notes/protocol.md section 7).
final class ReplayTests: XCTestCase {
    func eq(_ d: Data, _ hex: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(d.hex, hex, file: file, line: line)
    }
    func testHandshakeAndPower() {
        eq(Commands.hostType, "00dd0200010005002f00010001")
        eq(Commands.powerOff, "00dd020001000600110002000000")
    }
    func testNoise() {
        eq(Commands.noise(.anc), "00dd02000100050018000100ff")
        eq(Commands.noise(.off), "00dd020001000500180001007f")
        eq(Commands.noise(.ambient), "00dd02000100050019000100ff")
        eq(Commands.noise(.talkThru), "00dd0200010005001a000100ff")
    }
    func testVoiceAware() {
        eq(Commands.voiceAware(.low), "00dd0200010005002300010081")
        eq(Commands.voiceAware(.mid), "00dd0200010005002300010082")
        eq(Commands.voiceAware(.high), "00dd0200010005002300010083")
        eq(Commands.voiceAware(nil), "00dd0200010005002300010003")
    }
    func testBalanceSpatialAutoOff() {
        eq(Commands.balance(0, on: true), "00dd02000100050015000100b2")
        eq(Commands.balance(-16, on: true), "00dd02000100050015000100a2")
        eq(Commands.balance(16, on: true), "00dd02000100050015000100c2")
        eq(Commands.balance(0, on: false), "00dd0200010005001500010032")
        eq(Commands.spatial(.music), "00dd0200010005002200010082")
        eq(Commands.spatial(.movie), "00dd0200010005002200010081")
        eq(Commands.spatial(.game), "00dd0200010005002200010083")
        eq(Commands.autoOff(.min30), "00dd020001000600120002000887")
        eq(Commands.autoOff(.h1), "00dd02000100060012000200108e")
        eq(Commands.autoOff(.h2), "00dd02000100060012000200209c")
        eq(Commands.autoOff(.off), "00dd02000100060012000200201c")
        eq(Commands.voicePrompts(true), "00dd020001000a00400c0100ff410c010001")
    }
    func testAutoOffValuesDecode() throws {
        XCTAssertEqual(decodeSL2(Data(hex: "0887")!)?.seconds, 1800)
        XCTAssertEqual(decodeSL2(Data(hex: "0807")!)?.on, false)
    }
    func testGetAndParse() throws {
        eq(buildGet([Tag.battery]), "00dd0100010002000d00")
        let f = try Frame.parse(Data(hex: "00dd01000100070000000d0001002f")!)
        let (status, tlvs) = try parseStatusTLVs(f.payload)
        XCTAssertEqual(status, 0)
        XCTAssertEqual(tlvs, [TLV(Tag.battery, byte: 0x2f)])
        XCTAssertEqual(decodeSL1(tlvs[0].value)?.level, 47)
        XCTAssertEqual(try Frame.parse(ackFrame).command, Cmd.set)
    }
    /// First two TLVs of the captured connect reply: ProductID `5f21`, ColorID `09`.
    func testProductAndColour() throws {
        let (_, tlvs) = try parseStatusTLVs(Data(hex: "0000040002005f210500010009")!)
        XCTAssertEqual(tlvs.map(\.tag), [Tag.productID, Tag.colorID])
        let pid = try XCTUnwrap(Product.decodePID(tlvs[0].value))
        XCTAssertEqual(pid, 0x215F)
        XCTAssertEqual(Product.name(pid: pid), "JBL Tune 780NC")
        XCTAssertEqual(Product.colourKey(id: Int(tlvs[1].value[0])), "Beige")
        XCTAssertEqual(Product.colourName(id: 14), "Ghost Black")
        XCTAssertEqual(Product.colourKey(id: 37), "Teal")
        XCTAssertNil(Product.colourKey(id: 33))
        XCTAssertTrue(Product.isFamily(name: "JBL Tune 780NC"))
        XCTAssertTrue(Product.isFamily(name: "JBL TUNE 680NC"))
        XCTAssertFalse(Product.isFamily(name: "JBL Tune 770NC"))
        XCTAssertFalse(Product.isFamily(name: "Tune 780NC"))
        for f: Product.Feature in [.anc, .ambient, .talkThru, .voiceAware, .spatial, .balance, .autoOff, .voicePrompts, .powerOff] {
            XCTAssertTrue(Product.supports(f, pid: 0x215F), "780NC has every panel control")
            XCTAssertTrue(Product.supports(f, pid: nil), "unknown model keeps every control")
        }
        XCTAssertFalse(Product.supports(.anc, pid: 0x2162), "Tune 530BT has no ANC")
        XCTAssertFalse(Product.supports(.balance, pid: 0x21B3), "Vibe Buds 3 uses the other balance card")
    }
    func testRefusesUnverifiedTags() {
        for tag: UInt16 in [0x000F, 0x1F00, 0x0BA0, 0x0B86, 0x100F, 0x0E01, 0x0F82] {
            XCTAssertThrowsError(try buildSet([TLV(tag, byte: 0)]))
        }
    }
}

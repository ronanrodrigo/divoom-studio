import XCTest
#if os(iOS)
@testable import DivoomStudioMobile
#else
@testable import DivoomStudio
#endif

final class DivoomProtocolTests: XCTestCase {
    func testGoldenFramingAndChecksum() throws {
        XCTAssertEqual(DivoomProtocol.frame(Data([0x46])), Data([1, 3, 0, 0x46, 0x49, 0, 2]))
        XCTAssertEqual(DivoomProtocol.frame(DivoomProtocol.brightness(50)), Data([1, 4, 0, 0x74, 0x32, 0xAA, 0, 2]))
        let payload = Data([0x44, 1, 2, 3])
        XCTAssertEqual(try DivoomProtocol.decodeFrame(DivoomProtocol.frame(payload)), payload)
        XCTAssertEqual(DivoomProtocol.frame(payload).count, payload.count + 6, "Ditoo must not escape reserved bytes")
        XCTAssertThrowsError(try DivoomProtocol.decodeFrame(Data([1, 3, 0, 0x46, 0, 0, 2])))
        XCTAssertThrowsError(try DivoomProtocol.decodeFrame(Data([1, 3, 0, 0x46])))
    }

    func testIncrementalParserHandlesCoalescingAndEmbeddedMarkers() {
        let first = Data([0x04, 0x44, 0x55, 1, 2, 3])
        let second = Data([0x04, 0x46, 0x55, 0])
        let stream = Data([0x99, 0xFE]) + DivoomProtocol.frame(first) + DivoomProtocol.frame(second)
        var parser = DivoomFrameParser()
        XCTAssertTrue(parser.append(Data(stream.prefix(5))).isEmpty)
        XCTAssertEqual(parser.append(Data(stream.dropFirst(5))), [first, second])
        XCTAssertEqual(DivoomProtocol.acknowledgedCommand(in: first), 0x44)
        XCTAssertNil(DivoomProtocol.acknowledgedCommand(in: Data([4, 0x44, 0])))
    }

    func testTwoColorImageGoldenBitPacking() throws {
        let rgb: [UInt8] = (0..<256).flatMap { value -> [UInt8] in value.isMultiple(of: 2) ? [0, 0, 0] : [0, 0, 255] }
        let payload = try XCTUnwrap(DivoomProtocol.image(rgb: rgb).first)
        XCTAssertEqual(payload.count, 50)
        XCTAssertEqual(Array(payload.prefix(18)), [0x44, 0, 10, 10, 4, 0xAA, 45, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 255])
        XCTAssertEqual(Array(payload.dropFirst(18)), Array(repeating: 0xAA, count: 32))
        XCTAssertEqual(DivoomProtocol.frame(payload).count, 56)
    }

    func testFullPaletteUsesZeroCountAndEightBitIndices() throws {
        let rgb = (0..<256).flatMap { [UInt8($0), UInt8(0), UInt8(0)] }
        let payload = try XCTUnwrap(DivoomProtocol.image(rgb: rgb).first)
        XCTAssertEqual(payload[11], 0)
        XCTAssertEqual(payload.count, 5 + 7 + 768 + 256)
        XCTAssertEqual(Array(payload.suffix(256)), (0..<256).map(UInt8.init))
        XCTAssertEqual(Array(payload[6...7]), [7, 4]) // 1031-byte AA frame
    }

    func testAnimationChunkLengthsAndReassembly() throws {
        let rgb: [UInt8] = Array(repeating: [UInt8(0), UInt8(0), UInt8(255)], count: 256).flatMap { $0 }
        let payloads = try DivoomProtocol.animation(frames: Array(repeating: rgb, count: 6), durationMilliseconds: 125)
        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(Array(payloads[0].prefix(4)), [0x49, 252, 0, 0])
        XCTAssertEqual(Array(payloads[1].prefix(4)), [0x49, 252, 0, 1])
        XCTAssertEqual(payloads[0].count, 204)
        let reconstructed = payloads.reduce(Data()) { $0 + $1.dropFirst(4) }
        XCTAssertEqual(reconstructed.count, 252)
        XCTAssertEqual(Array(reconstructed.prefix(7)), [0xAA, 42, 0, 125, 0, 0, 1])
    }

    func testInvalidMediaAndLargeAnimationAreRejected() {
        XCTAssertThrowsError(try DivoomProtocol.image(rgb: [0]))
        XCTAssertThrowsError(try DivoomProtocol.animation(frames: [], durationMilliseconds: 100))
        let rgb = (0..<256).flatMap { [UInt8($0), UInt8(0), UInt8(0)] }
        XCTAssertThrowsError(try DivoomProtocol.animation(frames: [rgb, rgb], durationMilliseconds: 0))
        XCTAssertThrowsError(try DivoomProtocol.animation(frames: Array(repeating: rgb, count: 60), durationMilliseconds: 100))
    }

    func testAlarmAndClockGoldenPayloads() throws {
        XCTAssertEqual(try DivoomProtocol.alarm(slot: 0, enabled: true, hour: 7, minute: 30, weekdays: 0x3E, volume: 20), Data([0x43, 0, 1, 7, 30, 0x3E, 0, 0, 0, 0, 20]))
        XCTAssertThrowsError(try DivoomProtocol.alarm(slot: 0, enabled: true, hour: 24, minute: 0, weekdays: 0, volume: 20))
        XCTAssertEqual(DivoomProtocol.clock(style: 1, twentyFourHour: true, color: (255, 0, 20)), Data([0x45, 0, 1, 1, 1, 0, 0, 0, 255, 0, 20]))
        XCTAssertEqual(DivoomProtocol.brightness(999), Data([0x74, 100]))
        XCTAssertEqual(DivoomProtocol.brightness(-1), Data([0x74, 0]))
    }
}

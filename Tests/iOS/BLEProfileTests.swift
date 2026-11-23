import XCTest
@testable import DivoomStudioMobile

final class BLEProfileTests: XCTestCase {
    func testDitooPlusCapturedRCSPVectors() throws {
        // Live Ditoo Plus get-volume packet; MIT reference alikendir0/divoom-ble-web tests/test_protocol.py.
        XCTAssertEqual(try BLEProfile.rcspEnvelope(Data([0x09]), packetNumber: 1),
                       bytes("feefaa5508000101000000091300"))
        XCTAssertEqual(try BLEProfile.rcspEnvelope(Data([0x74, 0]), packetNumber: 1),
                       bytes("feefaa550900010100000074007f00"))
        let envelope = try BLEProfile.rcspEnvelope(Data([0x44, 1, 2, 3]), packetNumber: 0x12345678)
        XCTAssertEqual(Array(envelope[6...10]), [1, 0x78, 0x56, 0x34, 0x12])
        XCTAssertEqual(Array(envelope[11...14]), [0x44, 1, 2, 3], "No SPP framing or byte escaping inside RCSP")
        XCTAssertThrowsError(try BLEProfile.rcspEnvelope(Data(), packetNumber: 1))
        XCTAssertThrowsError(try BLEProfile.rcspEnvelope(Data(repeating: 0, count: 65529), packetNumber: 1))
    }

    func testPacketACKReassemblyAndCorrelation() {
        var parser = DivoomFrameParser()
        let stream = bytes("0109000433556b4c01004d010201060004325535c60002")
        XCTAssertTrue(parser.append(Data(stream.prefix(5))).isEmpty)
        let replies = parser.append(Data(stream.dropFirst(5)))
        XCTAssertEqual(replies.count, 2)
        XCTAssertEqual(BLEProfile.packetAcknowledgement(replies[0]), 0x00014C6B)
        XCTAssertNil(BLEProfile.packetAcknowledgement(replies[1]))
        XCTAssertNil(BLEProfile.packetAcknowledgement(Data([4, 0x33, 0x55, 1])))
        XCTAssertNil(BLEProfile.packetAcknowledgement(Data([4, 0x33, 0, 1, 0, 0, 0])))
    }

    func testProfileRequiresExactServiceAndBothCharacteristics() {
        let known = BLEProfile.issCSerial
        XCTAssertEqual(BLEProfile.recognized(serviceUUID: known.serviceUUID.lowercased(),
                                             characteristicUUIDs: [known.writeUUID.lowercased(), known.notifyUUID.lowercased()]), known)
        XCTAssertNil(BLEProfile.recognized(serviceUUID: "FFF0", characteristicUUIDs: [known.writeUUID, known.notifyUUID]))
        XCTAssertNil(BLEProfile.recognized(serviceUUID: known.serviceUUID, characteristicUUIDs: [known.writeUUID]))
        XCTAssertNil(BLEProfile.recognized(serviceUUID: known.serviceUUID, characteristicUUIDs: ["49535343-ACA3-481C-91EC-D85E28A60318", known.notifyUUID]))
    }

    func testSingleColorPlusAdaptationDoesNotChangeSharedClassicCodec() throws {
        let classic = try XCTUnwrap(DivoomProtocol.image(rgb: Array(repeating: [UInt8(255), UInt8(0), UInt8(0)], count: 256).flatMap { $0 }).first)
        XCTAssertEqual(classic.count, 47)
        XCTAssertEqual(BLEProfile.prepareCommandPayload(classic), bytes("44000a0a04aa0a0000000001ff0000"))
        XCTAssertEqual(classic.count, 47, "Classic Mac codec remains unchanged")
        let twoColor = try XCTUnwrap(DivoomProtocol.image(rgb: (0..<256).flatMap { index -> [UInt8] in index.isMultiple(of: 2) ? [0, 0, 0] : [255, 255, 255] }).first)
        XCTAssertEqual(BLEProfile.prepareCommandPayload(twoColor), twoColor)
    }

    func testPlusAnimationMonochromeFramesAndAnnounceGolden() throws {
        let red = Array(repeating: [UInt8(255), UInt8(0), UInt8(0)], count: 256).flatMap { $0 }
        let blue = Array(repeating: [UInt8(0), UInt8(0), UInt8(255)], count: 256).flatMap { $0 }
        let transfer = try BLEProfile.animationPayloads(frames: [red, blue], durationMilliseconds: 100)
        XCTAssertEqual(transfer.encodedFrames, bytes("aa0a0064000001ff0000aa0a00640000010000ff"))
        XCTAssertEqual(transfer.announce, bytes("8b0014000000"))
        XCTAssertEqual(transfer.chunks, [bytes("8b01140000000000") + transfer.encodedFrames])
        XCTAssertEqual(transfer.encodedFrames.first, 0xAA, "Never the MiniToo 0x25/Zstandard format")
    }

    func testPlusAnimationChunkReassemblyAndPalette256() throws {
        let rgb = (0..<256).flatMap { [UInt8($0), UInt8(0), UInt8(0)] }
        let transfer = try BLEProfile.animationPayloads(frames: [rgb, rgb], durationMilliseconds: 0x1234)
        XCTAssertEqual(transfer.encodedFrames.count, 2062)
        XCTAssertEqual(transfer.announce, bytes("8b000e080000"))
        XCTAssertEqual(transfer.chunks.count, 9)
        var reconstructed = Data()
        for (index, chunk) in transfer.chunks.enumerated() {
            XCTAssertEqual(Array(chunk.prefix(8)), [0x8B, 1, 0x0E, 8, 0, 0, UInt8(index), 0])
            XCTAssertLessThanOrEqual(chunk.count, 264)
            reconstructed.append(chunk.dropFirst(8))
        }
        XCTAssertEqual(reconstructed, transfer.encodedFrames)
        XCTAssertEqual(Array(reconstructed.prefix(7)), [0xAA, 7, 4, 0x34, 0x12, 0, 0])
        XCTAssertEqual(Array(reconstructed[775..<1031]), (0..<256).map(UInt8.init))
    }

    func testPlusAnimationRejectsLimitsInsteadOfDroppingFrames() {
        let rgb = (0..<256).flatMap { [UInt8($0), UInt8(0), UInt8(0)] }
        XCTAssertThrowsError(try BLEProfile.animationPayloads(frames: [], durationMilliseconds: 100))
        XCTAssertThrowsError(try BLEProfile.animationPayloads(frames: [rgb], durationMilliseconds: 100))
        XCTAssertThrowsError(try BLEProfile.animationPayloads(frames: [[0], rgb], durationMilliseconds: 100))
        XCTAssertThrowsError(try BLEProfile.animationPayloads(frames: [rgb, rgb], durationMilliseconds: 0))
        XCTAssertThrowsError(try BLEProfile.animationPayloads(frames: [rgb, rgb], durationMilliseconds: 65536))
        XCTAssertThrowsError(try BLEProfile.animationPayloads(frames: Array(repeating: rgb, count: 47), durationMilliseconds: 100))
        XCTAssertThrowsError(try BLEProfile.animationPayloads(frames: Array(repeating: rgb, count: 61), durationMilliseconds: 100))
    }

    func testAnimationReadyRequiresSpecificCommandReplyNotEnvelopeACK() {
        XCTAssertTrue(BLEProfile.isAnimationReadyReply(Data([4, 0x8B, 0x55, 0, 1])))
        XCTAssertFalse(BLEProfile.isAnimationReadyReply(Data([4, 0x33, 0x55, 0, 1, 0, 0])))
        XCTAssertFalse(BLEProfile.isAnimationReadyReply(Data([4, 0x8B, 0x55, 1])))
        XCTAssertFalse(BLEProfile.isAnimationReadyReply(Data([4, 0x8B, 0, 0])))
        XCTAssertFalse(BLEProfile.isAnimationReadyReply(Data([4, 0x8B, 0x55])))
    }

    func testCancelledConnectionCannotBeReusedBeforeTerminalCallback() throws {
        let id = UUID()
        var gate = BLESessionGate()
        let oldEpoch = try XCTUnwrap(gate.begin(deviceID: id))
        XCTAssertTrue(gate.accepts(epoch: oldEpoch, deviceID: id))
        gate.cancel()
        XCTAssertFalse(gate.accepts(epoch: oldEpoch, deviceID: id))
        XCTAssertNil(gate.begin(deviceID: id), "Same UUID cannot reconnect before the cancelled attempt terminates")
        XCTAssertFalse(gate.finishCancellation(deviceID: UUID()), "Other devices cannot release this barrier")
        gate.cancel() // repeated Disconnect must keep the original cancellation barrier
        XCTAssertNil(gate.begin(deviceID: id))
        XCTAssertTrue(gate.finishCancellation(deviceID: id))
        let newEpoch = try XCTUnwrap(gate.begin(deviceID: id))
        XCTAssertNotEqual(oldEpoch, newEpoch)
        XCTAssertFalse(gate.accepts(epoch: oldEpoch, deviceID: id), "Old write/ready/notify callbacks cannot complete a new operation")
        XCTAssertTrue(gate.accepts(epoch: newEpoch, deviceID: id))
    }

    func testBluetoothStackResetInvalidatesActiveAndCancellingEpochs() throws {
        let id = UUID()
        var gate = BLESessionGate()
        let oldEpoch = try XCTUnwrap(gate.begin(deviceID: id))
        gate.invalidate()
        XCTAssertFalse(gate.accepts(epoch: oldEpoch, deviceID: id))
        XCTAssertTrue(gate.mayConnect)
        _ = gate.begin(deviceID: id)
        gate.cancel()
        gate.invalidate()
        XCTAssertNil(gate.cancellingDeviceID)
        XCTAssertNil(gate.activeDeviceID)
        XCTAssertTrue(gate.mayConnect)
        XCTAssertFalse(gate.finishCancellation(deviceID: id), "A stale old terminal callback has no active cancellation to release")
    }

    func testDiscoveryAcceptsRenamedOrUnnamedKnownService() {
        let service = BLEProfile.issCSerial.serviceUUID.lowercased()
        XCTAssertTrue(BLEProfile.isDiscoveryCandidate(localName: nil, peripheralName: nil, advertisedServiceUUIDs: [service]))
        XCTAssertTrue(BLEProfile.isDiscoveryCandidate(localName: "Mesa do escritório", peripheralName: "Meu visor", advertisedServiceUUIDs: [service]))
        XCTAssertEqual(BLEProfile.discoveryName(localName: "  ", peripheralName: "Ditoo-Plus-light"), "Ditoo-Plus-light")
        XCTAssertEqual(BLEProfile.discoveryName(localName: nil, peripheralName: nil), "BLE com serviço compatível (sem nome)")
    }

    func testDiscoveryChecksBothNamesWithoutRequiringAdvertisedService() {
        XCTAssertTrue(BLEProfile.isDiscoveryCandidate(localName: "Ditoo-Plus-light", peripheralName: nil, advertisedServiceUUIDs: []))
        XCTAssertTrue(BLEProfile.isDiscoveryCandidate(localName: "", peripheralName: "Divoom", advertisedServiceUUIDs: []))
        XCTAssertTrue(BLEProfile.isDiscoveryCandidate(localName: "Nome local genérico", peripheralName: "DITOO", advertisedServiceUUIDs: []))
        XCTAssertTrue(BLEProfile.isDiscoveryCandidate(localName: "Pixoo", peripheralName: nil, advertisedServiceUUIDs: []))
    }

    func testDiscoveryRejectsUnrelatedAdvertisements() {
        XCTAssertFalse(BLEProfile.isDiscoveryCandidate(localName: "Fones", peripheralName: "Fones", advertisedServiceUUIDs: ["180F"]))
        XCTAssertFalse(BLEProfile.isDiscoveryCandidate(localName: nil, peripheralName: nil, advertisedServiceUUIDs: []))
        XCTAssertFalse(BLEProfile.isDiscoveryCandidate(localName: "Visor", peripheralName: nil, advertisedServiceUUIDs: ["FFF0"]))
        XCTAssertFalse(BLEProfile.isDiscoveryCandidate(localName: "Visor", peripheralName: nil, advertisedServiceUUIDs: [BLEProfile.issCSerial.writeUUID]))
    }

    @MainActor
    func testControllerStartsInDiagnosticModeWithoutScanning() throws {
        let suiteName = "DivoomStudio.BLETests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = MobileBluetoothController(defaults: defaults)
        XCTAssertFalse(controller.isScanning)
        XCTAssertFalse(controller.isConnected)
        XCTAssertFalse(controller.canSend)
        XCTAssertTrue(controller.devices.isEmpty)
        XCTAssertEqual(controller.profileSelection, .diagnostic)
    }

    private func bytes(_ hex: String) -> Data {
        Data(stride(from: 0, to: hex.count, by: 2).map { index in
            let start = hex.index(hex.startIndex, offsetBy: index)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        })
    }
}

import Foundation

/// Explicit opt-in prevents assuming that every device using ISSC UART speaks the same protocol.
enum BLEProtocolSelection: String, CaseIterable, Identifiable, Sendable {
    case diagnostic = "Somente diagnóstico"
    case ditooPlusRCSP = "Controlar Ditoo Plus (experimental)"
    var id: String { rawValue }
}

/// Observed on Ditoo Plus by this independent interoperability implementation:
/// https://github.com/alikendir0/divoom-ble-web/blob/03b2d4096a7650e9ccfd2e560d0e5df5f9f23085/docs/protocol.md
/// https://github.com/alikendir0/divoom-ble-web/blob/03b2d4096a7650e9ccfd2e560d0e5df5f9f23085/divoom_ble/protocol.py
/// UART UUIDs alone are not proof of compatibility with this particular physical device.
struct BLEProfile: Equatable, Sendable {
    let name: String
    let serviceUUID: String
    let writeUUID: String
    let notifyUUID: String

    static let issCSerial = BLEProfile(
        name: "UART ISSC identificado; escolha explícita de protocolo necessária",
        serviceUUID: "49535343-FE7D-4AE5-8FA9-9FAFD205E455",
        writeUUID: "49535343-8841-43F4-A8D4-ECBE34729BB3",
        notifyUUID: "49535343-1E4D-4BD9-BA61-23C647249616"
    )

    static func recognized(serviceUUID: String, characteristicUUIDs: Set<String>) -> BLEProfile? {
        let characteristics = Set(characteristicUUIDs.map { $0.uppercased() })
        let candidate = issCSerial
        guard serviceUUID.uppercased() == candidate.serviceUUID,
              characteristics.contains(candidate.writeUUID),
              characteristics.contains(candidate.notifyUUID) else { return nil }
        return candidate
    }

    /// The shared Classic encoder uses a 1-bit all-zero index plane for a single color.
    /// The Plus BLE reference's captured format uses zero bits; adapt only that exact layout.
    static func prepareCommandPayload(_ payload: Data) -> Data {
        let bytes = Array(payload)
        guard bytes.count == 47, Array(bytes.prefix(6)) == [0x44, 0, 10, 10, 4, 0xAA],
              bytes[6] == 42, bytes[7] == 0, bytes[11] == 1,
              bytes[15...].allSatisfy({ $0 == 0 }) else { return payload }
        var result = Data(bytes.prefix(15))
        result[6] = 10
        return result
    }

    enum EncodingError: Error { case invalidPayload, invalidAnimation, animationTooLarge }

    /// Accepts command+body, not a preframed RFCOMM packet. No byte escaping.
    /// FE EF AA55 LEN_LE16 RELIABLE=01 PACKET_LE32 CMD BODY CHECKSUM_LE16.
    static func rcspEnvelope(_ payload: Data, packetNumber: UInt32) throws -> Data {
        guard !payload.isEmpty, payload.count <= 65528 else { throw EncodingError.invalidPayload }
        let length = UInt16(7 + payload.count)
        var core = Data([UInt8(length & 255), UInt8(length >> 8), 1,
                         UInt8(packetNumber & 255), UInt8((packetNumber >> 8) & 255),
                         UInt8((packetNumber >> 16) & 255), UInt8(packetNumber >> 24)])
        core.append(payload)
        let checksum = core.reduce(UInt16(0)) { $0 &+ UInt16($1) }
        return Data([0xFE, 0xEF, 0xAA, 0x55]) + core + Data([UInt8(checksum & 255), UInt8(checksum >> 8)])
    }

    struct AnimationTransfer: Sendable {
        let announce: Data
        let chunks: [Data]
        let encodedFrames: Data
    }

    /// Plus 0x8B carries concatenated AA palette frames, never MiniToo 0x25/Zstandard.
    /// Reference: divoom-ble-web/divoom_ble/display.py encode_animation and _upload.
    /// The reference caps content at 48 KB; reject excess instead of silently dropping frames.
    static func animationPayloads(frames: [[UInt8]], durationMilliseconds: Int) throws -> AnimationTransfer {
        guard (2...60).contains(frames.count), (1...65535).contains(durationMilliseconds) else {
            throw EncodingError.invalidAnimation
        }
        var encoded = Data()
        for pixels in frames {
            guard let classic = try DivoomProtocol.image(rgb: pixels).first else { throw EncodingError.invalidAnimation }
            var frame = Data(prepareCommandPayload(classic).dropFirst(5))
            frame[3] = UInt8(durationMilliseconds & 255)
            frame[4] = UInt8(durationMilliseconds >> 8)
            encoded.append(frame)
        }
        guard encoded.count <= 48_000 else { throw EncodingError.animationTooLarge }
        let total = UInt32(encoded.count)
        let size = Data([UInt8(total & 255), UInt8((total >> 8) & 255), UInt8((total >> 16) & 255), UInt8(total >> 24)])
        let chunks = stride(from: 0, to: encoded.count, by: 256).enumerated().map { index, offset in
            Data([0x8B, 1]) + size + Data([UInt8(index & 255), UInt8(index >> 8)])
                + encoded.subdata(in: offset..<min(offset + 256, encoded.count))
        }
        return AnimationTransfer(announce: Data([0x8B, 0]) + size, chunks: chunks, encodedFrames: encoded)
    }

    /// The device requests animation data with a 0x8B command reply, control byte 0.
    /// An envelope ACK (0x33) or an unrelated/final animation reply is not this request.
    static func isAnimationReadyReply(_ payload: Data) -> Bool {
        let bytes = Array(payload)
        return bytes.count >= 4 && bytes[0] == 4 && bytes[1] == 0x8B && bytes[2] == 0x55 && bytes[3] == 0
    }

    /// Called only after the shared length/checksum-validating reply parser.
    static func packetAcknowledgement(_ payload: Data) -> UInt32? {
        let bytes = Array(payload)
        guard bytes.count == 7, bytes[0] == 4, bytes[1] == 0x33, bytes[2] == 0x55 else { return nil }
        return UInt32(bytes[3]) | UInt32(bytes[4]) << 8 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 24
    }
}

/// Pure lifecycle gate. A cancelled connection must reach its terminal callback before reuse.
/// Each peripheral delegate belongs to one epoch, so queued write/notify callbacks cannot
/// complete continuations belonging to a later connection to the same peripheral UUID.
struct BLESessionGate: Sendable {
    private(set) var epoch = UUID()
    private(set) var activeDeviceID: UUID?
    private(set) var cancellingDeviceID: UUID?
    var mayConnect: Bool { activeDeviceID == nil && cancellingDeviceID == nil }

    mutating func begin(deviceID: UUID) -> UUID? {
        guard mayConnect else { return nil }
        epoch = UUID()
        activeDeviceID = deviceID
        return epoch
    }
    mutating func cancel() {
        epoch = UUID()
        if let activeDeviceID { cancellingDeviceID = activeDeviceID }
        activeDeviceID = nil
    }
    mutating func finishCancellation(deviceID: UUID) -> Bool {
        guard cancellingDeviceID == deviceID else { return false }
        cancellingDeviceID = nil
        return true
    }
    mutating func invalidate() {
        epoch = UUID()
        activeDeviceID = nil
        cancellingDeviceID = nil
    }
    func accepts(epoch: UUID, deviceID: UUID) -> Bool {
        self.epoch == epoch && activeDeviceID == deviceID && cancellingDeviceID == nil
    }
}

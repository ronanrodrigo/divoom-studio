import Foundation

/// Legacy 16×16 Ditoo LED protocol. This is not the MiniToo LCD/Zstandard format.
/// References (MIT): https://github.com/d03n3rfr1tz3/hass-divoom/blob/0e9959a9009d9f8ce3be79476f464d593d85bc91/custom_components/divoom/devices/divoom.py
/// https://github.com/RomRider/node-divoom-timebox-evo/blob/2a086b86feaca1b544029f97803336579f0d3a25/PROTOCOL.md
/// Methods return command+body payloads; only frame(_:) adds transport framing.
enum DivoomProtocol {
    enum CodecError: Error, LocalizedError {
        case invalidPixels, invalidFrames, invalidDuration, transferTooLarge, invalidFrame, invalidChecksum, invalidAlarm
        var errorDescription: String? {
            switch self {
            case .invalidPixels: "Cada quadro deve ter exatamente 256 pixels RGB (768 bytes)."
            case .invalidFrames: "A animação deve ter de 2 a 60 quadros."
            case .invalidDuration: "A duração deve estar entre 1 e 65535 milissegundos."
            case .transferTooLarge: "A transferência excede os limites do protocolo Ditoo."
            case .invalidFrame: "Pacote Bluetooth inválido ou incompleto."
            case .invalidChecksum: "A soma de verificação do pacote é inválida."
            case .invalidAlarm: "Horário, repetição ou volume do alarme inválido."
            }
        }
    }

    static func frame(_ payload: Data) -> Data {
        precondition(!payload.isEmpty && payload.count <= 65533)
        let length = UInt16(payload.count + 2)
        var inner = Data([UInt8(length & 255), UInt8(length >> 8)])
        inner.append(payload)
        let sum = inner.reduce(UInt16(0)) { $0 &+ UInt16($1) }
        return Data([1]) + inner + Data([UInt8(sum & 255), UInt8(sum >> 8), 2])
    }

    static func decodeFrame(_ frame: Data) throws -> Data {
        let bytes = Array(frame)
        guard bytes.count >= 7, bytes.first == 1, bytes.last == 2 else { throw CodecError.invalidFrame }
        let length = Int(bytes[1]) | Int(bytes[2]) << 8
        guard length >= 3, bytes.count == length + 4 else { throw CodecError.invalidFrame }
        let expected = UInt16(bytes[bytes.count - 3]) | UInt16(bytes[bytes.count - 2]) << 8
        let actual = bytes[1..<(bytes.count - 3)].reduce(UInt16(0)) { $0 &+ UInt16($1) }
        guard expected == actual else { throw CodecError.invalidChecksum }
        return Data(bytes[3..<(bytes.count - 3)])
    }

    /// ACK observations are transport evidence, not proof that the display changed.
    static func acknowledgedCommand(in payload: Data) -> UInt8? {
        let bytes = Array(payload)
        guard bytes.count >= 3, bytes[0] == 4, bytes[2] == 0x55 else { return nil }
        return bytes[1]
    }

    static func brightness(_ value: Int) -> Data { Data([0x74, UInt8(clamping: min(100, max(0, value)))]) }
    static func screen(_ enabled: Bool) -> Data {
        light(color: (1, 1, 1), brightness: enabled ? 100 : 0, effect: 0, enabled: enabled)
    }
    static func channel(_ channel: UInt8) -> Data { Data([0x45, channel]) }
    static func clock(style: UInt8, twentyFourHour: Bool, color: (UInt8, UInt8, UInt8)) -> Data {
        Data([0x45, 0, twentyFourHour ? 1 : 0, min(style, 15), 1, 0, 0, 0, color.0, color.1, color.2])
    }
    static func timeFormat(twentyFourHour: Bool) -> Data { Data([0x2D, twentyFourHour ? 1 : 0]) }
    static func syncTime(_ date: Date) -> Data {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        let year = parts.year ?? 2000
        return Data([0x18, UInt8(clamping: year % 100), UInt8(clamping: year / 100), UInt8(parts.month ?? 1), UInt8(parts.day ?? 1), UInt8(parts.hour ?? 0), UInt8(parts.minute ?? 0), UInt8(parts.second ?? 0), UInt8((parts.weekday ?? 1) - 1)])
    }
    static func light(color: (UInt8, UInt8, UInt8), brightness: Int, effect: UInt8 = 0, enabled: Bool = true) -> Data {
        Data([0x45, 1, color.0, color.1, color.2, UInt8(clamping: min(100, max(0, brightness))), min(effect, 4), enabled ? 1 : 0, 0, 0, 0])
    }
    static func effect(_ index: UInt8) -> Data { Data([0x45, 3, index]) }
    static func visualizer(_ index: UInt8) -> Data { Data([0x45, 4, index]) }

    /// Sunday is bit 0; Saturday bit 6. Modes stay at hass-divoom's defaults until hardware validation.
    static func alarm(slot: UInt8, enabled: Bool, hour: Int, minute: Int, weekdays: UInt8, volume: Int) throws -> Data {
        guard (0...23).contains(hour), (0...59).contains(minute), weekdays <= 0x7F, (0...100).contains(volume) else { throw CodecError.invalidAlarm }
        return Data([0x43, slot, enabled ? 1 : 0, UInt8(hour), UInt8(minute), weekdays, 0, 0, 0, 0, UInt8(volume)])
    }

    static func image(rgb: [UInt8]) throws -> [Data] {
        let encoded = try paletteFrame(rgb: rgb, duration: 0)
        return [Data([0x44, 0, 0x0A, 0x0A, 4]) + encoded]
    }
    static func animation(frames: [[UInt8]], durationMilliseconds: Int) throws -> [Data] {
        guard (2...60).contains(frames.count) else { throw CodecError.invalidFrames }
        guard (1...65535).contains(durationMilliseconds) else { throw CodecError.invalidDuration }
        var encoded = Data()
        for rgb in frames { encoded.append(try paletteFrame(rgb: rgb, duration: UInt16(durationMilliseconds))) }
        let chunkCount = (encoded.count + 199) / 200
        guard encoded.count <= 65535, chunkCount <= 256 else { throw CodecError.transferTooLarge }
        let total = UInt16(encoded.count)
        return stride(from: 0, to: encoded.count, by: 200).enumerated().map { sequence, offset in
            Data([0x49, UInt8(total & 255), UInt8(total >> 8), UInt8(sequence)]) + encoded.subdata(in: offset..<min(offset + 200, encoded.count))
        }
    }

    private static func paletteFrame(rgb: [UInt8], duration: UInt16) throws -> Data {
        guard rgb.count == 768 else { throw CodecError.invalidPixels }
        var palette: [UInt32] = []
        var lookup: [UInt32: Int] = [:]
        var indices: [Int] = []
        for offset in stride(from: 0, to: rgb.count, by: 3) {
            let color = UInt32(rgb[offset]) << 16 | UInt32(rgb[offset + 1]) << 8 | UInt32(rgb[offset + 2])
            if let index = lookup[color] { indices.append(index) }
            else {
                lookup[color] = palette.count
                indices.append(palette.count)
                palette.append(color)
            }
        }
        var bits = 1
        while (1 << bits) < palette.count { bits += 1 }
        var pixels = Data()
        var accumulator = 0
        var bitCount = 0
        for index in indices {
            accumulator |= index << bitCount
            bitCount += bits
            while bitCount >= 8 {
                pixels.append(UInt8(accumulator & 255))
                accumulator >>= 8
                bitCount -= 8
            }
        }
        if bitCount > 0 { pixels.append(UInt8(accumulator & 255)) }
        let length = UInt16(7 + palette.count * 3 + pixels.count)
        var result = Data([0xAA, UInt8(length & 255), UInt8(length >> 8), UInt8(duration & 255), UInt8(duration >> 8), 0, UInt8(palette.count & 255)])
        for color in palette { result.append(contentsOf: [UInt8((color >> 16) & 255), UInt8((color >> 8) & 255), UInt8(color & 255)]) }
        result.append(pixels)
        return result
    }
}

/// Length-based reassembly: reserved marker bytes are valid inside an unescaped Ditoo packet.
struct DivoomFrameParser {
    private var buffer = Data()
    mutating func append(_ bytes: Data) -> [Data] {
        buffer.append(bytes)
        var payloads: [Data] = []
        while !buffer.isEmpty {
            guard let start = buffer.firstIndex(of: 1) else { buffer.removeAll(keepingCapacity: true); break }
            if start != buffer.startIndex { buffer.removeSubrange(buffer.startIndex..<start) }
            guard buffer.count >= 3 else { break }
            let header = Array(buffer.prefix(3))
            let length = Int(header[1]) | Int(header[2]) << 8
            guard length >= 3, length <= 8192 else { buffer.removeFirst(); continue }
            let count = length + 4
            guard buffer.count >= count else { break }
            let candidate = Data(buffer.prefix(count))
            if let payload = try? DivoomProtocol.decodeFrame(candidate) {
                payloads.append(payload)
                buffer.removeFirst(count)
            } else { buffer.removeFirst() }
        }
        return payloads
    }
    mutating func reset() { buffer.removeAll(keepingCapacity: true) }
}

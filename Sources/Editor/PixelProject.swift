import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct PixelFrame: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var rgb: [UInt8] = Array(repeating: 0, count: 16 * 16 * 3)
}

struct PixelProject: Codable, Equatable, Sendable {
    var formatVersion = 1
    var name = "Sem título"
    var durationMilliseconds = 200
    var frames = [PixelFrame()]

    static func load(from url: URL) throws -> Self {
        let limit = 2_000_000
        let info = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard info.isRegularFile == true, let size = info.fileSize, size <= limit else {
            throw CocoaError(.fileReadTooLarge)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // Bound the read itself as well as metadata: the file can grow after stat.
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }

    func validated() throws -> Self {
        guard formatVersion == 1, !frames.isEmpty, frames.count <= 60,
              frames.allSatisfy({ $0.rgb.count == 768 }),
              Set(frames.map(\.id)).count == frames.count,
              (50...5000).contains(durationMilliseconds) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return self
    }
}

struct LibraryEntry: Identifiable, Equatable {
    let id: URL
    let name: String
}

struct ImportedPixelMedia {
    let frames: [PixelFrame]
    let durationMilliseconds: Int
    let hasVariableTiming: Bool
}

enum PixelMedia {
    static func importFrames(from url: URL) throws -> [PixelFrame] { try importMedia(from: url).frames }

    static func importMedia(from url: URL) throws -> ImportedPixelMedia {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let count = min(CGImageSourceGetCount(source), 60)
        guard count > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let durations: [Int] = (0..<count).map { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let seconds = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0.2
            return min(5000, max(50, Int((seconds * 1000).rounded())))
        }
        let frames = try (0..<count).map { index in
            // Decode a bounded, orientation-corrected thumbnail rather than the full-resolution image.
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 16
            let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 16
            let ratio = max(width, height) / max(1, min(width, height))
            let thumbnailSize = min(512, max(16, Int(ceil(16 * ratio))))
            let options: CFDictionary = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: thumbnailSize,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, index, options) else { throw CocoaError(.fileReadCorruptFile) }
            let side = min(thumbnail.width, thumbnail.height)
            let crop = CGRect(x: (thumbnail.width - side) / 2, y: (thumbnail.height - side) / 2, width: side, height: side)
            guard let image = thumbnail.cropping(to: crop) else { throw CocoaError(.fileReadCorruptFile) }
            var rgba = [UInt8](repeating: 0, count: 16 * 16 * 4)
            let success = rgba.withUnsafeMutableBytes { bytes -> Bool in
                guard let context = CGContext(data: bytes.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
                return true
            }
            guard success else { throw CocoaError(.fileReadCorruptFile) }
            var frame = PixelFrame()
            for pixel in 0..<256 { for component in 0..<3 { frame.rgb[pixel * 3 + component] = rgba[pixel * 4 + component] } }
            return frame
        }
        return ImportedPixelMedia(frames: frames, durationMilliseconds: durations[0], hasVariableTiming: Set(durations).count > 1)
    }

    static func image(_ rgb: [UInt8]) -> CGImage? {
        guard rgb.count == 768, let provider = CGDataProvider(data: Data(rgb) as CFData) else { return nil }
        return CGImage(width: 16, height: 16, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: 48, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    static func export(_ project: PixelProject, to url: URL, animated: Bool) throws {
        let frames = animated ? project.frames : Array(project.frames.prefix(1))
        let type = animated ? UTType.gif.identifier : UTType.png.identifier
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, frames.count, nil) else { throw CocoaError(.fileWriteUnknown) }
        if animated { CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary) }
        for frame in frames {
            guard let image = image(frame.rgb) else { throw CocoaError(.fileWriteUnknown) }
            let properties: CFDictionary? = animated ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: Double(project.durationMilliseconds) / 1000]] as CFDictionary : nil
            CGImageDestinationAddImage(destination, image, properties)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}

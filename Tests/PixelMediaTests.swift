import XCTest
import ImageIO
import UniformTypeIdentifiers
#if os(iOS)
@testable import DivoomStudioMobile
#else
@testable import DivoomStudio
#endif

final class PixelMediaTests: XCTestCase {
    private func temporaryURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }

    func testPNGRoundTripPreservesTopBottomAndRGBOrder() throws {
        var frame = PixelFrame()
        for y in 0..<16 {
            for x in 0..<16 {
                let color: [UInt8] = y < 8 ? [255, 0, 0] : [0, 0, 255]
                frame.rgb.replaceSubrange(((y * 16 + x) * 3)..<((y * 16 + x) * 3 + 3), with: color)
            }
        }
        var project = PixelProject(); project.frames = [frame]
        let url = temporaryURL("png"); defer { try? FileManager.default.removeItem(at: url) }
        try PixelMedia.export(project, to: url, animated: false)
        let imported = try XCTUnwrap(PixelMedia.importFrames(from: url).first)
        XCTAssertEqual(imported.rgb, frame.rgb, "PNG import/export must preserve orientation and RGB channel order")
    }

    func testNonSquareImportCropsCenterInsteadOfStretching() throws {
        // 48×16 image: red left third, green central square, blue right third.
        let pixels: [UInt8] = (0..<(48 * 16)).flatMap { index -> [UInt8] in
            switch index % 48 { case 0..<16: [255, 0, 0]; case 16..<32: [0, 255, 0]; default: [0, 0, 255] }
        }
        let url = temporaryURL("png"); defer { try? FileManager.default.removeItem(at: url) }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(width: 48, height: 16, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: 144, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let imported = try XCTUnwrap(PixelMedia.importFrames(from: url).first)
        XCTAssertEqual(imported.rgb, Array(repeating: [UInt8(0), 255, 0], count: 256).flatMap { $0 })
    }

    func testEXIFOrientationIsAppliedDuringThumbnailDecode() throws {
        var rgb = [UInt8]()
        for _ in 0..<16 { for x in 0..<16 { rgb += x < 8 ? [255, 0, 0] : [0, 0, 255] } }
        let image = try XCTUnwrap(PixelMedia.image(rgb))
        let url = temporaryURL("jpg"); defer { try? FileManager.default.removeItem(at: url) }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        // The JPEG encoder omits a bare kCGImagePropertyOrientation. Inject a minimal
        // standards-shaped Exif APP1/TIFF IFD with tag 0x0112 (SHORT, count 1, value 6).
        // This makes the fixture carry real orientation metadata instead of assuming
        // CGImageDestination wrote the requested tag.
        var jpeg = try Data(contentsOf: url)
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xFF, 0xD8])
        let orientationAPP1: [UInt8] = [
            0xFF, 0xE1, 0, 34, 0x45, 0x78, 0x69, 0x66, 0, 0,
            0x49, 0x49, 0x2A, 0, 8, 0, 0, 0,
            1, 0, 0x12, 1, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0,
            0, 0, 0, 0
        ]
        jpeg.insert(contentsOf: orientationAPP1, at: 2)
        try jpeg.write(to: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, 6)
        let imported = try XCTUnwrap(PixelMedia.importFrames(from: url).first)
        // EXIF 6 rotates the red left half to the top and blue right half to the bottom.
        let top = (2 * 16 + 8) * 3
        let bottom = (13 * 16 + 8) * 3
        XCTAssertGreaterThan(imported.rgb[top], 220)
        XCTAssertLessThan(imported.rgb[top + 2], 30)
        XCTAssertGreaterThan(imported.rgb[bottom + 2], 220)
        XCTAssertLessThan(imported.rgb[bottom], 30)
    }

    func testGIFRoundTripPreservesUniformTimingAndColors() throws {
        var project = PixelProject()
        let red = PixelFrame(rgb: Array(repeating: [UInt8(255), 0, 0], count: 256).flatMap { $0 })
        let blue = PixelFrame(rgb: Array(repeating: [UInt8(0), 0, 255], count: 256).flatMap { $0 })
        project.frames = [red, blue]
        project.durationMilliseconds = 250
        let url = temporaryURL("gif"); defer { try? FileManager.default.removeItem(at: url) }
        try PixelMedia.export(project, to: url, animated: true)
        let imported = try PixelMedia.importMedia(from: url)
        XCTAssertEqual(imported.frames.count, 2)
        XCTAssertEqual(imported.durationMilliseconds, 250)
        XCTAssertFalse(imported.hasVariableTiming)
        XCTAssertEqual(imported.frames[0].rgb, red.rgb)
        XCTAssertEqual(imported.frames[1].rgb, blue.rgb)
    }

    func testGIFVariableTimingIsDetectedAndFirstDurationChosen() throws {
        let url = temporaryURL("gif"); defer { try? FileManager.default.removeItem(at: url) }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil))
        for (color, duration) in [([UInt8(255), 0, 0], 0.15), ([UInt8(0), 0, 255], 0.3)] {
            let pixels = Array(repeating: color, count: 256).flatMap { $0 }
            let image = try XCTUnwrap(PixelMedia.image(pixels))
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: duration]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let imported = try PixelMedia.importMedia(from: url)
        XCTAssertEqual(imported.durationMilliseconds, 150)
        XCTAssertTrue(imported.hasVariableTiming)
        XCTAssertEqual(imported.frames.count, 2)
    }

    func testProjectJSONRoundTripAndValidationRejectsCorruptShape() throws {
        let project = PixelProject()
        let decoded = try JSONDecoder().decode(PixelProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(try decoded.validated(), project)
        var invalid = project; invalid.frames = []
        XCTAssertThrowsError(try invalid.validated())
        invalid = project; invalid.frames.append(invalid.frames[0])
        XCTAssertThrowsError(try invalid.validated())
        invalid = project; invalid.durationMilliseconds = 0
        XCTAssertThrowsError(try invalid.validated())
        invalid.durationMilliseconds = 5001
        XCTAssertThrowsError(try invalid.validated())
        invalid = project; invalid.frames[0].rgb = [1, 2, 3]
        XCTAssertThrowsError(try invalid.validated())
    }
    func testProjectFileLoadRejectsSparseOversizedFileAndLoadsValidProject() throws {
        let url = temporaryURL("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let project = PixelProject()
        try JSONEncoder().encode(project).write(to: url)
        XCTAssertEqual(try PixelProject.load(from: url), project)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 100_000_000)
        try handle.close()
        XCTAssertThrowsError(try PixelProject.load(from: url)) { error in
            XCTAssertEqual((error as NSError).code, CocoaError.fileReadTooLarge.rawValue)
        }
    }

}

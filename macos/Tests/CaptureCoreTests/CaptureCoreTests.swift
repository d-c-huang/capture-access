import CoreGraphics
import ImageIO
import XCTest
@testable import CaptureCore

final class CaptureCoreTests: XCTestCase {
    func testRetinaSizeIsPixelAccurate() throws {
        let size = try CaptureSize.calculate(points: CGSize(width: 800, height: 600), scale: 2)
        XCTAssertEqual(size.width, 1600)
        XCTAssertEqual(size.height, 1200)
        XCTAssertFalse(size.wasReduced)
    }

    func testInvalidGeometryIsRejected() {
        for (size, scale) in [
            (CGSize(width: 0, height: 100), CGFloat(1)),
            (CGSize(width: 100, height: -1), CGFloat(1)),
            (CGSize(width: 100, height: 100), CGFloat.nan),
            (CGSize(width: .infinity, height: 100), CGFloat(1)),
            (CGSize(width: 100, height: 100), CGFloat(0))
        ] {
            XCTAssertThrowsError(try CaptureSize.calculate(points: size, scale: scale))
        }
    }

    func testLargeCaptureFitsMemoryBudgetWithoutDistortion() throws {
        let size = try CaptureSize.calculate(points: CGSize(width: 20000, height: 10000), scale: 2)
        XCTAssertTrue(size.wasReduced)
        XCTAssertLessThanOrEqual(size.width, 16384)
        XCTAssertLessThanOrEqual(size.height, 16384)
        XCTAssertLessThanOrEqual(size.width * size.height, 32_000_000)
        XCTAssertEqual(Double(size.width) / Double(size.height), 2, accuracy: 0.002)
    }

    func testPNGCanBeDecodedWithCorrectSizeAndPixels() throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try XCTUnwrap(context.makeImage())
        let png = try PNGExport.encode(image)
        XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 2)
        context.clear(CGRect(x: 0, y: 0, width: 2, height: 2))
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: 2, height: 2))
        let pixels = try XCTUnwrap(context.data?.assumingMemoryBound(to: UInt8.self))
        XCTAssertEqual(pixels[0], 255)
        XCTAssertEqual(pixels[1], 0)
        XCTAssertEqual(pixels[2], 0)
        XCTAssertEqual(pixels[3], 255)
    }
}

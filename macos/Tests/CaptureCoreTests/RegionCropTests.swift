import CoreGraphics
import ImageIO
import XCTest
@testable import CaptureCore

final class RegionCropTests: XCTestCase {
    func testAllDragDirectionsProduceTheSameRetinaCrop() {
        let display = CGRect(x: 40, y: 60, width: 400, height: 300)
        let pixels = CGSize(width: 800, height: 600)
        for drag in [
            CGRect(x: 90, y: 100, width: 100, height: 80),
            CGRect(x: 190, y: 100, width: -100, height: 80),
            CGRect(x: 90, y: 180, width: 100, height: -80),
            CGRect(x: 190, y: 180, width: -100, height: -80)
        ] {
            XCTAssertEqual(RegionCrop.pixelRect(selection: drag, displayRect: display, pixelSize: pixels),
                           CGRect(x: 100, y: 80, width: 200, height: 160))
        }
    }

    func testLetterboxedImageUsesItsOwnOriginAndIndependentScales() {
        let result = RegionCrop.pixelRect(selection: CGRect(x: 30.2, y: 55.2, width: 10.1, height: 10.1),
                                          displayRect: CGRect(x: 20, y: 40, width: 200, height: 100),
                                          pixelSize: CGSize(width: 600, height: 200))
        XCTAssertEqual(result, CGRect(x: 30, y: 30, width: 31, height: 21))
    }

    func testSelectionClipsToImageInsteadOfIncludingSurroundings() {
        let display = CGRect(x: 20, y: 40, width: 100, height: 80)
        let pixels = CGSize(width: 200, height: 160)
        XCTAssertEqual(RegionCrop.pixelRect(selection: CGRect(x: -100, y: 60, width: 160, height: 200),
                                            displayRect: display, pixelSize: pixels),
                       CGRect(x: 0, y: 40, width: 80, height: 120))
        XCTAssertEqual(RegionCrop.pixelRect(selection: CGRect(x: -100, y: -100, width: 500, height: 500),
                                            displayRect: display, pixelSize: pixels),
                       CGRect(x: 0, y: 0, width: 200, height: 160))
        XCTAssertNil(RegionCrop.pixelRect(selection: CGRect(x: 121, y: 40, width: 20, height: 20),
                                          displayRect: display, pixelSize: pixels))
    }

    func testClicksTinyDragsAndInvalidGeometryAreRejected() {
        let valid = CGRect(x: 0, y: 0, width: 100, height: 80)
        let pixels = CGSize(width: 200, height: 160)
        for drag in [
            CGRect(x: 10, y: 10, width: 0, height: 0),
            CGRect(x: 10, y: 10, width: 0.5, height: 50),
            CGRect(x: 10, y: 10, width: 50, height: 0.5),
            CGRect(x: CGFloat.nan, y: 10, width: 50, height: 50),
            CGRect(x: 10, y: 10, width: CGFloat.infinity, height: 50)
        ] {
            XCTAssertNil(RegionCrop.pixelRect(selection: drag, displayRect: valid, pixelSize: pixels))
        }
        for display in [CGRect.zero, CGRect(x: 0, y: 0, width: -10, height: 20),
                        CGRect(x: 0, y: CGFloat.infinity, width: 100, height: 80)] {
            XCTAssertNil(RegionCrop.pixelRect(selection: valid, displayRect: display, pixelSize: pixels))
        }
        for size in [CGSize.zero, CGSize(width: -1, height: 160), CGSize(width: 200.5, height: 160),
                     CGSize(width: CGFloat.nan, height: 160), CGSize(width: 200, height: CGFloat.infinity)] {
            XCTAssertNil(RegionCrop.pixelRect(selection: valid, displayRect: valid, pixelSize: size))
        }
    }

    func testCropPreservesOriginalPixelsAndTopLeftOrientationAfterPNGExport() throws {
        // Direct image rows are top to bottom: red/green above blue/yellow.
        let colors: [[UInt8]] = [[255, 0, 0, 255], [0, 255, 0, 255],
                                 [0, 0, 255, 255], [255, 255, 0, 255]]
        var bytes: [UInt8] = []
        for y in 0..<4 {
            for x in 0..<6 { bytes += colors[(y < 2 ? 0 : 2) + (x < 3 ? 0 : 1)] }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let original = try XCTUnwrap(CGImage(width: 6, height: 4, bitsPerComponent: 8, bitsPerPixel: 32,
                                             bytesPerRow: 24, space: colorSpace,
                                             bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                                                 | CGBitmapInfo.byteOrder32Big.rawValue),
                                             provider: provider, decode: nil, shouldInterpolate: false,
                                             intent: .defaultIntent))
        let display = CGRect(x: 10, y: 20, width: 3, height: 2)
        for (selection, expected) in [
            (CGRect(x: 10, y: 20, width: 1.5, height: 1), colors[0]),
            (CGRect(x: 11.5, y: 20, width: 1.5, height: 1), colors[1]),
            (CGRect(x: 10, y: 21, width: 1.5, height: 1), colors[2]),
            (CGRect(x: 11.5, y: 21, width: 1.5, height: 1), colors[3])
        ] {
            let crop = try XCTUnwrap(RegionCrop.crop(image: original, selection: selection, displayRect: display))
            let encoded = try PNGExport.encode(crop)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(encoded as CFData, nil))
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(decoded.width, 3)
            XCTAssertEqual(decoded.height, 2)
            let context = try XCTUnwrap(CGContext(data: nil, width: 3, height: 2, bitsPerComponent: 8,
                                                  bytesPerRow: 12, space: colorSpace,
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                                    | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(decoded, in: CGRect(x: 0, y: 0, width: 3, height: 2))
            let output = try XCTUnwrap(context.data?.assumingMemoryBound(to: UInt8.self))
            for pixel in 0..<6 {
                XCTAssertEqual(Array(UnsafeBufferPointer(start: output + pixel * 4, count: 4)), expected)
            }
        }
    }
}

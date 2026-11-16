import CoreGraphics
import XCTest
@testable import CaptureCore

final class RegionSelectionGeometryTests: XCTestCase {
    private let bounds = CGRect(x: 10, y: 20, width: 200, height: 180)
    private let selection = CGRect(x: 40, y: 50, width: 80, height: 60)

    func testCreatingSelectionSupportsEveryDirectionAndClipsToImage() {
        let pairs: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 40, y: 50), CGPoint(x: 120, y: 110)),
            (CGPoint(x: 120, y: 110), CGPoint(x: 40, y: 50)),
            (CGPoint(x: 40, y: 110), CGPoint(x: 120, y: 50)),
            (CGPoint(x: 120, y: 50), CGPoint(x: 40, y: 110))
        ]
        for (start, end) in pairs {
            XCTAssertEqual(RegionSelectionGeometry.rect(from: start, to: end, in: bounds), selection)
        }
        XCTAssertEqual(RegionSelectionGeometry.rect(from: CGPoint(x: -100, y: -100),
                                                     to: CGPoint(x: 500, y: 500), in: bounds), bounds)
        XCTAssertNil(RegionSelectionGeometry.rect(from: CGPoint(x: 15, y: 25),
                                                   to: CGPoint(x: 16, y: 100), in: bounds))
        XCTAssertNil(RegionSelectionGeometry.rect(from: CGPoint(x: 15, y: 25),
                                                   to: CGPoint(x: 100, y: 26), in: bounds))
    }

    func testMovingPreservesSizeAndStopsAtAllFourImageEdges() {
        let moved = RegionSelectionGeometry.moved(selection, by: CGSize(width: 17, height: -13), in: bounds)
        XCTAssertEqual(moved, CGRect(x: 57, y: 37, width: 80, height: 60))
        for (delta, origin) in [
            (CGSize(width: -1_000, height: -1_000), CGPoint(x: 10, y: 20)),
            (CGSize(width: 1_000, height: -1_000), CGPoint(x: 130, y: 20)),
            (CGSize(width: -1_000, height: 1_000), CGPoint(x: 10, y: 140)),
            (CGSize(width: 1_000, height: 1_000), CGPoint(x: 130, y: 140))
        ] {
            let result = RegionSelectionGeometry.moved(selection, by: delta, in: bounds)
            XCTAssertEqual(result.origin, origin)
            XCTAssertEqual(result.size, selection.size)
            XCTAssertTrue(bounds.contains(result))
        }
    }

    func testEachHandleMovesOnlyItsEdgesAndPreservesOppositeEdges() {
        let expected: [(RegionSelectionHandle, CGRect)] = [
            (.topLeft, CGRect(x: 50, y: 65, width: 70, height: 45)),
            (.top, CGRect(x: 40, y: 65, width: 80, height: 45)),
            (.topRight, CGRect(x: 40, y: 65, width: 90, height: 45)),
            (.right, CGRect(x: 40, y: 50, width: 90, height: 60)),
            (.bottomRight, CGRect(x: 40, y: 50, width: 90, height: 75)),
            (.bottom, CGRect(x: 40, y: 50, width: 80, height: 75)),
            (.bottomLeft, CGRect(x: 50, y: 50, width: 70, height: 75)),
            (.left, CGRect(x: 50, y: 50, width: 70, height: 60))
        ]
        XCTAssertEqual(expected.count, RegionSelectionHandle.allCases.count)
        for (handle, rectangle) in expected {
            XCTAssertEqual(RegionSelectionGeometry.resized(selection, handle: handle,
                                                            by: CGSize(width: 10, height: 15), in: bounds), rectangle)
        }
    }

    func testHandlesCannotCrossTheirOppositeEdge() {
        let cases: [(RegionSelectionHandle, CGSize, CGRect)] = [
            (.topLeft, CGSize(width: 1_000, height: 1_000), CGRect(x: 118, y: 108, width: 2, height: 2)),
            (.top, CGSize(width: 1_000, height: 1_000), CGRect(x: 40, y: 108, width: 80, height: 2)),
            (.topRight, CGSize(width: -1_000, height: 1_000), CGRect(x: 40, y: 108, width: 2, height: 2)),
            (.right, CGSize(width: -1_000, height: 1_000), CGRect(x: 40, y: 50, width: 2, height: 60)),
            (.bottomRight, CGSize(width: -1_000, height: -1_000), CGRect(x: 40, y: 50, width: 2, height: 2)),
            (.bottom, CGSize(width: -1_000, height: -1_000), CGRect(x: 40, y: 50, width: 80, height: 2)),
            (.bottomLeft, CGSize(width: 1_000, height: -1_000), CGRect(x: 118, y: 50, width: 2, height: 2)),
            (.left, CGSize(width: 1_000, height: -1_000), CGRect(x: 118, y: 50, width: 2, height: 60))
        ]
        for (handle, delta, expected) in cases {
            XCTAssertEqual(RegionSelectionGeometry.resized(selection, handle: handle, by: delta, in: bounds), expected)
        }
    }

    func testResizingStopsAtImageBoundaryAndHonorsExplicitMinimum() {
        XCTAssertEqual(RegionSelectionGeometry.resized(selection, handle: .topLeft,
                                                        by: CGSize(width: -1_000, height: -1_000), in: bounds),
                       CGRect(x: 10, y: 20, width: 110, height: 90))
        XCTAssertEqual(RegionSelectionGeometry.resized(selection, handle: .bottomRight,
                                                        by: CGSize(width: 1_000, height: 1_000), in: bounds),
                       CGRect(x: 40, y: 50, width: 170, height: 150))
        XCTAssertEqual(RegionSelectionGeometry.resized(selection, handle: .topLeft,
                                                        by: CGSize(width: 1_000, height: 1_000), in: bounds,
                                                        minimumSize: 12),
                       CGRect(x: 108, y: 98, width: 12, height: 12))
        let smallBounds = CGRect(x: 10, y: 20, width: 1, height: 1)
        XCTAssertEqual(RegionSelectionGeometry.resized(smallBounds, handle: .bottomRight,
                                                        by: CGSize(width: -100, height: -100), in: smallBounds), smallBounds)
    }

    func testStaleOutOfBoundsSelectionsAreFittedBeforeEditing() {
        let tooLarge = CGRect(x: -50, y: -60, width: 300, height: 400)
        XCTAssertEqual(RegionSelectionGeometry.moved(tooLarge, by: .zero, in: bounds), bounds)
        let outside = CGRect(x: 500, y: 500, width: 80, height: 60)
        XCTAssertEqual(RegionSelectionGeometry.moved(outside, by: .zero, in: bounds),
                       CGRect(x: 130, y: 140, width: 80, height: 60))
    }

    func testInvalidValuesDoNotPropagateNonfiniteCoordinates() {
        let invalidDelta = CGSize(width: CGFloat.nan, height: 4)
        XCTAssertEqual(RegionSelectionGeometry.moved(selection, by: invalidDelta, in: bounds), selection)
        XCTAssertEqual(RegionSelectionGeometry.resized(selection, handle: .left, by: invalidDelta, in: bounds), selection)
        for minimum in [CGFloat.nan, CGFloat.infinity, 0, -1] {
            XCTAssertEqual(RegionSelectionGeometry.resized(selection, handle: .top, by: .zero,
                                                            in: bounds, minimumSize: minimum), selection)
        }
        let invalidRects = [CGRect.zero, CGRect(x: CGFloat.nan, y: 0, width: 20, height: 30),
                            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 30),
                            CGRect(x: 0, y: 0, width: -20, height: 30)]
        for invalid in invalidRects {
            XCTAssertEqual(RegionSelectionGeometry.moved(invalid, by: .zero, in: bounds), .zero)
            XCTAssertEqual(RegionSelectionGeometry.resized(selection, handle: .left, by: .zero, in: invalid), .zero)
        }
        XCTAssertNil(RegionSelectionGeometry.rect(from: CGPoint(x: CGFloat.nan, y: 25),
                                                   to: CGPoint(x: 50, y: 60), in: bounds))
    }
}

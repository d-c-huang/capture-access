import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import CaptureCore

final class ScreenshotHistoryStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureAccess-HistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testSavedPNGAndMetadataReloadInNewestFirstOrder() async throws {
        let directory = temporaryDirectory.appendingPathComponent("History")
        let store = ScreenshotHistoryStore(directory: directory)
        let image = try testImage()
        let olderDate = Date(timeIntervalSince1970: 1_000)
        let newerDate = Date(timeIntervalSince1970: 2_000)
        _ = try await store.record(image: image, date: newerDate)
        let recorded = try await store.record(image: image, date: olderDate)
        XCTAssertEqual(recorded.map(\.date), [newerDate, olderDate])

        let reloaded = try await ScreenshotHistoryStore(directory: directory).load()
        XCTAssertEqual(reloaded, recorded)
        let url = store.fileURL(for: try XCTUnwrap(recorded.first))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 12)
        XCTAssertEqual(decoded.height, 8)
    }

    func testClearMovesOnlyRecordedImagesAndPreservesManualExports() async throws {
        let directory = temporaryDirectory.appendingPathComponent("History")
        let trash = temporaryDirectory.appendingPathComponent("Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let store = ScreenshotHistoryStore(directory: directory) { url in
            try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
        }
        let records = try await store.record(image: testImage(), date: Date())
        let owned = store.fileURL(for: try XCTUnwrap(records.first))
        let exported = directory.appendingPathComponent("CaptureAccess-export.png")
        let unlisted = directory.appendingPathComponent("CaptureAccess-History-\(UUID().uuidString).png")
        try Data("manual export".utf8).write(to: exported)
        try Data("unlisted file".utf8).write(to: unlisted)

        let result = try await store.removeAll()
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertNil(result.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appendingPathComponent(owned.lastPathComponent).path))
        XCTAssertEqual(try Data(contentsOf: exported), Data("manual export".utf8))
        XCTAssertEqual(try Data(contentsOf: unlisted), Data("unlisted file".utf8))
        let reloaded = try await ScreenshotHistoryStore(directory: directory).load()
        XCTAssertTrue(reloaded.isEmpty)
    }

    func testReplacedImageSymlinkCannotReadOrClearExternalFile() async throws {
        let directory = temporaryDirectory.appendingPathComponent("History")
        let store = ScreenshotHistoryStore(directory: directory)
        let records = try await store.record(image: testImage(), date: Date())
        let owned = store.fileURL(for: try XCTUnwrap(records.first))
        let external = temporaryDirectory.appendingPathComponent("private.png")
        let externalContents = Data("outside history".utf8)
        try externalContents.write(to: external)
        try FileManager.default.removeItem(at: owned)
        try FileManager.default.createSymbolicLink(at: owned, withDestinationURL: external)

        let reopened = ScreenshotHistoryStore(directory: directory)
        let reloaded = try await reopened.load()
        XCTAssertTrue(reloaded.isEmpty)
        _ = try await reopened.removeAll()
        XCTAssertEqual(try Data(contentsOf: external), externalContents)
        XCTAssertFalse(ScreenshotHistoryStore.isOwnedRegularFile(owned, in: directory))
    }

    func testManifestSymlinkIsRejectedWithoutChangingExternalFile() async throws {
        let directory = temporaryDirectory.appendingPathComponent("History")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let external = temporaryDirectory.appendingPathComponent("other.json")
        let contents = Data(#"{"version":1,"records":[]}"#.utf8)
        try contents.write(to: external)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("history.json"),
                                                 withDestinationURL: external)
        let store = ScreenshotHistoryStore(directory: directory)
        do {
            _ = try await store.load()
            XCTFail("A manifest symlink must not be read")
        } catch { }
        do {
            _ = try await store.record(image: testImage(), date: Date())
            XCTFail("A manifest symlink must not be overwritten")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: external), contents)
    }

    func testClearFailureRetainsRemainingRecordsForRetry() async throws {
        let directory = temporaryDirectory.appendingPathComponent("History")
        let store = ScreenshotHistoryStore(directory: directory) { _ in
            throw NSError(domain: "HistoryTests", code: 1)
        }
        let records = try await store.record(image: testImage(), date: Date())
        let result = try await store.removeAll()
        XCTAssertEqual(result.records, records)
        XCTAssertNotNil(result.errorMessage)
        let reloaded = try await ScreenshotHistoryStore(directory: directory).load()
        XCTAssertEqual(reloaded, records)
    }

    private func testImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 12, height: 8, bitsPerComponent: 8,
            bytesPerRow: 12 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.5, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        return try XCTUnwrap(context.makeImage())
    }
}

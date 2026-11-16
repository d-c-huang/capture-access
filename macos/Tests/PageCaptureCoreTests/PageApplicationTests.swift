import Foundation
import XCTest
@testable import PageCaptureCore

final class PageApplicationTests: XCTestCase {
    func testResolvesChosenBundleAndExecutableWithoutProductAssumptions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApplication(in: root)
        let resolved = try PageApplication(url: app)
        XCTAssertEqual(resolved.bundleIdentifier, "local.captureaccess.test")
        XCTAssertEqual(resolved.executableURL.lastPathComponent, "ExampleExecutable")
        XCTAssertEqual(resolved.url, app.resolvingSymlinksInPath())
    }

    func testRejectsUnsupportedNativeAppBeforeLaunchingAnything() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApplication(in: root)
        try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/Frameworks"))
        XCTAssertThrowsError(try PageApplication(url: app))
    }

    func testExecutableCannotEscapeSelectedBundleThroughSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApplication(in: root)
        let executable = app.appendingPathComponent("Contents/MacOS/ExampleExecutable")
        try FileManager.default.removeItem(at: executable)
        try FileManager.default.createSymbolicLink(at: executable, withDestinationURL: URL(fileURLWithPath: "/bin/sh"))
        XCTAssertThrowsError(try PageApplication(url: app))
    }

    private func makeApplication(in root: URL) throws -> URL {
        let app = root.appendingPathComponent("示例 Client.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/Frameworks/Electron Framework.framework"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "local.captureaccess.test", "CFBundleExecutable": "ExampleExecutable", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let executable = app.appendingPathComponent("Contents/MacOS/ExampleExecutable")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return app
    }
}

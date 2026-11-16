import Foundation
import XCTest
@testable import UpdateCore

final class ReleaseUpdateTests: XCTestCase {
    func testStableVersionsCompareNumericallyIncludingLegacyTwoParts() throws {
        XCTAssertTrue(try XCTUnwrap(ReleaseVersion("v0.10.0")) > XCTUnwrap(ReleaseVersion("0.9.99")))
        XCTAssertTrue(try XCTUnwrap(ReleaseVersion("2.0.0")) > XCTUnwrap(ReleaseVersion("1.99.99")))
        XCTAssertEqual(ReleaseVersion("0.8"), ReleaseVersion("0.8.0"))
        XCTAssertEqual(ReleaseVersion("V0.8.0")?.description, "0.8.0")
        for value in ["0.8.0-beta.1", "0.8.0+build", " v0.8.0", "0.8.0 ", "v", "1", "1.2.3.4", "1..0", "1.02.0", "1.-1.0", "١.٢.٣", "999999999999999999999.0.0"] {
            XCTAssertNil(ReleaseVersion(value), value)
        }
    }

    func testNewerStableReleaseOffersOnlyExactUniversalMacAsset() throws {
        let update = try XCTUnwrap(ReleaseUpdate.available(from: fixture(), currentVersion: "0.8.0"))
        XCTAssertEqual(update.version.description, "0.9.0")
        XCTAssertEqual(update.releaseURL.absoluteString, "https://github.com/d-c-huang/capture-access/releases/tag/v0.9.0")
        XCTAssertEqual(update.downloadURL?.absoluteString, "https://github.com/d-c-huang/capture-access/releases/download/v0.9.0/CaptureAccess-macOS-universal.zip")
    }

    func testEqualOlderDraftAndPrereleaseDoNotTriggerUpdate() throws {
        XCTAssertNil(try ReleaseUpdate.available(from: fixture(tag: "v0.8.0"), currentVersion: "0.8.0"))
        XCTAssertNil(try ReleaseUpdate.available(from: fixture(tag: "v0.7.9"), currentVersion: "0.8.0"))
        XCTAssertNil(try ReleaseUpdate.available(from: fixture(draft: true), currentVersion: "0.8.0"))
        XCTAssertNil(try ReleaseUpdate.available(from: fixture(prerelease: true), currentVersion: "0.8.0"))
    }

    func testMissingOrOtherPlatformAssetLeavesVerifiedReleasePage() throws {
        let other = asset(name: "CaptureAccess-Windows.zip", url: "https://github.com/d-c-huang/capture-access/releases/download/v0.9.0/CaptureAccess-Windows.zip")
        let update = try XCTUnwrap(ReleaseUpdate.available(from: fixture(assets: [other]), currentVersion: "0.8.0"))
        XCTAssertNil(update.downloadURL)
        XCTAssertTrue(update.releaseURL.path.hasSuffix("/tag/v0.9.0"))
    }

    func testMaliciousDownloadURLsNeverBecomeDownloadActions() throws {
        let path = "/d-c-huang/capture-access/releases/download/v0.9.0/CaptureAccess-macOS-universal.zip"
        let candidates = [
            "http://github.com" + path,
            "https://github.com.evil.example" + path,
            "https://github.com@evil.example" + path,
            "https://other@github.com" + path,
            "https://github.com:8443" + path,
            "https://github.com" + path + "?redirect=elsewhere",
            "https://github.com" + path + "#fragment",
            "https://github.com" + path.replacingOccurrences(of: "v0.9.0", with: "v0.8.0"),
            "https://github.com" + path.replacingOccurrences(of: "/capture-access/", with: "/other/"),
            "https://github.com" + path.replacingOccurrences(of: "CaptureAccess", with: "%43aptureAccess"),
            "file:///tmp/CaptureAccess-macOS-universal.zip"
        ]
        for candidate in candidates {
            let update = try XCTUnwrap(ReleaseUpdate.available(from: fixture(assets: [asset(url: candidate)]), currentVersion: "0.8.0"))
            XCTAssertNil(update.downloadURL, candidate)
        }
    }

    func testUntrustedReleasePageIsRejected() throws {
        for page in ["https://example.com/releases/tag/v0.9.0", "https://github.com/d-c-huang/capture-access-other/releases/tag/v0.9.0", "https://github.com/d-c-huang/capture-access/releases/tag/v0.9.0?next=bad"] {
            XCTAssertThrowsError(try ReleaseUpdate.available(from: fixture(page: page), currentVersion: "0.8.0")) {
                XCTAssertEqual($0 as? ReleaseUpdateError, .untrustedReleaseURL)
            }
        }
    }

    func testDuplicateUnfinishedOrEmptyAssetsAreNotDownloaded() throws {
        let ordinary = asset()
        for assets in [[ordinary, ordinary], [asset(state: "new")], [asset(size: 0)], [asset(size: -1)]] {
            let update = try XCTUnwrap(ReleaseUpdate.available(from: fixture(assets: assets), currentVersion: "0.8.0"))
            XCTAssertNil(update.downloadURL)
        }
    }

    func testInvalidPayloadAndUnsupportedVersionsFailExplicitly() throws {
        XCTAssertThrowsError(try ReleaseUpdate.available(from: Data("{}".utf8), currentVersion: "0.8.0")) {
            XCTAssertEqual($0 as? ReleaseUpdateError, .invalidResponse)
        }
        XCTAssertThrowsError(try ReleaseUpdate.available(from: fixture(), currentVersion: "debug")) {
            XCTAssertEqual($0 as? ReleaseUpdateError, .invalidCurrentVersion)
        }
        XCTAssertThrowsError(try ReleaseUpdate.available(from: fixture(tag: "nightly"), currentVersion: "0.8.0")) {
            XCTAssertEqual($0 as? ReleaseUpdateError, .invalidReleaseVersion)
        }
        XCTAssertThrowsError(try ReleaseUpdate.available(from: Data(repeating: 32, count: 2_000_001), currentVersion: "0.8.0"))
    }

    func testAutomaticChecksAreThrottledWithoutBlockingManualRetries() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(ReleaseUpdate.shouldCheckAutomatically(lastAttempt: nil, now: now))
        XCTAssertFalse(ReleaseUpdate.shouldCheckAutomatically(lastAttempt: now.addingTimeInterval(-3600), now: now))
        XCTAssertFalse(ReleaseUpdate.shouldCheckAutomatically(lastAttempt: now.addingTimeInterval(-86_399), now: now))
        XCTAssertTrue(ReleaseUpdate.shouldCheckAutomatically(lastAttempt: now.addingTimeInterval(-86_400), now: now))
        XCTAssertTrue(ReleaseUpdate.shouldCheckAutomatically(lastAttempt: now.addingTimeInterval(60), now: now))
    }

    private func asset(name: String = ReleaseUpdate.assetName,
                       url: String = "https://github.com/d-c-huang/capture-access/releases/download/v0.9.0/CaptureAccess-macOS-universal.zip",
                       state: String = "uploaded", size: Int = 1024) -> [String: Any] {
        ["name": name, "browser_download_url": url, "state": state, "size": size]
    }

    private func fixture(tag: String = "v0.9.0", draft: Bool = false, prerelease: Bool = false,
                         page: String? = nil, assets: [[String: Any]]? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "draft": draft, "prerelease": prerelease,
            "html_url": page ?? "https://github.com/d-c-huang/capture-access/releases/tag/\(tag)",
            "assets": assets ?? [asset()]
        ])
    }
}

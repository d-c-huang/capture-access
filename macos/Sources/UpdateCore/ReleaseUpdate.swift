import Foundation

public struct ReleaseVersion: Equatable, Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    /// Stable release tags only. Prereleases and arbitrary labels are not updates.
    public init?(_ value: String) {
        let plain = value.hasPrefix("v") || value.hasPrefix("V") ? String(value.dropFirst()) : value
        let components = plain.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 2 || components.count == 3 else { return nil }
        var numbers: [Int] = []
        for component in components {
            guard !component.isEmpty, component.utf8.allSatisfy({ (48...57).contains($0) }),
                  component.count == 1 || component.first != "0",
                  let number = Int(component), number <= 1_000_000 else { return nil }
            numbers.append(number)
        }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers.count == 3 ? numbers[2] : 0
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

public struct AvailableUpdate: Equatable, Sendable {
    public let version: ReleaseVersion
    public let releaseURL: URL
    public let downloadURL: URL?
}

public enum ReleaseUpdateError: Error, Equatable {
    case invalidCurrentVersion, invalidResponse, untrustedReleaseURL, invalidReleaseVersion
}

public enum ReleaseUpdate {
    public static let repository = "d-c-huang/capture-access"
    public static let assetName = "CaptureAccess-macOS-universal.zip"
    public static let endpoint = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    public static let releasesURL = URL(string: "https://github.com/\(repository)/releases")!

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    private struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let state: String
        let size: Int64
    }

    /// Only published stable releases, and only an exact asset in this repository.
    /// A newer release without a matching package remains visible as a release page.
    public static func available(from data: Data, currentVersion: String) throws -> AvailableUpdate? {
        guard let current = ReleaseVersion(currentVersion) else { throw ReleaseUpdateError.invalidCurrentVersion }
        guard data.count <= 2_000_000,
              let release = try? JSONDecoder().decode(Release.self, from: data) else {
            throw ReleaseUpdateError.invalidResponse
        }
        guard !release.draft, !release.prerelease else { return nil }
        guard let version = ReleaseVersion(release.tag_name) else { throw ReleaseUpdateError.invalidReleaseVersion }
        guard version > current else { return nil }
        guard let page = trustedURL(release.html_url, path: "/\(repository)/releases/tag/\(release.tag_name)") else {
            throw ReleaseUpdateError.untrustedReleaseURL
        }
        let matches = release.assets.filter { $0.name == assetName && $0.state == "uploaded" && $0.size > 0 }
        let download: URL?
        if matches.count == 1 {
            download = trustedURL(matches[0].browser_download_url,
                                  path: "/\(repository)/releases/download/\(release.tag_name)/\(assetName)")
        } else {
            download = nil
        }
        return AvailableUpdate(version: version, releaseURL: page, downloadURL: download)
    }

    public static func shouldCheckAutomatically(lastAttempt: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        let elapsed = now.timeIntervalSince(lastAttempt)
        // A corrected system clock must not suppress checking indefinitely.
        return elapsed >= 24 * 60 * 60 || elapsed < 0
    }

    private static func trustedURL(_ value: String, path: String) -> URL? {
        guard let components = URLComponents(string: value), components.scheme == "https",
              components.host?.lowercased() == "github.com", components.port == nil,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.percentEncodedPath == path else { return nil }
        return components.url
    }
}

import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// Records contain identifiers only; filenames from a manifest are never trusted.
public struct ScreenshotHistoryRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let width: Int
    public let height: Int

    public init(id: UUID = UUID(), date: Date, width: Int, height: Int) {
        self.id = id
        self.date = date
        self.width = width
        self.height = height
    }
}

public struct ScreenshotHistoryClearResult: Sendable {
    public let records: [ScreenshotHistoryRecord]
    public let errorMessage: String?
}

/// Serializes disk work away from the UI and owns only the files in its manifest.
public actor ScreenshotHistoryStore {
    public nonisolated let directory: URL
    private let trashFile: @Sendable (URL) throws -> Void
    private var records: [ScreenshotHistoryRecord] = []
    private var loaded = false

    private struct Manifest: Codable {
        var version = 1
        let records: [ScreenshotHistoryRecord]
    }

    public init(directory: URL, trashFile: @escaping @Sendable (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }) {
        self.directory = directory.standardizedFileURL
        self.trashFile = trashFile
    }

    public nonisolated func fileURL(for record: ScreenshotHistoryRecord) -> URL {
        directory.appendingPathComponent("CaptureAccess-History-\(record.id.uuidString).png")
    }

    private var manifestURL: URL { directory.appendingPathComponent("history.json") }

    public func load() throws -> [ScreenshotHistoryRecord] {
        if loaded { return records }
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            loaded = true
            return []
        }
        guard Self.isOwnedRegularFile(manifestURL, in: directory) else { throw HistoryError.invalidManifest }
        let attributes = try FileManager.default.attributesOfItem(atPath: manifestURL.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 10_000_000 else {
            throw HistoryError.invalidManifest
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.version == 1 else { throw HistoryError.invalidManifest }
        var seen = Set<UUID>()
        records = manifest.records.filter { record in
            record.width > 0 && record.height > 0 && record.width <= 32_768 && record.height <= 32_768
                && record.date.timeIntervalSinceReferenceDate.isFinite
                && seen.insert(record.id).inserted
                && Self.isOwnedRegularFile(fileURL(for: record), in: directory)
        }.sorted { $0.date > $1.date }
        loaded = true
        return records
    }

    public func record(image: CGImage, date: Date) throws -> [ScreenshotHistoryRecord] {
        _ = try load()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let record = ScreenshotHistoryRecord(date: date, width: image.width, height: image.height)
        let destination = fileURL(for: record)
        let data = try PNGExport.encode(image)
        try data.write(to: destination, options: .atomic)
        let updated = (records + [record]).sorted { $0.date > $1.date }
        do {
            try writeManifest(updated)
        } catch {
            // A failed metadata write must not leave an unlisted screenshot behind.
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        records = updated
        return records
    }

    /// Moves recorded images to the Trash. Unlisted files, including manual
    /// exports placed in this directory, are deliberately left untouched.
    public func removeAll() throws -> ScreenshotHistoryClearResult {
        _ = try load()
        var remaining: [ScreenshotHistoryRecord] = []
        var failures = 0
        for record in records {
            let url = fileURL(for: record)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard Self.isOwnedRegularFile(url, in: directory) else {
                // Never follow a replaced entry into a different directory.
                failures += 1
                continue
            }
            do { try trashFile(url) }
            catch { remaining.append(record); failures += 1 }
        }
        try writeManifest(remaining)
        records = remaining
        return ScreenshotHistoryClearResult(
            records: remaining,
            errorMessage: failures == 0 ? nil : "有 \(failures) 张历史截图未能移到废纸篓，请重试。"
        )
    }

    public func thumbnail(for record: ScreenshotHistoryRecord, maximumSize: Int = 180) -> CGImage? {
        guard records.contains(where: { $0.id == record.id }) else { return nil }
        let url = fileURL(for: record)
        guard Self.isOwnedRegularFile(url, in: directory),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maximumSize)
        ] as CFDictionary)
    }

    public nonisolated static func isOwnedRegularFile(_ url: URL, in directory: URL) -> Bool {
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return false }
        return url.resolvingSymlinksInPath().deletingLastPathComponent()
            == directory.resolvingSymlinksInPath()
    }

    private func writeManifest(_ records: [ScreenshotHistoryRecord]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // An existing symlink must not redirect metadata writes outside history.
        if FileManager.default.fileExists(atPath: manifestURL.path),
           !Self.isOwnedRegularFile(manifestURL, in: directory) { throw HistoryError.invalidManifest }
        let data = try JSONEncoder().encode(Manifest(records: records))
        try data.write(to: manifestURL, options: .atomic)
    }

    private enum HistoryError: LocalizedError {
        case invalidManifest
        var errorDescription: String? { "截图历史索引无效，无法读取或写入历史记录。" }
    }
}

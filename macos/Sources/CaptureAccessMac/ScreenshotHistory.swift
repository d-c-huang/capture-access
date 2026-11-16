import AppKit
import CaptureCore
import Combine
import ImageIO

typealias ScreenshotHistoryEntry = ScreenshotHistoryRecord

@MainActor
final class ScreenshotHistory: ObservableObject {
    @Published private(set) var entries: [ScreenshotHistoryEntry] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isWorking = false

    private let store: ScreenshotHistoryStore
    private let thumbnails = NSCache<NSString, NSImage>()
    private var pendingTask: Task<Void, Never>?
    private var pendingCount = 0

    init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        store = ScreenshotHistoryStore(directory: directory
            ?? base.appendingPathComponent("CaptureAccess/History", isDirectory: true))
        thumbnails.countLimit = 100
        enqueue { history in
            do {
                history.entries = try await history.store.load()
                history.lastError = nil
            } catch {
                history.lastError = "无法读取截图历史：\(error.localizedDescription)"
            }
        }
    }

    func record(image: CGImage, date: Date) {
        enqueue { history in
            do {
                history.entries = try await history.store.record(image: image, date: date)
                history.lastError = nil
            } catch {
                history.lastError = "截图已完成，但未能保存到历史：\(error.localizedDescription)"
            }
        }
    }

    func removeAll() {
        enqueue { history in
            do {
                let result = try await history.store.removeAll()
                history.entries = result.records
                history.thumbnails.removeAllObjects()
                history.lastError = result.errorMessage
            } catch {
                history.lastError = "未能清空截图历史：\(error.localizedDescription)"
            }
        }
    }

    func image(for entry: ScreenshotHistoryEntry) -> CGImage? {
        guard entries.contains(where: { $0.id == entry.id }) else { return nil }
        let url = store.fileURL(for: entry)
        guard ScreenshotHistoryStore.isOwnedRegularFile(url, in: store.directory),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            lastError = "无法打开这张历史截图，文件可能已被移动或删除。"
            return nil
        }
        lastError = nil
        return image
    }

    func thumbnail(for entry: ScreenshotHistoryEntry) async -> NSImage? {
        let key = entry.id.uuidString as NSString
        if let image = thumbnails.object(forKey: key) { return image }
        guard let image = await store.thumbnail(for: entry),
              entries.contains(where: { $0.id == entry.id }) else { return nil }
        let preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        thumbnails.setObject(preview, forKey: key)
        return preview
    }

    /// App termination can await queued PNG writes rather than losing a new shot.
    func finishPendingWrites() async { await pendingTask?.value }

    private func enqueue(_ operation: @escaping @MainActor (ScreenshotHistory) async -> Void) {
        let previous = pendingTask
        pendingCount += 1
        isWorking = true
        pendingTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await operation(self)
            self.pendingCount -= 1
            self.isWorking = self.pendingCount > 0
        }
    }
}

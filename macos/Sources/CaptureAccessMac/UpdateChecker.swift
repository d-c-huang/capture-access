import AppKit
import Combine
import UpdateCore

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var isChecking = false
    @Published private(set) var available: AvailableUpdate?
    @Published private(set) var message = "从项目的 GitHub 发布页获取最新版本。"
    @Published private(set) var lastChecked: Date?
    @Published private(set) var failed = false

    private let preferences: AppPreferences
    private let currentVersion: String
    private var task: Task<Void, Never>?

    init(preferences: AppPreferences,
         currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") {
        self.preferences = preferences
        self.currentVersion = currentVersion
        lastChecked = preferences.lastUpdateAttempt
    }

    func checkAutomaticallyIfNeeded() {
        guard preferences.automaticallyChecksForUpdates,
              ReleaseUpdate.shouldCheckAutomatically(lastAttempt: preferences.lastUpdateAttempt, now: Date()) else { return }
        check(manual: false)
    }

    func check(manual: Bool = true) {
        guard !isChecking else { return }
        guard ReleaseVersion(currentVersion) != nil else {
            if manual { failed = true; message = "无法识别当前版本，请从 GitHub 发布页下载正式版本。" }
            return
        }
        isChecking = true
        failed = false
        if manual { message = "正在检查 GitHub 上的新版本…" }
        let previousMessage = message
        let now = Date()
        preferences.lastUpdateAttempt = now
        lastChecked = now
        task = Task { [weak self] in
            guard let self else { return }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 15
            let session = URLSession(configuration: configuration, delegate: UpdateRequestDelegate(), delegateQueue: nil)
            defer { session.invalidateAndCancel(); self.isChecking = false; self.task = nil }
            do {
                var request = URLRequest(url: ReleaseUpdate.endpoint)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
                request.setValue("CaptureAccess/\(self.currentVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else { throw UpdateFailure.invalidResponse }
                switch http.statusCode {
                case 200: break
                case 404: throw UpdateFailure.noRelease
                case 403, 429: throw UpdateFailure.rateLimited
                default: throw UpdateFailure.server
                }
                let update = try ReleaseUpdate.available(from: data, currentVersion: self.currentVersion)
                self.available = update
                if let update {
                    self.message = update.downloadURL != nil
                        ? "发现新版本 \(update.version)。下载完成后退出旧版，解压并替换应用。"
                        : "发现新版本 \(update.version)，Mac 安装包尚未就绪，可查看发布页。"
                } else {
                    self.message = "当前版本 \(self.currentVersion) 已是最新正式版。"
                }
            } catch is CancellationError {
                // App termination should not produce a connection error.
            } catch {
                guard !Task.isCancelled else { return }
                if manual {
                    self.failed = true
                    self.message = Self.message(for: error)
                } else {
                    self.message = previousMessage
                }
            }
        }
    }

    func openDownload() {
        guard let update = available else { return }
        if !NSWorkspace.shared.open(update.downloadURL ?? update.releaseURL) {
            failed = true
            message = "无法打开浏览器，请重试或打开项目的 GitHub 发布页。"
        }
    }

    func openReleases() { NSWorkspace.shared.open(ReleaseUpdate.releasesURL) }

    func cancel() { task?.cancel() }

    private static func message(for error: Error) -> String {
        switch error {
        case UpdateFailure.noRelease: return "GitHub 仓库尚未发布正式版本，可稍后再检查。"
        case UpdateFailure.rateLimited: return "GitHub 暂时限制了请求频率，请稍后重试。"
        case UpdateFailure.server: return "GitHub 暂时不可用，请稍后重试。"
        case is ReleaseUpdateError, UpdateFailure.invalidResponse: return "无法确认 GitHub 返回的版本信息，请稍后重试。"
        default: return "暂时无法连接 GitHub，请检查网络后重试。"
        }
    }
}

private enum UpdateFailure: Error { case noRelease, rateLimited, server, invalidResponse }

/// Version metadata is fetched only from the fixed API endpoint; no credentials,
/// cookies or screenshots are sent, and an unexpected redirect is not followed.
private final class UpdateRequestDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

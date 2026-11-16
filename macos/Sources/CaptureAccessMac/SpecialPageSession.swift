import AppKit
import ImageIO
import PageCaptureCore

@MainActor
final class SpecialPageSession {
    private let application: PageApplication

    init(application: PageApplication) { self.application = application }
    private var process: Process?
    private var connection: DebuggerPipe?
    private var terminatingOriginals: [NSRunningApplication] = []
    private var mustRestore = false
    private var cleanupTask: Task<Void, Never>?
    private var restored = false
    private var prepared = false
    private var clientExited = false
    var onClientExit: (() -> Void)?
    private(set) var restorationFailure: String?

    var isRunning: Bool { process?.isRunning == true && cleanupTask == nil && !clientExited }

    var restorationStatus: String {
        if let restorationFailure { return restorationFailure }
        if clientExited { return "目标应用已退出。" }
        return restored ? "目标应用已恢复正常运行。" : "客户端未被更改。"
    }

    private struct TargetList: Decodable { let targetInfos: [PageTarget] }

    func prepare() async throws {
        let bridgeURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CaptureAccessPageBridge")
        guard FileManager.default.isExecutableFile(atPath: bridgeURL.path) else {
            throw sessionError("缺少页面截图组件，请使用完整的 Capture Access 应用。")
        }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: application.bundleIdentifier) {
            guard app.bundleURL?.resolvingSymlinksInPath() == application.url else { continue }
            guard app.terminate() else { throw sessionError("无法退出目标应用，请先保存内容并退出客户端后重试。") }
            terminatingOriginals.append(app)
            mustRestore = true
            for _ in 0..<100 {
                if app.isTerminated { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard app.isTerminated else { throw sessionError("目标应用尚未退出，请处理客户端提示后重试。") }
        }
        try Task.checkCancellation()
        let input = Pipe(), output = Pipe()
        let process = Process()
        process.executableURL = bridgeURL
        process.arguments = [application.url.path]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        self.process = process
        let connection = DebuggerPipe(reader: output.fileHandleForReading, writer: input.fileHandleForWriting)
        self.connection = connection
        process.terminationHandler = { [weak self] _ in
            connection.close()
            Task { @MainActor [weak self] in
                guard let self, self.cleanupTask == nil, self.prepared else { return }
                // Respect a user closing the client while the mode is idle;
                // ending the mode must not reopen an intentionally quit app.
                self.clientExited = true
                self.mustRestore = false
                self.onClientExit?()
            }
        }
        mustRestore = true
        try process.run()
        // The parent must not retain the child sides, including inherited pipe
        // descriptors held by Electron helpers after its main process exits.
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        for _ in 0..<50 {
            try Task.checkCancellation()
            guard process.isRunning else { throw PageCaptureError.connectionClosed }
            do {
                _ = try await mainPage()
                prepared = true
                return
            }
            catch PageCaptureError.pageUnavailable { }
            catch PageCaptureError.timeout { }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw PageCaptureError.pageUnavailable
    }

    func capture() async throws -> CGImage {
        guard isRunning, let connection else { throw PageCaptureError.connectionClosed }
        try await activateForCapture()
        let png = try await PageScreenshot.capturePNG(using: connection, application: application.url)
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PageCaptureError.invalidImage
        }
        return image
    }

    func showClient() {
        guard let app = runningClient else { return }
        NSApp.yieldActivation(to: app)
        app.activate(from: .current, options: [])
    }

    private var runningClient: NSRunningApplication? {
        guard let process else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: application.bundleIdentifier).first {
            $0.processIdentifier == process.processIdentifier && $0.bundleURL?.resolvingSymlinksInPath() == application.url
        }
    }

    /// Restore the application's actual active window before inspecting page
    /// focus. Do not cache a renderer ID: that could capture an old window.
    private func activateForCapture() async throws {
        try Task.checkCancellation()
        guard let app = runningClient, !app.isTerminated else { throw PageCaptureError.connectionClosed }
        if !app.isActive {
            NSApp.yieldActivation(to: app)
            guard app.activate(from: .current, options: []) else {
                throw sessionError("无法切换到目标应用，请打开目标窗口后重试。")
            }
        }
        // Activation and the renderer's focus notification are asynchronous.
        // Wait at most one second, including a short settled-focus interval.
        for _ in 0..<10 {
            try Task.checkCancellation()
            guard isRunning, !app.isTerminated else { throw PageCaptureError.connectionClosed }
            let wasActive = app.isActive && NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
            try await Task.sleep(nanoseconds: 100_000_000)
            if wasActive, app.isActive,
               NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return }
        }
        throw sessionError("目标应用未能切到前台，请打开目标窗口后重试。")
    }

    /// Window metadata only positions the selection surface. The pixels always
    /// come from the verified main page, never from the desktop behind it.
    func windowFrame(for image: CGImage) -> CGRect? {
        guard let process, let primaryScreen = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return nil }
        let ratio = CGFloat(image.width) / CGFloat(image.height)
        let matches = windows.compactMap { info -> CGRect? in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == process.processIdentifier,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width > 0, rect.height > 0,
                  abs(rect.width / rect.height - ratio) < 0.01 else { return nil }
            return CGRect(x: rect.minX, y: primaryScreen.frame.maxY - rect.maxY,
                          width: rect.width, height: rect.height)
        }
        // A separate window with a matching aspect ratio must not cause the
        // selector to silently anchor to the wrong window. Let it use a fitted
        // page preview when the metadata is absent or ambiguous.
        return matches.count == 1 ? matches[0] : nil
    }

    /// Cleanup runs in an uncancelled, shared task so cancellation or app quit
    /// cannot abandon the private connection or skip restoring normal launch.
    func close() async {
        if let cleanupTask { await cleanupTask.value; return }
        let task = Task { @MainActor in
            self.onClientExit = nil
            // The pipe can report EOF before the termination handler reaches
            // the main actor. Preserve an already-quit client in either order.
            if self.prepared, let process = self.process, !process.isRunning {
                self.clientExited = true
                self.mustRestore = false
            }
            self.connection?.close()
            self.connection = nil
            if let process = self.process, process.isRunning {
                // The selected application may now contain unsaved work.
                // Request its normal quit flow; never send SIGTERM/SIGKILL
                // or relaunch a second copy while that client remains alive.
                _ = self.runningClient?.terminate()
                for _ in 0..<50 {
                    if !process.isRunning { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if process.isRunning {
                    self.restorationFailure = "截图连接已关闭，目标应用仍在运行。请先保存内容并处理退出提示，再手动退出并重新打开目标应用。"
                    return
                }
            }
            self.process = nil
            // Cancellation during prepare() can interrupt its wait for the
            // original client. Opening it before it exits only returns that
            // same dying process, so finish the wait in this uncancelled task.
            for _ in 0..<100 {
                if self.terminatingOriginals.allSatisfy(\.isTerminated) { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard self.terminatingOriginals.allSatisfy(\.isTerminated) else {
                self.restorationFailure = "原目标应用客户端尚未退出，无法完成恢复；请保存内容并处理退出提示，再手动重新打开客户端。"
                return
            }
            self.terminatingOriginals.removeAll()
            if self.mustRestore {
                self.mustRestore = false
                let options = NSWorkspace.OpenConfiguration()
                options.activates = false
                do {
                    _ = try await NSWorkspace.shared.openApplication(at: application.url, configuration: options)
                    self.restored = true
                } catch {
                    self.restorationFailure = "临时连接已关闭，但无法自动重启目标应用，请手动打开客户端。"
                }
            }
        }
        cleanupTask = task
        await task.value
    }

    private func mainPage() async throws -> PageTarget {
        guard let connection else { throw PageCaptureError.connectionClosed }
        let response = try await connection.request("Target.getTargets", timeout: 0.5)
        let list = try JSONDecoder().decode(TargetList.self, from: response)
        guard let target = list.targetInfos.first(where: { $0.belongsToMainPage(in: application.url) }) else {
            throw PageCaptureError.pageUnavailable
        }
        return target
    }

    private func sessionError(_ message: String) -> NSError {
        NSError(domain: "CaptureAccess.PageSession", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

import AppKit
import CaptureCore
import Combine
import CoreGraphics
import ScreenCaptureKit
import UniformTypeIdentifiers

struct CapturedFrame {
    let image: CGImage
    let date: Date
    let wasReduced: Bool

    var preview: NSImage {
        NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height)))
    }
}

@MainActor
final class CaptureModel: NSObject, ObservableObject {
    enum Phase: Equatable { case idle, choosing, capturing }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var frame: CapturedFrame?
    @Published private(set) var status = "选择一个窗口，开始截图。"
    @Published private(set) var lastError: String?
    @Published private(set) var hasSelection = false
    @Published private(set) var needsPermission = false
    @Published private(set) var logs: [String] = []

    private var filter: SCContentFilter?
    private var operationID = UUID()
    private var captureTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var observer: PickerObserver?
    private let picker = SCContentSharingPicker.shared

    var isBusy: Bool { phase != .idle }
    var canCaptureAgain: Bool { hasSelection && !isBusy }

    override init() {
        super.init()
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow]
        if let identifier = Bundle.main.bundleIdentifier {
            configuration.excludedBundleIDs = [identifier]
        }
        configuration.allowsChangingSelectedContent = false
        picker.defaultConfiguration = configuration
        picker.maximumStreamCount = 1
    }

    func chooseWindow() {
        guard !isBusy else { return }
        operationID = UUID()
        detachObserver()
        let observer = PickerObserver(model: self, selectionID: operationID)
        self.observer = observer
        picker.add(observer)
        filter = nil
        hasSelection = false
        lastError = nil
        needsPermission = false
        phase = .choosing
        status = "请在系统选择器中选择要截图的窗口。"
        picker.isActive = true
        picker.present(using: .window)
    }

    func captureAgain() {
        guard let filter, canCaptureAgain else { return }
        capture(filter)
    }

    func clear() {
        operationID = UUID()
        captureTask?.cancel()
        timeoutTask?.cancel()
        captureTask = nil
        timeoutTask = nil
        filter = nil
        frame = nil
        hasSelection = false
        picker.isActive = false
        detachObserver()
        phase = .idle
        lastError = nil
        status = "预览和窗口选择已清除。"
        // Deliberately leave any previously copied image in the user's clipboard.
    }

    func cancel() {
        let previous = frame
        clear()
        frame = previous
        status = "已取消操作，原有预览保留。"
    }

    fileprivate func accept(_ filter: SCContentFilter, selectionID: UUID) {
        guard phase == .choosing, observer?.selectionID == selectionID else { return }
        self.filter = filter
        hasSelection = true
        capture(filter)
    }

    private func capture(_ filter: SCContentFilter) {
        captureTask?.cancel()
        timeoutTask?.cancel()
        let currentID = UUID()
        operationID = currentID
        phase = .capturing
        lastError = nil
        status = "正在获取所选窗口…"

        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) }
            catch { return }
            guard let self, self.operationID == currentID, self.phase == .capturing else { return }
            self.operationID = UUID()
            self.captureTask?.cancel()
            self.fail("截图超时。请确认目标窗口仍可见，然后重新选择。")
        }

        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let size = try CaptureSize.calculate(points: filter.contentRect.size,
                                                     scale: CGFloat(filter.pointPixelScale))
                let configuration = SCStreamConfiguration()
                configuration.width = size.width
                configuration.height = size.height
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true
                configuration.capturesAudio = false
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: configuration
                )
                guard self.operationID == currentID, !Task.isCancelled else { return }
                self.timeoutTask?.cancel()
                self.frame = CapturedFrame(image: image, date: Date(), wasReduced: size.wasReduced)
                self.phase = .idle
                self.needsPermission = false
                self.status = "截图完成 · \(image.width) × \(image.height) 像素"
                self.appendLog(self.status)
            } catch {
                guard self.operationID == currentID, !Task.isCancelled else { return }
                self.timeoutTask?.cancel()
                let native = error as NSError
                self.needsPermission = native.code == -3801 || !CGPreflightScreenCaptureAccess()
                let explanation = self.needsPermission
                    ? "需要屏幕录制授权。请使用下方的授权按钮，或到系统设置中允许 Capture Access，随后重新启动应用。"
                    : "未能截图。请确认窗口仍可见；目标内容也可能不允许捕获。"
                self.fail("\(explanation)\n\(native.localizedDescription) [\(native.domain): \(native.code)]")
            }
        }
    }

    private func fail(_ message: String) {
        phase = .idle
        filter = nil
        hasSelection = false
        picker.isActive = false
        detachObserver()
        lastError = message
        status = "截图未完成；原有预览保留。"
        appendLog(message)
    }

    func savePNG() {
        guard let frame, !isBusy else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = PNGExport.suggestedName(date: frame.date)
        let response: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                let data = try PNGExport.encode(frame.image)
                try data.write(to: url, options: .atomic)
                self.lastError = nil
                self.status = "已保存：\(url.lastPathComponent)"
                self.appendLog(self.status)
            } catch {
                self.lastError = "保存失败：\(error.localizedDescription)"
                self.appendLog(self.lastError!)
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: response)
        } else {
            response(panel.runModal())
        }
    }

    func copyImage() {
        guard let frame, !isBusy else { return }
        let clipboard = NSPasteboard.general
        clipboard.clearContents()
        if clipboard.writeObjects([frame.preview]) {
            lastError = nil
            status = "图片已复制到剪贴板。"
            appendLog(status)
        } else {
            lastError = "未能写入剪贴板，请重试或保存 PNG。"
        }
    }

    func requestPermission() {
        let granted = CGRequestScreenCaptureAccess()
        needsPermission = !granted
        if granted { lastError = nil }
        status = granted ? "系统已授权，请重新选择窗口截图。" : "请按系统提示授权；授权后可能需要重新启动应用。"
        appendLog(status)
    }

    func openPermissionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func openDemo() {
        guard let url = Bundle.main.url(forResource: "CaptureAccessDemo", withExtension: "app"),
              NSWorkspace.shared.open(url) else {
            lastError = "未找到演示应用，请使用 build.sh 生成完整的 .app 后再试。"
            return
        }
        appendLog("已打开测试窗口。请在系统选择器中选择 Capture Access Demo。")
    }

    private func appendLog(_ message: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("\(time)  \(message)")
        if logs.count > 60 { logs.removeFirst(logs.count - 60) }
    }

    private func detachObserver() {
        if let observer { picker.remove(observer) }
        observer = nil
    }

    fileprivate func selectionCancelled(_ selectionID: UUID) {
        guard observer?.selectionID == selectionID, phase != .capturing else { return }
        phase = .idle
        filter = nil
        hasSelection = false
        picker.isActive = false
        detachObserver()
        status = "窗口选择已取消或结束，原有预览保留。"
    }

    fileprivate func selectionFailed(_ error: Error, selectionID: UUID) {
        guard observer?.selectionID == selectionID, phase == .choosing else { return }
        fail("系统窗口选择器无法启动：\(error.localizedDescription)")
    }
}

/// Each presentation owns an observer token, so callbacks queued for an old
/// selection cannot start a capture after cancellation and a new presentation.
private final class PickerObserver: NSObject, SCContentSharingPickerObserver {
    let selectionID: UUID
    private weak var model: CaptureModel?

    init(model: CaptureModel, selectionID: UUID) {
        self.model = model
        self.selectionID = selectionID
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker,
                              didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        let token = selectionID
        Task { @MainActor [weak model = self.model] in model?.accept(filter, selectionID: token) }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        let token = selectionID
        Task { @MainActor [weak model = self.model] in model?.selectionCancelled(token) }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        let token = selectionID
        Task { @MainActor [weak model = self.model] in model?.selectionFailed(error, selectionID: token) }
    }
}

import AppKit
import CaptureCore
import Combine
import CoreGraphics
import PageCaptureCore
import ScreenCaptureKit
import UniformTypeIdentifiers

struct CapturedFrame {
    let image: CGImage
    let date: Date
    let wasReduced: Bool
    var isVisibleArea = false
    var isPageExport = false
    var isRegion = false

    var preview: NSImage {
        NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height)))
    }
}

@MainActor
final class CaptureModel: NSObject, ObservableObject {
    enum Phase: Equatable { case idle, choosing, capturing, pagePreparing, pageReady, pageCapturing, pageSelecting, desktopSelecting, restoring }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var frame: CapturedFrame?
    @Published private(set) var status = "选择一个窗口，开始截图。"
    @Published private(set) var lastError: String?
    @Published private(set) var hasSelection = false
    @Published private(set) var needsPermission = false
    @Published private(set) var logs: [String] = []
    @Published var confirmPageCapture = false
    @Published var globalShortcutAvailable = false
    @Published var ordinaryShortcutAvailable = false
    @Published var confirmClearHistory = false
    let preferences = AppPreferences()
    let history = ScreenshotHistory()
    private var observations: Set<AnyCancellable> = []
    var showSettings: (() -> Void)?
    var showAbout: (() -> Void)?
    var targetName: String { preferences.targetApplicationName }
    // Menu-bar actions can reveal the preview window before presenting the
    // initial client-restart confirmation, even when every window is hidden.
    var showMainWindow: (() -> Void)?

    private var filter: SCContentFilter?
    private var operationID = UUID()
    private var captureTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var observer: PickerObserver?
    private let picker = SCContentSharingPicker.shared
    private var visibleAreaMode = false
    private var pageSession: SpecialPageSession?
    private let regionSelector = RegionSelector()
    private let desktopCapture = DesktopRegionCapture()

    var hasPageSession: Bool { pageSession != nil }
    var isPageFlow: Bool { [.pagePreparing, .pageReady, .pageCapturing, .pageSelecting, .restoring].contains(phase) }

    var supportsVisibleArea: Bool {
        #if compiler(>=6.1)
        if #available(macOS 15.2, *) { return true }
        #endif
        return false
    }

    var isBusy: Bool { phase != .idle && phase != .pageReady }
    var canStartSelection: Bool { !isBusy && !hasPageSession }
    var canCaptureSpecialPage: Bool { phase == .pageReady }
    var canCaptureAgain: Bool { hasSelection && canStartSelection }

    override init() {
        super.init()
        preferences.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.objectWillChange.send() }
        }.store(in: &observations)
        history.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.objectWillChange.send() }
        }.store(in: &observations)
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
        beginSelection(visibleArea: false)
    }

    func requestOrdinaryCapture() {
        guard !isBusy, NSApp.modalWindow == nil,
              !NSApp.windows.contains(where: { $0.attachedSheet != nil }) else { return }
        timeoutTask?.cancel()
        picker.isActive = false
        detachObserver()
        let token = operationID
        phase = .desktopSelecting
        lastError = nil
        status = "拖动框选屏幕区域，可调整选区后确认并复制；Esc 取消。"
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await self.desktopCapture.capture()
                guard self.operationID == token, !Task.isCancelled else { return }
                self.phase = self.hasPageSession ? .pageReady : .idle
                guard let image else {
                    self.status = "已取消本次截图，原有预览和剪贴板保留。"
                    return
                }
                guard try !CaptureImageValidation.isFullyTransparent(image) else { throw CaptureFailure.emptyImage }
                self.acceptFrame(CapturedFrame(image: image, date: Date(), wasReduced: false, isVisibleArea: true, isRegion: true))
                self.copyImage()
                self.needsPermission = false
                self.status = "普通区域截图完成 · \(image.width) × \(image.height) 像素\(self.lastError == nil ? " · 已复制" : "")"
                self.appendLog(self.status)
            } catch {
                guard self.operationID == token, !Task.isCancelled else { return }
                self.phase = self.hasPageSession ? .pageReady : .idle
                self.needsPermission = !CGPreflightScreenCaptureAccess()
                self.lastError = error.localizedDescription
                self.status = "普通截图未完成；原有预览保留。"
                self.appendLog(self.lastError!)
                self.showMainWindow?()
            }
        }
    }

    private func acceptFrame(_ value: CapturedFrame) {
        frame = value
        if preferences.keepsHistory { history.record(image: value.image, date: value.date) }
    }

    func selectHistory(_ entry: ScreenshotHistoryEntry) {
        guard !isBusy, let image = history.image(for: entry) else { return }
        frame = CapturedFrame(image: image, date: entry.date, wasReduced: false)
        lastError = nil
        status = "已打开历史截图，可复制或另存 PNG。"
    }

    func requestClearHistory() {
        guard !isBusy else { return }
        showMainWindow?()
        confirmClearHistory = true
    }

    func clearHistory() {
        guard !isBusy else { return }
        history.removeAll()
        clear()
        status = "正在清空工具内的截图记录；另存的文件不受影响。"
        let clearingStatus = status
        Task { [weak self] in
            guard let self else { return }
            await self.history.finishPendingWrites()
            guard self.status == clearingStatus else { return }
            self.status = self.history.lastError == nil
                ? "历史截图和预览已清空，另存文件与剪贴板保留。"
                : "部分历史截图未能清空，请查看历史列表中的提示后重试。"
        }
    }

    func requestSpecialCapture() {
        guard !isBusy, NSApp.modalWindow == nil,
              !NSApp.windows.contains(where: { $0.attachedSheet != nil }) else { return }
        if canCaptureSpecialPage {
            captureSpecialPage()
        } else {
            guard let applicationURL = preferences.targetApplicationURL else { showSettings?(); return }
            do { _ = try PageApplication(url: applicationURL) }
            catch { lastError = error.localizedDescription; showMainWindow?(); return }
            showMainWindow?()
            NSApp.activate(ignoringOtherApps: true)
            confirmPageCapture = true
        }
    }

    func prepareSpecialPage() {
        guard canStartSelection, let applicationURL = preferences.targetApplicationURL else { return }
        let application: PageApplication
        do { application = try PageApplication(url: applicationURL) }
        catch { lastError = error.localizedDescription; return }
        operationID = UUID()
        let token = operationID
        captureTask?.cancel()
        timeoutTask?.cancel()
        filter = nil
        hasSelection = false
        picker.isActive = false
        detachObserver()
        needsPermission = false
        lastError = nil
        phase = .pagePreparing
        status = "正在准备特殊应用页面截图…"
        let session = SpecialPageSession(application: application)
        pageSession = session
        session.onClientExit = { [weak self] in
            guard let self, self.operationID == token, self.pageSession != nil else { return }
            self.endPageCapture(message: "客户端已关闭，截图模式已结束。")
        }
        captureTask = Task { [weak self] in
            do {
                try await session.prepare()
                guard let self, self.operationID == token, !Task.isCancelled else {
                    await session.close()
                    return
                }
                self.phase = .pageReady
                self.status = "连续截图已开启。按 \(self.preferences.specialShortcut.displayName) 框选并调整，点击“确认并复制”完成。"
                self.appendLog("特殊应用截图模式已开启；选区可拖动、缩放，确认后复制，Esc 取消。")
                session.showClient()
            } catch {
                await session.close()
                guard let self, self.operationID == token else { return }
                self.pageSession = nil
                self.phase = .idle
                self.lastError = error.localizedDescription
                self.status = "页面截图未完成，\(session.restorationStatus)"
                self.appendLog(self.lastError!)
            }
        }
    }

    func showSpecialClient() { pageSession?.showClient() }

    func captureEntireSpecialPage() { captureSpecialPage(selectRegion: false) }

    func cancelRegionSelection() { regionSelector.cancel(); desktopCapture.cancel() }

    func captureSpecialPage(selectRegion: Bool = true) {
        guard phase == .pageReady, let session = pageSession else { return }
        timeoutTask?.cancel()
        let token = operationID
        phase = .pageCapturing
        lastError = nil
        status = "正在获取特殊应用的当前页面…"
        captureTask = Task { [weak self] in
            do {
                var image = try await session.capture()
                guard try !CaptureImageValidation.isFullyTransparent(image) else { throw CaptureFailure.emptyImage }
                let capturedAt = Date()
                let pageWidth = image.width, pageHeight = image.height
                guard let self, self.operationID == token, !Task.isCancelled else { return }
                if selectRegion {
                    self.phase = .pageSelecting
                    self.status = "框选后可拖动选区或边角调整，点击“确认并复制”或按回车完成；Esc 取消。"
                    let selected = await self.regionSelector.select(image: image, preferredFrame: session.windowFrame(for: image), title: "特殊应用 · 框选截图")
                    guard self.operationID == token, !Task.isCancelled else { return }
                    guard let selected else {
                        self.phase = .pageReady
                        self.lastError = nil
                        self.status = "已取消本次框选，原有预览和剪贴板保留；可继续截图。"
                        self.appendLog(self.status)
                        return
                    }
                    image = selected
                }
                let isRegion = image.width != pageWidth || image.height != pageHeight
                let frame = CapturedFrame(image: image, date: capturedAt, wasReduced: false,
                                          isPageExport: true, isRegion: isRegion)
                self.acceptFrame(frame)
                self.phase = .pageReady
                let clipboard = NSPasteboard.general
                clipboard.clearContents()
                let copied = clipboard.writeObjects([frame.preview])
                self.lastError = copied ? nil : "截图完成，但自动复制失败，请使用“复制图片”或保存 PNG。"
                self.status = "特殊应用\(isRegion ? "区域" : "整窗")截图完成 · \(image.width) × \(image.height) 像素\(copied ? " · 已复制" : "")。可继续截图，无需重启。"
                self.appendLog(self.status)
                // Keep the user's current app in front for repeated hotkey
                // captures; the preview remains available in Capture Access.
            } catch {
                guard let self, self.operationID == token, !Task.isCancelled else { return }
                if !session.isRunning || (error as? PageCaptureError) == .connectionClosed {
                    self.endPageCapture(message: "截图连接已断开。", failure: error.localizedDescription)
                    return
                }
                self.phase = .pageReady
                self.lastError = error.localizedDescription
                self.status = "本次截图未完成，原有预览保留。截图模式仍在，可打开目标页面后重试。"
                self.appendLog(self.lastError!)
            }
        }
    }

    func endPageCapture(message: String = "已结束截图模式。", failure: String? = nil) {
        guard let session = pageSession else { return }
        operationID = UUID()
        cancelRegionSelection()
        captureTask?.cancel()
        timeoutTask?.cancel()
        let token = operationID
        phase = .restoring
        status = "正在关闭临时连接并恢复特殊应用…"
        captureTask = Task { [weak self] in
            await session.close()
            guard let self, self.operationID == token else { return }
            self.pageSession = nil
            self.phase = .idle
            let errors = [failure, session.restorationFailure].compactMap { $0 }
            self.lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
            self.status = message + " " + session.restorationStatus
            self.appendLog(self.status)
        }
    }

    func prepareToTerminate() async {
        phase = .restoring
        operationID = UUID()
        cancelRegionSelection()
        captureTask?.cancel()
        timeoutTask?.cancel()
        await pageSession?.close()
        pageSession = nil
        await history.finishPendingWrites()
    }

    func chooseVisibleArea() {
        guard supportsVisibleArea else { return }
        beginSelection(visibleArea: true)
    }

    private func beginSelection(visibleArea: Bool) {
        guard canStartSelection else { return }
        visibleAreaMode = visibleArea
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
        if pageSession != nil {
            guard phase == .pageReady else { return }
            frame = nil
            lastError = nil
            status = "预览已清除，截图模式仍在，可继续截图。"
            return
        }
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
        if phase == .pageSelecting || phase == .desktopSelecting { cancelRegionSelection(); return }
        if pageSession != nil { endPageCapture(); return }
        let previous = frame
        clear()
        frame = previous
        status = "已取消操作，原有预览保留。"
    }

    fileprivate func accept(_ filter: SCContentFilter, selectionID: UUID) {
        guard phase == .choosing, observer?.selectionID == selectionID else { return }
        self.filter = filter
        hasSelection = true
        #if compiler(>=6.1)
        if #available(macOS 15.2, *) {
            let applications = Set(filter.includedWindows.compactMap { $0.owningApplication?.applicationName })
            appendLog("已选择窗口：\(applications.sorted().joined(separator: "、"))")
        }
        #endif
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
                configuration.queueDepth = 3
                let screenshot: CGImage
                #if compiler(>=6.1)
                if self.visibleAreaMode, #available(macOS 15.2, *) {
                    self.appendLog("正在获取所选窗口的屏幕可见区域，遮挡内容也会包含在图中。")
                    screenshot = try await ScreenshotCapture.visibleArea(filter: filter, size: size)
                } else {
                    screenshot = try await ScreenshotCapture.window(filter: filter, configuration: configuration)
                }
                #else
                screenshot = try await ScreenshotCapture.window(filter: filter, configuration: configuration)
                #endif
                guard self.operationID == currentID, !Task.isCancelled else { return }
                let image: CGImage
                if try CaptureImageValidation.isFullyTransparent(screenshot) {
                    self.status = "截图返回空图，正在尝试获取所选窗口的完整画面…"
                    self.appendLog("单帧截图返回全透明图片，改用同一窗口的短时采集。")
                    do {
                        image = try await SingleFrameCapture.capture(filter: filter, configuration: configuration)
                    } catch CaptureFailure.emptyImage {
                        try Task.checkCancellation()
                        #if compiler(>=6.1)
                        if #available(macOS 15.2, *), CGPreflightScreenCaptureAccess() {
                            self.appendLog("独立窗口采集仍为空，尝试只包含所选窗口的显示器过滤方式。")
                            image = try await DisplayWindowCapture.capture(selectedFilter: filter, size: size)
                        } else {
                            throw CaptureFailure.emptyImage
                        }
                        #else
                        throw CaptureFailure.emptyImage
                        #endif
                    }
                } else {
                    image = screenshot
                }
                guard self.operationID == currentID, !Task.isCancelled else { return }
                self.timeoutTask?.cancel()
                self.acceptFrame(CapturedFrame(image: image, date: Date(), wasReduced: size.wasReduced,
                                               isVisibleArea: self.visibleAreaMode))
                self.phase = .idle
                self.needsPermission = false
                self.status = self.visibleAreaMode
                    ? "屏幕区域已获取 · \(image.width) × \(image.height) 像素，请核对目标内容。"
                    : "截图完成 · \(image.width) × \(image.height) 像素"
                self.appendLog(self.status)
            } catch {
                guard self.operationID == currentID, !Task.isCancelled else { return }
                self.timeoutTask?.cancel()
                let native = error as NSError
                if let failure = error as? CaptureFailure {
                    self.needsPermission = false
                    self.fail(failure.localizedDescription)
                    return
                }
                self.needsPermission = native.domain == SCStreamErrorDomain && native.code == -3801
                let explanation = self.needsPermission
                    ? "系统未接受当前版本的屏幕录制授权。若权限开关已打开，请从系统权限列表移除旧的 Capture Access，再添加并允许当前应用，随后重新启动。"
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

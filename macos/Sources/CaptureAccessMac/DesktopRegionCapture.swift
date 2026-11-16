import AppKit
import CaptureCore
import ScreenCaptureKit

/// Captures every display before showing any overlay. Each overlay uses the
/// display's own backing resolution, including displays left of/above primary.
@MainActor
final class DesktopRegionCapture: NSObject, NSWindowDelegate {
    private struct Snapshot {
        let screen: NSScreen
        let image: CGImage
    }

    private var operationID: UUID?
    private var panels: [RegionSelectionPanel] = []
    private var continuation: CheckedContinuation<CGImage?, Never>?
    private var previousApplication: NSRunningApplication?
    private var applicationObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var cancelPreparation: (() -> Void)?

    func capture() async throws -> CGImage? {
        cancel()
        try Task.checkCancellation()
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw DesktopCaptureError.permissionRequired
        }
        let id = UUID()
        operationID = id
        previousApplication = NSWorkspace.shared.frontmostApplication
        do {
            let snapshots = try await boundedCapture(id: id)
            guard operationID == id, !Task.isCancelled else { return nil }
            return await select(snapshots, id: id)
        } catch {
            if operationID == id { finish(nil, id: id, restorePreviousFocus: false) }
            if error is CancellationError { return nil }
            throw error
        }
    }

    func cancel() {
        guard let id = operationID else { return }
        finish(nil, id: id, restorePreviousFocus: false)
    }

    /// A timed continuation can finish even when a system capture request does
    /// not promptly honor task cancellation. A late result is discarded.
    private func boundedCapture(id: UUID) async throws -> [Snapshot] {
        let waiter = DesktopCaptureWaiter<[Snapshot]>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter.continuation = continuation
                guard !Task.isCancelled, operationID == id else {
                    waiter.finish(.failure(CancellationError()))
                    return
                }
                cancelPreparation = { waiter.finish(.failure(CancellationError())) }
                waiter.work = Task { @MainActor in
                    do { waiter.finish(.success(try await Self.snapshots())) }
                    catch { waiter.finish(.failure(error)) }
                }
                waiter.timeout = Task { @MainActor in
                    do { try await Task.sleep(nanoseconds: 15_000_000_000) }
                    catch { return }
                    waiter.finish(.failure(DesktopCaptureError.timeout))
                }
            }
        } onCancel: {
            Task { @MainActor in waiter.finish(.failure(CancellationError())) }
        }
    }

    private static func snapshots() async throws -> [Snapshot] {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { throw DesktopCaptureError.noDisplay }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        let ownApplications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        var snapshots: [Snapshot] = []
        for screen in screens {
            guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = content.displays.first(where: { $0.displayID == displayNumber.uint32Value }) else {
                throw DesktopCaptureError.displayChanged
            }
            let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
            let scale = CGFloat(filter.pointPixelScale)
            let width = (filter.contentRect.width * scale).rounded()
            let height = (filter.contentRect.height * scale).rounded()
            guard width.isFinite, height.isFinite, width >= 1, height >= 1,
                  width <= 32_768, height <= 32_768, width * height <= 100_000_000 else {
                throw DesktopCaptureError.invalidSize
            }
            let configuration = SCStreamConfiguration()
            configuration.width = Int(width)
            configuration.height = Int(height)
            configuration.showsCursor = false
            configuration.capturesAudio = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            try Task.checkCancellation()
            guard try !CaptureImageValidation.isFullyTransparent(image) else { throw CaptureFailure.emptyImage }
            snapshots.append(Snapshot(screen: screen, image: image))
        }
        return snapshots
    }

    private func select(_ snapshots: [Snapshot], id: UUID) async -> CGImage? {
        cancelPreparation = nil
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard operationID == id, !Task.isCancelled else { continuation.resume(returning: nil); return }
                self.continuation = continuation
                let mouseLocation = NSEvent.mouseLocation
                for snapshot in snapshots {
                    let frame = snapshot.screen.frame
                    let panel = RegionSelectionPanel(contentRect: frame, styleMask: [.borderless],
                                                     backing: .buffered, defer: false)
                    panel.title = "普通区域截图"
                    panel.isReleasedWhenClosed = false
                    panel.isOpaque = true
                    panel.backgroundColor = .black
                    panel.hasShadow = false
                    panel.level = .popUpMenu
                    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                    panel.hidesOnDeactivate = false
                    panel.isMovable = false
                    panel.acceptsMouseMovedEvents = true
                    panel.delegate = self
                    let imageRect = CGRect(origin: .zero, size: frame.size)
                    let toolbarWidth = min(730, max(1, frame.width - 24))
                    let safeBottom = max(12, snapshot.screen.safeAreaInsets.bottom + 12)
                    let toolbarRect = CGRect(x: (frame.width - toolbarWidth) / 2,
                                             y: frame.height - 44 - safeBottom,
                                             width: toolbarWidth, height: 44)
                    let view = RegionSelectionView(frame: imageRect, image: snapshot.image,
                                                   imageRect: imageRect, toolbarRect: toolbarRect,
                                                   title: "普通区域截图 · 可拖动和调整选区", fullSelectionTitle: "全屏")
                    view.completion = { [weak self] image in self?.finish(image, id: id) }
                    view.selectionBegan = { [weak self, weak panel] in
                        guard let self, let panel else { return }
                        self.activateSelection(in: panel)
                    }
                    panel.contentView = view
                    panels.append(panel)
                }
                guard let activePanel = panels.first(where: { $0.frame.contains(mouseLocation) }) ?? panels.first else {
                    finish(nil, id: id, restorePreviousFocus: false)
                    return
                }
                NSApp.activate(ignoringOtherApps: true)
                for panel in panels { panel.orderFrontRegardless() }
                activePanel.makeKeyAndOrderFront(nil)
                activePanel.makeFirstResponder(activePanel.contentView)
                applicationObserver = NotificationCenter.default.addObserver(
                    forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.finish(nil, id: id, restorePreviousFocus: false) }
                }
                screenObserver = NotificationCenter.default.addObserver(
                    forName: NSApplication.didChangeScreenParametersNotification, object: NSApp, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.finish(nil, id: id, restorePreviousFocus: false) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(nil, id: id, restorePreviousFocus: false) }
        }
    }

    private func activateSelection(in selectedPanel: RegionSelectionPanel) {
        for panel in panels where panel !== selectedPanel {
            (panel.contentView as? RegionSelectionView)?.resetSelection()
        }
        selectedPanel.makeKeyAndOrderFront(nil)
        selectedPanel.makeFirstResponder(selectedPanel.contentView)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, panels.contains(where: { $0 === window }) else { return }
        cancel()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              panels.contains(where: { $0 === window }), let id = operationID else { return }
        // Clicking another display transfers key status between our panels.
        // Wait until that transfer finishes before distinguishing it from
        // opening Settings or another app window behind the screen overlay.
        Task { @MainActor [weak self] in
            guard let self, self.operationID == id,
                  !self.panels.contains(where: \.isKeyWindow) else { return }
            self.finish(nil, id: id, restorePreviousFocus: false)
        }
    }

    private func finish(_ image: CGImage?, id: UUID, restorePreviousFocus: Bool = true) {
        guard operationID == id else { return }
        operationID = nil
        let cancelPreparation = self.cancelPreparation
        self.cancelPreparation = nil
        cancelPreparation?()
        if let applicationObserver { NotificationCenter.default.removeObserver(applicationObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        applicationObserver = nil
        screenObserver = nil
        let continuation = self.continuation
        self.continuation = nil
        let previousApplication = self.previousApplication
        self.previousApplication = nil
        let restoreFocus = restorePreviousFocus && NSApp.isActive
        for panel in panels {
            panel.delegate = nil
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
        }
        panels.removeAll()
        if restoreFocus, let previousApplication,
           !previousApplication.isTerminated,
           previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            NSApp.yieldActivation(to: previousApplication)
            previousApplication.activate(from: .current, options: [])
        }
        continuation?.resume(returning: image)
    }
}

private enum DesktopCaptureError: LocalizedError {
    case permissionRequired, timeout, noDisplay, displayChanged, invalidSize

    var errorDescription: String? {
        switch self {
        case .permissionRequired: return "普通区域截图需要屏幕录制权限。请在系统设置中允许 Capture Access 后重试。"
        case .timeout: return "屏幕截图超时，请确认屏幕可用后重试。"
        case .noDisplay: return "没有找到可截图的显示器。"
        case .displayChanged: return "显示器已发生变化，请重新开始截图。"
        case .invalidSize: return "当前显示器尺寸无法处理，请调整显示设置后重试。"
        }
    }
}

@MainActor
private final class DesktopCaptureWaiter<Value> {
    var continuation: CheckedContinuation<Value, Error>?
    var work: Task<Void, Never>?
    var timeout: Task<Void, Never>?

    func finish(_ result: Result<Value, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        work?.cancel()
        work = nil
        continuation.resume(with: result)
    }
}

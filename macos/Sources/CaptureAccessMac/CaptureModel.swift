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
    @Published private(set) var status = "ѡ��һ�����ڣ���ʼ��ͼ��"
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
        status = "����ϵͳѡ������ѡ��Ҫ��ͼ�Ĵ��ڡ�"
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
        status = "Ԥ���ʹ���ѡ���������"
        // Deliberately leave any previously copied image in the user's clipboard.
    }

    func cancel() {
        let previous = frame
        clear()
        frame = previous
        status = "��ȡ��������ԭ��Ԥ��������"
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
        status = "���ڻ�ȡ��ѡ���ڡ�"

        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) }
            catch { return }
            guard let self, self.operationID == currentID, self.phase == .capturing else { return }
            self.operationID = UUID()
            self.captureTask?.cancel()
            self.fail("��ͼ��ʱ����ȷ��Ŀ�괰���Կɼ���Ȼ������ѡ��")
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
                self.status = "��ͼ��� �� \(image.width) �� \(image.height) ����"
                self.appendLog(self.status)
            } catch {
                guard self.operationID == currentID, !Task.isCancelled else { return }
                self.timeoutTask?.cancel()
                let native = error as NSError
                self.needsPermission = native.code == -3801 || !CGPreflightScreenCaptureAccess()
                let explanation = self.needsPermission
                    ? "��Ҫ��Ļ¼����Ȩ����ʹ���·�����Ȩ��ť����ϵͳ���������� Capture Access�������������Ӧ�á�"
                    : "δ�ܽ�ͼ����ȷ�ϴ����Կɼ���Ŀ������Ҳ���ܲ���������"
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
        status = "��ͼδ��ɣ�ԭ��Ԥ��������"
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
                self.status = "�ѱ��棺\(url.lastPathComponent)"
                self.appendLog(self.status)
            } catch {
                self.lastError = "����ʧ�ܣ�\(error.localizedDescription)"
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
            status = "ͼƬ�Ѹ��Ƶ������塣"
            appendLog(status)
        } else {
            lastError = "δ��д������壬�����Ի򱣴� PNG��"
        }
    }

    func requestPermission() {
        let granted = CGRequestScreenCaptureAccess()
        needsPermission = !granted
        if granted { lastError = nil }
        status = granted ? "ϵͳ����Ȩ��������ѡ�񴰿ڽ�ͼ��" : "�밴ϵͳ��ʾ��Ȩ����Ȩ�������Ҫ��������Ӧ�á�"
        appendLog(status)
    }

    func openPermissionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func openDemo() {
        guard let url = Bundle.main.url(forResource: "CaptureAccessDemo", withExtension: "app"),
              NSWorkspace.shared.open(url) else {
            lastError = "δ�ҵ���ʾӦ�ã���ʹ�� build.sh ���������� .app �����ԡ�"
            return
        }
        appendLog("�Ѵ򿪲��Դ��ڡ�����ϵͳѡ������ѡ�� Capture Access Demo��")
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
        status = "����ѡ����ȡ���������ԭ��Ԥ��������"
    }

    fileprivate func selectionFailed(_ error: Error, selectionID: UUID) {
        guard observer?.selectionID == selectionID, phase == .choosing else { return }
        fail("ϵͳ����ѡ�����޷�������\(error.localizedDescription)")
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

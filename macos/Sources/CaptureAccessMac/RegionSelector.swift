import AppKit
import CaptureCore

/// Select on a frozen image, never on a composite of the desktop. The image
/// stays at the client's location when there is room for a separate toolbar.
@MainActor
final class RegionSelector: NSObject, NSWindowDelegate {
    private var panel: RegionSelectionPanel?
    private var continuation: CheckedContinuation<CGImage?, Never>?
    private var selectionID: UUID?
    private var previousApplication: NSRunningApplication?

    func select(image: CGImage, preferredFrame: CGRect?, title: String = "区域截图") async -> CGImage? {
        cancel()
        guard !Task.isCancelled else { return nil }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: nil); return }
                self.continuation = continuation
                self.selectionID = id
                self.previousApplication = NSWorkspace.shared.frontmostApplication
                guard let layout = Self.layout(image: image, preferredFrame: preferredFrame) else {
                    finish(nil, id: id, restorePreviousFocus: false)
                    return
                }
                let panel = RegionSelectionPanel(contentRect: layout.frame,
                                                  styleMask: [.borderless], backing: .buffered, defer: false)
                panel.title = title
                panel.isReleasedWhenClosed = false
                panel.isOpaque = true
                panel.backgroundColor = .windowBackgroundColor
                panel.hasShadow = true
                panel.level = .popUpMenu
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                panel.hidesOnDeactivate = false
                panel.isMovable = false
                panel.acceptsMouseMovedEvents = true
                panel.delegate = self
                let view = RegionSelectionView(frame: NSRect(origin: .zero, size: layout.frame.size),
                                               image: image, imageRect: layout.imageRect,
                                               toolbarRect: layout.toolbarRect, title: title)
                view.completion = { [weak self] image in self?.finish(image, id: id) }
                panel.contentView = view
                self.panel = panel
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(view)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(nil, id: id, restorePreviousFocus: false) }
        }
    }

    func cancel() {
        guard let id = selectionID else { return }
        finish(nil, id: id, restorePreviousFocus: false)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        cancel()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        cancel()
    }

    private func finish(_ image: CGImage?, id: UUID, restorePreviousFocus: Bool = true) {
        guard selectionID == id else { return }
        selectionID = nil
        let continuation = self.continuation
        self.continuation = nil
        let previousApplication = self.previousApplication
        self.previousApplication = nil
        let restoreFocus = restorePreviousFocus && NSApp.isActive
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
        // A user switching to another app while the selector is open should
        // not have their new choice of foreground application overridden.
        if restoreFocus, let previousApplication,
           !previousApplication.isTerminated,
           previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            NSApp.yieldActivation(to: previousApplication)
            previousApplication.activate(from: .current, options: [])
        }
        continuation?.resume(returning: image)
    }

    private struct Layout {
        let frame: CGRect
        let imageRect: CGRect
        let toolbarRect: CGRect
    }

    private static func layout(image: CGImage, preferredFrame: CGRect?) -> Layout? {
        let toolbarHeight: CGFloat = 44
        let imageAspect = CGFloat(image.width) / CGFloat(image.height)
        let preferredScreen = preferredFrame.flatMap { target in
            NSScreen.screens.max {
                let a = $0.frame.intersection(target), b = $1.frame.intersection(target)
                return a.width * a.height < b.width * b.height
            }
        }
        guard let screen = preferredScreen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return nil }
        let available = screen.visibleFrame
        if let preferredFrame, preferredFrame.width >= 460, preferredFrame.height > 0,
           preferredFrame.minX.isFinite, preferredFrame.minY.isFinite,
           preferredFrame.width.isFinite, preferredFrame.height.isFinite,
           abs(preferredFrame.width / preferredFrame.height / imageAspect - 1) < 0.005 {
            // Add the toolbar above or below the exact image bounds. Neither
            // its controls nor selection decoration enters the cropped pixels.
            let above = CGRect(x: preferredFrame.minX, y: preferredFrame.minY,
                               width: preferredFrame.width, height: preferredFrame.height + toolbarHeight)
            if available.contains(above) {
                return Layout(frame: above,
                              imageRect: CGRect(x: 0, y: toolbarHeight, width: preferredFrame.width, height: preferredFrame.height),
                              toolbarRect: CGRect(x: 0, y: 0, width: preferredFrame.width, height: toolbarHeight))
            }
            let below = CGRect(x: preferredFrame.minX, y: preferredFrame.minY - toolbarHeight,
                               width: preferredFrame.width, height: preferredFrame.height + toolbarHeight)
            if available.contains(below) {
                return Layout(frame: below,
                              imageRect: CGRect(origin: .zero, size: preferredFrame.size),
                              toolbarRect: CGRect(x: 0, y: preferredFrame.height, width: preferredFrame.width, height: toolbarHeight))
            }
        }
        // Off-screen, ambiguous or full-screen windows get a complete fitted
        // snapshot on the relevant display instead of a clipped selection area.
        let usable = available.insetBy(dx: 24, dy: 24)
        let imageWidth = min(usable.width, max(1, usable.height - toolbarHeight) * imageAspect)
        let height = imageWidth / imageAspect
        // A narrow application page still needs room for the three toolbar
        // buttons. Center its image without stretching or changing crop scale.
        let panelWidth = min(usable.width, max(460, imageWidth))
        let frame = CGRect(x: usable.midX - panelWidth / 2,
                           y: usable.midY - (height + toolbarHeight) / 2,
                           width: panelWidth, height: height + toolbarHeight)
        return Layout(frame: frame,
                      imageRect: CGRect(x: (panelWidth - imageWidth) / 2, y: toolbarHeight,
                                        width: imageWidth, height: height),
                      toolbarRect: CGRect(x: 0, y: 0, width: panelWidth, height: toolbarHeight))
    }
}

@MainActor
final class RegionSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class RegionSelectionView: NSView {
    private enum Drag {
        case creating(start: CGPoint)
        case moving(original: CGRect, start: CGPoint)
        case resizing(original: CGRect, handle: RegionSelectionHandle, start: CGPoint)
    }

    let image: CGImage
    let imageRect: CGRect
    private let toolbarRect: CGRect
    private let preview: NSImage
    private let instructions = NSTextField(labelWithString: "拖动框选 · 调整后回车确认")
    private let confirmButton = NSButton(title: "确认并复制", target: nil, action: nil)
    private var tracking: NSTrackingArea?
    private var drag: Drag?
    private var selection: CGRect?
    var completion: ((CGImage?) -> Void)?
    var selectionBegan: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame: NSRect, image: CGImage, imageRect: CGRect, toolbarRect: CGRect,
         title: String = "区域截图", fullSelectionTitle: String = "整窗") {
        self.image = image
        self.imageRect = imageRect
        self.toolbarRect = toolbarRect
        self.preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        super.init(frame: frame)
        setAccessibilityLabel(title)
        setAccessibilityHelp("拖动框选后，可拖动选区内部移动，拖动八个控制点调整大小。点击确认并复制或按回车完成；Escape 取消。")

        instructions.font = .systemFont(ofSize: 13, weight: .medium)
        instructions.textColor = .labelColor
        instructions.frame = CGRect(x: toolbarRect.minX + 14, y: toolbarRect.minY + 13,
                                    width: max(1, toolbarRect.width - 280), height: 20)
        instructions.lineBreakMode = .byTruncatingTail
        instructions.toolTip = "拖动选区内部移动；拖动边线或控制点缩放；在选区外重新框选。回车确认，Esc 取消。"
        addSubview(instructions)
        let full = NSButton(title: fullSelectionTitle, target: self, action: #selector(selectFullWindow))
        full.bezelStyle = .rounded
        full.frame = CGRect(x: toolbarRect.maxX - 255, y: toolbarRect.minY + 8, width: 62, height: 28)
        full.setAccessibilityLabel("选择全部画面")
        addSubview(full)
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelSelection))
        cancel.bezelStyle = .rounded
        cancel.frame = CGRect(x: toolbarRect.maxX - 187, y: toolbarRect.minY + 8, width: 62, height: 28)
        cancel.setAccessibilityLabel("取消框选截图")
        addSubview(cancel)
        confirmButton.target = self
        confirmButton.action = #selector(confirmSelection)
        confirmButton.bezelStyle = .rounded
        confirmButton.keyEquivalent = "\r"
        confirmButton.frame = CGRect(x: toolbarRect.maxX - 119, y: toolbarRect.minY + 8, width: 104, height: 28)
        confirmButton.setAccessibilityLabel("确认选区并复制截图")
        confirmButton.isEnabled = false
        addSubview(confirmButton)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func resetCursorRects() {
        addCursorRect(imageRect, cursor: .crosshair)
        if let selection {
            addCursorRect(selection, cursor: .openHand)
            for handle in RegionSelectionHandle.allCases {
                let point = anchor(for: handle, in: selection)
                addCursorRect(CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14),
                              cursor: resizeCursor(for: handle))
            }
        }
    }

    override func mouseMoved(with event: NSEvent) { updateCursor(at: convert(event.locationInWindow, from: nil)) }
    override func cursorUpdate(with event: NSEvent) { updateCursor(at: convert(event.locationInWindow, from: nil)) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        preview.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        let shade = NSBezierPath(rect: imageRect)
        if let selection { shade.appendRect(selection) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(selection == nil ? 0.14 : 0.42).setFill()
        shade.fill()
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: toolbarRect, xRadius: 9, yRadius: 9).fill()
        guard let selection, selection.width > 0, selection.height > 0 else { return }
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection)
        border.lineWidth = 2
        border.stroke()
        NSColor.systemBlue.setStroke()
        border.lineWidth = 1
        border.stroke()
        for handle in RegionSelectionHandle.allCases {
            let point = anchor(for: handle, in: selection)
            let marker = NSBezierPath(roundedRect: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8),
                                      xRadius: 1.5, yRadius: 1.5)
            NSColor.white.setFill()
            marker.fill()
            NSColor.systemBlue.setStroke()
            marker.lineWidth = 1.5
            marker.stroke()
        }
        if let pixels = RegionCrop.pixelRect(selection: selection, displayRect: imageRect,
                                              pixelSize: CGSize(width: image.width, height: image.height)) {
            let text = "\(Int(pixels.width)) × \(Int(pixels.height)) 像素" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let size = text.size(withAttributes: attributes)
            let label = CGRect(x: min(max(imageRect.minX + 4, selection.minX), imageRect.maxX - size.width - 16),
                               y: min(max(imageRect.minY + 4, selection.maxY + 10), imageRect.maxY - size.height - 12),
                               width: size.width + 12, height: size.height + 8)
            NSColor.black.withAlphaComponent(0.78).setFill()
            NSBezierPath(roundedRect: label, xRadius: 4, yRadius: 4).fill()
            text.draw(at: CGPoint(x: label.minX + 6, y: label.minY + 4), withAttributes: attributes)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Handles can straddle the image boundary; allow their small hit area
        // while all geometry remains clamped to the source image.
        if let selection, let handle = handle(at: point, in: selection) {
            window?.makeFirstResponder(self)
            drag = .resizing(original: selection, handle: handle, start: point)
        } else if let selection, selection.contains(point) {
            window?.makeFirstResponder(self)
            drag = .moving(original: selection, start: point)
        } else if imageRect.contains(point) {
            window?.makeFirstResponder(self)
            drag = .creating(start: point)
            selection = nil
        } else { return }
        selectionBegan?()
        updateControls()
        updateCursor(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        updateSelection(event)
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        updateSelection(event)
        drag = nil
        if let selection, selection.width < 2 || selection.height < 2 { self.selection = nil }
        updateControls()
        updateCursor(at: convert(event.locationInWindow, from: nil))
        // Mouse release intentionally never crops, completes or touches the
        // clipboard. The user can move/resize repeatedly before confirming.
    }

    override func rightMouseDown(with event: NSEvent) { cancelSelection() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelSelection() }
        else if event.keyCode == 36 || event.keyCode == 76 { confirmSelection() }
        else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { cancelSelection() }

    @objc private func cancelSelection() { completion?(nil) }

    func resetSelection() {
        drag = nil
        selection = nil
        updateControls()
    }

    @objc private func selectFullWindow() {
        selectionBegan?()
        drag = nil
        selection = imageRect
        window?.makeFirstResponder(self)
        updateControls()
    }

    @objc private func confirmSelection() {
        guard drag == nil, let selection, selection.width >= 2, selection.height >= 2,
              let crop = RegionCrop.crop(image: image, selection: selection, displayRect: imageRect) else { return }
        completion?(crop)
    }

    private func updateSelection(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch drag {
        case .creating(let start):
            selection = RegionSelectionGeometry.rect(from: start, to: point, in: imageRect)
        case .moving(let original, let start):
            selection = RegionSelectionGeometry.moved(original,
                by: CGSize(width: point.x - start.x, height: point.y - start.y), in: imageRect)
        case .resizing(let original, let handle, let start):
            selection = RegionSelectionGeometry.resized(original, handle: handle,
                by: CGSize(width: point.x - start.x, height: point.y - start.y), in: imageRect, minimumSize: 2)
        case nil: return
        }
        updateControls()
    }

    private func updateControls() {
        let valid = selection.map { $0.width >= 2 && $0.height >= 2 } ?? false
        confirmButton.isEnabled = valid && drag == nil
        instructions.stringValue = valid ? "拖动内部移动 · 边角缩放 · 回车确认" : "拖动框选 · 调整后回车确认"
        if let selection, let pixels = RegionCrop.pixelRect(selection: selection, displayRect: imageRect,
                                                             pixelSize: CGSize(width: image.width, height: image.height)) {
            setAccessibilityValue("已选 \(Int(pixels.width)) × \(Int(pixels.height)) 像素，待确认")
        } else { setAccessibilityValue("尚未选择区域") }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func anchor(for handle: RegionSelectionHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    private func handle(at point: CGPoint, in rect: CGRect) -> RegionSelectionHandle? {
        let corners: [RegionSelectionHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
        if let nearest = corners.min(by: { distance(point, anchor(for: $0, in: rect)) < distance(point, anchor(for: $1, in: rect)) }),
           distance(point, anchor(for: nearest, in: rect)) <= 9 { return nearest }
        let edges: [RegionSelectionHandle] = [.top, .right, .bottom, .left]
        for edge in edges {
            let anchor = anchor(for: edge, in: rect)
            switch edge {
            case .top, .bottom:
                if abs(point.y - anchor.y) <= 5, point.x >= rect.minX, point.x <= rect.maxX { return edge }
            default:
                if abs(point.x - anchor.x) <= 5, point.y >= rect.minY, point.y <= rect.maxY { return edge }
            }
        }
        return nil
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func updateCursor(at point: CGPoint) {
        switch drag {
        case .moving: NSCursor.closedHand.set()
        case .resizing(_, let handle, _): resizeCursor(for: handle).set()
        case .creating: NSCursor.crosshair.set()
        case nil:
            if let selection, let handle = handle(at: point, in: selection) { resizeCursor(for: handle).set() }
            else if selection?.contains(point) == true { NSCursor.openHand.set() }
            else if imageRect.contains(point) { NSCursor.crosshair.set() }
            else { NSCursor.arrow.set() }
        }
    }

    private func resizeCursor(for handle: RegionSelectionHandle) -> NSCursor {
        #if compiler(>=6.0)
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch handle {
            case .topLeft: position = .topLeft
            case .top: position = .top
            case .topRight: position = .topRight
            case .right: position = .right
            case .bottomRight: position = .bottomRight
            case .bottom: position = .bottom
            case .bottomLeft: position = .bottomLeft
            case .left: position = .left
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        #endif
        switch handle {
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        case .topLeft, .bottomRight: return Self.downDiagonalCursor
        case .topRight, .bottomLeft: return Self.upDiagonalCursor
        }
    }

    private static let downDiagonalCursor = diagonalCursor(rising: false)
    private static let upDiagonalCursor = diagonalCursor(rising: true)

    private static func diagonalCursor(rising: Bool) -> NSCursor {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { _ in
            let a = CGPoint(x: 8, y: rising ? 8 : 24), b = CGPoint(x: 24, y: rising ? 24 : 8)
            let path = NSBezierPath()
            path.move(to: a); path.line(to: b)
            for (tip, sign) in [(a, CGFloat(1)), (b, CGFloat(-1))] {
                path.move(to: CGPoint(x: tip.x + sign * 7, y: tip.y))
                path.line(to: tip)
                path.line(to: CGPoint(x: tip.x, y: tip.y + sign * (rising ? 7 : -7)))
            }
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.white.setStroke(); path.lineWidth = 4; path.stroke()
            NSColor.black.setStroke(); path.lineWidth = 2; path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 16, y: 16))
    }
}

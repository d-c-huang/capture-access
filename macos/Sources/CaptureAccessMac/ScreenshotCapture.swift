import AppKit
import CaptureCore
import ScreenCaptureKit

enum ScreenshotCapture {
    static func window(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let options = SCScreenshotConfiguration()
            options.width = configuration.width
            options.height = configuration.height
            options.showsCursor = false
            options.ignoreShadows = true
            options.ignoreClipping = true
            options.dynamicRange = .sdr
            let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: options)
            try Task.checkCancellation()
            if let image = output.sdrImage, try !CaptureImageValidation.isFullyTransparent(image) {
                return image
            }
        }
        #endif
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    #if compiler(>=6.1)
    @available(macOS 15.2, *)
    @MainActor
    static func visibleArea(filter: SCContentFilter, size: CaptureSize) async throws -> CGImage {
        guard filter.includedWindows.count == 1, let selected = filter.includedWindows.first else {
            throw CaptureFailure.invalidSize
        }
        // Read current bounds by window ID; windows can move after selection.
        guard let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, selected.windowID) as? [[String: Any]],
              let info = windows.first,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds),
              rect.width > 0, rect.height > 0 else {
            throw CaptureFailure.invalidSize
        }
        guard (info[kCGWindowSharingState as String] as? NSNumber)?.intValue != 0 else {
            throw CaptureFailure.protectedWindow
        }
        let owner = selected.owningApplication.flatMap { NSRunningApplication(processIdentifier: $0.processID) }
        // This mode captures the visible screen region, including overlaps.
        // Hide our own preview and bring the selected app forward first.
        if let owner {
            NSApp.yieldActivation(to: owner)
            owner.activate(from: .current, options: [])
        }
        NSApp.hide(nil)
        defer { NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true) }
        try await Task.sleep(nanoseconds: 500_000_000)
        guard let owner, NSWorkspace.shared.frontmostApplication == owner else {
            throw CaptureFailure.targetNotFrontmost
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.frame.contains(rect) }) else {
            throw CaptureFailure.invalidSize
        }
        // Capture the composited display rather than including a protected
        // window in the filter. Request only its screen rectangle as output.
        let displayFilter = SCContentFilter(display: display, excludingWindows: [])
        let streamOptions = SCStreamConfiguration()
        streamOptions.width = size.width
        streamOptions.height = size.height
        streamOptions.sourceRect = CGRect(x: rect.minX - display.frame.minX,
                                          y: rect.minY - display.frame.minY,
                                          width: rect.width, height: rect.height)
        streamOptions.showsCursor = false
        streamOptions.capturesAudio = false
        streamOptions.queueDepth = 3
        return try await SingleFrameCapture.capture(filter: displayFilter, configuration: streamOptions)
    }
    #endif
}

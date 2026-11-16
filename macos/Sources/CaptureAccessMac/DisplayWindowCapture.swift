import CaptureCore
import CoreGraphics
import ScreenCaptureKit

#if compiler(>=6.1)
/// A display-bound filter can behave differently from an independent-window
/// filter. It still includes exactly the single window selected by the user.
enum DisplayWindowCapture {
    @available(macOS 15.2, *)
    static func capture(selectedFilter: SCContentFilter, size: CaptureSize) async throws -> CGImage {
        guard selectedFilter.includedWindows.count == 1,
              let selectedWindow = selectedFilter.includedWindows.first else {
            throw CaptureFailure.emptyImage
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        // Avoid quietly truncating a window that spans displays or is offscreen.
        guard let window = content.windows.first(where: { $0.windowID == selectedWindow.windowID }),
              let display = content.displays.first(where: { $0.frame.contains(window.frame) }) else {
            throw CaptureFailure.emptyImage
        }
        let filter = SCContentFilter(display: display, including: [window])
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.sourceRect = CGRect(
            x: window.frame.minX - display.frame.minX,
            y: window.frame.minY - display.frame.minY,
            width: window.frame.width, height: window.frame.height
        )
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsDisplay = true
        // Keep the default transparent background, so an excluded window cannot
        // be mistaken for a successful screenshot of an opaque black surface.
        configuration.queueDepth = 3
        return try await SingleFrameCapture.capture(filter: filter, configuration: configuration)
    }
}
#endif

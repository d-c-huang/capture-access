import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    init(model: CaptureModel) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Capture Access · 窗口截图"
        window.contentMinSize = NSSize(width: 820, height: 640)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(model: model)
            .frame(minWidth: 820, minHeight: 640))
        if !window.setFrameUsingName("CaptureAccess.MainWindow") { window.center() }
        window.setFrameAutosaveName("CaptureAccess.MainWindow")
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

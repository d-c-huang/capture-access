import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let preferences: AppPreferences
    private let launchAtLogin: LaunchAtLoginController
    private let canChangeTarget: () -> Bool
    private let showAbout: () -> Void

    init(preferences: AppPreferences, launchAtLogin: LaunchAtLoginController, showAbout: @escaping () -> Void, canChangeTarget: @escaping () -> Bool) {
        self.preferences = preferences
        self.launchAtLogin = launchAtLogin
        self.showAbout = showAbout
        self.canChangeTarget = canChangeTarget
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 610),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Capture Access · 设置"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        installContent()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        guard let window else { return }
        installContent()
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func installContent() {
        guard let window else { return }
        window.contentView = NSHostingView(rootView: SettingsView(
            preferences: preferences,
            launchAtLogin: launchAtLogin,
            canChangeTarget: canChangeTarget,
            showAbout: showAbout,
            dismiss: { [weak window] in window?.close() }
        ))
    }
}

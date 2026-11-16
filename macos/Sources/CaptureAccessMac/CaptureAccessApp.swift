import AppKit
import Combine
import ScreenCaptureKit

/// Bootstrap AppKit directly: a SwiftUI Settings-only App can create an empty
/// settings window on launch, even when no preview was requested.
@main
struct CaptureAccessApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = ApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    let model = CaptureModel()
    private lazy var updates = UpdateChecker(preferences: model.preferences)
    private let launchAtLogin = LaunchAtLoginController()
    private var isTerminating = false
    private let globalShortcut = GlobalCaptureShortcut()
    private let ordinaryShortcut = GlobalCaptureShortcut()
    private var settingsWindowController: SettingsWindowController?
    private var aboutWindowController: AboutWindowController?
    private var preferenceObservation: AnyCancellable?
    private var requestedShortcuts: [CaptureShortcut] = []
    private var activeShortcuts: [CaptureShortcut] = []
    private var mainWindowController: MainWindowController?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.showMainWindow = { [weak self] in self?.showMainWindow() }
        model.showSettings = { [weak self] in self?.showSettings() }
        model.showAbout = { [weak self] in self?.showAbout() }
        model.preferences.applyShortcutChanges = { [weak self] in self?.registerShortcuts() }
        menuBarController = MenuBarController(model: model, updates: updates, checkForUpdates: { [weak self] in self?.checkForUpdates() }) { [weak self] in self?.showMainWindow() }
        registerShortcuts()
        preferenceObservation = model.preferences.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.registerShortcuts() }
        }
        if !model.preferences.hasCompletedSetup { showSettings() }
        updates.checkAutomaticallyIfNeeded()
    }

    private func registerShortcuts() {
        guard !isTerminating else { return }
        let preferences = model.preferences
        let requested = [preferences.specialShortcut, preferences.ordinaryShortcut]
        guard requested != requestedShortcuts else { return }
        requestedShortcuts = requested
        let previous = activeShortcuts
        globalShortcut.unregister()
        ordinaryShortcut.unregister()
        let specialOK = globalShortcut.register(requested[0]) { [weak model] in model?.requestSpecialCapture() }
        let ordinaryOK = requested[0] != requested[1] && ordinaryShortcut.register(requested[1]) { [weak model] in model?.requestOrdinaryCapture() }
        if specialOK && ordinaryOK {
            activeShortcuts = requested
            preferences.shortcutRegistrationError = nil
            model.globalShortcutAvailable = true
            model.ordinaryShortcutAvailable = true
        } else if previous.count == 2 {
            globalShortcut.unregister()
            ordinaryShortcut.unregister()
            model.globalShortcutAvailable = globalShortcut.register(previous[0]) { [weak model] in model?.requestSpecialCapture() }
            model.ordinaryShortcutAvailable = ordinaryShortcut.register(previous[1]) { [weak model] in model?.requestOrdinaryCapture() }
            requestedShortcuts = previous
            preferences.specialShortcut = previous[0]
            preferences.ordinaryShortcut = previous[1]
            preferences.shortcutRegistrationError = model.globalShortcutAvailable && model.ordinaryShortcutAvailable
                ? "该快捷键已被占用，已恢复原来的快捷键。请换一组组合键。"
                : "该快捷键已被占用，原快捷键也未能恢复。请重新选择；菜单按钮仍可使用。"
        } else {
            model.globalShortcutAvailable = specialOK
            model.ordinaryShortcutAvailable = ordinaryOK
            preferences.shortcutRegistrationError = "部分全局快捷键已被占用。请在设置中更换；菜单中的截图按钮仍可使用。"
        }
    }

    private func showSettings() {
        guard !isTerminating else { return }
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(preferences: model.preferences, launchAtLogin: launchAtLogin,
                showAbout: { [weak self] in self?.showAbout() }) { [weak model] in
                guard let model else { return false }
                return !model.isBusy && !model.hasPageSession
            }
        }
        settingsWindowController?.present()
    }

    private func showAbout() {
        guard !isTerminating else { return }
        if aboutWindowController == nil { aboutWindowController = AboutWindowController(updates: updates) }
        aboutWindowController?.present()
    }

    private func checkForUpdates() {
        guard !isTerminating else { return }
        showAbout()
        updates.check()
    }

    private func showMainWindow() {
        guard !isTerminating else { return }
        if mainWindowController == nil { mainWindowController = MainWindowController(model: model) }
        mainWindowController?.present()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !isTerminating {
            isTerminating = true
            updates.cancel()
            globalShortcut.unregister()
            ordinaryShortcut.unregister()
            menuBarController?.disableForTermination()
            Task {
                await model.prepareToTerminate()
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        globalShortcut.unregister()
        ordinaryShortcut.unregister()
        menuBarController?.remove()
        model.showMainWindow = nil
        model.showSettings = nil
        model.showAbout = nil
        SCContentSharingPicker.shared.isActive = false
    }
}

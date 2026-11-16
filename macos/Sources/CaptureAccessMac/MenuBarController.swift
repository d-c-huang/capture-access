import AppKit
import Combine

/// Own the status item independently of any preview window. Menu actions use
/// the same model and private capture session as the global shortcut.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private let model: CaptureModel
    private let updates: UpdateChecker
    private let checkForUpdates: () -> Void
    private let showMainWindow: () -> Void
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var observation: AnyCancellable?
    private var updateObservation: AnyCancellable?
    private var terminating = false
    private var applicationCommands: [NSMenuItem] = []

    private let state = NSMenuItem(title: "Capture Access", action: nil, keyEquivalent: "")
    private let open = NSMenuItem(title: "打开截图工具", action: #selector(openWindow), keyEquivalent: "")
    private let region = NSMenuItem(title: "开启特殊应用截图…", action: #selector(captureRegion), keyEquivalent: "s")
    private let entire = NSMenuItem(title: "截取特殊应用整个窗口", action: #selector(captureEntire), keyEquivalent: "")
    private let cancel = NSMenuItem(title: "取消本次框选", action: #selector(cancelSelection), keyEquivalent: "")
    private let client = NSMenuItem(title: "打开特殊应用", action: #selector(showClient), keyEquivalent: "")
    private let end = NSMenuItem(title: "结束截图模式", action: #selector(endSession), keyEquivalent: "")
    private let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
    private let about = NSMenuItem(title: "关于与授权声明…", action: #selector(openAbout), keyEquivalent: "")
    private let checkUpdates = NSMenuItem(title: "检查更新…", action: #selector(checkUpdate), keyEquivalent: "")
    private let downloadUpdate = NSMenuItem(title: "从 GitHub 下载更新…", action: #selector(downloadLatest), keyEquivalent: "")
    private let ordinary = NSMenuItem(title: "普通区域截图", action: #selector(captureDesktop), keyEquivalent: "a")
    private let clearHistory = NSMenuItem(title: "清空截图…", action: #selector(clearScreenshots), keyEquivalent: "")
    private let normal = NSMenuItem(title: "选择其他窗口并截图…", action: #selector(captureWindow), keyEquivalent: "")
    private let save = NSMenuItem(title: "保存最近截图 PNG…", action: #selector(saveImage), keyEquivalent: "")
    private let copy = NSMenuItem(title: "复制最近截图", action: #selector(copyImage), keyEquivalent: "")
    private let quit = NSMenuItem(title: "退出 Capture Access", action: #selector(quitApplication), keyEquivalent: "q")

    init(model: CaptureModel, updates: UpdateChecker, checkForUpdates: @escaping () -> Void, showMainWindow: @escaping () -> Void) {
        self.model = model
        self.updates = updates
        self.checkForUpdates = checkForUpdates
        self.showMainWindow = showMainWindow
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        region.keyEquivalentModifierMask = [.control, .option]
        quit.keyEquivalentModifierMask = [.command]
        region.toolTip = AppInformation.specialCaptureExplanation
        for item in [state, open, settings, about, checkUpdates, downloadUpdate, .separator(), ordinary, normal, .separator(), region, entire, cancel, client, end,
                     .separator(), save, copy, clearHistory, .separator(), quit] {
            item.target = self
            menu.addItem(item)
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Capture Access 截图工具")
            image?.isTemplate = true
            button.image = image
            if image == nil { button.title = "截" }
            button.setAccessibilityLabel("Capture Access 截图工具")
            button.toolTip = "Capture Access · 点击打开截图菜单"
        }
        item.menu = menu
        statusItem = item
        installApplicationMenu()
        observation = model.objectWillChange.sink { [weak self] _ in
            // objectWillChange arrives before the new value is assigned.
            Task { @MainActor [weak self] in self?.refresh() }
        }
        updateObservation = updates.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refresh() }

    func disableForTermination() {
        terminating = true
        refresh()
    }

    func remove() {
        observation?.cancel()
        observation = nil
        updateObservation?.cancel()
        updateObservation = nil
        menu.delegate = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    private func refresh() {
        state.isEnabled = false
        if terminating {
            state.title = "正在关闭并恢复客户端…"
            for item in menu.items + applicationCommands { item.isEnabled = false }
            return
        }
        switch model.phase {
        case .pagePreparing: state.title = "正在开启特殊应用截图…"
        case .pageReady: state.title = "特殊应用截图模式已开启"
        case .pageCapturing: state.title = "正在读取特殊应用画面…"
        case .pageSelecting, .desktopSelecting: state.title = "正在调整截图选区"
        case .restoring: state.title = "正在结束截图模式…"
        case .choosing, .capturing: state.title = "正在截取所选窗口…"
        case .idle: state.title = "Capture Access · 截图工具"
        }
        checkUpdates.title = updates.isChecking ? "正在检查更新…" : "检查更新…"
        checkUpdates.isEnabled = !updates.isChecking
        downloadUpdate.isHidden = updates.available == nil
        downloadUpdate.isEnabled = updates.available != nil
        if let update = updates.available {
            downloadUpdate.title = update.downloadURL != nil
                ? "下载新版本 \(update.version)…" : "查看新版本 \(update.version)…"
        }
        open.isEnabled = true
        settings.isEnabled = true
        settings.keyEquivalentModifierMask = [.command]
        ordinary.isEnabled = !model.isBusy
        clearHistory.isEnabled = !model.isBusy && !model.history.isWorking && (!model.history.entries.isEmpty || model.frame != nil)
        ordinary.keyEquivalent = model.preferences.ordinaryShortcut.keyEquivalent
        ordinary.keyEquivalentModifierMask = model.preferences.ordinaryShortcut.eventModifiers
        region.keyEquivalent = model.preferences.specialShortcut.keyEquivalent
        region.keyEquivalentModifierMask = model.preferences.specialShortcut.eventModifiers
        region.title = model.hasPageSession ? "框选特殊应用" : "开启特殊应用截图…"
        region.isEnabled = !model.isBusy
        entire.isEnabled = model.canCaptureSpecialPage
        cancel.isHidden = model.phase != .pageSelecting && model.phase != .desktopSelecting
        cancel.isEnabled = model.phase == .pageSelecting || model.phase == .desktopSelecting
        client.isEnabled = model.canCaptureSpecialPage
        end.isEnabled = model.hasPageSession && model.phase != .restoring
        normal.isEnabled = model.canStartSelection
        save.isEnabled = model.frame != nil && !model.isBusy
        copy.isEnabled = model.frame != nil && !model.isBusy
        quit.isEnabled = true
        for item in applicationCommands {
            item.isEnabled = validateMenuItem(item)
            if item.action == #selector(captureRegion) {
                item.title = region.title
                item.keyEquivalent = region.keyEquivalent
                item.keyEquivalentModifierMask = region.keyEquivalentModifierMask
            }
            if item.action == #selector(captureDesktop) {
                item.keyEquivalent = ordinary.keyEquivalent
                item.keyEquivalentModifierMask = ordinary.keyEquivalentModifierMask
            }
        }
        let updateHint = updates.available.map { " · 发现新版本 \($0.version)" } ?? ""
        statusItem?.button?.toolTip = state.title + updateHint + " · " + model.preferences.ordinaryShortcut.displayName + " 普通截图"
    }


    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard !terminating else { return false }
        switch item.action {
        case #selector(checkUpdate): return !updates.isChecking
        case #selector(downloadLatest): return updates.available != nil
        case #selector(captureRegion), #selector(captureDesktop): return !model.isBusy
        case #selector(captureEntire), #selector(showClient): return model.canCaptureSpecialPage
        case #selector(cancelSelection): return model.phase == .pageSelecting || model.phase == .desktopSelecting
        case #selector(clearScreenshots): return !model.isBusy && !model.history.isWorking && (!model.history.entries.isEmpty || model.frame != nil)
        case #selector(endSession): return model.hasPageSession && model.phase != .restoring
        case #selector(captureWindow): return model.canStartSelection
        case #selector(captureAgain): return model.canCaptureAgain
        case #selector(saveImage), #selector(copyImage): return model.frame != nil && !model.isBusy
        default: return true
        }
    }

    private func installApplicationMenu() {
        let bar = NSMenu()
        func section(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            item.submenu = submenu
            bar.addItem(item)
            return submenu
        }
        func systemItem(_ title: String, _ selector: Selector, key: String = "",
                        modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            return item
        }
        func command(_ title: String, _ selector: Selector, key: String = "",
                     modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
            let item = systemItem(title, selector, key: key, modifiers: modifiers, target: self)
            applicationCommands.append(item)
            return item
        }

        let application = section("Capture Access")
        application.addItem(command("关于与授权声明…", #selector(openAbout)))
        application.addItem(command("检查更新…", #selector(checkUpdate)))
        application.addItem(command("设置…", #selector(openSettings), key: ","))
        application.addItem(.separator())
        application.addItem(systemItem("隐藏 Capture Access", #selector(NSApplication.hide(_:)), key: "h", target: NSApp))
        application.addItem(systemItem("隐藏其他应用", #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option], target: NSApp))
        application.addItem(systemItem("显示全部", #selector(NSApplication.unhideAllApplications(_:)), target: NSApp))
        application.addItem(.separator())
        application.addItem(command("退出 Capture Access", #selector(quitApplication), key: "q"))

        let edit = section("编辑")
        edit.addItem(systemItem("撤销", Selector(("undo:")), key: "z"))
        edit.addItem(systemItem("重做", Selector(("redo:")), key: "z", modifiers: [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(systemItem("剪切", #selector(NSText.cut(_:)), key: "x"))
        edit.addItem(systemItem("复制", #selector(NSText.copy(_:)), key: "c"))
        edit.addItem(systemItem("粘贴", #selector(NSText.paste(_:)), key: "v"))
        edit.addItem(systemItem("全选", #selector(NSText.selectAll(_:)), key: "a"))

        let capture = section("截图")
        capture.autoenablesItems = false
        capture.delegate = self
        capture.addItem(command("打开截图工具", #selector(openWindow), key: "0"))
        capture.addItem(.separator())
        capture.addItem(command("普通区域截图", #selector(captureDesktop)))
        capture.addItem(command("开启特殊应用截图…", #selector(captureRegion), key: "s", modifiers: [.control, .option]))
        capture.addItem(command("截取特殊应用整个窗口", #selector(captureEntire)))
        capture.addItem(command("取消本次框选", #selector(cancelSelection)))
        capture.addItem(command("结束特殊应用截图模式", #selector(endSession)))
        capture.addItem(.separator())
        capture.addItem(command("选择窗口并截图", #selector(captureWindow), key: "1", modifiers: [.command, .shift]))
        capture.addItem(command("再次截图", #selector(captureAgain), key: "2", modifiers: [.command, .shift]))
        capture.addItem(.separator())
        capture.addItem(command("保存 PNG…", #selector(saveImage), key: "s"))
        capture.addItem(command("复制图片", #selector(copyImage), key: "c", modifiers: [.command, .shift]))
        capture.addItem(command("清空截图…", #selector(clearScreenshots)))

        let windows = section("窗口")
        windows.addItem(systemItem("关闭窗口", #selector(NSWindow.performClose(_:)), key: "w"))
        windows.addItem(systemItem("最小化", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        windows.addItem(systemItem("缩放", #selector(NSWindow.performZoom(_:))))
        windows.addItem(.separator())
        windows.addItem(systemItem("前置全部窗口", #selector(NSApplication.arrangeInFront(_:)), target: NSApp))
        NSApp.windowsMenu = windows
        NSApp.mainMenu = bar
    }

    @objc private func checkUpdate() { checkForUpdates() }
    @objc private func downloadLatest() { updates.openDownload() }
    @objc private func openSettings() { model.showSettings?() }
    @objc private func openAbout() { model.showAbout?() }
    @objc private func captureDesktop() { model.requestOrdinaryCapture() }
    @objc private func clearScreenshots() { model.requestClearHistory() }
    @objc private func openWindow() { showMainWindow() }
    @objc private func captureRegion() { model.requestSpecialCapture() }
    @objc private func captureEntire() { model.captureEntireSpecialPage() }
    @objc private func cancelSelection() { model.cancelRegionSelection() }
    @objc private func showClient() { model.showSpecialClient() }
    @objc private func endSession() { model.endPageCapture() }
    @objc private func captureWindow() { showMainWindow(); model.chooseWindow() }
    @objc private func captureAgain() { model.captureAgain() }
    @objc private func saveImage() { showMainWindow(); model.savePNG() }
    @objc private func copyImage() { model.copyImage() }
    @objc private func quitApplication() { NSApp.terminate(nil) }
}

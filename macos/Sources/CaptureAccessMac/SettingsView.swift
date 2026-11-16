import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var launchAtLogin: LaunchAtLoginController
    let canChangeTarget: () -> Bool
    let showAbout: () -> Void
    let dismiss: () -> Void
    @State private var specialDraft: CaptureShortcut = .specialDefault
    @State private var ordinaryDraft: CaptureShortcut = .ordinaryDefault
    @State private var error: String?
    @State private var targetChangeAllowed = true

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text(AppInformation.specialCaptureExplanation)
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Image(nsImage: targetIcon).resizable().frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preferences.targetApplicationName).font(.headline)
                            if let url = preferences.targetApplicationURL {
                                Text(url.path).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2).textSelection(.enabled)
                            } else {
                                Text("选择需要单独处理截图的应用").foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("选择应用…", action: chooseApplication)
                            .disabled(!targetChangeAllowed)
                            .accessibilityIdentifier("settings.chooseApplication")
                    }
                    Text("首次开启特殊截图会重启所选应用，之后可以连续截图。此方式适用于支持页面截图的应用；其他应用请使用普通截图。")
                        .font(.caption).foregroundStyle(.secondary)
                    if !targetChangeAllowed {
                        Text("请先完成当前操作，并结束特殊截图模式，再更换应用。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("特殊截图应用")
                }

                Section {
                    shortcutRow("特殊应用框选", shortcut: $specialDraft)
                    shortcutRow("普通区域截图", shortcut: $ordinaryDraft)
                    HStack {
                        Text("两组热键可以在其他应用中使用。")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("应用热键", action: applyShortcuts)
                            .disabled(!shortcutsChanged)
                            .accessibilityIdentifier("settings.applyShortcuts")
                    }
                    if let message = preferences.shortcutRegistrationError {
                        Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("截图热键")
                }

                Section {
                    Toggle("自动保留截图历史", isOn: $preferences.keepsHistory)
                        .accessibilityIdentifier("settings.keepsHistory")
                    Text("关闭后，新截图只保留当前预览，仍可复制或手动保存。已有历史不会自动删除，可在截图工具中清空。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("截图历史")
                }

                Section {
                    Toggle("登录 Mac 时启动", isOn: Binding(get: { launchAtLogin.isEnabled }, set: launchAtLogin.setEnabled))
                        .disabled(launchAtLogin.isChanging)
                        .accessibilityIdentifier("settings.launchAtLogin")
                    Text(launchAtLogin.message).font(.caption).foregroundStyle(.secondary)
                    if launchAtLogin.needsApproval {
                        Button("打开系统登录项设置", action: launchAtLogin.openSystemSettings)
                    }
                    if let launchError = launchAtLogin.error {
                        Text(launchError).font(.caption).foregroundStyle(.red)
                    }
                    Toggle("自动检查更新", isOn: $preferences.automaticallyChecksForUpdates)
                        .accessibilityIdentifier("settings.automaticUpdates")
                    Text("启动时每天最多检查一次 GitHub 新版本，不上传截图。发现更新后由你选择下载和替换应用。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("启动与更新")
                }

                if let error {
                    Text(error).font(.callout).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("关于与授权声明", action: showAbout)
                Spacer()
                if preferences.targetApplicationURL == nil && !preferences.hasCompletedSetup {
                    Button("暂不选择", action: finish)
                }
                Button("完成", action: finish).keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 640, minHeight: 570)
        .onAppear {
            specialDraft = preferences.specialShortcut
            ordinaryDraft = preferences.ordinaryShortcut
            targetChangeAllowed = canChangeTarget()
            launchAtLogin.refresh()
        }
        .onChange(of: preferences.specialShortcut) { _, value in specialDraft = value }
        .onChange(of: preferences.ordinaryShortcut) { _, value in ordinaryDraft = value }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            targetChangeAllowed = canChangeTarget()
            launchAtLogin.refresh()
        }
    }

    private var targetIcon: NSImage {
        if let url = preferences.targetApplicationURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }

    private var shortcutsChanged: Bool {
        specialDraft != preferences.specialShortcut || ordinaryDraft != preferences.ordinaryShortcut
    }

    private func shortcutRow(_ title: String, shortcut: Binding<CaptureShortcut>) -> some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 105, alignment: .leading)
            Picker("\(title)修饰键", selection: Binding(
                get: { shortcut.wrappedValue.modifiers },
                set: { shortcut.wrappedValue = CaptureShortcut(keyCode: shortcut.wrappedValue.keyCode, modifiers: $0) }
            )) {
                ForEach(CaptureShortcut.modifierChoices, id: \.value) { choice in
                    Text(choice.label).tag(choice.value)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            Picker("\(title)按键", selection: Binding(
                get: { shortcut.wrappedValue.keyCode },
                set: { shortcut.wrappedValue = CaptureShortcut(keyCode: $0, modifiers: shortcut.wrappedValue.modifiers) }
            )) {
                ForEach(CaptureShortcut.keys) { key in Text(key.label).tag(key.code) }
            }
            .labelsHidden()
            .frame(width: 70)
        }
    }

    private func chooseApplication() {
        guard canChangeTarget() else {
            targetChangeAllowed = false
            error = "请先结束特殊截图模式或等待当前截图完成，再更换应用。"
            return
        }
        let panel = NSOpenPanel()
        panel.title = "选择特殊截图应用"
        panel.prompt = "选择应用"
        panel.message = AppInformation.specialCaptureSummary
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = preferences.targetApplicationURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: "/Applications", isDirectory: true)
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            guard canChangeTarget() else {
                targetChangeAllowed = false
                error = "当前正在截图，请完成后再更换应用。"
                return
            }
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.pathExtension.lowercased() == "app",
                  let bundle = Bundle(url: resolved), let executable = bundle.executableURL,
                  FileManager.default.isExecutableFile(atPath: executable.path) else {
                error = "请选择可以运行的 Mac 应用。"
                return
            }
            guard resolved != Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL,
                  bundle.bundleIdentifier != Bundle.main.bundleIdentifier else {
                error = "请选择其他应用。Capture Access 用于截取其他应用的内容。"
                return
            }
            preferences.targetApplicationPath = resolved.path
            error = nil
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func applyShortcuts() {
        if let command = specialDraft.conflictingApplicationCommand ?? ordinaryDraft.conflictingApplicationCommand {
            error = "该组合键已用于“\(command)”，请为截图选择其他热键。"
            return
        }
        guard specialDraft.isValid, ordinaryDraft.isValid else {
            error = "请为截图热键选择修饰键和字母或数字。"
            return
        }
        guard specialDraft != ordinaryDraft else {
            error = "特殊截图和普通截图需要使用不同的热键。"
            return
        }
        preferences.specialShortcut = specialDraft
        preferences.ordinaryShortcut = ordinaryDraft
        preferences.applyShortcutChanges?()
        error = nil
    }

    private func finish() {
        if shortcutsChanged {
            applyShortcuts()
            guard error == nil, preferences.shortcutRegistrationError == nil else { return }
        }
        preferences.hasCompletedSetup = true
        dismiss()
    }
}

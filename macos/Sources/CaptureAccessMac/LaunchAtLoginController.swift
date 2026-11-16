import Combine
import ServiceManagement

/// Reflect the real per-user login item state. Opening settings never registers
/// a login item; only an explicit toggle changes the operating system setting.
@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var isChanging = false
    @Published private(set) var message = ""
    @Published private(set) var error: String?

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
        switch status {
        case .enabled:
            message = "已启用：登录 Mac 后自动显示菜单栏图标。"
        case .requiresApproval:
            message = "已登记，但尚未生效。请在系统“登录项”中允许 Capture Access。"
        case .notRegistered:
            message = "关闭时只会在你手动打开应用后运行。"
        case .notFound:
            message = "无法确认登录项。请将完整应用放在固定位置后重新打开。"
        @unknown default:
            message = "无法确认系统登录项状态，请打开系统设置检查。"
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard !isChanging else { return }
        isChanging = true
        error = nil
        Task {
            defer { refresh(); isChanging = false }
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval {
                        try SMAppService.mainApp.register()
                    }
                } else if SMAppService.mainApp.status != .notRegistered {
                    try await SMAppService.mainApp.unregister()
                }
            } catch {
                self.error = "未能更改登录启动设置：\(error.localizedDescription)"
            }
        }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

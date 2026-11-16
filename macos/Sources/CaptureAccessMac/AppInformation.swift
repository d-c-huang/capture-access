import Foundation

/// Shared product explanations keep setup, capture, and About wording aligned.
enum AppInformation {
    static let specialCaptureSummary = "用于在 Mac 上主动禁止或限制截图的应用；仅支持部分兼容应用。"

    static let specialCaptureExplanation = "“特殊截图应用”指在 macOS 上主动禁止或限制用户截取自身窗口的应用。普通截图可能出现黑屏、透明图片或遗漏该窗口。可选择该应用尝试特殊截图；此方式仅适用于部分兼容应用。"

    static let purpose = "Capture Access 是一款 Mac 菜单栏截图工具，支持普通区域截图和兼容应用的特殊截图。框选后可以移动、调整大小，确认后复制，也可以保存 PNG。两组截图热键及历史保存方式均可在设置中修改。"

    static let captureLifecycle = "特殊截图开启时会重启所选应用一次，之后可连续截图；结束模式时会关闭临时连接，并尝试恢复正常启动。开启前请先保存正在编辑的内容。"

    static let dataHandling = "检查更新时仅向 GitHub 请求公开版本信息，不发送截图、目标应用或历史记录；可在设置中关闭自动检查。\n\nCapture Access 不主动上传截图。历史截图默认保存在本机，可在设置中关闭新截图的历史保存，也可清空已有历史。手动另存的图片不受清空历史影响。\n\n复制图片后，内容进入系统剪贴板；后续粘贴或系统同步由系统和其他应用处理。"

    // The release configuration supplies the chosen software license and its
    // full text in Contents/Resources/LICENSE.txt.
    static let licenseName = "MIT License"

    static let licenseSummary = "允许个人和商业使用、复制、修改与分发；分发时须保留版权和许可声明。软件按“原样”提供，不作保证。具体条款以以下许可原文为准。"

    static let licenseScope = "本许可适用于 Capture Access macOS 软件，不授予截图内容或第三方应用的权利。"

    static var licenseText: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            return "当前应用未附带软件许可文本。请联系发布者确认软件的使用、复制、修改和分发权限。"
        }
        return text
    }

    static var versionDescription: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return "开发版本"
        }
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            return "版本 \(version)（\(build)）"
        }
        return "版本 \(version)"
    }
}

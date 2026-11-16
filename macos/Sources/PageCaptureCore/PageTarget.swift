import Foundation

public enum PageCaptureError: LocalizedError, Equatable {
    case connectionClosed, timeout, malformedMessage, ambiguousPage, pageUnavailable, invalidImage
    case rejected(Int)

    public var errorDescription: String? {
        switch self {
        case .connectionClosed: return "目标应用已关闭临时连接，请重新开启特殊截图模式。"
        case .timeout: return "页面截图超时，请确认目标应用仍正常运行。"
        case .malformedMessage: return "无法读取客户端的页面导出响应。"
        case .ambiguousPage: return "检测到多个应用页面。请先点选要截图的窗口，再按特殊截图快捷键；或关闭多余窗口后重试。"
        case .pageUnavailable: return "尚未找到可截图的应用页面，请打开目标窗口后重试。"
        case .invalidImage: return "客户端没有返回有效的 PNG 图片。"
        case .rejected(let code): return "客户端拒绝了页面导出请求（\(code)）。"
        }
    }
}

public struct PageTarget: Decodable, Equatable, Sendable {
    public let targetId: String
    public let type: String
    public let url: String

    public func belongsToMainPage(in application: URL) -> Bool {
        guard type == "page", !targetId.isEmpty, let location = URL(string: url),
              let scheme = location.scheme?.lowercased(),
              !["devtools", "chrome", "chrome-extension", "about"].contains(scheme) else { return false }
        if location.isFileURL {
            guard location.host == nil || location.host == "" || location.host == "localhost" else { return false }
            let prefix = application.standardizedFileURL.resolvingSymlinksInPath().path + "/Contents/Resources/"
            return location.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(prefix)
        }
        // The private pipe belongs exclusively to the selected application's
        // process. Its web/custom-protocol pages are valid too; no route name
        // or installed product name is assumed.
        return true
    }

    public static func select(from targets: [PageTarget], application: URL) throws -> PageTarget {
        let matching = targets.filter { $0.belongsToMainPage(in: application) }
        guard matching.count < 2 else { throw PageCaptureError.ambiguousPage }
        guard let target = matching.first else { throw PageCaptureError.pageUnavailable }
        return target
    }

    public static func selectVisible(from targets: [PageTarget], focusedIDs: Set<String>, visibleIDs: Set<String>) throws -> PageTarget {
        let focused = targets.filter { focusedIDs.contains($0.targetId) }
        guard focused.count < 2 else { throw PageCaptureError.ambiguousPage }
        if focused.count == 1 { return focused[0] }
        let visible = targets.filter { visibleIDs.contains($0.targetId) }
        if visible.count == 1 { return visible[0] }
        if targets.count == 1 { return targets[0] }
        throw targets.isEmpty ? PageCaptureError.pageUnavailable : PageCaptureError.ambiguousPage
    }
}

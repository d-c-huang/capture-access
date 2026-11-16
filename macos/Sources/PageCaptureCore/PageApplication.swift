import Foundation

/// Resolve the chosen bundle before closing any running application. Both the
/// UI process and the pipe bridge apply the same validation.
public struct PageApplication {
    public let url: URL
    public let executableURL: URL
    public let bundleIdentifier: String

    public init(url: URL) throws {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: resolved),
              let identifier = bundle.bundleIdentifier, !identifier.isEmpty,
              let executable = bundle.executableURL?.resolvingSymlinksInPath(),
              executable.path.hasPrefix(resolved.path + "/Contents/MacOS/"),
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw Self.failure("所选应用不存在或不完整，请在设置中重新选择。")
        }
        guard FileManager.default.fileExists(atPath: resolved.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path) else {
            throw Self.failure("此应用不支持特殊页面截图。请使用“普通区域截图”或“选择窗口并截图”。")
        }
        self.url = resolved
        self.executableURL = executable
        self.bundleIdentifier = identifier
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "CaptureAccess.Application", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

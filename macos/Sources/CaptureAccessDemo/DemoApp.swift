import AppKit

@main
enum DemoApplication {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = DemoDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class DemoDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let stateLabel = NSTextField(labelWithString: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 360),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Capture Access Demo"
        window.isReleasedWhenClosed = false
        window.sharingType = .none

        let heading = NSTextField(labelWithString: "Capture Access 测试窗口")
        heading.font = .boldSystemFont(ofSize: 25)
        let description = NSTextField(wrappingLabelWithString:
            "请在截图助手的系统选择器中选择此窗口。\n\n此窗口可以设置旧式分享保护。新版 macOS 的截图接口仍可能捕获它；这正是需要在实机上确认的行为。")
        description.font = .systemFont(ofSize: 15)
        let toggle = NSButton(checkboxWithTitle: "设置旧式窗口保护（sharingType = none）",
                              target: self, action: #selector(toggleProtection(_:)))
        toggle.state = .on
        stateLabel.stringValue = "当前：旧式保护已设置。"
        let stack = NSStackView(views: [heading, description, toggle, stateLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -30),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 30)
        ])
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleProtection(_ sender: NSButton) {
        window.sharingType = sender.state == .on ? .none : .readOnly
        stateLabel.stringValue = sender.state == .on ? "当前：旧式保护已设置。" : "当前：允许旧式分享读取。"
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

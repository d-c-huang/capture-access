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

        let heading = NSTextField(labelWithString: "Capture Access ���Դ���")
        heading.font = .boldSystemFont(ofSize: 25)
        let description = NSTextField(wrappingLabelWithString:
            "���ڽ�ͼ���ֵ�ϵͳѡ������ѡ��˴��ڡ�\n\n�˴��ڿ������þ�ʽ�����������°� macOS �Ľ�ͼ�ӿ��Կ��ܲ���������������Ҫ��ʵ����ȷ�ϵ���Ϊ��")
        description.font = .systemFont(ofSize: 15)
        let toggle = NSButton(checkboxWithTitle: "���þ�ʽ���ڱ�����sharingType = none��",
                              target: self, action: #selector(toggleProtection(_:)))
        toggle.state = .on
        stateLabel.stringValue = "��ǰ����ʽ���������á�"
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
        stateLabel.stringValue = sender.state == .on ? "��ǰ����ʽ���������á�" : "��ǰ��������ʽ������ȡ��"
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

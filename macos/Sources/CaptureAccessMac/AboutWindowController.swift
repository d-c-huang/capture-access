import AppKit
import SwiftUI

@MainActor
final class AboutWindowController: NSWindowController {
    private let updates: UpdateChecker

    init(updates: UpdateChecker) {
        self.updates = updates
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 680),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Capture Access · 关于与授权声明"
        window.contentMinSize = NSSize(width: 620, height: 570)
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
        window.contentView = NSHostingView(rootView: AboutView(updates: updates, dismiss: { [weak window] in window?.close() }))
    }
}

private struct AboutView: View {
    @ObservedObject var updates: UpdateChecker
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Capture Access").font(.title.bold())
                    Text(AppInformation.versionDescription)
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    updateSection
                    informationSection("用途说明", paragraphs: [AppInformation.purpose])
                    informationSection("特殊截图应用是什么？", paragraphs: [
                        AppInformation.specialCaptureExplanation,
                        AppInformation.captureLifecycle
                    ])
                    informationSection("截图与数据", paragraphs: [AppInformation.dataHandling])
                    VStack(alignment: .leading, spacing: 10) {
                        Text("软件授权声明").font(.headline)
                        Text(AppInformation.licenseName).font(.body.weight(.semibold))
                        Text(AppInformation.licenseSummary)
                            .font(.body).lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(AppInformation.licenseScope)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        DisclosureGroup("查看软件许可全文") {
                            Text(AppInformation.licenseText)
                                .font(.system(.caption, design: .monospaced))
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        }
                        Link("MIT 许可说明", destination: URL(string: "https://opensource.org/license/mit")!)
                            .font(.caption)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            Divider()
            HStack {
                Text("可随时从菜单栏查看本说明。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("关闭", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("about.close")
            }.padding(16)
        }
        .frame(minWidth: 620, minHeight: 570)
    }

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("软件更新").font(.headline)
                Spacer()
                Button("检查更新") { updates.check() }
                    .disabled(updates.isChecking)
                    .accessibilityIdentifier("about.checkUpdates")
            }
            HStack(alignment: .top, spacing: 8) {
                if updates.isChecking { ProgressView().controlSize(.small) }
                Text(updates.message)
                    .font(.callout).foregroundStyle(updates.failed ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let update = updates.available {
                Button(update.downloadURL != nil ? "从 GitHub 下载更新" : "查看 GitHub 发布页", action: updates.openDownload)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("about.downloadUpdate")
            } else if updates.failed {
                Button("打开 GitHub 发布页", action: updates.openReleases)
            }
            Text("下载由浏览器完成。不会自动安装，也不会上传截图内容。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func informationSection(_ title: String, paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(paragraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .font(.body)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

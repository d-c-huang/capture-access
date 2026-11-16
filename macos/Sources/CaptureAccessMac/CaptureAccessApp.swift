import AppKit
import ScreenCaptureKit
import SwiftUI

@main
@MainActor
struct CaptureAccessApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var appDelegate
    @StateObject private var model = CaptureModel()

    var body: some Scene {
        WindowGroup("Capture Access · 窗口截图") {
            ContentView(model: model)
                .frame(minWidth: 820, minHeight: 640)
        }
        .defaultSize(width: 1040, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("截图") {
                Button("选择窗口并截图") { model.chooseWindow() }
                    .keyboardShortcut("1", modifiers: [.command, .shift])
                    .disabled(model.isBusy)
                Button("再次截图") { model.captureAgain() }
                    .keyboardShortcut("2", modifiers: [.command, .shift])
                    .disabled(!model.canCaptureAgain)
                Divider()
                Button("保存 PNG…") { model.savePNG() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(model.frame == nil || model.isBusy)
                Button("复制图片") { model.copyImage() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.frame == nil || model.isBusy)
            }
        }
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        SCContentSharingPicker.shared.isActive = false
    }
}

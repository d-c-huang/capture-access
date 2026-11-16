import SwiftUI

@MainActor
struct ContentView: View {
    @ObservedObject var model: CaptureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Capture Access").font(.largeTitle.bold())
                    Text("框选、调整、确认并复制。截图随时可以另存 PNG。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.showAbout?() } label: { Label("关于", systemImage: "info.circle") }
                Button { model.showSettings?() } label: { Label("设置", systemImage: "gearshape") }
            }
            HStack(spacing: 12) {
                Button(action: model.requestOrdinaryCapture) { Label("普通区域截图", systemImage: "viewfinder") }
                    .buttonStyle(.borderedProminent).disabled(model.isBusy)
                Text(model.preferences.ordinaryShortcut.displayName).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("选择窗口并截图", action: model.chooseWindow).disabled(!model.canStartSelection)
                Button("再次截图", action: model.captureAgain).disabled(!model.canCaptureAgain)
            }
            HStack(spacing: 12) {
                Button(model.hasPageSession ? "特殊应用区域截图" : "开启特殊应用截图…", action: model.requestSpecialCapture)
                    .disabled(model.isBusy)
                    .help(AppInformation.specialCaptureExplanation)
                Text(model.preferences.specialShortcut.displayName).font(.callout).foregroundStyle(.secondary)
                if model.hasPageSession {
                    Button("截取整窗", action: model.captureEntireSpecialPage).disabled(!model.canCaptureSpecialPage)
                    Button("打开目标应用", action: model.showSpecialClient).disabled(!model.canCaptureSpecialPage)
                    Button("结束特殊模式") { model.endPageCapture() }.disabled(model.phase == .restoring)
                } else {
                    Text(model.preferences.targetApplicationURL == nil ? "在设置中选择需要特殊处理的应用" : "目标：\(model.targetName)")
                        .lineLimit(1).font(.callout).foregroundStyle(.secondary)
                }
            }
            Text(AppInformation.specialCaptureSummary)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.phase == .pageSelecting || model.phase == .desktopSelecting {
                Button("取消本次框选", action: model.cancelRegionSelection)
            } else if model.isBusy && !model.isPageFlow {
                Button("取消", action: model.cancel)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .underPageBackgroundColor))
                        if let frame = model.frame {
                            Image(nsImage: frame.preview).resizable().interpolation(.high).scaledToFit().padding(14)
                                .accessibilityLabel("截图预览")
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "rectangle.dashed").font(.system(size: 42))
                                Text("截图预览").font(.title3)
                                Text("按快捷键或点击截图按钮开始。")
                            }.foregroundStyle(.secondary)
                        }
                        if [.capturing, .pageCapturing].contains(model.phase) {
                            ProgressView("正在截图…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 220)
                    if let frame = model.frame {
                        HStack {
                            Text("\(frame.image.width) × \(frame.image.height) 像素")
                            Text(frame.date, style: .time)
                            if frame.wasReduced { Text("已等比缩小") }
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(action: model.savePNG) { Label("另存 PNG…", systemImage: "square.and.arrow.down") }
                        Button(action: model.copyImage) { Label("复制图片", systemImage: "doc.on.doc") }
                        Spacer()
                        Button("清除预览", action: model.clear)
                    }.disabled(model.frame == nil || model.isBusy)
                }
                ScreenshotHistoryView(history: model.history, onSelect: model.selectHistory,
                                      onClear: model.requestClearHistory, enabled: model.preferences.keepsHistory)
                    .frame(width: 230).disabled(model.isBusy)
            }.frame(maxHeight: .infinity)
            if let error = model.lastError {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if let error = model.preferences.shortcutRegistrationError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            if model.needsPermission {
                HStack {
                    Button("申请屏幕录制权限", action: model.requestPermission)
                    Button("打开系统权限设置", action: model.openPermissionSettings)
                }
            }
            HStack {
                if model.isBusy && model.phase != .pageSelecting && model.phase != .desktopSelecting { ProgressView().controlSize(.small) }
                Text(model.status).font(.callout).textSelection(.enabled)
            }
            DisclosureGroup("操作日志") {
                ScrollView {
                    Text(model.logs.isEmpty ? "暂无操作记录。" : model.logs.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 70)
            }
            Text("关闭窗口后仍驻留右上角菜单栏。回车确认选区，Esc 取消。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24)
        .alert("开启特殊应用截图", isPresented: $model.confirmPageCapture) {
            Button("重启一次并开启", action: model.prepareSpecialPage)
            Button("取消", role: .cancel) { }
        } message: {
            Text("请先保存“\(model.targetName)”中正在编辑的内容。开启时会重启该应用一次，之后可连续框选截图。结束模式或退出工具时，会关闭临时连接并恢复普通启动。")
        }
        .confirmationDialog("清空所有历史截图和当前预览？", isPresented: $model.confirmClearHistory, titleVisibility: .visible) {
            Button("清空截图", role: .destructive, action: model.clearHistory)
            Button("取消", role: .cancel) { }
        } message: {
            Text("工具保存的历史记录将移至废纸篓。你另存的 PNG 文件和剪贴板不受影响。")
        }
    }
}

import SwiftUI

@MainActor
struct ContentView: View {
    @ObservedObject var model: CaptureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("选择窗口，直接截图").font(.largeTitle.bold())
                    Text("选取目标窗口后预览，保存 PNG 或复制图片。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 36)).foregroundStyle(.blue)
            }

            HStack(spacing: 12) {
                Button(action: model.chooseWindow) {
                    Label("选择窗口并截图", systemImage: "viewfinder")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
                Button("再次截图", action: model.captureAgain).disabled(!model.canCaptureAgain)
                if model.isBusy { Button("取消", action: model.cancel) }
                Spacer()
                Button("打开测试窗口", action: model.openDemo).disabled(model.isBusy)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .underPageBackgroundColor))
                if let frame = model.frame {
                    Image(nsImage: frame.preview)
                        .resizable().interpolation(.high).scaledToFit().padding(16)
                        .accessibilityLabel("最近一次窗口截图预览")
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.dashed").font(.system(size: 46))
                        Text("截图预览").font(.title3)
                        Text("点击“选择窗口并截图”，在系统选择器中确认一个窗口。")
                            .font(.callout)
                    }.foregroundStyle(.secondary)
                }
                if model.phase == .capturing {
                    ProgressView("正在截图…")
                        .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 240)

            if let frame = model.frame {
                HStack {
                    Text("\(frame.image.width) × \(frame.image.height) 像素")
                    Text(frame.date, style: .time)
                    if frame.wasReduced { Text("大尺寸窗口已等比缩小") }
                }.font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(action: model.savePNG) { Label("保存 PNG…", systemImage: "square.and.arrow.down") }
                Button(action: model.copyImage) { Label("复制图片", systemImage: "doc.on.doc") }
                Spacer()
                Button("清除预览与选择", action: model.clear)
            }
            .disabled(model.frame == nil || model.isBusy)

            if let error = model.lastError {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.needsPermission {
                HStack {
                    Button("申请屏幕录制权限", action: model.requestPermission)
                    Button("打开系统权限设置", action: model.openPermissionSettings)
                }
            }
            HStack {
                if model.isBusy { ProgressView().controlSize(.small) }
                Text(model.status).font(.callout).textSelection(.enabled)
            }
            DisclosureGroup("操作日志") {
                ScrollView {
                    Text(model.logs.isEmpty ? "暂无操作记录。" : model.logs.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 85)
            }
            Text("仅对你选定的窗口截图。受保护视频等内容仍可能显示为空白。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

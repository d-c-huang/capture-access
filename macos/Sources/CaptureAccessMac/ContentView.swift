import SwiftUI

@MainActor
struct ContentView: View {
    @ObservedObject var model: CaptureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ѡ�񴰿ڣ�ֱ�ӽ�ͼ").font(.largeTitle.bold())
                    Text("ѡȡĿ�괰�ں�Ԥ�������� PNG ����ͼƬ��")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 36)).foregroundStyle(.blue)
            }

            HStack(spacing: 12) {
                Button(action: model.chooseWindow) {
                    Label("ѡ�񴰿ڲ���ͼ", systemImage: "viewfinder")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
                Button("�ٴν�ͼ", action: model.captureAgain).disabled(!model.canCaptureAgain)
                if model.isBusy { Button("ȡ��", action: model.cancel) }
                Spacer()
                Button("�򿪲��Դ���", action: model.openDemo).disabled(model.isBusy)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .underPageBackgroundColor))
                if let frame = model.frame {
                    Image(nsImage: frame.preview)
                        .resizable().interpolation(.high).scaledToFit().padding(16)
                        .accessibilityLabel("���һ�δ��ڽ�ͼԤ��")
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.dashed").font(.system(size: 46))
                        Text("��ͼԤ��").font(.title3)
                        Text("�����ѡ�񴰿ڲ���ͼ������ϵͳѡ������ȷ��һ�����ڡ�")
                            .font(.callout)
                    }.foregroundStyle(.secondary)
                }
                if model.phase == .capturing {
                    ProgressView("���ڽ�ͼ��")
                        .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 240)

            if let frame = model.frame {
                HStack {
                    Text("\(frame.image.width) �� \(frame.image.height) ����")
                    Text(frame.date, style: .time)
                    if frame.wasReduced { Text("��ߴ細���ѵȱ���С") }
                }.font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(action: model.savePNG) { Label("���� PNG��", systemImage: "square.and.arrow.down") }
                Button(action: model.copyImage) { Label("����ͼƬ", systemImage: "doc.on.doc") }
                Spacer()
                Button("���Ԥ����ѡ��", action: model.clear)
            }
            .disabled(model.frame == nil || model.isBusy)

            if let error = model.lastError {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.needsPermission {
                HStack {
                    Button("������Ļ¼��Ȩ��", action: model.requestPermission)
                    Button("��ϵͳȨ������", action: model.openPermissionSettings)
                }
            }
            HStack {
                if model.isBusy { ProgressView().controlSize(.small) }
                Text(model.status).font(.callout).textSelection(.enabled)
            }
            DisclosureGroup("������־") {
                ScrollView {
                    Text(model.logs.isEmpty ? "���޲�����¼��" : model.logs.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 85)
            }
            Text("������ѡ���Ĵ��ڽ�ͼ���ܱ�����Ƶ�������Կ�����ʾΪ�հס�")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

import SwiftUI

@MainActor
struct ScreenshotHistoryView: View {
    @ObservedObject var history: ScreenshotHistory
    let onSelect: (ScreenshotHistoryEntry) -> Void
    let onClear: () -> Void
    let enabled: Bool
    var selectedID: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("截图历史").font(.headline)
                Text("\(history.entries.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if history.isWorking { ProgressView().controlSize(.small) }
                Button("清空", action: onClear)
                    .disabled(history.entries.isEmpty || history.isWorking)
            }
            Text(enabled ? "截图会自动保存在此，可随时另存或复制。" : "历史记录已关闭，新截图仅保留当前预览。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if history.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled").font(.title)
                    Text("暂无历史截图").font(.callout)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(history.entries) { entry in
                            ScreenshotHistoryRow(history: history, entry: entry,
                                                 isSelected: selectedID == entry.id) {
                                onSelect(entry)
                            }
                        }
                    }
                    .padding(2)
                }
            }
            if let error = history.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(minWidth: 190, idealWidth: 220, maxWidth: 260)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

@MainActor
private struct ScreenshotHistoryRow: View {
    let history: ScreenshotHistory
    let entry: ScreenshotHistoryEntry
    let isSelected: Bool
    let action: () -> Void
    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .underPageBackgroundColor))
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFit().padding(2)
                    } else {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 62, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.date, format: .dateTime.month().day().hour().minute().second())
                        .font(.caption).lineLimit(1)
                    Text("\(entry.width) × \(entry.height)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(7)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("历史截图，\(entry.date.formatted())，\(entry.width) 乘 \(entry.height) 像素")
        .task(id: entry.id) { thumbnail = await history.thumbnail(for: entry) }
    }
}

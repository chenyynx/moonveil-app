// ChatMessageAttachments.swift — AA 官方 Views/Chat/ChatMessageAttachments.swift 逐字搬运
// （P1 会话聊天页批）。
//
// 搬运差异（全部留据）：
//   • 官方文件尾部的 `ChatComposerAttachment` 未重复搬运——COMPOSER-FULL 批已按同名
//     逐字搬到 ChatComposerAttachment.swift（当时即注明「本文件其余部分随聊天页批搬运」），
//     同模块重复声明会编译失败，故此处删除该 struct（官方 84-121 行）。
//   • `onScrollVisibilityChange` 是 iOS 18 API（铁律④）→ `aaScrollVisibility`
//     （RemoteGlassIfAvailable.swift，18+ 官方 EXACT 参数）。<18 无可见性回调，
//     改为 onAppear 即置 visible = true：缩略图照常加载（代价：离屏项也取图），
//     功能不缺失。
import SwiftUI
import UIKit

struct ChatMessageAttachments: View {
    let files: [ChatMessageAttachment]
    let onOpen: (V2AttachmentContent) -> Void
    let loadThumbnail: (V2AttachmentContent) async throws -> Data?
    var alignment: HorizontalAlignment = .trailing

    var body: some View {
        VStack(alignment: alignment, spacing: 8) {
            ForEach(files) { file in
                if file.content.isImage {
                    ChatMessageImage(file: file, onOpen: onOpen, loadThumbnail: loadThumbnail)
                } else {
                    Button { onOpen(file.content) } label: {
                        HStack(spacing: 12) {
                            AppSymbol(AppFileSymbol.name(for: file.content.name ?? ""), size: 24).frame(width: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(file.content.name ?? String(localized: "附件")).font(.subheadline.weight(.medium)).lineLimit(2)
                                Text(description(file.content)).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            AppSymbol("arrow.up.right", size: 14).foregroundStyle(.secondary)
                        }.padding(12).frame(maxWidth: 320, alignment: .leading)
                            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 16))
                            .contentShape(.rect(cornerRadius: 16))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private func description(_ file: V2AttachmentContent) -> String {
        let ext = ((file.name ?? "") as NSString).pathExtension.uppercased()
        return [ext.isEmpty ? String(localized: "文件") : ext, file.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

private struct ChatMessageImage: View {
    let file: ChatMessageAttachment
    let onOpen: (V2AttachmentContent) -> Void
    let loadThumbnail: (V2AttachmentContent) async throws -> Data?
    @State private var image: UIImage?
    @State private var visible = false
    @State private var failed = false
    @State private var retry = 0

    var body: some View {
        Button {
            if failed && image == nil { failed = false; retry += 1 }
            else { onOpen(file.content) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.quaternary.opacity(0.6))
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if failed {
                    Label(String(localized: "轻点重试预览"), appSymbol: "arrow.clockwise").font(.caption).foregroundStyle(.secondary)
                } else {
                    ProgressView().progressViewStyle(.circular)
                }
            }
            // Fixed preview footprint: decoding or switching from local bytes
            // to a remote thumbnail cannot move the surrounding conversation.
            .aspectRatio(4.0 / 3.0, contentMode: .fit).frame(maxWidth: 320)
            .clipShape(.rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain).accessibilityLabel(file.content.name ?? String(localized: "图片附件"))
        .onAppear {
            if image == nil, let data = file.previewData { image = UIImage(data: data) }
            if #unavailable(iOS 18.0) { visible = true }
        }
        .aaScrollVisibility(threshold: 0.01) { visible = $0 }
        .task(id: Request(visible: visible, key: file.content.cacheKey, retry: retry)) {
            guard visible, image == nil else { return }
            do {
                let data = try await loadThumbnail(file.content)
                guard !Task.isCancelled else { return }
                image = data.flatMap { UIImage(data: $0) }
                failed = image == nil
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
    private struct Request: Equatable { let visible: Bool; let key: String; let retry: Int }
}

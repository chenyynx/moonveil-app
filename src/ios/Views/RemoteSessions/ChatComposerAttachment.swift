// ChatComposerAttachment.swift — 从 AA 官方 Views/Chat/ChatMessageAttachments.swift
// 拆出 ChatComposerAttachment 部分逐字搬运（该文件其余部分 ChatMessageAttachments /
// ChatMessageImage 属于聊天消息附件显示，随「会话聊天页」批整体搬运）。
// AppFileSymbol / ByteCountFormatter 沿用。

import SwiftUI

struct ChatComposerAttachment: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void
    @State private var image: UIImage?
    var body: some View {
        Group {
            if attachment.isImage {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                    if let image { Image(uiImage: image).resizable().scaledToFill() }
                    else { AppSymbol("photo").foregroundStyle(.secondary) }
                }.frame(width: 72, height: 72).clipShape(.rect(cornerRadius: 12))
            } else {
                HStack(spacing: 8) {
                    AppSymbol(AppFileSymbol.name(for: attachment.name), size: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(attachment.name).font(.caption.weight(.medium)).lineLimit(2)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                            .font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: 140, alignment: .leading)
                }.padding(.horizontal, 12).padding(.trailing, 20).frame(height: 72)
                    .background(.primary.opacity(0.07), in: .rect(cornerRadius: 12))
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                AppSymbol("xmark.circle.fill").symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.7)).font(.system(size: 19))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).offset(x: 9, y: -9).accessibilityLabel(String(localized: "移除 \(attachment.name)"))
        }
        .task(id: attachment.id) {
            if let data = attachment.previewData { image = UIImage(data: data) }
        }
        .accessibilityLabel(attachment.name)
    }
}

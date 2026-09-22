// SessionTimelineRow.swift — AA 官方 Views/Chat/SessionTimelineRow.swift 逐字搬运（P1 会话聊天页批）。
// 差异：
//   • `ChatMarkdownView`（官方 Textual 渲染件）→ Moonveil `SelectableMarkdownView`（§0f）。
//   • `ChatSelectableText` 保持符号与调用形状，实现换成本仓 UITextView 件
//     （RemoteSelectableText.swift，§0f 禁 Textual）；字号改由调用点显式传入。
//     （B9-FIX4 起该件实名 `LocalChatSelectableText`——官方同名件随 [T-remote-skin]
//     Batch 1 落地，垫片让名。）
//   • `.traceChatLayout(...)` 诊断修饰剥离（本仓无 ChatLayoutDiagnostics 基建，
//     见差集表 A-1 末行）；官方 markdown 件上的 `.environment(\.chatLayoutTraceOwner,)`
//     是同一诊断链的键（仅被 trace 读取，SwiftUI environment 亦不下传 UIViewRepresentable）
//     → 随基建一并剥离，不留空转修饰。
//   • 官方 `ChatMarkdownView(isStreaming:resolvesFileReferences:)` 两参数属 Textual
//     渲染件私有（§0f 禁令）：流式由 `SelectableMarkdownView` 自身随 markdown 字符串
//     更新驱动；`file:行号` 引用内联可点（官方 resolvesFileReferences）在本渲染层无对应
//     物 → 已用 `SessionFileReferenceLinks.rewrite` 补齐（送渲染前把命中的
//     file:行号 inline code 重写成 markdown 链接，判定委托冻结件
//     `SessionFileReference.inlineReference`，与官方同源；点击走
//     SessionChatView 已注入的 `.environment(\.openURL)` 拦截器）。文件改动的
//     可点预览另由 TimelineFileChangeView / TimelineToolDetails 的 `onFile`
//     承担（已在链路内）。
//   • 文件末尾 `extension JSONValue { readableText }` 为官方 app 层 extension，
//     与官方同文件同位置保留（单模块下与搬运件同层，无 AAV2 冻结区改动）。

import SwiftUI
import UIKit

struct SessionTimelineRow: View {
    let row: ChatTimelineRowModel
    let chat: SessionChatModel
    let onAttachment: (V2AttachmentContent) -> Void
    var cwd: String?
    let disclosures: TimelineDisclosureState
    let onFile: (String) -> Void
    @ScaledMetric(relativeTo: .body) private var lineHeight: CGFloat = 22

    var body: some View {
        Group {
            switch row.value.content {
            case let .message(message):
                let files = chat.session.attachmentPreviews.resolve(message.attachments, clientID: row.value.source["clientMessageId"]?.stringValue)
                if row.value.role == .user {
                    UserMessageBubble(text: row.text, attachments: files, onAttachment: onAttachment, loadThumbnail: chat.thumbnail)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        markdown
                        if !files.isEmpty {
                            ChatMessageAttachments(files: files, onOpen: onAttachment, loadThumbnail: chat.thumbnail, alignment: .leading)
                        }
                        // Waiting feedback lives in the fixed header slot. An
                        // extra placeholder row would disappear on the first token.
                        if !row.value.isStreamingText {
                            if row.value.status == .interrupted || row.value.status == .cancelled {
                                Text(String(localized: "已停止生成")).font(.caption).foregroundStyle(.secondary)
                            }
                            if row.value.status == .failed { Text(String(localized: "生成未完成")).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            default:
                SessionTimelineEventView(row: row, cwd: cwd, disclosures: disclosures, onFile: onFile)

            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Long presses belong to the text selection interaction inside the row.
        // A row-wide context menu would intercept them and highlight the item.
    }

    @AppStorage(RemoteChatSkinStore.userDefaultsKey) private var skinRaw = RemoteChatSkin.fallback.rawValue
    private var markdown: some View {
        // §0f 渲染桥接 → [T-remote-skin] 皮肤分派（pp 2026-09-22 拍板三皮肤）：
        //  • aaOriginal：官方 ChatMarkdownView（Textual）原样，file:行号由官方在解析
        //    阶段挂 .link（ChatMarkdownView:44-52），resolvesFileReferences 同官方调用点。
        //  • local（默认，现状）：Moonveil SelectableMarkdownView；本仓解析器不跑挂链
        //    那趟 → 送渲染前先重写成 markdown 链接（见 SessionFileReferenceLinks）。
        // isStreaming 用本行现役流式标记（与 §0f 桥接前的一致语义）。
        if skinRaw == RemoteChatSkin.aaOriginal.rawValue {
            ChatMarkdownView(text: row.text, isStreaming: row.value.isStreamingText, resolvesFileReferences: true)
                .id(row.layoutGeneration)
        } else {
            SelectableMarkdownView(markdown: SessionFileReferenceLinks.rewrite(row.text))
                .id(row.layoutGeneration)
                .frame(minHeight: row.value.isStreamingText ? lineHeight : nil, alignment: .topLeading)
        }
    }
}

struct UserMessageBubble: View {
    let text: String
    var attachments: [ChatMessageAttachment] = []
    var onAttachment: (V2AttachmentContent) -> Void = { _ in }
    var loadThumbnail: (V2AttachmentContent) async throws -> Data? = { _ in nil }
    var isPending = false
    var onDeliveryIssue: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 8) {
                if !attachments.isEmpty {
                    ChatMessageAttachments(files: attachments, onOpen: onAttachment, loadThumbnail: loadThumbnail)
                }
                if !text.isEmpty {
                    LocalChatSelectableText(text: text, font: ChatSelectableTextStyle.body)
                        .padding(.horizontal, 17).padding(.vertical, 12)
                        .background(colorScheme == .dark ? Color(white: 0.13) : Color(white: 0.94), in: .rect(cornerRadius: 24))
                }
            }
            .overlay(alignment: .bottomLeading) {
                // Delivery state occupies the existing leading gutter, so the
                // echo never changes text wrapping or attachment width.
                if isPending {
                    ProgressView().progressViewStyle(.circular).controlSize(.small)
                        .frame(width: 18, height: 44).offset(x: -26).accessibilityLabel(String(localized: "正在发送消息"))
                } else if let onDeliveryIssue {
                    Button(action: onDeliveryIssue) {
                        AppSymbol("exclamationmark.circle").foregroundStyle(.red).frame(width: 24, height: 44)
                    }.buttonStyle(.plain).offset(x: -30).accessibilityLabel(String(localized: "查看发送问题"))
                }
            }
        }
    }
}

struct PendingMessageRow: View {
    let pending: V2PendingMessage
    let chat: SessionChatModel
    let onAttachment: (V2AttachmentContent) -> Void
    let onDismiss: () -> Void
    @State private var confirmsDismiss = false
    var body: some View {
        UserMessageBubble(text: pending.content,
            attachments: chat.session.attachmentPreviews.resolve(pending.attachments.map(\.content), clientID: pending.id),
            onAttachment: onAttachment, loadThumbnail: chat.thumbnail, isPending: pending.delivery == .sending || pending.delivery == .accepted,
            onDeliveryIssue: deliveryIssue == nil ? nil : { confirmsDismiss = true })
        .confirmationDialog(deliveryIssue ?? "", isPresented: $confirmsDismiss, titleVisibility: .visible) {
            Button(String(localized: "返回编辑")) {
                if chat.session.isLocalCreation { chat.onEditCreation?(pending) }
                else { _ = chat.session.restoreDraft(from: pending) }
            }
            Button(String(localized: "移除此发送记录")) {
                if chat.session.isLocalCreation { chat.onDiscardCreation?() } else { onDismiss() }
            }
            Button(String(localized: "取消"), role: .cancel) {}
        }
    }
    private var deliveryIssue: String? {
        switch pending.delivery {
        case .uncertain: String(localized: "发送结果尚未确认，草稿已保留。请先检查会话是否已收到消息；移除记录后再次发送可能产生重复消息。")
        case let .rejected(error): error.message
        default: nil
        }
    }
}

extension JSONValue {
    var readableText: String {
        if case let .string(value) = self { return value }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

// ChatComposer.swift — AA 官方 Views/Chat/Composer/ChatComposer.swift 逐字搬运。
//
// 唯一适配（版本守卫，先例 AuthGlassCompat / AppGlassButton）：GlassEffectContainer /
// glassEffect / glassEffectID 是 iOS 26 API，主 target 17.0 —— 26+ 用官方 EXACT 参数；
// <26 用系统最接近物（.regularMaterial 圆角背景），不发明玻璃。文案为官方 zh-Hans 显示值。

import SwiftUI

struct ChatComposer: View {
    @Bindable var draft: ComposerDraft
    let editor: ComposerEditorController
    let isStreaming: Bool
    var canSend = true
    var canStop = true
    var isBusy = false
    // 官方 key「询问 Agents」的 zh-Hans 显示值 =「描述任务...」。
    var placeholder = String(localized: "描述任务...")
    let maximumEditorHeight: CGFloat
    let controls: ChatControlMetrics
    let onSend: () -> Void
    let onStop: () -> Void
    let onOptions: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glass

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 12) {
                    composerContent
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: draft.isExpanded ? controls.expandedCornerRadius : controls.collapsedCornerRadius))
                        .glassEffectID("composer", in: glass)
                }
            } else {
                composerContent
                    .background(.regularMaterial, in: RoundedRectangle(
                        cornerRadius: draft.isExpanded ? controls.expandedCornerRadius : controls.collapsedCornerRadius,
                        style: .continuous))
            }
        }
        .padding(.horizontal, draft.isExpanded ? ChatControlMetrics.expandedHorizontalInset : ChatControlMetrics.collapsedHorizontalInset)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: draft.isExpanded)
    }

    private var composerContent: some View {
        VStack(spacing: 0) {
            if !draft.attachments.isEmpty { attachmentTray }
            ComposerLayout(expanded: draft.isExpanded, maximumEditorHeight: maximumEditorHeight, controls: controls) {
                Button(action: onOptions) {
                    AppSymbol("plus", size: 24)
                        .frame(width: controls.touchTarget, height: controls.touchTarget)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "附件与对话选项"))
                .accessibilityIdentifier("chat.composer.options")

                ZStack(alignment: .topLeading) {
                    if draft.text.isEmpty {
                        Text(placeholder)
                            .font(.body)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                    }
                    NativeComposerEditor(draft: draft, controller: editor, maximumHeight: maximumEditorHeight, onCommandSend: onSend)
                }

                Button(action: isStreaming ? onStop : onSend) {
                    AppSymbol(isStreaming ? "stop.fill" : "arrow.up", size: isStreaming ? 13 : 18)
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(AppTheme.primaryControlForeground(colorScheme))
                        .frame(width: controls.sendDiameter, height: controls.sendDiameter)
                        .background(AppTheme.primaryControlBackground(colorScheme).opacity((isStreaming ? canStop : canSend && draft.canAttemptSend) && !isBusy ? 1 : 0.42), in: Circle())
                        .frame(width: controls.touchTarget, height: controls.touchTarget)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy || (isStreaming ? !canStop : !canSend || !draft.canAttemptSend))
                // 官方 key「发送消息」→「发送」；「停止生成」→「中断」。
                .accessibilityLabel(isStreaming ? String(localized: "中断") : String(localized: "发送"))
                .accessibilityHint(draft.isComposing ? String(localized: "请先确认输入法候选文字") : "")
                .accessibilityIdentifier("chat.composer.send")
            }
        }
    }

    private var attachmentTray: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(draft.attachments) { attachment in
                    ChatComposerAttachment(attachment: attachment) {
                        draft.attachments.removeAll { $0.id == attachment.id }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }
}

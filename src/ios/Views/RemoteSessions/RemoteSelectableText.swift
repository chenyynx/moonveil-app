// RemoteSelectableText.swift — 官方 Views/Chat/Markdown/ChatSelectableText.swift 的本仓等价物。
//
// §0f 禁令：官方件依赖 Textual（`InlineText` + `.textual.textSelection`），官方
// Markdown 家族 UI 与 Textual 均不得落地。官方对该件的语义（原文注释）：
//   "Uses the same range selection as Markdown without interpreting user input or
//    tool output as markup. SwiftUI Text's copy menu selects the entire value on iOS."
// 本实现用 UITextView（isEditable=false / isSelectable=true / isScrollEnabled=false）
// 还原该语义：局部范围选择 ✓、逐字不解释标记 ✓。
//
// 与官方的差异（合法差异类②「官方依赖本仓不存在的能力」）：SwiftUI 的 `.font()`
// 不传导进 UITextView（iOS 17 无公开 Font→UIFont 转换），故字号/颜色由调用点显式
// 传入，三处调用点各给与官方等值的样式（见各文件字据）。符号沿用官方名
// `ChatSelectableText`，使搬运件的调用形状保持逐字。
// 尺寸语义补齐（BUBBLE-HUG）：官方 `InlineText` 在 SwiftUI 里按文本用字宽度参与
// 布局；UIViewRepresentable 默认不参与 → 必须自己实现 `sizeThatFits` 报 hug 宽度，
// 否则官方 `UserMessageBubble` 的 `Spacer(minLength: 48)` 与本件平分宽度。
//
// 先例：本机线 AIChatView 内同法 `SelectableTextView`（private 不可复用）。

import SwiftUI

/// 两种尺寸模式：
/// - 默认：宽度 = 文本在容器上限内的实际排版宽度（hug，同官方 `InlineText`），
///   高度 = 该宽度下的排版高度（用户气泡）。
/// - `ownsContentWidth`：按内容宽度撑开（官方 code / diff 面板在横向 ScrollView
///   内用 `.fixedSize(horizontal: true, vertical: false)`）。
final class ChatSelectableTextView: UITextView {
    var ownsContentWidth = false

    override var intrinsicContentSize: CGSize {
        guard ownsContentWidth else { return super.intrinsicContentSize }
        let fit = sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: ceil(fit.width), height: ceil(fit.height))
    }

    /// 官方 `InlineText` 的宽度语义：在给定上限内按文本实际排版宽度收拢。
    /// 不能用 `sizeThatFits` 的返回值当宽度——UITextView 在该路径回传的是约束
    /// 宽度而非用字宽度（气泡会被拉满整行、文字左靠，pp 2026-09-21 装机截图），
    /// 故临时把 textContainer 撑到上限后取 `usedRect`，量完立即还原；
    /// `widthTracksTextView` 保持 true，下一次布局仍按 bounds 复位容器宽度。
    func hugSize(maxWidth: CGFloat) -> CGSize {
        let container = textContainer
        let saved = container.size
        container.size = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        container.size = saved
        return CGSize(width: min(ceil(used.width), maxWidth), height: ceil(used.height))
    }
}

struct ChatSelectableText: UIViewRepresentable {
    let text: String
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var color: Color = .primary
    var ownsContentWidth = false

    func makeUIView(context: Context) -> ChatSelectableTextView {
        let view = ChatSelectableTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        return view
    }

    func updateUIView(_ view: ChatSelectableTextView, context: Context) {
        view.font = font
        view.textColor = UIColor(color)
        view.ownsContentWidth = ownsContentWidth
        if view.text != text { view.text = text }
        view.invalidateIntrinsicContentSize()
        view.setNeedsLayout()
    }

    /// 默认模式的 SwiftUI 尺寸入口。不实现则 SwiftUI 落到 `intrinsicContentSize`
    /// 的宽度 = `noIntrinsicMetric` → 本件在宽度上"可变"，会和同一 `HStack` 里的
    /// `Spacer(minLength: 48)`（官方 `UserMessageBubble`）平分宽度，气泡被拉满。
    /// `ownsContentWidth` 返回 nil：走 SwiftUI 默认（读 intrinsicContentSize），
    /// 由调用点 `.fixedSize(horizontal: true, ...)` 决定宽度。
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ChatSelectableTextView, context: Context) -> CGSize? {
        guard !uiView.ownsContentWidth else { return nil }
        let proposed = proposal.width ?? .infinity
        let maxWidth = proposed.isFinite ? proposed : UIView.layoutFittingExpandedSize.width
        return uiView.hugSize(maxWidth: maxWidth)
    }
}

/// 调用点常用的两组等值样式（官方 SwiftUI 字级 → UIFont）。
enum ChatSelectableTextStyle {
    /// 官方 `.font(.body)`（用户气泡）。
    static let body = UIFont.preferredFont(forTextStyle: .body)
    /// 官方 `.font(.system(.caption, design: .monospaced))`（code / diff 面板）。
    static let captionMonospace = UIFont.monospacedSystemFont(
        ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .regular)
}

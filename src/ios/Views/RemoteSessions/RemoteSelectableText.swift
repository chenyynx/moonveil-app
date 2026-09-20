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
//
// 先例：本机线 AIChatView 内同法 `SelectableTextView`（private 不可复用）。

import SwiftUI

/// 两种尺寸模式：
/// - 默认：宽度由 SwiftUI 容器给定，高度 = 该宽度下的排版高度（用户气泡）。
/// - `ownsContentWidth`：按内容宽度撑开（官方 code / diff 面板在横向 ScrollView
///   内用 `.fixedSize(horizontal: true, vertical: false)`）。
final class ChatSelectableTextView: UITextView {
    var ownsContentWidth = false
    private var lastHeight: CGFloat = 0

    override var intrinsicContentSize: CGSize {
        if ownsContentWidth {
            let fit = sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
            return CGSize(width: ceil(fit.width), height: ceil(fit.height))
        }
        return CGSize(width: UIView.noIntrinsicMetric, height: lastHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !ownsContentWidth, bounds.width > 0 else { return }
        let fit = sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        let height = ceil(fit.height)
        guard abs(height - lastHeight) > 0.5 else { return }
        lastHeight = height
        invalidateIntrinsicContentSize()
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
}

/// 调用点常用的两组等值样式（官方 SwiftUI 字级 → UIFont）。
enum ChatSelectableTextStyle {
    /// 官方 `.font(.body)`（用户气泡）。
    static let body = UIFont.preferredFont(forTextStyle: .body)
    /// 官方 `.font(.system(.caption, design: .monospaced))`（code / diff 面板）。
    static let captionMonospace = UIFont.monospacedSystemFont(
        ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .regular)
}

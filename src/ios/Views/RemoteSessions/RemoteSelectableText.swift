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

    /// 影子测量用字体。`UITextView.font` 是 `UIFont?`，而 `ShadowMeasurer.measure`
    /// 要非可选（`addAttribute(.font, value:)` 收到 nil 会 trap）；不用 `?? 兜底`，
    /// 因为兜底等于悄悄拿错字体量宽度（code / diff 面板是等宽字体）。由
    /// `updateUIView` 与 representable 的 `font` 保持同步，默认值与那里逐字一致。
    var measurementFont: UIFont = .preferredFont(forTextStyle: .body)

    override var intrinsicContentSize: CGSize {
        guard ownsContentWidth else { return super.intrinsicContentSize }
        let fit = sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: ceil(fit.width), height: ceil(fit.height))
    }

    /// 官方 `InlineText` 的宽度语义：在给定上限内按文本实际排版宽度收拢。
    /// 不能用 `sizeThatFits` 的返回值当宽度——UITextView 在该路径回传的是约束
    /// 宽度而非用字宽度（气泡会被拉满整行、文字左靠，pp 2026-09-21 装机截图）。
    ///
    /// [STREAMING-LOOP-FIX] 旧实现在 `sizeThatFits` 同步路径里直接改本 view 自己的
    /// `textContainer.size` + `ensureLayout`。SwiftUI 一次布局 pass 会用不同 proposal
    /// 对同一视图测多遍，每遍都动 container 状态 → TextKit invalidation → SwiftUI
    /// 重新布局 → 乒乓（pp 2026-09-22 装机：agent 流式回复时 881 次重复 setSize、
    /// 主线程 hang 2.7s、内存 57→520MB、前台被杀）。官方 `InlineText` 是纯 SwiftUI
    /// Text，measure 无副作用，本仓 UITextView 件必须靠**影子测量**补齐这个差异：
    /// 用一套完全独立的离屏 TextKit 组件量宽度，绝不碰 uiView 自己的容器状态。
    func hugSize(maxWidth: CGFloat) -> CGSize {
        ShadowMeasurer.shared.measure(text, font: measurementFont, maxWidth: maxWidth)
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
        view.measurementFont = font
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
/// 离屏文本测量器（[STREAMING-LOOP-FIX]）：供 `hugSize` 在 SwiftUI 的
/// `sizeThatFits` 同步路径里安全地量"用字宽度"，完全不触碰任何屏幕上的
/// NSTextContainer/NSLayoutManager 状态，因而不会触发 invalidation → 布局乒乓。
/// UITextView 的 `sizeThatFits` 回传的是约束宽度（不是用字宽度），所以必须自己
/// 用 `usedRect` 量；把 TextKit 三件套按 (text, font) 缓存复用，避免每帧重建。
private final class ShadowMeasurer {
    static let shared = ShadowMeasurer()

    private struct Key: Hashable {
        let text: String
        let font: UIFont
        let maxWidth: CGFloat
    }

    private var cache: [Key: CGSize] = [:]
    private var storage = NSTextStorage()
    private var layoutManager = NSLayoutManager()
    private var container: NSTextContainer!

    /// 流式回复时每个 token 都是新文本，缓存命中率为 0 却会无限堆积（正是本批要修的
    /// 内存膨胀面）。设上限：超过即整体清空——静态历史消息重算的代价远小于泄漏。
    private let cacheLimit = 64

    private init() {
        container = NSTextContainer(size: CGSize(width: 0, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
    }

    func measure(_ text: String, font: UIFont, maxWidth: CGFloat) -> CGSize {
        let key = Key(text: text, font: font, maxWidth: maxWidth)
        if let hit = cache[key] { return hit }
        if cache.count >= cacheLimit { cache.removeAll() }

        let capped = min(maxWidth, 10_000)
        container.size = CGSize(width: capped, height: .greatestFiniteMagnitude)
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
        storage.addAttribute(.font, value: font, range: NSRange(location: 0, length: storage.length))
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let result = CGSize(width: min(ceil(used.width), maxWidth), height: ceil(used.height))
        cache[key] = result
        return result
    }
}

enum ChatSelectableTextStyle {
    /// 官方 `.font(.body)`（用户气泡）。
    static let body = UIFont.preferredFont(forTextStyle: .body)
    /// 官方 `.font(.system(.caption, design: .monospaced))`（code / diff 面板）。
    static let captionMonospace = UIFont.monospacedSystemFont(
        ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .regular)
}

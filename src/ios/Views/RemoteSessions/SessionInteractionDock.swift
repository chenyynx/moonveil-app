// SessionInteractionDock.swift — AA 官方 Views/Chat/SessionInteractionDock.swift 逐字搬运。
//
// 唯一差异（铁律④）：`scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))`
// 的 limitBehavior 参数是 iOS 18 API；<18 退化为官方同款 `.viewAligned`（仍逐卡吸附，
// 只是不强制一次一张）。
import SwiftUI

private struct DockSnapBehavior: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        } else {
            content.scrollTargetBehavior(.viewAligned)
        }
    }
}

struct SessionInteractionDock: View {
    let chat: SessionChatModel
    let onShowAll: (String) -> Void
    @State private var selectedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var metrics = SessionInteractionMetrics()

    private var items: [SessionNoticeModel] { chat.session.notices.notices.filter { $0.blocks(chat.session.id) } }
    private var selectedIndex: Int { items.firstIndex { $0.id == selectedID } ?? 0 }
    // Reserve the same peeking space for one or several cards, so resolving a
    // queued item does not resize the entire dock. Status text never measures it.
    private let peek: CGFloat = 12
    private var pageHeight: CGFloat {
        metrics.compactHeight
    }

    var body: some View {
        // [STREAMING-LOOP-FIX] 旧实现在一次 body 求值里访问 `items` 计算属性 5 次
        // （!isEmpty / ForEach / count×2 / onChange），每次都对全部 notices 跑一遍
        // filter，而 blocks() 内部访问 @Observable 的 submission/notice 属性 →
        // 读一次注册一次依赖。SSE 高频投递时 update() 的 notice=next 赋值
        // （@Observable 不做相等性短路）反复使依赖失效 → body 重算 → 循环
        // （pp 2026-09-22 装机：agent 流式回复时主线程 hang 2.7s、内存 57→520MB、
        // 前台被杀）。在此算一次局部常量，body 内全部引用走它：filter 只跑一遍，
        // 依赖只注册一轮（依赖数随 notices 数量而非访问次数增长）。
        let items = chat.session.notices.notices.filter { $0.blocks(chat.session.id) }
        let motionReduced = reduceMotion
        if !items.isEmpty {
            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        SessionInteractionCard(item: item, chat: chat,
                            page: items.count > 1 ? "\(index + 1)/\(items.count)" : nil,
                            height: pageHeight, onExpand: { onShowAll(item.id) })
                            .scrollTransition(.interactive, axis: .vertical) { content, phase in
                                content.scaleEffect(motionReduced ? 1 : 1 - min(abs(phase.value), 1) * 0.04)
                                    .opacity(1 - min(abs(phase.value), 1) * 0.3)
                            }
                            .accessibilityAction(named: String(localized: "下一项")) { step(1) }
                            .accessibilityAction(named: String(localized: "上一项")) { step(-1) }
                            .id(item.id)
                    }
                }.scrollTargetLayout()
            }
            .contentMargins(.vertical, peek, for: .scrollContent)
            modifier(DockSnapBehavior())
            .scrollPosition(id: $selectedID, anchor: .center)
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
            .frame(height: pageHeight + peek * 2).clipped()
            .onChange(of: items.map(\.id), initial: true) { old, next in
                if let selectedID, next.contains(selectedID) { return }
                let index = old.firstIndex(of: selectedID ?? "") ?? 0
                selectedID = next.isEmpty ? nil : next[min(index, next.count - 1)]
            }
            .padding(.horizontal, 24)
        }
    }
    private func step(_ delta: Int) {
        let index = selectedIndex + delta
        guard items.indices.contains(index) else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { selectedID = items[index].id }
    }
}

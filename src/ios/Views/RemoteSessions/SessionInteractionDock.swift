// SessionInteractionDock.swift — AA 官方 Views/Chat/SessionInteractionDock.swift 逐字搬运。
//
// 唯一差异（铁律④）：`scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))`
// 的 limitBehavior 参数是 iOS 18 API；<18 退化为官方同款 `.viewAligned`（仍逐卡吸附，
// 只是不强制一次一张）。
import SwiftUI

private struct DockSnapBehavior: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            contentmodifier(DockSnapBehavior())
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

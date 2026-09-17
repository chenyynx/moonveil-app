import SwiftUI

// MARK: - Thinking Detail Sheet (汇聚页, 原生 sheet 版)
//
// 2026-09-17 pp 装机两连改判：
//   ① 弹窗用【原生 sheet】——grabber/圆角/dimming/拖拽吸附/下拉关闭全交系统，
//     弃用自绘 overlay 壳（B1 自绘版随本改删除）。
//   ② 排版对照 Grok 实拍（photo_800AE8C8）：标题居中、白卡、大 copy 按钮（22pt）、
//     spinner 20pt、卡圆角 16、去描边。
// 本视图 = sheet 的内容；detents/背景由调用侧 presentation 修饰符给。
// 已拍板交互：点思考行 = 展开该阶段思考原文（保持现状）[B5]；尾部渐显 [A6]。

struct ThinkingDetailOverlay: View {
    @ObservedObject var message: ChatMessage
    let segment: TurnActivitySegment
    let isActiveMessage: Bool

    @State private var thinkingExpanded = false

    // MARK: Colors (Grok 实拍对照 photo_800AE8C8)

    private static let sheetBg = Color(red: 0.953, green: 0.953, blue: 0.953)     // #F3F3F3
    private static let titleGray = Color(red: 0.431, green: 0.431, blue: 0.431)   // #6E6E6E
    private static let thinkingGray = Color(red: 0.439, green: 0.439, blue: 0.439) // #707070
    private static let timelineGray = Color(red: 0.890, green: 0.890, blue: 0.882) // #E3E3E1

    /// All thinking blocks of this stage (a stage absorbs every
    /// thinking/tool loop until the next reply content) [pp 09-17 v3].
    private var thinkingBlocks: [AssistantBlock] {
        segment.thinkingIds.compactMap { id in message.blocks.first { $0.id == id } }
    }

    private var toolBlocks: [AssistantBlock] {
        segment.toolIds.compactMap { id in message.blocks.first { $0.id == id } }
    }

    private var isSegmentRunning: Bool { !segment.isDone }

    var body: some View {
        VStack(spacing: 0) {
            // 居中灰标题 [Grok 对照：标题居中，非左对齐]
            Text(verbatim: "Thinking") // [pp 09-17] 灰标题固定英文
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Self.titleGray)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .shimmerText()

            thinkingRow
                .padding(.horizontal, 20)
                .padding(.top, 14)

            if thinkingExpanded {
                thinkingBody
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(.opacity)
            }

            cardsList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Self.sheetBg)
        .animation(.easeInOut(duration: 0.25), value: thinkingExpanded)
    }

    // MARK: Thinking row (状态跟随)

    private var thinkingRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { thinkingExpanded.toggle() }
        } label: {
            HStack(spacing: 10) {
                // [pp 09-17] 完成态不显示图标——只有运行中的 thinking 图标
                // （spinner/点阵）才显示。
                if isSegmentRunning {
                    CometSpinner(size: 20, color: Self.thinkingGray) // [Grok 对照] 大 spinner
                }
                Group {
                    if isSegmentRunning {
                        Text(AppLocalized("Thinking…"))
                    } else {
                        Text(verbatim: "Thinking") // [pp 09-17] 完成态
                    }
                }
                .font(.system(size: 16))
                .foregroundStyle(Self.thinkingGray)
                .shimmerText()
                Spacer(minLength: 0)
                AppSymbol("chevron.down", size: 16)
                    .foregroundStyle(Self.thinkingGray.opacity(0.8))
                    .rotationEffect(.degrees(thinkingExpanded ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Thinking source text with streaming tail fade [A6]: settled chars in
    /// ink, latest run in light gray, all ink when finished.
    @ViewBuilder
    private var thinkingBody: some View {
        let merged = thinkingBlocks.map(\.content).filter { !$0.isEmpty }.joined(separator: "\n\n")
        if !merged.isEmpty {
            let text = merged
            let tailCount = min(24, text.count)
            let settled = String(text.dropLast(tailCount))
            let tail = String(text.suffix(tailCount))
            (Text(
                (try? AttributedString(markdown: settled)) ?? AttributedString(settled)
            )
            .font(.system(size: 13))
            .foregroundStyle(Color(uiColor: .label)) // settled black
            +
            Text(
                (try? AttributedString(markdown: tail)) ?? AttributedString(tail)
            )
            .font(.system(size: 13))
            .foregroundStyle(Color(uiColor: .lightGray))) // streaming tail 浅灰
            .padding(.leading, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Timeline + cards

    private var cardsList: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Self.timelineGray)
                    .frame(width: 2)
                    .padding(.top, 12)
                VStack(spacing: 14) {
                    ForEach(toolBlocks, id: \.id) { block in
                        card(for: block)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
    }

    @ViewBuilder
    private func card(for block: AssistantBlock) -> some View {
        if let item = ToolEventRowFactory.item(for: block) {
            let inFlight: Bool = {
                switch block.toolStatus {
                case .streaming, .running: return true
                default: return false
                }
            }()
            ToolCardView(
                title: item.title,
                subtitle: item.detail.isEmpty ? nil : item.detail,
                content: block.content,
                iconName: item.iconName,
                usesSFSymbol: item.usesSFSymbol,
                accentColor: ToolActivityIcon.accentColor(for: block.kind),
                isInFlight: inFlight
            )
        }
    }
}

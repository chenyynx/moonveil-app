import SwiftUI

// MARK: - Thinking Detail Sheet (汇聚页, 原生 sheet 版)
//
// 2026-09-17 pp 装机两连改判：
//   ① 弹窗用【原生 sheet】——grabber/圆角/dimming/拖拽吸附/下拉关闭全交系统，
//     弃用自绘 overlay 壳（B1 自绘版随本改删除）。
//   ② 排版对照 Grok 实拍：标题居中。
// 2026-09-18 pp 第三轮改判（Grok photo_353E81A2 / photo_2F211FE1 逐像素实测 +
// Claude 纯思考弹窗截图）：
//   - sheet 底 #F5F5F5；顶部标题 =「思考结果」（有工具）/ "Thought for Ns"（纯思考）
//   - 阶段行完成态 = ✓ + "Thought for Ns"（时长 = ThinkingRunClock 落定值）
//   - timeline = 项目间短竖线段（1.33pt #DCDCDC，gutter 列）；无贯穿长线
//   - 无输出工具 = ✓ 完成行（12.5pt #3D3D3D）；有输出 = 描边卡（ToolCardView）
//   - 纯思考段 = 原文衬线直展（无折叠行 / 无 timeline / 无 chevron）
// 本视图 = sheet 的内容；detents/背景由调用侧 presentation 修饰符给。
// 已拍板交互：点思考行 = 展开该阶段思考原文（保持现状）[B5]；尾部渐显 [A6]。

struct ThinkingDetailOverlay: View {
    @ObservedObject var message: ChatMessage
    let segment: TurnActivitySegment
    let isActiveMessage: Bool

    @State private var thinkingExpanded = false

    // MARK: Colors (Grok 实拍对照 photo_353E81A2 / photo_2F211FE1)

    private static let sheetBg = Color(red: 0.961, green: 0.961, blue: 0.961)       // #F5F5F5
    private static let stepInk = Color(red: 0.239, green: 0.239, blue: 0.239)       // #3D3D3D
    private static let checkGray = Color(red: 0.478, green: 0.478, blue: 0.478)     // #7A7A7A
    private static let connectorGray = Color(red: 0.863, green: 0.863, blue: 0.863) // #DCDCDC

    // gutter 几何 [实测：✓中心 x≈25.7pt / 文字 x≈38.3 / 卡 x≈49.3；左缘 20]
    private static let gutterWidth: CGFloat = 12
    private static let gutterGap: CGFloat = 7
    private static let cardIndent: CGFloat = 11

    /// All thinking blocks of this stage (a stage absorbs every
    /// thinking/tool loop until the next reply content) [pp 09-17 v3].
    private var thinkingBlocks: [AssistantBlock] {
        segment.thinkingIds.compactMap { id in message.blocks.first { $0.id == id } }
    }

    private var toolBlocks: [AssistantBlock] {
        segment.toolIds.compactMap { id in message.blocks.first { $0.id == id } }
    }

    private var isSegmentRunning: Bool { !segment.isDone }

    /// 纯思考段 = 无任何工具调用 [pp 09-18 Claude 对照：原文直展]。
    private var isPureThinking: Bool { toolBlocks.isEmpty }

    /// 落定思考时长（秒）；nil = 无数据（旧消息/未落定）。
    private var settledSeconds: Int? {
        guard let t = ThinkingRunClock.frozenValue(anchorId: segment.anchorId) else { return nil }
        return max(1, Int(t.rounded()))
    }

    /// 语义标题：LLM 摘要优先（对齐 classic 胶囊 displayTitle [pp 09-18：改 UI 不改语义]），fallback 类型名。
    private func displayTitle(for block: AssistantBlock, fallback: String) -> String {
        if let s = block.toolSummary, !s.isEmpty { return s }
        return fallback
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isPureThinking {
                // [pp 09-18] 纯思考：原文衬线直展（无折叠行 / 无 timeline）。
                ScrollView {
                    thinkingText(size: 15.5, serif: true)
                        .padding(.horizontal, 24)
                        .padding(.top, 14)
                        .padding(.bottom, 30)
                }
            } else {
                thinkingRow
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                if thinkingExpanded {
                    thinkingText(size: 13, serif: false)
                        .padding(.leading, 39) // 20 + gutter 12 + gap 7 [Grok 实测对齐]
                        .padding(.trailing, 20)
                        .padding(.top, 8)
                        .transition(.opacity)
                }

                cardsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Self.sheetBg)
        .animation(.easeInOut(duration: 0.25), value: thinkingExpanded)
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        Group {
            if isPureThinking, isSegmentRunning {
                Text(AppLocalized("Thinking…"))
            } else if isPureThinking, let secs = settledSeconds {
                Text(verbatim: "Thought for \(secs)s") // [pp 09-18] Claude 式
            } else {
                Text(AppLocalized("Thinking result")) // 思考结果
            }
        }
        .font(.system(size: 17, weight: .semibold)) // [pp 09-18 Claude Summary 实测：标题 ~17.5pt 近黑 #0E0E0E，与正文同级；原 13pt 灰过弱]
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity)
        .padding(.top, 16) // [pp 09-18] 抓条到标题间距
        .shimmerText()
    }

    // MARK: Thinking row (状态跟随)

    private var thinkingRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { thinkingExpanded.toggle() }
        } label: {
            HStack(spacing: Self.gutterGap) {
                // gutter 列：运行=spinner / 完成=✓ [Grok 图C：✓ 挂在 timeline 列上]
                Group {
                    if isSegmentRunning {
                        CometSpinner(size: 12, color: Self.stepInk)
                    } else {
                        checkGlyph
                    }
                }
                .frame(width: Self.gutterWidth, height: 14)

                Group {
                    if isSegmentRunning {
                        Text(AppLocalized("Thinking…"))
                    } else if let secs = settledSeconds {
                        Text(verbatim: "Thought for \(secs)s") // [pp 09-18]
                    } else {
                        Text(verbatim: "Thought")
                    }
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Self.stepInk)
                .shimmerText()

                Spacer(minLength: 0)
                AppSymbol("chevron.down", size: 16)
                    .foregroundStyle(Self.stepInk.opacity(0.7))
                    .rotationEffect(.degrees(thinkingExpanded ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var checkGlyph: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Self.checkGray)
    }

    /// Thinking source text with streaming tail fade [A6]: settled chars in
    /// ink, latest run light gray while streaming, all ink when finished.
    @ViewBuilder
    private func thinkingText(size: CGFloat, serif: Bool) -> some View {
        let merged = thinkingBlocks.map(\.content).filter { !$0.isEmpty }.joined(separator: "\n\n")
        if !merged.isEmpty {
            let text = merged
            let tailCount = min(24, text.count)
            let settled = String(text.dropLast(tailCount))
            let tail = String(text.suffix(tailCount))
            let font: Font = serif ? .system(size: size, design: .serif) : .system(size: size)
            (Text(
                (try? AttributedString(markdown: settled)) ?? AttributedString(settled)
            )
            .font(font)
            .foregroundStyle(Color(uiColor: .label)) // settled ink
            +
            Text(
                (try? AttributedString(markdown: tail)) ?? AttributedString(tail)
            )
            .font(font)
            .foregroundStyle(isSegmentRunning ? Color(uiColor: .lightGray) : Color(uiColor: .label)))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Timeline + cards [Grok 图C：项目间短竖线段，gutter 列挂 ✓/spinner]

    private var cardsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(toolBlocks, id: \.id) { block in
                    connectorRow
                    itemRow(for: block)
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .padding(.top, 6)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 项目间连接短线段 [实测：1.33pt 宽 #DCDCDC，居中于 gutter 列]。
    private var connectorRow: some View {
        HStack(spacing: 0) {
            Capsule()
                .fill(Self.connectorGray)
                .frame(width: 1.33, height: 5.5)
                .frame(width: Self.gutterWidth, alignment: .center)
            Spacer(minLength: 0)
        }
        .frame(height: 14)
    }

    @ViewBuilder
    private func itemRow(for block: AssistantBlock) -> some View {
        if let item = ToolEventRowFactory.item(for: block) {
            let inFlight: Bool = {
                switch block.toolStatus {
                case .streaming, .running: return true
                default: return false
                }
            }()
            // [pp 09-18] 完成且无输出 → ✓ 完成行；有输出/运行中 → 描边卡。
            let isStep = block.content.isEmpty && !inFlight
            HStack(alignment: .center, spacing: Self.gutterGap) {
                Group {
                    if isStep {
                        checkGlyph
                    } else {
                        Color.clear
                    }
                }
                .frame(width: Self.gutterWidth, height: 14)

                if isStep {
                    Text(displayTitle(for: block, fallback: item.title))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Self.stepInk)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 22, alignment: .center)
                } else {
                    ToolCardView(
                        title: displayTitle(for: block, fallback: item.title),
                        subtitle: item.detail.isEmpty ? nil : item.detail,
                        content: block.content,
                        iconName: item.iconName,
                        usesSFSymbol: item.usesSFSymbol,
                        isInFlight: inFlight
                    )
                    .padding(.leading, Self.cardIndent)
                }
            }
        }
    }
}

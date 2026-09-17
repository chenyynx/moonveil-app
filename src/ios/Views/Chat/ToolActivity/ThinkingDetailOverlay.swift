import SwiftUI

// MARK: - Thinking Detail Overlay (汇聚页, 自绘 sheet)
//
// [B1-B5, 报告§2.3] Self-drawn overlay: no background scale/blur, flat
// ~22% dimming [B1 复测实锤]; panel detents: half (top ≈45%±3) ⇄ tall
// (top ≈7%), drag-to-follow with snap [B2]; open ~0.30s spring, close
// 0.4-0.55s [B3]. Structure: grabber (47×4 #B4B4B4) → gray title →
// thinking row (state-following) → timeline → cards indented 8pt right of
// the 2pt #E3E3E1 line [B4].
// 已拍板交互：点思考行 = 展开该阶段思考原文（工具列表常显）[B5]。
// 待装机校准：弹起/关闭时长、detent 精确高度、dimming 精度。
// 待 pp 拍板（默认按标准实现 [R7]）：标题固定头 + 内容滚动（B10）；
// 常驻滚动指示条不做（B9 默认不做）。

struct ThinkingDetailOverlay: View {
    @ObservedObject var message: ChatMessage
    let segment: TurnActivitySegment
    let isActiveMessage: Bool
    @Binding var isPresented: Bool

    // MARK: Detents

    private enum Detent {
        case half   // top ≈45% of screen
        case tall   // top ≈7% of screen
    }

    @State private var detent: Detent = .half
    @State private var dragOffset: CGFloat = 0
    @State private var appeared = false
    @State private var thinkingExpanded = false

    private func topInset(_ h: CGFloat, _ d: Detent) -> CGFloat {
        switch d {
        case .half: return h * 0.45
        case .tall: return h * 0.07
        }
    }

    // MARK: Colors (B+ 色值表)

    private static let bg = Color(red: 0.953, green: 0.953, blue: 0.953)      // #F3F3F3
    private static let titleGray = Color(red: 0.431, green: 0.431, blue: 0.431) // #6E6E6E
    private static let thinkingGray = Color(red: 0.439, green: 0.439, blue: 0.439) // #707070
    private static let grabberGray = Color(red: 0.706, green: 0.706, blue: 0.706)  // #B4B4B4
    private static let timelineGray = Color(red: 0.890, green: 0.890, blue: 0.882) // #E3E3E1

    private var thinkingBlock: AssistantBlock? {
        segment.thinkingId.flatMap { id in message.blocks.first { $0.id == id } }
    }

    private var toolBlocks: [AssistantBlock] {
        segment.toolIds.compactMap { id in message.blocks.first { $0.id == id } }
    }

    private var isSegmentRunning: Bool { !segment.isDone }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // [B1] Flat dimming ~22%, no blur, no background scale.
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture { close(geo.size.height) }

                panel(in: geo.size)
                    .offset(y: appeared
                        ? topInset(geo.size.height, detent) + dragOffset
                        : geo.size.height)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) { // B3 弹起 ~0.30s
                appeared = true
            }
        }
    }

    // MARK: Panel

    private func panel(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            grabber
                .padding(.top, 8)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
                // Grabber area drives the detent drag.
                .contentShape(Rectangle())
                .gesture(detentDrag(in: size))

            titleRow
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            contentList
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: size.height, alignment: .top)
        .background(
            RoundedCorners(radius: 14, corners: [.topLeft, .topRight])
                .fill(Self.bg)
                .ignoresSafeArea()
                .shadow(color: .black.opacity(0.08), radius: 18, y: -4)
        )
    }

    private var grabber: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Self.grabberGray)
            .frame(width: 47, height: 4) // [B4]
    }

    private var titleRow: some View {
        Text(AppLocalized("Thinking"))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Self.titleGray)
            .frame(maxWidth: .infinity, alignment: .leading)
            .shimmerText() // A7 实锤：sheet 标题带慢扫光
    }

    // MARK: Content

    private var contentList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                thinkingRow
                if thinkingExpanded {
                    thinkingBody
                        .transition(.opacity)
                }
                timelineAndCards
                    .padding(.top, 14)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        // [B10 待拍板] 默认标准固定头：标题区不随内容滚动（R7）。
    }

    /// [B5] State-following row: running = comet spinner + "Thinking…";
    /// done = spinner stops + copy changes. Tap = toggle thinking source.
    private var thinkingRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { thinkingExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                if isSegmentRunning {
                    CometSpinner(size: 14, color: Self.thinkingGray)
                } else {
                    AppSymbol("sparkles", size: 14)
                        .foregroundStyle(Self.thinkingGray)
                }
                Text(AppLocalized(isSegmentRunning ? "Thinking…" : "Thinking"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Self.thinkingGray)
                    .shimmerText() // A7 实锤：「思考中……」同步扫光
                Spacer(minLength: 0)
                AppSymbol("chevron.down", size: 12)
                    .foregroundStyle(Self.thinkingGray.opacity(0.7))
                    .rotationEffect(.degrees(thinkingExpanded ? 0 : -90))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Thinking source text with streaming tail fade [A6]: settled chars in
    /// ink, latest run in light gray, all ink when finished.
    @ViewBuilder
    private var thinkingBody: some View {
        if let tb = thinkingBlock, !tb.content.isEmpty {
            let text = tb.content
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
            .padding(.top, 8)
            .padding(.leading, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Timeline line + tool cards (cards indent 8pt right of the line) [B4].
    @ViewBuilder
    private var timelineAndCards: some View {
        if !toolBlocks.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Self.timelineGray)
                    .frame(width: 2)
                    .padding(.top, 6)
                VStack(spacing: 10) {
                    ForEach(toolBlocks, id: \.id) { block in
                        card(for: block)
                    }
                }
            }
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

    // MARK: Gestures

    private func detentDrag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in
                dragOffset = max(-40, min(size.height * 0.5, v.translation.height))
            }
            .onEnded { v in
                let projected = topInset(size.height, detent) + v.predictedEndTranslation.height
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    detent = projected < size.height * 0.26 ? .tall : .half
                    dragOffset = 0
                }
            }
    }

    private func close(_ h: CGFloat) {
        withAnimation(.easeInOut(duration: 0.45)) { // B3 关闭 0.4-0.55s（装机复测）
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
            isPresented = false
        }
    }
}

// MARK: - Rounded corners helper (top-only radius)

struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath)
    }
}

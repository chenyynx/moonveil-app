import SwiftUI

// MARK: - Tool Activity Group View (new-skin chat slot, Grok-style)
//
// [A1-A8, 报告§八/§动画清单] One Grok-style activity stage, rendered whole
// inside its anchor block's cell. State machine (one-way, 铁律: 入口行永留):
//
//   running ── slot: ThinkingDotIcon + "Thinking · N秒" + event rows suffix(2)
//   done    ── entry row: "Thinking ›" (tap → 汇聚页, batch B N6)
//
// Timing is per-segment [A3]: no counter for the first ~0.7s, then "·1秒"
// stepping at 1 Hz from the segment start. The start instant lives in a
// view-layer cache keyed by anchor id (block model is untouched [H4]).

struct ToolActivityGroupView: View {
    @ObservedObject var message: ChatMessage
    let segment: TurnActivitySegment
    let isActiveMessage: Bool
    /// Batch C: wiring to the aggregation sheet (N6). Nil in mock contexts.
    var onOpenDetail: ((TurnActivitySegment) -> Void)?
    /// Batch C: shell in-flight stop passthrough (feature parity [H6]).
    var onStop: (() -> Void)?

    // MARK: State

    /// Segment start instant (view-layer cache survives cell rebuilds).
    @State private var startedAt: Date?

    private static var startCache: [UUID: Date] = [:]

    /// 入口行统一灰（图标/文字/chevron 同色）[Claude photo_25B6FFE9 实测核心墨色]。
    private static let headlineGray = Color(red: 0.478, green: 0.475, blue: 0.455)  // #7A7974

    /// Event window: chat shows the last three event lines [A4, pp 定 2026-09-17：最多排三个].
    private var eventBlocks: [AssistantBlock] {
        segment.toolIds.suffix(3).compactMap { id in
            message.blocks.first { $0.id == id }
        }
    }

    private var running: Bool { !segment.isDone }
    /// 模型实际开始思考 = 该段任一 thinking 块已有流式内容 [pp 09-18：
    /// 「Thinking」文字与计时在此刻出现/起算；此前只有点阵动画]。
    private var thinkingHasStarted: Bool {
        segment.thinkingIds.contains { id in
            message.blocks.first { $0.id == id }?.content.isEmpty == false
        }
    }
    /// 思考要点句 [pp 09-18 Claude 对照实锤：消息流入口行句子 = Summary 弹窗最后一条
    /// 思考叙述句（同源同数据）；Claude 的句子由其「摘要思考」层生成，moonveil 无此层，
    /// 以启发式对齐——取该段思考最后一个有意义句（≥8 字，跳过「好的。」类应答短句）。
    /// 仍取不到 → 该段最后一条 toolSummary（聚合页重点内容）→「思考结果」（entryRow 侧兜底）。
    private var thinkingHeadline: String? {
        let merged = segment.thinkingIds
            .compactMap { id in message.blocks.first { $0.id == id } }
            .map(\.content)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "#", with: "")
        let sentences = merged
            .components(separatedBy: CharacterSet(charactersIn: "。！？!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let last = sentences.reversed().first(where: { $0.count >= 8 }) else { return nil }
        return last.count > 80 ? String(last.prefix(80)) + "…" : last
    }

    /// 兜底摘要：该段最后一条工具的 LLM 语义摘要 [pp 09-18：取不到思考句时取聚合页重点]。
    private var lastToolSummary: String? {
        for id in segment.toolIds.reversed() {
            if let b = message.blocks.first(where: { $0.id == id }),
               let s = b.toolSummary, !s.isEmpty {
                return s
            }
        }
        return nil
    }

    var body: some View {
        Group {
            if running {
                runningSlot
                    .transition(.opacity)
            } else {
                entryRow
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: segment.isDone) // A1 ③ 交叉淡变 ~0.25s
        .onAppear {
            ensureStarted()
            withAnimation(.easeOut(duration: 0.34)) { dotsAppeared = true } // [pp 09-18] 点阵出现动画
        }
        .onChange(of: thinkingHasStarted) { started in
            // [pp 09-18] 首个思考内容到达那一刻起表 + 「Thinking」/计时出现动画
            // + 触屏反馈（与发送消息同款轻档；Claude app 无公开逆向，装机对比可调）。
            if started {
                withAnimation(.easeOut(duration: 0.34)) { textAppeared = true }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                ensureStarted()
            }
        }
        // [C2] Any segment change (event rows inserted / state flipped) can
        // change the cell height — reuse the existing thinking-toggle
        // invalidation channel (object = anchor block id).
        .onChange(of: segment) { _ in
            NotificationCenter.default.post(name: .thinkingBlockToggled, object: segment.anchorId)
        }
        // [pp 09-18] 错误冻结 / 重试续走：失败等待不计入思考秒数。
        .onChange(of: message.error) { err in
            if err != nil {
                ThinkingRunClock.pause(anchorId: segment.anchorId)
            } else {
                ThinkingRunClock.resume(anchorId: segment.anchorId)
            }
        }
        // [pp 09-18] 阶段完成 → 落定时长（供汇聚页「Thought for Ns」）。
        .onChange(of: segment.isDone) { done in
            if done {
                ThinkingRunClock.settle(anchorId: segment.anchorId, start: startedAt)
            }
        }
    }

    // MARK: Running slot

    private var runningSlot: some View {
        // [pp 09-17] 运行中的槽整体可点 → 汇聚页（实时进度），与完成态入口行
        // 同一 onOpenDetail 通道；stop 是嵌套内层 Button，点击优先级高于外层。
        Button {
            onOpenDetail?(segment)
        } label: {
            // [pp 09-18 Grok 对照 photo_CCA700E4] 行距对齐：Thinking→首事件 34.7pt /
            // 事件行间 36pt（Grok 实测）→ VStack 4→18（现值实测 19.7/22pt 偏紧）。
            VStack(alignment: .leading, spacing: 18) {
                // [pp 09-18 真机] 点阵与 Thinking 间距对齐入口行 clock→摘要（spacing 10），
                // 原 6 视觉仅 ~8.7pt 偏近。
                HStack(spacing: 10) {
                    ThinkingDotIcon(size: 18)
                        .opacity(dotsAppeared ? 1 : 0) // [pp 09-18] 两段式 D 出现动画
                        .offset(x: dotsAppeared ? 0 : -10)
                    // [pp 09-18 真机] 模型实际开始思考（首个思考内容到达）才出现
                    // 「Thinking」与计时；等待响应阶段只有点阵动画（启动槽同）。
                    Group {
                        Text(verbatim: "Thinking") // [pp 09-17] 固定英文（非本地化）
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.secondary) // Grok 对照：灰（非黑）
                            .sweepShimmer(base: Color.secondary) // [pp 09-18] Claude 同款扫光（cds-shimmer-text-shine 1:1）
                        elapsedCounter
                    }
                    .opacity(textAppeared ? 1 : 0)
                    .offset(x: textAppeared ? 0 : -10)
                    .accessibilityHidden(!textAppeared)
                    Spacer(minLength: 0)
                    if showsStop {
                        Button(action: { onStop?() }) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppLocalized("Stop"))
                    }
                }
                ForEach(eventBlocks, id: \.id) { block in
                    if let item = ToolEventRowFactory.item(for: block) {
                        ToolEventRow(
                            item: item,
                            accentColor: ToolActivityIcon.accentColor(for: block.kind),
                            status: block.toolStatus
                        )
                        // [pp 09-18 Grok 对照] 事件行图标列与点阵同列（Grok 三行图标
                        // 中心同 x≈27pt）——删 21pt 缩进；列对齐由 ToolEventRow 内部
                        // 18pt 图标 frame + spacing 10 保证。
                        .transition(.opacity.animation(.easeInOut(duration: 0.35))) // A4 淡入 0.3-0.4s
                    }
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(AppLocalized("Thinking"))
    }

    /// [A3] 计时文字（与启动槽共用同一组件，0.7s 规则 + 1Hz）。
    private var elapsedCounter: some View {
        ThinkingElapsedText(start: startedAt, anchorId: segment.anchorId)
    }

    /// Shell stop affordance only while a shell tool is in flight
    /// (mirrors classic ToolCapsuleView's stop visibility).
    private var showsStop: Bool {
        guard let onStop else { return false }
        return message.blocks.contains { block in
            guard segment.toolIds.contains(block.id) else { return false }
            guard case .shellTool = block.kind else { return false }
            if case .streaming = block.toolStatus { return true }
            if case .running = block.toolStatus { return true }
            return false
        }
    }

    // MARK: Entry row (永留)

    private var entryRow: some View {
        Button {
            onOpenDetail?(segment)
        } label: {
            HStack(spacing: 12) {
                // [pp 09-18 1:1 复刻 Claude photo_25B6FFE9 实测] ⏱16pt + 摘要 14pt regular
                // #7A7974 + chevron 紧跟文字后 21pt（未满行随文字收尾，非贴右缘）。
                ClaudeClockIcon(size: 16, color: Self.headlineGray) // [pp 09-18 二次校准] 缺口环+等大三点自绘时钟（photo_8E721157 拟合参数）
                Text(thinkingHeadline ?? lastToolSummary ?? AppLocalized("Thinking result")) // [pp 09-18] 思考要点句 → 聚合页重点（toolSummary）→ 思考结果
                    .font(.system(size: 14)) // [pp 09-18] 14pt regular（Claude 同档，轻质感；1:1 实测）
                    .foregroundStyle(Self.headlineGray)
                    .lineLimit(1)
                AppSymbol("chevron.right", size: 20) // [pp 09-17] Lucide 官方 chevron-right（视觉 ~6×11pt = Claude 同尺寸）
                    .foregroundStyle(Self.headlineGray)
                    .padding(.leading, 9) // 文字→chevron 总距 21pt [Claude 实测]
            }
            .frame(maxWidth: .infinity, alignment: .leading) // 热区全宽（Spacer 推挤改随文布局）
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(AppLocalized("Thinking"))
    }

    // MARK: 出现动画状态 [pp 09-18] 点阵/文字两段式 D 动画（左滑入+淡入 0.34s）
    @State private var dotsAppeared = false
    @State private var textAppeared = false

    // MARK: Helpers

    private func ensureStarted() {
        // [pp 09-18] 计时起点 = 思考实际开始（首个思考内容到达），不再从发送
        // 时刻接力（启动槽已不再 seed）——等待响应不计入思考时长。
        guard thinkingHasStarted else { return }
        if startedAt == nil {
            if let cached = Self.startCache[segment.anchorId] {
                startedAt = cached
            } else {
                let start = Date.now
                Self.startCache[segment.anchorId] = start
                startedAt = start
            }
        }
    }
}

// MARK: - Aggregation adapter + notifications [C1]

extension Notification.Name {
    /// New-skin entry row → 汇聚页 request. userInfo: ["segment":
    /// TurnActivitySegment, "messageId": UUID]. Received by AIChatView
    /// (single host for both local and remote sessions) [H5].
    static let toolActivityDetailRequested = Notification.Name("toolActivityDetailRequested")
}

extension TurnActivityAggregator {
    /// AssistantBlock stream → normalized aggregation input.
    /// isActiveThinking mirrors ThinkingBlockView's streaming flag
    /// (isActiveMessage && message.blocks.last?.id == block.id).
    static func adapt(_ blocks: [AssistantBlock], isActiveMessage: Bool) -> [TurnActivityBlock] {
        let lastId = blocks.last?.id
        return blocks.map { b in
            let kind: TurnActivityBlockKind
            switch b.kind {
            case .text: kind = .text
            case .thinking: kind = .thinking
            case .info: kind = .info
            case .shellTool, .fileReadTool, .fileWriteTool, .fileEditTool,
                 .browserTool, .readImageTool, .memoryTool:
                kind = .tool
            }
            var state: TurnActivityToolState?
            if kind == .tool {
                switch b.toolStatus {
                case .streaming, .running: state = .active
                case .success: state = .finished
                case .failed, .cancelled: state = .failed
                case .none: state = .unknown
                }
            }
            return TurnActivityBlock(
                id: b.id,
                kind: kind,
                toolState: state,
                isActiveThinking: kind == .thinking && b.id == lastId && isActiveMessage
            )
        }
    }
}

// MARK: - 新皮肤启动槽 + 计时衔接 [pp 09-17 装机反馈]

/// 计时衔接：发送 → 首个块 期间由 PendingThinkingIndicator 起表；消息内组视图
/// 接管同一段计时（消费起点），保证计数连续不重数、不跳回。
enum ThinkingRunClock {

    // [pp 09-18] 三态计时：运行 → 冻结（错误/完成）→ 续走（重试不跳回）。
    // 冻结/续走按 segment 锚点（anchorId 全局唯一）；错误等待不计入时长。
    private static var pauseAt: [UUID: Date] = [:]              // 暂停时刻（冻结显示基准）
    private static var pausedOffset: [UUID: TimeInterval] = [:] // 累计暂停时长（resume 平移）
    private static var frozen: [UUID: TimeInterval] = [:]       // 终值（完成/错误冻结后查询）

    /// 显示时长：终值优先；暂停中冻结在暂停时刻；否则实时。
    static func elapsed(anchorId: UUID, start: Date, now: Date) -> TimeInterval {
        if let f = frozen[anchorId] { return f }
        let effectiveNow = pauseAt[anchorId] ?? now
        return max(0, effectiveNow.timeIntervalSince(start) - (pausedOffset[anchorId] ?? 0))
    }

    /// 错误出现 → 冻结（仅从运行态进入一次）；重试前秒数停住不涨。
    static func pause(anchorId: UUID, now: Date = .now) {
        guard frozen[anchorId] == nil, pauseAt[anchorId] == nil else { return }
        pauseAt[anchorId] = now
    }

    /// 错误清除/重试 → 续走（暂停时长折入 offset，数字连续不跳回）。
    static func resume(anchorId: UUID, now: Date = .now) {
        guard frozen[anchorId] == nil, let pa = pauseAt[anchorId] else { return }
        pausedOffset[anchorId, default: 0] += now.timeIntervalSince(pa)
        pauseAt[anchorId] = nil
    }

    /// 阶段完成 → 落定终值（供汇聚页「Thought for Ns」）。
    static func settle(anchorId: UUID, start: Date?, now: Date = .now) {
        guard frozen[anchorId] == nil, let start else { return }
        frozen[anchorId] = elapsed(anchorId: anchorId, start: start, now: now)
        pauseAt[anchorId] = nil
    }

    /// 汇聚页查询：完成态时长（nil = 无数据，旧消息/未落定）。
    static func frozenValue(anchorId: UUID) -> TimeInterval? {
        frozen[anchorId]
    }
}

/// [A3 共用] 计时文字：前 ~0.7s 不显示，随后 "· Ns" 1Hz。
struct ThinkingElapsedText: View {
    let start: Date?
    /// [pp 09-18] 三态计时锚点（错误冻结 / 重试续走 / 完成落定）。
    var anchorId: UUID? = nil

    var body: some View {
        if let start {
            TimelineView(.periodic(from: start, by: 1)) { timeline in
                let elapsed: TimeInterval = anchorId
                    .map { ThinkingRunClock.elapsed(anchorId: $0, start: start, now: timeline.date) }
                    ?? timeline.date.timeIntervalSince(start)
                if elapsed >= 0.7 {
                    Text("• \(max(1, Int(ceil(elapsed - 0.7))))秒") // [帧01] Grok 格式
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }
}

/// [pp 09-17→09-18 改版] 新皮肤启动槽：发送后、模型响应前显示 —— 只有点阵
/// 动画 [pp 09-18：「Thinking」文字与计时在思考实际开始（运行槽侧）才出现，
/// 计时不再从发送起虚走]。只在 blocks 为空时被调用（否则组视图已承担指示）。
struct PendingThinkingIndicator: View {
    let messageId: UUID
    @State private var appeared = false // [pp 09-18] D 出现动画（与运行槽同款）

    var body: some View {
        HStack(spacing: 6) {
            ThinkingDotIcon(size: 18)
                .opacity(appeared ? 1 : 0)
                .offset(x: appeared ? 0 : -10)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .onAppear {
            withAnimation(.easeOut(duration: 0.34)) { appeared = true }
        }
    }
}


// MARK: - Claude Clock Icon (入口行) [pp 09-18 参数替换：photo_8E721157 拟合版]
//
// 形状来源：photo_8E721157.png 像素级拟合（参数坐标下降优化，软 IoU 0.951，
// 存档 shared/claude-clock-svg/fitted2.json）。24 画布归一（外缘=12，撑满）：
// 环中径 10.6438 / 线宽 2.7123；缺口弧 264.7046°→527.6624°（顺时针跨 0°，圆头）；
// 三点等大 φ2.9256 @ 190.356°/215.060°/239.836°（R 10.2809）；指针折线
// (11.2483,6.9451)→(11.4659,12.4278)→(16.0784,14.3009)。颜色/尺寸与文字同灰。
// 覆盖 photo_25B6FFE9 初版参数（递进三点/66°缺口/线宽2.0）——以新版拟合为准 [pp 09-18 拍板]。

struct ClaudeClockIcon: View {
    var size: CGFloat = 16
    var color: Color

    var body: some View {
        Canvas { ctx, sz in
            let u = sz.width / 24 // 设计画布 24
            let c = CGPoint(x: 12 * u, y: 12 * u)
            let lw = 2.7123 * u

            // 缺口圆环：264.7046°→527.6624°（=167.6624°+360）顺时针，缺口左上 [拟合]
            var arc = Path()
            arc.addArc(center: c, radius: 10.6438 * u,
                       startAngle: .degrees(264.7046), endAngle: .degrees(527.6624),
                       clockwise: true)
            ctx.stroke(arc, with: .color(color),
                       style: StrokeStyle(lineWidth: lw, lineCap: .round))

            // 缺口区三点：等大 φ2.9256 @ 190.356/215.060/239.836° [拟合]
            let dots: [Double] = [190.356, 215.060, 239.836]
            for deg in dots {
                let rad = deg * Double.pi / 180
                let px = c.x + CGFloat(cos(rad)) * 10.2809 * u
                let py = c.y + CGFloat(sin(rad)) * 10.2809 * u
                let d = CGFloat(2.9256) * u
                ctx.fill(Path(ellipseIn: CGRect(x: px - d / 2, y: py - d / 2, width: d, height: d)),
                         with: .color(color))
            }

            // 指针：竖针+右下臂折线 [拟合]（与环同宽，拟合差 0.6% 噪声内）
            var hands = Path()
            hands.move(to: CGPoint(x: 11.2483 * u, y: 6.9451 * u))
            hands.addLine(to: CGPoint(x: 11.4659 * u, y: 12.4278 * u))
            hands.addLine(to: CGPoint(x: 16.0784 * u, y: 14.3009 * u))
            ctx.stroke(hands, with: .color(color),
                       style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

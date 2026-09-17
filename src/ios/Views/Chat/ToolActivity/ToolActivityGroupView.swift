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

    /// Event window: chat shows the last three event lines [A4, pp 定 2026-09-17：最多排三个].
    private var eventBlocks: [AssistantBlock] {
        segment.toolIds.suffix(3).compactMap { id in
            message.blocks.first { $0.id == id }
        }
    }

    private var running: Bool { !segment.isDone }

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
        .onAppear { ensureStarted() }
        // [C2] Any segment change (event rows inserted / state flipped) can
        // change the cell height — reuse the existing thinking-toggle
        // invalidation channel (object = anchor block id).
        .onChange(of: segment) { _ in
            NotificationCenter.default.post(name: .thinkingBlockToggled, object: segment.anchorId)
        }
    }

    // MARK: Running slot

    private var runningSlot: some View {
        // [pp 09-17] 运行中的槽整体可点 → 汇聚页（实时进度），与完成态入口行
        // 同一 onOpenDetail 通道；stop 是嵌套内层 Button，点击优先级高于外层。
        Button {
            onOpenDetail?(segment)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ThinkingDotIcon(size: 18)
                    Text(verbatim: "Thinking") // [pp 09-17] 固定英文（非本地化）
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.secondary) // Grok 对照：灰（非黑）
                    elapsedCounter
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
                        .padding(.leading, 21)
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
        ThinkingElapsedText(start: startedAt)
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
            HStack(spacing: 4) { // [帧06] Grok 文字-箭头间距 ≈10pt
                // [pp 09-17] 入口行无图标（Grok 帧证据 06_entry_row：只有
                // 文字+chevron）；"thinking 图标"仅运行态点阵显示。
                Text(AppLocalized("Thinking result")) // [pp 09-17] 完成态=思考结果
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.secondary)
                AppSymbol("chevron.right", size: 20) // [pp 09-17] Lucide 官方 chevron-right；尺寸对齐 Grok 实测（视觉 5×10pt）
                    .foregroundStyle(Color.secondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(AppLocalized("Thinking"))
    }

    // MARK: Helpers

    private func ensureStarted() {
        if startedAt == nil {
            if let cached = Self.startCache[segment.anchorId] {
                startedAt = cached
            } else if let pending = ThinkingRunClock.takeover(message.id) {
                // [pp 09-17] 接管启动槽的计时起点 → 计数从发送起连续。
                Self.startCache[segment.anchorId] = pending
                startedAt = pending
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
    private static var pending: [UUID: Date] = [:]

    /// 启动槽调用：取已存在起点或写入 now（cell 复用重建时不重数）。
    static func seed(_ messageId: UUID) -> Date {
        if let d = pending[messageId] { return d }
        let d = Date()
        pending[messageId] = d
        return d
    }

    /// 组视图接管调用：消费该起点（一次性）。
    static func takeover(_ messageId: UUID) -> Date? {
        pending.removeValue(forKey: messageId)
    }
}

/// [A3 共用] 计时文字：前 ~0.7s 不显示，随后 "· Ns" 1Hz。
struct ThinkingElapsedText: View {
    let start: Date?

    var body: some View {
        if let start {
            TimelineView(.periodic(from: start, by: 1)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(start)
                if elapsed >= 0.7 {
                    Text("• \(max(1, Int(ceil(elapsed - 0.7))))秒") // [帧01] Grok 格式
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }
}

/// [pp 09-17] 新皮肤启动槽：发送后、首个内容块到达前显示 —— 点阵图标 +
/// 「Thinking」+ 计时（从发送起）。替代旧版「正在思考…」；块到达后由消息内
/// 组视图接管续计。只在 blocks 为空时被调用（否则组视图已承担指示）。
struct PendingThinkingIndicator: View {
    let messageId: UUID
    @State private var start: Date?

    var body: some View {
        HStack(spacing: 6) {
            ThinkingDotIcon(size: 18)
            Text(verbatim: "Thinking") // [pp 09-17] 固定英文
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.secondary)
            ThinkingElapsedText(start: start)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .onAppear {
            if start == nil { start = ThinkingRunClock.seed(messageId) }
        }
    }
}

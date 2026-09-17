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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ThinkingDotIcon(size: 15)
                Text(AppLocalized("Thinking"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(uiColor: .label))
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
    }

    /// [A3] No counter for the first ~0.7s, then "· Ns" at 1 Hz from start.
    @ViewBuilder
    private var elapsedCounter: some View {
        if let start = startedAt {
            TimelineView(.periodic(from: start, by: 1)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(start)
                Group {
                    if elapsed >= 0.7 {
                        Text("· \(max(1, Int(ceil(elapsed - 0.7))))s")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
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
            HStack(spacing: 6) {
                AppSymbol("sparkles", size: 14) // thinking = sparkles [SELECTION.md]
                    .foregroundStyle(Color.secondary)
                Text(AppLocalized("Thinking"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.secondary)
                AppSymbol("chevron.right", size: 12)
                    .foregroundStyle(Color.secondary.opacity(0.7))
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
            let cached = Self.startCache[segment.anchorId]
            let start = cached ?? Date.now
            Self.startCache[segment.anchorId] = start
            startedAt = start
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

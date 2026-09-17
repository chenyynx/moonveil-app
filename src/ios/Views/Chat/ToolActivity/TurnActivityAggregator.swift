import Foundation

// MARK: - Turn Activity Aggregator (Grok-style stage segmentation)
//
// [tool-render-replication N2 2026-09-17] Pure-logic aggregator: converts a
// message's normalized block stream into Grok-style activity segments.
//
// 段完成语义（pp 2026-09-17 装机拍板）：**回复了正文才算完成一个阶段** ——
// 工具全部终态但正文还没来时，槽继续转（Thinking·N秒 + 计时继续），
// 正文块出现（或新思考段开始接替 / 消息整体终态）才落定为入口行。
//
// Inputs are normalized value snapshots (not AssistantBlock) so this file
// compiles and unit-tests off-iOS; the UI layer adapts AssistantBlock →
// TurnActivityBlock. Zero new event sources [铁律④].

/// Normalized block kind for aggregation.
enum TurnActivityBlockKind: Equatable {
    case text
    case thinking
    case tool
    case info
}

/// Normalized tool liveness. `active` covers streaming + running; `finished`
/// is success; `failed` covers failed + cancelled.
enum TurnActivityToolState: Equatable {
    case active
    case finished
    case failed
    case unknown
}

struct TurnActivityBlock: Equatable {
    let id: UUID
    let kind: TurnActivityBlockKind
    /// Non-nil for `.tool` blocks.
    let toolState: TurnActivityToolState?
    /// True while this thinking block is the live-streaming one
    /// (isActiveMessage && message.blocks.last?.id == id).
    let isActiveThinking: Bool
}

// MARK: - Segment model

/// One Grok-style activity stage: a thinking block plus the run of tool
/// calls that immediately follows it. Text/info blocks close the run
/// (they render normally between segments).
struct TurnActivitySegment: Equatable {
    /// First block of the segment — its cell renders the whole group view.
    let anchorId: UUID
    /// The segment's thinking block (nil for a tool run with no thinking lead).
    let thinkingId: UUID?
    let toolIds: [UUID]
    /// The thinking block is live-streaming right now.
    let isThinkingActive: Bool
    /// Any tool in the segment is in flight right now.
    let isToolActive: Bool
    /// Segment closed by a text/info block (正文已回复 → 阶段完成) [pp 09-17].
    let closedByContent: Bool
    /// Segment closed by a new thinking block taking over (新阶段接替).
    let closedByNewSegment: Bool
    /// The owning message is still processing (streaming).
    let isMessageActive: Bool

    /// 阶段完成 = 正文已回复 / 被新阶段接替 / 消息整体终态（含停止）。
    /// 活跃消息里块虽终态但正文未到 → 仍视为运行中（槽继续转）[pp 09-17]。
    var isDone: Bool {
        if closedByContent || closedByNewSegment { return true }
        return !isMessageActive
    }
}

// MARK: - Aggregator

enum TurnActivityAggregator {
    /// Split a message's normalized block list into Grok-style segments.
    /// Rules [E 区; pp 拍板]:
    ///   - a thinking block starts a new segment and anchors it;
    ///   - consecutive tool blocks join the open segment;
    ///   - text/info blocks close the open segment (正文 = 阶段终点);
    ///   - a tool run with no open segment forms a thinking-less segment
    ///     (anchor = its first tool block);
    ///   - a thinking block with no following tools is still a segment.
    static func segments(from blocks: [TurnActivityBlock], isMessageActive: Bool) -> [TurnActivitySegment] {
        var result: [TurnActivitySegment] = []
        var anchor: UUID?
        var thinking: (id: UUID, active: Bool)?
        var tools: [UUID] = []
        var toolActive = false

        func flush(closedByContent: Bool, closedByNewSegment: Bool) {
            if let a = anchor {
                result.append(TurnActivitySegment(
                    anchorId: a,
                    thinkingId: thinking?.id,
                    toolIds: tools,
                    isThinkingActive: thinking?.active ?? false,
                    isToolActive: toolActive,
                    closedByContent: closedByContent,
                    closedByNewSegment: closedByNewSegment,
                    isMessageActive: isMessageActive
                ))
            }
            anchor = nil
            thinking = nil
            tools = []
            toolActive = false
        }

        for b in blocks {
            switch b.kind {
            case .thinking:
                flush(closedByContent: false, closedByNewSegment: anchor != nil)
                anchor = b.id
                thinking = (b.id, b.isActiveThinking)
            case .tool:
                if anchor == nil {
                    anchor = b.id
                }
                tools.append(b.id)
                if b.toolState == .active { toolActive = true }
            case .text, .info:
                flush(closedByContent: true, closedByNewSegment: false)
            }
        }
        flush(closedByContent: false, closedByNewSegment: false) // end of stream
        return result
    }

    /// Convenience: which segment (if any) does this block belong to, and is
    /// it the anchor? Used by the render dispatch (M1).
    static func role(of blockId: UUID, in segments: [TurnActivitySegment])
        -> (segment: TurnActivitySegment, isAnchor: Bool)? {
        for seg in segments {
            if seg.anchorId == blockId { return (seg, true) }
            if seg.thinkingId == blockId || seg.toolIds.contains(blockId) {
                return (seg, false)
            }
        }
        return nil
    }
}

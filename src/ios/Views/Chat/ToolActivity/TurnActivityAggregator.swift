import Foundation

// MARK: - Turn Activity Aggregator (Grok-style stage segmentation)
//
// [tool-render-replication N2 2026-09-17] Pure-logic aggregator: converts a
// message's normalized block stream into Grok-style activity segments.
//
// 分段语义（pp 2026-09-17 二次澄清）：**正文才是分段点** ——
//   一个阶段的定义 = 直到（且包含）下一段正文之前的全部 thinking + 工具
//   循环。中间连续出现的多个 thinking 块【不】开新段，全部并入当前开放段；
//   直到 text/info 出现才关闭该段（回复了正文 = 这一阶段结束）。
//   活跃消息里正文没来 → 槽继续转（isDone=false）。
// 这样聊天内不会出现"连续多个入口行"（pp 装机反馈 photo_436F4A9B）。
//
// Inputs are normalized value snapshots (not AssistantBlock); the UI layer
// adapts AssistantBlock → TurnActivityBlock. Zero new event sources [铁律④].

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

/// One activity stage: every thinking block and tool run between two content
/// blocks (正文为界). Rendered whole inside the anchor cell.
struct TurnActivitySegment: Equatable {
    /// First block of the segment — its cell renders the whole group view.
    let anchorId: UUID
    /// All thinking blocks in the segment, in order (may be several — a stage
    /// absorbs every thinking/tool loop until the next reply content).
    let thinkingIds: [UUID]
    let toolIds: [UUID]
    /// Any thinking block in the segment is live-streaming right now.
    let isThinkingActive: Bool
    /// Any tool in the segment is in flight right now.
    let isToolActive: Bool
    /// Segment closed by a text/info block (正文已回复 → 阶段完成) [pp 09-17].
    let closedByContent: Bool
    /// The owning message is still processing (streaming).
    let isMessageActive: Bool

    /// 阶段完成 = 正文已回复 / 消息整体终态（含停止）。
    /// 活跃消息里正文未到 → 仍视为运行中（槽继续转）[pp 09-17]。
    var isDone: Bool {
        if closedByContent { return true }
        return !isMessageActive
    }
}

// MARK: - Aggregator

enum TurnActivityAggregator {
    /// Split a message's normalized block list into segments.
    /// Rules [pp 2026-09-17 二次拍板：正文才是分段点]:
    ///   - thinking / tool blocks join the OPEN segment (a thinking with no
    ///     open segment anchors a new one; a tool run without a thinking lead
    ///     also anchors one);
    ///   - text/info blocks CLOSE the open segment — 回复了正文 = 一阶段结束;
    ///   - no open segment → nothing (pure content).
    static func segments(from blocks: [TurnActivityBlock], isMessageActive: Bool) -> [TurnActivitySegment] {
        var result: [TurnActivitySegment] = []
        var anchor: UUID?
        var thinkingIds: [UUID] = []
        var thinkingActive = false
        var tools: [UUID] = []
        var toolActive = false

        func flush(closedByContent: Bool) {
            if let a = anchor {
                result.append(TurnActivitySegment(
                    anchorId: a,
                    thinkingIds: thinkingIds,
                    toolIds: tools,
                    isThinkingActive: thinkingActive,
                    isToolActive: toolActive,
                    closedByContent: closedByContent,
                    isMessageActive: isMessageActive
                ))
            }
            anchor = nil
            thinkingIds = []
            thinkingActive = false
            tools = []
            toolActive = false
        }

        for b in blocks {
            switch b.kind {
            case .thinking:
                if anchor == nil { anchor = b.id }
                thinkingIds.append(b.id)
                if b.isActiveThinking { thinkingActive = true }
            case .tool:
                if anchor == nil { anchor = b.id }
                tools.append(b.id)
                if b.toolState == .active { toolActive = true }
            case .text, .info:
                flush(closedByContent: true)
            }
        }
        flush(closedByContent: false) // end of stream
        return result
    }

    /// Convenience: which segment (if any) does this block belong to, and is
    /// it the anchor? Used by the render dispatch (M1).
    static func role(of blockId: UUID, in segments: [TurnActivitySegment])
        -> (segment: TurnActivitySegment, isAnchor: Bool)? {
        for seg in segments {
            if seg.anchorId == blockId { return (seg, true) }
            if seg.thinkingIds.contains(blockId) || seg.toolIds.contains(blockId) {
                return (seg, false)
            }
        }
        return nil
    }
}

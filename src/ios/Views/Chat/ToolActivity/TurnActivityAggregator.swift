import Foundation

// MARK: - Turn Activity Aggregator (Grok-style stage segmentation)
//
// [tool-render-replication N2 2026-09-17] Pure-logic aggregator: converts a
// message's normalized block stream into Grok-style activity segments
// (报告§八/§十一, E 区映射, pp 拍板「按思考块分段」「阶段级汇聚」).
//
// Inputs are normalized value snapshots (not AssistantBlock) so this file
// compiles and unit-tests off-iOS; the UI layer adapts AssistantBlock →
// TurnActivityBlock. Zero new event sources — all state derives from the
// existing block kinds / ToolBlockStatus [铁律④].

/// Normalized block kind for aggregation.
enum TurnActivityBlockKind: Equatable {
    case text
    case thinking
    case tool
    case info
}

/// Normalized tool liveness. `active` covers streaming + running (the two
/// in-flight states, per AssistantBlockView's existing isToolRunning gate);
/// `finished` is success; `failed` covers failed + cancelled.
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
    /// (isActiveMessage && message.blocks.last?.id == id — the same rule
    /// ThinkingBlockView uses for its streaming flag).
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
    /// Segment finished: nothing streaming/running within it.
    var isDone: Bool { !isThinkingActive && !isToolActive }
}

// MARK: - Aggregator

enum TurnActivityAggregator {
    /// Split a message's normalized block list into Grok-style segments.
    /// Rules [E 区; pp 拍板]:
    ///   - a thinking block starts a new segment and anchors it;
    ///   - consecutive tool blocks join the open segment;
    ///   - text/info blocks close the open segment (render order stays
    ///     monotonic: group → text → next group);
    ///   - a tool run with no open segment forms a thinking-less segment
    ///     (anchor = its first tool block);
    ///   - a thinking block with no following tools is still a segment
    ///     (its entry row must remain tappable).
    static func segments(from blocks: [TurnActivityBlock]) -> [TurnActivitySegment] {
        var result: [TurnActivitySegment] = []
        var anchor: UUID?
        var thinking: (id: UUID, active: Bool)?
        var tools: [UUID] = []
        var toolActive = false

        func flush() {
            if let a = anchor {
                result.append(TurnActivitySegment(
                    anchorId: a,
                    thinkingId: thinking?.id,
                    toolIds: tools,
                    isThinkingActive: thinking?.active ?? false,
                    isToolActive: toolActive
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
                flush()
                anchor = b.id
                thinking = (b.id, b.isActiveThinking)
            case .tool:
                if anchor == nil {
                    anchor = b.id
                }
                tools.append(b.id)
                if b.toolState == .active { toolActive = true }
            case .text, .info:
                flush()
            }
        }
        flush()
        return result
    }

    /// Convenience: which segment (if any) does this block belong to, and is
    /// it the anchor? Used by the render dispatch (M1): anchors render the
    /// whole group; non-anchor segment members render nothing (the group
    /// view is drawn once, in the anchor's cell).
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

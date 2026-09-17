import SwiftUI

// MARK: - Tool Event Row (Grok-style in-slot event line)
//
// [A4/A5, 报告§2.2/§九] Two visual classes:
//   - file class: black semibold title + mono path pill (#F2F2F4 capsule, 13pt)
//   - command class: gray #7C7C81 title + sans gray detail text
// Titles reuse the existing ChatModels fallback strings verbatim (文案映射原则:
// moonveil 的语义, 不搬 Grok 字面). Icons are Lucide assets via AppSymbol
// [SELECTION.md]; colors follow the existing per-tool accent mapping [铁律②].

struct ToolEventRowItem: Equatable {
    let id: UUID
    let iconName: String
    /// memory 特例：直接渲染 SF Symbol（pp 拍板保持老版）。
    var usesSFSymbol: Bool = false
    let title: String
    let detail: String
    let isFileClass: Bool
    /// True while the underlying block is streaming/running (icon shows
    /// first, detail fills in later — 报告§八-⑥).
    let isInFlight: Bool
}

enum ToolEventRowFactory {
    /// AssistantBlock → event row item. Copy comes from the block's own
    /// description/summary; no Grok strings are introduced here.
    static func item(for block: AssistantBlock) -> ToolEventRowItem? {
        let inFlight: Bool
        switch block.toolStatus {
        case .streaming, .running: inFlight = true
        default: inFlight = false
        }

        switch block.kind {
        case .shellTool:
            let detail = block.toolSummary?.isEmpty == false
                ? block.toolSummary!
                : block.toolDescription
            return ToolEventRowItem(
                id: block.id, iconName: "terminal",
                title: AppLocalized("Shell command"), detail: detail,
                isFileClass: false, isInFlight: inFlight)
        case .fileReadTool(let path):
            return ToolEventRowItem(
                id: block.id, iconName: "doc.text",
                title: AppLocalized("Read file"), detail: path,
                isFileClass: true, isInFlight: inFlight)
        case .fileWriteTool(let path):
            return ToolEventRowItem(
                id: block.id, iconName: "doc.plus" /* mapped to aa-FilePlus */,
                title: AppLocalized("Write file"), detail: path,
                isFileClass: true, isInFlight: inFlight)
        case .fileEditTool(let path):
            return ToolEventRowItem(
                id: block.id, iconName: "square.and.pencil" /* aa-SquarePen below */,
                title: AppLocalized("Edit file"), detail: path,
                isFileClass: true, isInFlight: inFlight)
        case .browserTool:
            let detail = block.toolSummary?.isEmpty == false
                ? block.toolSummary!
                : block.toolDescription
            return ToolEventRowItem(
                id: block.id, iconName: "globe",
                title: AppLocalized("Browser action"), detail: detail,
                isFileClass: false, isInFlight: inFlight)
        case .readImageTool(let path):
            return ToolEventRowItem(
                id: block.id, iconName: "photo" /* aa-Image below */,
                title: AppLocalized("Read image"), detail: path,
                isFileClass: true, isInFlight: inFlight)
        case .memoryTool(let action):
            return ToolEventRowItem(
                id: block.id, iconName: "brain.head.profile",
                usesSFSymbol: true, // pp 拍板：记忆保持 SF 老版，不走 Lucide
                title: action.isEmpty ? AppLocalized("Memory") : action,
                detail: "", isFileClass: false, isInFlight: inFlight)
        case .text, .thinking, .info:
            return nil
        }
    }
}

/// One event line inside the activity slot. 状态色沿用既有逻辑：运行中=
/// 工具 accentColor，完成=green，失败=red，取消=yellow（ToolCapsuleView
/// iconColor 同规则，状态色逻辑不动 [SELECTION.md 落地检查]）。
struct ToolEventRow: View {
    let item: ToolEventRowItem
    let accentColor: Color
    var status: ToolBlockStatus?

    var body: some View {
        // [pp 09-18 真机 photo_E2402C58] .firstTextBaseline 使 Lucide 画布图标视觉中心
        // 比文字高 ~2.8pt（图标无基线概念）→ 垂直居中对齐。
        HStack(alignment: .center, spacing: 6) {
            if item.usesSFSymbol {
                Image(systemName: item.iconName)
                    .font(.system(size: 15))
                    .foregroundStyle(iconColor)
            } else {
                AppSymbol(item.iconName, size: 16) // [Grok 对照] 图标与标题等高偏大
                    .foregroundStyle(iconColor)
            }
            if item.isFileClass {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .label))
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color(uiColor: .label))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(red: 0.949, green: 0.949, blue: 0.957))) // #F2F2F4
                }
            } else {
                Text(item.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.486, green: 0.486, blue: 0.506)) // #7C7C81
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 0.486, green: 0.486, blue: 0.506))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var iconColor: Color {
        switch status {
        case .success: return .green
        case .failed: return .red
        case .cancelled: return .yellow
        default: return accentColor
        }
    }
}

// MARK: - Icon mapping (Lucide assets, one place for the new skin)

/// New-skin tool icon names (AppSymbol asset keys). memory keeps its SF
/// symbol `brain.head.profile` (pp 拍板 2026-09-17: 不换 Lucide).
enum ToolActivityIcon {
    /// Per-tool accent color — mirrors the classic dispatch in
    /// AssistantBlockView.body (green/cyan/blue/orange/blue/purple/pink).
    static func accentColor(for kind: AssistantBlockKind) -> Color {
        switch kind {
        case .shellTool: return .green
        case .fileReadTool: return .cyan
        case .fileWriteTool: return .blue
        case .fileEditTool: return .orange
        case .browserTool: return .blue
        case .readImageTool: return .purple
        case .memoryTool: return .pink
        case .text, .thinking, .info: return .gray
        }
    }
}

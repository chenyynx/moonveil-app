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

    /// [pp 09-18 暗色适配] 路径胶囊底：浅 #F2F2F4（原值）/ 深 #2C2C2E。
    /// 胶囊内文字用 `.label`（暗色解析成白），写死浅底 = 白底白字、路径看不见。
    static let pathCapsuleBg = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255, alpha: 1)
        : UIColor(red: 0.949, green: 0.949, blue: 0.957, alpha: 1) })
    /// [pp 09-18 暗色适配] command 类标题/详情灰：浅 #7C7C81（原值）/ 深 #A0A0A0。
    static let commandGray = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xA0 / 255, green: 0xA0 / 255, blue: 0xA0 / 255, alpha: 1)
        : UIColor(red: 0.486, green: 0.486, blue: 0.506, alpha: 1) })

    var body: some View {
        // [pp 09-18 真机 photo_E2402C58] .firstTextBaseline 使 Lucide 画布图标视觉中心
        // 比文字高 ~2.8pt（图标无基线概念）→ 垂直居中对齐。
        // [pp 09-18 Grok 对照 photo_CCA700E4] 图标列 frame 18（与点阵同宽）+ spacing 10
        // → 事件行图标/文字列与 Thinking 行完全同列（Grok 实测：图标中心 ~27pt、文字 ~47pt）。
        HStack(alignment: .center, spacing: 10) {
            if item.usesSFSymbol {
                Image(systemName: item.iconName)
                    .font(.system(size: 15))
                    .foregroundStyle(iconColor)
                    .frame(width: 18)
            } else {
                AppSymbol(item.iconName, size: 16) // [Grok 对照] 图标与标题等高偏大
                    .foregroundStyle(iconColor)
                    .frame(width: 18)
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
                        // [pp 09-18 暗色适配] 原写死 #F2F2F4：暗色下浅底 + 上面
                        // `.label` 文字变白 = 白底白字、路径不可见 → 改动态双档
                        // （浅 #F2F2F4 / 深 #2C2C2E，系统 group 色同档）。
                        .background(Capsule().fill(Self.pathCapsuleBg))
                }
            } else {
                Text(item.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Self.commandGray)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Self.commandGray)
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

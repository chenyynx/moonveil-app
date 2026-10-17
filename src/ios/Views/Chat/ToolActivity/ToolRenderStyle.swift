import SwiftUI
import Foundation

// MARK: - Tool Render Style (skin system)
//
// [tool-render-replication 2026-09-17] Introduced by the Grok-style tool
// activity replication work (pp approved 2026-09-17).
//   - `classic`: the pre-existing rendering path (AssistantBlockView's
//     original switch). Frozen — no visual or behavioral changes.
//   - `new`: the replicated activity-slot / aggregation-sheet skin
//     (Views/Chat/ToolActivity/).
// Default = `new` (pp 2026-09-17). Applies to BOTH local and remote chat
// (shared render layer reads the same key) [H5].
// Data layer is untouched — both skins render the same AssistantBlock
// stream [H4].

enum ToolRenderStyle: Int, CaseIterable {
    case classic = 0
    case new = 1

    /// Default when the key was never written. NOTE: must be `.new`; reads
    /// go through ToolRenderStyleStore which tolerates a missing key
    /// (UserDefaults.integer would silently return 0 == classic).
    static let fallback: ToolRenderStyle = .new
}

extension Notification.Name {
    /// Posted after the tool render style changes so the message list can
    /// invalidate height caches and rebuild visible cells [H3].
    static let toolRenderStyleChanged = Notification.Name("toolRenderStyleChanged")
    /// TOOLSPACING-1: posted when the tool row spacing setting changes.
    static let toolRowSpacingChanged = Notification.Name("toolRowSpacingChanged")
    /// TOOLSPACING-2: posted when the block spacing setting changes.
    static let blockSpacingChanged = Notification.Name("blockSpacingChanged")
}

/// UserDefaults bridge for `ToolRenderStyle`.
enum ToolRenderStyleStore {
    static let userDefaultsKey = "toolRenderStyle"

    static var current: ToolRenderStyle {
        let raw = UserDefaults.standard.object(forKey: userDefaultsKey) as? Int
        return ToolRenderStyle(rawValue: raw ?? ToolRenderStyle.fallback.rawValue) ?? .fallback
    }

    /// Persists the style and posts `.toolRenderStyleChanged`.
    static func set(_ style: ToolRenderStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: userDefaultsKey)
        NotificationCenter.default.post(name: .toolRenderStyleChanged, object: nil)
    }
}

// MARK: - Glass toolbar switch
//
// [H7 2026-09-17] Master switch for the floating glass toolbar above the
// composer (FloatingToolBar). Two-version universal: independent of
// ToolRenderStyle, applies to classic and new skins alike.

enum GlassToolBarStore {
    static let userDefaultsKey = "floatingToolBarEnabled"
    static let defaultEnabled = true

    static var isEnabled: Bool {
        let raw = UserDefaults.standard.object(forKey: userDefaultsKey) as? Bool
        return raw ?? defaultEnabled
    }
}

// MARK: - TOOLSPACING-2

/// User-adjustable tool-related spacing (new skin only; classic keeps its frozen values).
/// Reads @AppStorage-backed keys with explicit defaults (key-absent check so the
/// default is authoritative until the user first moves a slider).
enum ToolSpacingSettings {
    static let rowSpacingKey = "toolRowSpacing"
    static let blockSpacingKey = "blockSpacing"
    static let rowSpacingDefault: Double = 18
    static let blockSpacingDefault: Double = 8

    static func rowSpacing() -> CGFloat {
        let d = UserDefaults.standard
        return CGFloat(d.object(forKey: rowSpacingKey) != nil ? d.double(forKey: rowSpacingKey) : rowSpacingDefault)
    }

    static func blockSpacing() -> CGFloat {
        let d = UserDefaults.standard
        return CGFloat(d.object(forKey: blockSpacingKey) != nil ? d.double(forKey: blockSpacingKey) : blockSpacingDefault)
    }
}

// MARK: - Tool Capsule Skin (classic 皮肤胶囊改版)
//
// [tool-capsule-skin 2026-10-17] pp 指定：本地聊天页旧版（classic 皮肤）的
// 工具调用 / 思考块，改用参照文件 ToolCallCapsule.swift 的材质、尺寸与配色。
//   - 材质（flat）：不透明基底 + tint @16% 填充 + 0.5pt 同色 hairline
//     （浅 25% / 深 24.5%）。参照的投影（black 9.3%、blur 24、y+4）未采用：
//     V3 列表 cell 的 contentView.clipsToBounds = true 会把超出胶囊边界的
//     shadow 整块裁掉，只剩左右两条侧光，比没有更脏。
//   - 尺寸：35.5pt（命令行行 33.3pt）、水平内边距 16、图标 12pt medium、
//     标题 11pt semibold、次要文字 11pt regular。
//   - 配色：工具 = systemGreen；思考 = 浅 #0071F5 / 深 #0A84FF。
//   - 间距：相邻胶囊 6pt（MessageListLayout 按「两块都是胶囊」成对应用）。
// 只作用于 classic 皮肤；new 皮肤（Grok 活动槽）一行不动。

enum ToolCapsuleSkin {
    static let standardHeight: CGFloat = 35.5
    static let compactHeight: CGFloat = 33.3
    static let horizontalPadding: CGFloat = 16
    static let rowSpacing: CGFloat = 6
    static let fillOpacity: Double = 0.16
    static let expandedCornerRadius: CGFloat = 18
    static let expandedMaxBodyHeight: CGFloat = 236

    static let titleFont = Font.system(size: 11, weight: .semibold)
    static let detailFont = Font.system(size: 11)
    static let iconFont = Font.system(size: 12, weight: .medium)

    /// 工具统一绿色（pp 2026-10-17：「工具是绿色的」）。
    static let green = Color(UIColor.systemGreen)

    /// 思考蓝：参照实测 浅 #0071F5 / 深 #0A84FF。
    static let blue = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 10 / 255, green: 132 / 255, blue: 255 / 255, alpha: 1)
            : UIColor(red: 0 / 255, green: 113 / 255, blue: 245 / 255, alpha: 1)
    })

    /// 不透明基底：tint 叠在它上面，颜色不随 sheet / elevated 层级漂移。
    static let base = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 44 / 255, green: 44 / 255, blue: 46 / 255, alpha: 1)
            : .white
    })

    static func hairlineOpacity(for scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.245 : 0.25
    }
}

private struct ToolCapsuleSurfaceModifier<S: InsettableShape>: ViewModifier {
    let tint: Color
    let shape: S
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(ToolCapsuleSkin.base)
                    shape.fill(tint.opacity(ToolCapsuleSkin.fillOpacity))
                    if scheme == .light {
                        // 参照的浅色底部极淡压暗（black @2%，下 30%），给胶囊一点体积。
                        shape.fill(
                            LinearGradient(colors: [.clear, .black.opacity(0.02)],
                                           startPoint: UnitPoint(x: 0.5, y: 0.7),
                                           endPoint: .bottom)
                        )
                    }
                }
            }
            .overlay {
                shape.strokeBorder(
                    tint.opacity(ToolCapsuleSkin.hairlineOpacity(for: scheme)),
                    lineWidth: 0.5
                )
            }
    }
}

extension View {
    /// 胶囊材质（flat）：纯色基底 + tint 16% + 0.5pt hairline。不改尺寸 / 内边距。
    func toolCapsuleSurface<S: InsettableShape>(tint: Color, shape: S) -> some View {
        modifier(ToolCapsuleSurfaceModifier(tint: tint, shape: shape))
    }
}

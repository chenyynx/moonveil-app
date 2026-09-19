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

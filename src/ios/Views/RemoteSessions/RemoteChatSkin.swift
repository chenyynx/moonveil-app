// RemoteChatSkin.swift — 远端聊天渲染皮肤开关（[T-remote-skin]，pp 2026-09-22 拍板三皮肤）。
// 数据层不动（官方 AAV2 冻结区）；本开关只决定消息内容用哪套渲染组件画出：
//   local      = 现状：官方骨架 + Moonveil SelectableMarkdownView（§0f 桥接，本仓默认）
//   aaOriginal = AA 原版：官方 ChatMarkdownView 全家（Textual，官方 vendored 包逐字引入）
// 本地经典/新版本地观感档（官方行 → AssistantBlock 适配层）为 Batch 2，枚举值预留不开放
// ——功能完整性铁律：不开放的档位不出现在设置 UI，杜绝 stub 假选。
import SwiftUI

enum RemoteChatSkin: Int {
    /// 现状渲染（§0f 桥接）。
    case local = 0
    /// AA 原版渲染（Textual）。
    case aaOriginal = 1

    static let fallback: RemoteChatSkin = .local
}

enum RemoteChatSkinStore {
    static let userDefaultsKey = "remoteChatSkin"

    static var current: RemoteChatSkin {
        RemoteChatSkin(rawValue: UserDefaults.standard.integer(forKey: userDefaultsKey)) ?? .fallback
    }

    static func set(_ skin: RemoteChatSkin) {
        UserDefaults.standard.set(skin.rawValue, forKey: userDefaultsKey)
    }
}

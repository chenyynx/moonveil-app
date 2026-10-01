// SearchEntry.swift — 顶栏工具钮 + 搜索占位页。
//
// [SEARCH-SWAP 2026-10-01 pp「搜索 ⇄ 新会话 互换位置」] 本文件原来只放右上角
// 🔍（SearchToolbarButton）。互换后：
//   · 搜索入口 = 底栏 ModeTabBar 右侧玻璃圆钮（新增 `onSearchTapped` 回调，
//     三棵树的挂载点各传自己的 `showsSearch = true`；按钮本体在 ModeTabBar 内，
//     与本文件无关）；
//   · 右上角腾出来的位置 = ＋ 新会话钮（本文件 NewSessionToolbarButton），
//     本机树接 QuickActionRouter 新建本机会话、远端树接远端新会话页；
//   · SearchPlaceholderView 原样保留（三树的 `showsSearch` sheet 仍在用），
//     正式搜索 UI 落地时把 sheet 的 content 换成真搜索页即可，入口不动。
// 故 SearchToolbarButton 已随互换退役（零调用点），不保留死件。
//
// [ICON-SWAP 2026-10-01 · pp「顶部的那个新会话按钮你又造了个＋号 应该直接用
// 原来的图标」] 互换时顶栏钮临时用系统 plus（「先占位、图标后议」），现归位：
// 用互换前 🔍 钮同款的预栅格化管线 + 会话语义图标——aa-Tabler-Edit（Tabler
// 铅笔；与底栏圆钮互换前所用同源），尺寸 22pt 与本机页 ≡ / 终端钮同栅格。
// 同时底栏圆钮拿到 aa-Search（见 ModeTabBar.searchAsset）——两件互换彻底闭环。

import SwiftUI

/// 各 tab 页右上角的新会话按钮——[SEARCH-SWAP 2026-10-01] 占原 🔍 的位置；
/// [ICON-SWAP 2026-10-01] 图标 = aa-Tabler-Edit 22pt 预栅格化（ContentView
/// .toolbarIcon 共用管线，防切 tab 重建闪帧）。动作由调用方注入（各树新建
/// 链路不同）。
struct NewSessionToolbarButton: View {
    /// 点击动作：本机树 = 新建本机会话；远端树 = 开远端新会话页。
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            // [ICON-SWAP 2026-10-01] 走 ContentView.toolbarIcon 预栅格化位图
            //（与 🔍 时代同管线、与本机页 ≡ 同 22pt 栅格）：template=true 让
            // 位图吃 tint（图层染色黑/白自适应，勿删）。
            ContentView.toolbarIcon("aa-Tabler-Edit", pointSize: 22, template: true)
        }
        // [TINT-FIX2] foregroundStyle 盖不住 toolbar 的 AccentColor tint，
        // 直接改 Button 的 tint。
        .tint(.primary)
        // 文案沿用 ModeTabBar 的 "New Chat" key（zh-Hans=新对话，勿自创）。
        .accessibilityLabel(Text(String(localized: "New Chat")))
    }
}

/// 搜索占位页：空页面，以后再补。
struct SearchPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Coming soon"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.systemBackground))
            .navigationTitle(String(localized: "Search"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Close")) { dismiss() }
                }
            }
        }
    }
}

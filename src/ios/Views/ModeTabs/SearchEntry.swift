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

import SwiftUI

/// 各 tab 页右上角的 ＋ 按钮（系统 plus，19pt）——[SEARCH-SWAP 2026-10-01]
/// 顶栏新会话入口，占的是原 🔍 的位置。动作由调用方注入（各树的新建链路不同）。
struct NewSessionToolbarButton: View {
    /// 点击动作：本机树 = 新建本机会话；远端树 = 开远端新会话页。
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            // [FIX-toolbar-flash] SF Symbol 用 font 定尺寸，不用 .resizable()
            //（切 tab toolbar 重建时 resizable 要等布局才渲染，会闪一帧）。
            // 2026-09-27：22→19，之前在液态玻璃 pill 里显得比旁边的终端圆钮大一圈
            //（🔍 时代定的尺寸，＋ 沿用同栅格）。
            // weight .medium：同栏 alarm 钮（:15 medium）与 ≡ 菜单（22pt Tabler 描边）
            // 对齐，纯 regular 的 plus 在 19pt 框里偏细。
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .medium))
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

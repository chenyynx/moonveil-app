// SearchEntry.swift — 全局搜索入口（pp 2026-09-26「搜索放右上角」）。
//
// 原先是底栏 TabRole.search 独立圆形按钮；现改为各 tab 页导航栏右上角 🔍。
// 点开展示 SearchPlaceholderView（sheet；pp「先占位，点开是空页面以后再补」）。
// 正式搜索 UI 落地时：把 sheet 的 content 换成真搜索页即可，入口不动。

import SwiftUI

/// 各 tab 页右上角的 🔍 按钮（系统 magnifyingglass，19pt）。
struct SearchToolbarButton: View {
    @Binding var showsSearch: Bool

    var body: some View {
        Button {
            showsSearch = true
        } label: {
            // [FIX-toolbar-flash] SF Symbol 用 font 定尺寸，不用 .resizable()
            //（切 tab toolbar 重建时 resizable 要等布局才渲染，会闪一帧）。
            // 2026-09-27：22→19，之前在液态玻璃 pill 里显得比旁边的终端圆钮大一圈。
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19))
                // [TINT-FIX] tabContent 的 AccentColor 蓝 tint 会透进来，盖回黑。
                .foregroundStyle(.primary)
        }
        .accessibilityLabel(Text(String(localized: "Search")))
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

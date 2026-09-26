// SearchEntry.swift — 全局搜索入口（pp 2026-09-26「搜索放右上角」）。
//
// 原先是底栏 TabRole.search 独立圆形按钮；现改为各 tab 页导航栏右上角 🔍。
// 点开展示 SearchPlaceholderView（sheet；pp「先占位，点开是空页面以后再补」）。
// 正式搜索 UI 落地时：把 sheet 的 content 换成真搜索页即可，入口不动。

import SwiftUI

/// 各 tab 页右上角的 🔍 按钮（系统 magnifyingglass，22pt）。
struct SearchToolbarButton: View {
    @Binding var showsSearch: Bool

    var body: some View {
        Button {
            showsSearch = true
        } label: {
            Image(systemName: "magnifyingglass")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
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

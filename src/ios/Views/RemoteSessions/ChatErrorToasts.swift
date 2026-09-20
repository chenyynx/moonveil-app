// ChatErrorToasts.swift — AA 官方 Views/Chat/ChatErrorToasts.swift 逐字搬运。
//
// 唯一差异（铁律④）：`.glassEffect(.regular, in: .rect(cornerRadius: 24))` 是 iOS 26
// API → `remoteGlassCard()`（RemoteGlassIfAvailable.swift）；26+ 官方 EXACT 参数，
// <26 用 .regularMaterial 圆角 24 背景（先例 AuthGlassCompat / ChatComposer）。
// 差异/落地说明补充：
//   • 文案：本文件 String(localized:) 键为官方源键，取值已按官方 Localizable.xcstrings
//     的 zh-Hans 显示值落地（先例 COMPOSER-FULL / NEWSESSION-COPY；官方源键与其 en/zh
//     条目见 origin-cache/Resources/Localization/Localizable.xcstrings）。
import SwiftUI

/// Non-inline errors float below the header. Paging only changes the visible
/// toast; retry is always an explicit read, never a replay of the failed action.
struct ChatErrorToasts: View {
    let store: ChatToastStore
    let isRetrying: Bool
    let onRetry: (String) async -> Void
    @State private var selected: String?
    @ScaledMetric(relativeTo: .footnote) private var lineHeight: CGFloat = 18
    private var height: CGFloat { min(220, max(136, lineHeight * 4 + 74)) }

    var body: some View {
        if !store.items.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                AppSymbol("exclamationmark.circle").foregroundStyle(.secondary)
                                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                Spacer(minLength: 0)
                                if store.items.count > 1 {
                                    Text("\(index + 1)/\(store.items.count)").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                                }
                                Button { store.dismiss(item.id) } label: {
                                    AppSymbol("xmark", size: 11).frame(width: 44, height: 44)
                                }.buttonStyle(.plain).accessibilityLabel(String(localized: "关闭此提示"))
                            }
                            ScrollView(.vertical) {
                                Text(item.message).font(.footnote).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            }.scrollBounceBehavior(.basedOnSize)
                            if item.canRetry {
                                Button(isRetrying ? String(localized: "正在刷新…") : String(localized: "刷新")) { Task { await onRetry(item.id) } }
                                    .font(.footnote.weight(.medium)).frame(minHeight: 36).disabled(isRetrying)
                            }
                        }
                        .padding(.leading, 16).padding(.trailing, 4).padding(.bottom, 12)
                        .frame(height: height)
                        .containerRelativeFrame(.horizontal)
                        .remoteGlassCard()
                        .id(item.id)
                    }
                }.scrollTargetLayout()
            }
            .scrollIndicators(.hidden).scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selected).scrollClipDisabled()
            .frame(height: height)
            .padding(.horizontal, ChatControlMetrics.collapsedHorizontalInset)
            .padding(.top, 4).padding(.bottom, 10)
            .frame(maxWidth: ChatControlMetrics.maximumContentWidth)
            .onChange(of: store.items.map(\.id), initial: true) { _, ids in
                if selected == nil || !ids.contains(selected ?? "") { selected = ids.first }
            }
            .accessibilityHint(store.items.count > 1 ? String(localized: "左右滑动查看其他提示") : "")
        }
    }
}

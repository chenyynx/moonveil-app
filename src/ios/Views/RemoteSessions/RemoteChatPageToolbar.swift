// RemoteChatPageToolbar.swift — AA 官方 Views/Chat/ChatPageToolbar.swift
// 逐字搬运（ChatPageToolbar + ChatToolbarSubtitle + SidebarMenuIcon）。
//
// 唯一适配（版本守卫，非裁剪）：navigationSubtitle / toolbar(removing:) /
// sharedBackgroundVisibility / ToolbarItemPlacement.subtitle 是 iOS 26 API，
// 主 target 17.0 —— `#available(iOS 26.0, *)` 官方同款；以下版本按官方语义
// 去掉这四处（低版本系统无对应能力，非本仓裁剪）。
// ChatDetailNavigation 未搬：其 drawer 宿主逻辑依赖官方侧栏抽屉体系（本仓无
// 侧栏），非 drawer 分支的两个视觉点（systemBackground 背景 + primaryControl
// tint）由调用页直接应用（RemoteNewSessionView）。

import SwiftUI

/// Native title/subtitle placements and toolbar items own size, spacing, glass
/// grouping and scroll-edge rendering. No header view sits in the timeline.
struct ChatPageToolbar: ViewModifier {
    let title: String
    var subtitle: String?
    var status: ChatHeaderStatus?
    var alignsTitleLeading = false
    /// [CHAT-LEADING-FENCE] 是否显示官方侧栏 ≡ 按钮。官方 ≡ = 打开侧栏
    /// （drawer 体系，本仓无侧栏）；聊天页由 NavigationStack push 进入，
    /// 系统已提供返回箭头，且本仓 onMenu 的语义就是 dismiss —— 与返回箭头
    /// 重复（pp 2026-09-22 装机：左上角两颗按钮叠着，≡ 多余）。push 型
    /// 调用点传 false 只留系统返回；默认 true 保持官方形状供其他调用点。
    var showsSidebarButton = true
    let onMenu: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .navigationTitle(title)
                .navigationSubtitle(alignsTitleLeading ? "" : subtitle ?? "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbar(removing: .sidebarToggle)
                .toolbar { toolbarItems }
        } else {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbar { toolbarItems }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if showsSidebarButton {
            ToolbarItem(placement: .topBarLeading) {
                // 官方 label 是「打开侧栏」；本仓此键位语义为关闭（无侧栏），
                // 读屏文案随实际动作（必要语义适配）。
                Button(action: onMenu) { SidebarMenuIcon() }
                    .accessibilityLabel(String(localized: "关闭"))
            }
        }
        if alignsTitleLeading {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .principal) { principalTitle }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .principal) { principalTitle }
            }
        } else if subtitle != nil || status != nil {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .subtitle) {
                    ChatToolbarSubtitle(subtitle: subtitle, status: status)
                }
            } else {
                // 低版本无 subtitle placement：保留数据可达性（principal 副行）。
                ToolbarItem(placement: .principal) {
                    ChatToolbarSubtitle(subtitle: subtitle, status: status)
                }
            }
        }
    }

    private var principalTitle: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.headline).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            if subtitle != nil || status != nil {
                ChatToolbarSubtitle(subtitle: subtitle, status: status)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChatToolbarSubtitle: View {
    let subtitle: String?
    let status: ChatHeaderStatus?
    @ScaledMetric(relativeTo: .caption) private var lineHeight: CGFloat = 16

    private var text: String {
        [subtitle, status?.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var body: some View {
        HStack(spacing: 4) {
            if let status {
                Group {
                    if status.isProgress { ProgressView().controlSize(.mini) }
                    else { AppSymbol(status.symbol, size: 12) }
                }.frame(width: lineHeight, height: lineHeight)
            }
            Text(verbatim: text).lineLimit(1)
        }
        .font(.caption).foregroundStyle(.secondary)
        .frame(height: lineHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([subtitle, status?.detail].compactMap { $0 }.joined(separator: " · "))
    }
}

struct SidebarMenuIcon: View {
    var body: some View {
        AppSymbol("sidebar.left", size: 22).accessibilityHidden(true)
    }
}

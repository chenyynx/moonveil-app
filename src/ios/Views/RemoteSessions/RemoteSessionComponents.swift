// RemoteSessionComponents.swift — 远端列表的呈现组件（AA 视觉，零本机依赖）
//
// 复用仓内已有的 AA 视觉资产（AppGlassButton / AppTheme / SheetCloseToolbar /
// appSheetPresentation），不新造设计语言。状态指示器四态照抄 AA 的
// ChatSidebarSessionIndicator，卡片背景照抄 moonveil 本机列表的 SessionRowCardBackground。

import SwiftUI

// MARK: - 状态指示器（AA ChatSidebarSessionIndicator 四态）

struct RemoteStatusIndicator: View {
    enum Indicator: Equatable {
        case waitingApproval
        case running
        case unread
        case none
    }

    let indicator: Indicator

    var body: some View {
        switch indicator {
        case .waitingApproval:
            Text("等待批准")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.mint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.mint.opacity(0.16), in: Capsule())
                .fixedSize()
                .accessibilityLabel("等待批准")
        case .running:
            ProgressView()
                .controlSize(.mini)
                .tint(.primary)
                .frame(width: 14, height: 14)
                .accessibilityLabel("运行中")
        case .unread:
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .accessibilityLabel("未读")
        case .none:
            EmptyView()
        }
    }
}

// MARK: - 会话行卡片背景（moonveil 本机列表同款取样平色 + 发丝描边）

struct RemoteRowCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if colorScheme == .dark {
                RemoteCardSurface.dark
            } else {
                RemoteCardSurface.light
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

enum RemoteCardSurface {
    static var light: some View {
        Color.white
            .overlay(alignment: .top) { Color.white.opacity(0.9).frame(height: 0.75) }
            .overlay(alignment: .bottom) { Color.black.opacity(0.07).frame(height: 0.75) }
    }
    static var dark: some View {
        Color(white: 0.07)
            .overlay(alignment: .top) { Color.white.opacity(0.10).frame(height: 0.75) }
            .overlay(alignment: .bottom) { Color.black.opacity(0.35).frame(height: 0.75) }
    }
}

// MARK: - 长按菜单（值语义，无闭包捕获 — T-ios-crash-contextmenu-uaf 同款约束）

struct RemoteSessionContextMenu: View {
    let item: RemoteSessionItem
    let onAction: (RemoteSessionMenuAction) -> Void

    var body: some View {
        Button { onAction(.open) } label: {
            Label("Open", systemImage: "folder.fill")
        }
        Button { onAction(.rename) } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button { onAction(.togglePin) } label: {
            Label(item.isPinned ? "Unpin" : "Pin", systemImage: "pin")
        }
        Button { onAction(.archive) } label: {
            Label("Archive", systemImage: "archivebox")
        }
        Divider()
        Button { onAction(.copyId) } label: {
            Label("Copy session ID", systemImage: "doc.on.doc")
        }
    }
}

// MARK: - 六位配对码输入（AA OneTimeCodeField 的等价实现）

/// AA 的 PairDeviceSheet 用 OneTimeCodeField 收六位配对码；moonveil 未移植该组件，
/// 这里用原生 TextField + 数字键盘提供等价能力（官方语义：六位、自动提交）。
struct OneTimeCodeField: View {
    @Binding var code: String
    let title: String

    var body: some View {
        TextField(title, text: $code)
            .keyboardType(.numberPad)
            .textInputAutocapitalization(.never)
            .multilineTextAlignment(.center)
            .font(.system(.title3, design: .monospaced))
            .padding(.vertical, 8)
    }
}

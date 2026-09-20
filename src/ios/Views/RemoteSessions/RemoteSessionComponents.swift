// RemoteSessionComponents.swift — 远端列表的呈现组件（AA 视觉，零本机依赖）
//
// 复用仓内已有的 AA 视觉资产（AppGlassButton / AppTheme / SheetCloseToolbar /
// appSheetPresentation），不新造设计语言。状态指示器四态照抄 AA 的
// ChatSidebarSessionIndicator。（列表行/底栏的本机同款件走 ContentView 的
// 共享配方：BottomBarRecipe / SearchBarSurface / BottomBarFadeView）

import SwiftUI

// MARK: - 状态四态（语义沿用 AA ChatSidebarSessionIndicator；渲染位随本机卡头像槽位：
// 运行中 = 头像外圈转圈 / 未读 = 头像右上红点 / 等待批准 = 头像右下 mint 角标）

enum RemoteSessionIndicator: Equatable {
    case waitingApproval
    case running
    case unread
    case none
}

/// 本机 SessionRow 的 SpinningRing 逐字复制（原件是 ContentView 的 private——
/// 复制而不改本机大文件的可见性，死隔离；参数与视觉与其保持一致）。
struct RemoteSpinningRing: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let angle = timeline.date.timeIntervalSinceReferenceDate.remainder(dividingBy: 1.0) * 360
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(angle))
        }
    }
}

/// 本机 SessionRow 的 badgeCircle 同款角标（16pt 圆底白字形；offset 由调用方给）。
struct RemoteBadgeCircle: View {
    let icon: String
    let color: Color
    var iconSize: CGFloat = 9

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: iconSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(color)
            .clipShape(Circle())
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

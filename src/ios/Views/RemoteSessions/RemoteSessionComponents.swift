// RemoteSessionComponents.swift — 远端列表的呈现组件（AA 视觉，零本机依赖）
//
// 复用仓内已有的 AA 视觉资产（AppGlassButton / AppTheme / SheetCloseToolbar /
// appSheetPresentation），不新造设计语言。状态指示器四态照抄 AA 的
// ChatSidebarSessionIndicator。（列表行/底栏的本机同款件走 ContentView 的
// 共享配方：BottomBarRecipe / SearchBarSurface / BottomBarFadeView）

import SwiftUI

// MARK: - 状态四态（语义沿用 AA ChatSidebarSessionIndicator；方案 B 渲染位：
// 运行中 = 头像 teal 外圈 + 尾部 mono running / 未读 = 卡角珊瑚点 / 等待批准 = 尾部琥珀胶囊）

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

// MARK: - 方案 B 调色板（claude.md tokens；dynamic 深浅适配——REMOTE-REDESIGN-4）

enum RemotePalette {
    /// 页面画布：与本机页同款 systemBackground（pp 2026-09-26「把远端聊天页的背景
    /// 颜色改成和本地背景颜色一样」——本机画布 = 亮白/暗黑 systemBackground，
    /// 见 ContentView BottomBarFadeView 字据）。原方案 B 暖奶油 #FAF9F5 / 暖黑
    /// #181715 退役（dyn 仍服务 card/ink 等其余 token）。
    static let canvas = Color(UIColor.systemBackground)
    /// 会话卡：暖纸 / elevated
    static let card = dyn(0xEFE9DE, 0x252320)
    /// 终端窗卡底（深一档于画布，保证窗口感）
    static let terminal = dyn(0x181715, 0x0E0D0C)
    static let terminalText = dyn(0xFAF9F5, 0xFAF9F5)
    static let terminalFaint = dyn(0x8E8B82, 0x8E8B82)
    /// 主/次/三级文字
    static let ink = dyn(0x141413, 0xFAF9F5)
    static let body = dyn(0x6C6A64, 0xA09D96)
    static let faint = dyn(0xA6A29B, 0x8E8B82)
    static let timeFaint = dyn(0x8E8B82, 0x8E8B82)
    /// 头像
    static let avatarInk = dyn(0x3D3D3A, 0xFAF9F5)
    static let avatarWash = dyn(0xFAF9F5, 0x3A3733)
    /// 品牌点缀（claude.md 同名 tokens）
    static let coral = Color(red: 0.800, green: 0.471, blue: 0.361)   // #cc785c
    static let amber = Color(red: 0.910, green: 0.647, blue: 0.353)   // #e8a55a
    static let teal = Color(red: 0.365, green: 0.722, blue: 0.651)    // #5db8a6
    static let runningTeal = dyn(0x3D9D8C, 0x5DB8A6)
    /// 终端窗三色点
    static let trafficRed = Color(red: 1.000, green: 0.373, blue: 0.341)
    static let trafficYellow = Color(red: 0.996, green: 0.737, blue: 0.180)
    static let trafficGreen = Color(red: 0.157, green: 0.784, blue: 0.251)

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? ui(dark) : ui(light)
        })
    }

    private static func ui(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: 1)
    }
}

// MARK: - Anthropic 四芒星（✳）内容标记

struct RemoteSpikeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let d = r * 0.7071
        p.move(to: CGPoint(x: c.x, y: c.y - r)); p.addLine(to: CGPoint(x: c.x, y: c.y + r))
        p.move(to: CGPoint(x: c.x - r, y: c.y)); p.addLine(to: CGPoint(x: c.x + r, y: c.y))
        p.move(to: CGPoint(x: c.x - d, y: c.y - d)); p.addLine(to: CGPoint(x: c.x + d, y: c.y + d))
        p.move(to: CGPoint(x: c.x + d, y: c.y - d)); p.addLine(to: CGPoint(x: c.x - d, y: c.y + d))
        return p
    }
}

struct RemoteSpikeMark: View {
    var size: CGFloat = 10
    var body: some View {
        RemoteSpikeShape()
            .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            .frame(width: size, height: size)
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
        // [SESSION-SWIPE-TO-LONGPRESS 2026-09-24 pp「改成长按」] Delete 从行
        // swipeActions 迁入；服务端无删除端点（Staged），接线批到来前点了不生效
        // （与 Rename 同款暂不假造成功态）。
        Button(role: .destructive) { onAction(.delete) } label: {
            Label("Delete", systemImage: "trash")
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

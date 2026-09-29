//
//  TabBarInsetEnvironment.swift
//  MinisApp
//
//  [TAB-CLEARANCE 2026-09-29] tab 常驻时代的底部安全区基线。
//
//  背景：本仓给聊天页加了常驻底部 tab（feature/tab-persistent-simple）后，
//  实机（8b968b4 包）实锤 iOS 26 浮动 tab 栏的占位没有传进 NavigationStack
//  pushed 页面——聊天页输入条贴屏幕底、被 tab 玻璃胶囊压住（pp 2026-09-29
//  「tab压住了输入框」）。镜像判例：d3f92b5 时代 tab 隐藏后 ~65pt inset 赖着
//  不走把输入条顶高 70pt（bug #2）——同一套「inset 与 tab 协调」在 push 场景
//  两头都出过病。根层（tab 内容层）的 List 停在 tab 上方 = 该层安全区含 tab；
//  pushed 页只拿到 home 安全区 = inset 在 NavigationStack push 边界丢了。
//
//  修复 = 自校准让位，无状态机、无定时器、无 UIKit 内省：
//      clearance = max(0, tabContent 层底部安全区 − pushed 页自身底部安全区)
//  根层值由 RootModeTabsView 在 Tab 内容层（NavigationStack 外）量一次，经
//  `tabContentBottomInset` 环境值下发；pushed 页（AIChatView / SessionChatView）
//  用 BottomSafeAreaInsetProbe 量自身后取差值。公式自动覆盖：
//    • 键盘弹出：自身 inset 含键盘 → 差值 ≤ 0 → 不加垫（输入条贴键盘顶）；
//    • 语音面板：AIChatView 该态 ignore 键盘 edge → 差值恢复 → 面板抬到 tab 上方；
//    • iPad 宽屏：detail 非被 push，自身即含 tab → 0，不受影响；
//    • 未来系统修好 inset 传播：自身 = 根层 → 0，不加双垫。
//  探针测量模式逐字照抄仓内先例（AIChatView iOS<26 分支的 topSafeAreaInset：
//  onGeometryChange + ignoresSafeArea + frame(height:0)）。
//

import SwiftUI

private struct TabContentBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Tab 内容层（NavigationStack 外侧）量得的底部安全区，含常驻 tab 占位。
    /// 默认 0 = 尚未测量（RootModeTabsView 挂载前的兜底，此时不加垫）。
    var tabContentBottomInset: CGFloat {
        get { self[TabContentBottomInsetKey.self] }
        set { self[TabContentBottomInsetKey.self] = newValue }
    }
}

/// 底部安全区探针：供根层与 pushed 页各读一次 `safeAreaInsets.bottom`。
/// 挂在目标视图的 background 上；自带 ignoresSafeArea + frame(height: 0)，
/// 不影响宿主布局。
struct BottomSafeAreaInsetProbe: View {
    let onRead: (CGFloat) -> Void

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.safeAreaInsets.bottom
            } action: { onRead($0) }
            .ignoresSafeArea()
            .frame(height: 0)
    }
}

/// [TAB-CLEARANCE 2026-09-29] 探针 + 让位日志一体挂件。
/// AIChatView 的 body 已在编译器 type-check 阈值边缘（664 行超时判例，CI 实测；
/// 同族 SessionChatView:72），链上每多一个闭包表达式都可能压垮——所以探针
/// background 与 onChange 日志收进本 modifier，页面链上只占一个 `.modifier` 位。
/// 读数 = destination 层 `safeAreaInsets.bottom`（不含本页 safeAreaInset 的扩展）。
struct TabBarInsetProbeModifier: ViewModifier {
    @Environment(\.tabContentBottomInset) private var rootInset
    @Binding var ownInset: CGFloat
    /// 日志前缀（"local" / "remote"），装机日志判读用。
    var tag: String

    func body(content: Content) -> some View {
        content
            .background {
                BottomSafeAreaInsetProbe { ownInset = $0 }
            }
            .onChange(of: max(0, rootInset - ownInset)) { _, newValue in
                AppLogger(category: "TabClearance").info("[TAB-CLEARANCE][\(tag)] root=\(rootInset) own=\(ownInset) clearance=\(newValue)")
            }
    }
}

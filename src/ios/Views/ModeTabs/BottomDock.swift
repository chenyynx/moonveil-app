// BottomDock.swift — [DOCK-ON-PAGE 2026-09-28 pp] 底部导航改「长在页面上」：
// 系统 tab 栏在 RootModeTabsView 的 Tab 内容里侧静态隐藏（旧状态机同挂点，
// iOS 26 实测认这里；挂 TabView 本体不认），本 dock 经各页 safeAreaInset
// 长进页面布局（与上游 fabRow 同机制）——push/pop 时随页面一起滑动，滑一半
// 就跟手；系统从此零次 tab 栏藏/显转场，「新会话四连症 + 滑回 tab 不跟手」
// 那族 bug 的发病路径整体拆除（状态机只是帮凶，藏/显转场本身才是病根；
// 原装 OpenMinis 没有 tab 栏，所以从不走这条路径）。
//
// 产品语义与被替换的系统栏逐条对齐：3 tab 纯图标（选中黑/未选中灰，pp
// 2026-09-26pm）+ 右侧分离圆形新建钮（永不选中，点按走 QuickActionRouter
// 发新会话信号——与 RootModeTabsView tabSelection 的 compose 拦截同一通道）；
// 选择写 RootTabRouter.route(to:) 单通道（seenRemote 懒挂载/持久化/lastTab
// 全在 router，D4 红线不破）。
//
// 材质策略照搬上游 fabCircleSurface（build #396 教训：App 主 target 部署
// 目标 <26，iOS26 API 必须带可用性分支——206 本地门禁只做语法级检查，
// 可用性归 CI 编译级）：
// ① iOS 26+: Liquid Glass（glassEffect，系统 tab bar 同款渲染）；不叠手搓
//    阴影——玻璃自带边缘/阴影，叠了发黑晕（上游注释字据）；
// ② <26: 实底 + 轻阴影（上游回退分支同款）；
// ③ 玻璃只画不命中 → 两个分支都补 .contentShape（上游
//    [T-ios-search-bar-glass-hit-hole]：否则触点穿透到下层列表）；
// ④ 不包 GlassEffectContainer——上游实测它会掐死长按菜单
//    （[T-fab-glass-contextmenu-regression]）；本 dock 无 morph 需求；
// ⑤ 图标放面片内侧：面片当背景，图标骑在上面。

import SwiftUI
import UIKit

@MainActor
struct BottomDock: View {
    @ObservedObject private var router = RootTabRouter.shared

    /// 三个内容 tab（.compose 是动作钮，见 composeButton，不进此列）。
    private static let tabModes: [AppSourceMode] = [.local, .remote, .works]

    /// 图标资产与 RootModeTabsView 同源（pp 2026-09-27 钦定四组）。
    private static let tabIcon: [AppSourceMode: String] = [
        .local: "aa-Tabler-MessageCircle",
        .remote: "aa-Tabler-Cloud",
        .works: "aa-Tabler-Puzzle",
    ]
    private static let composeIcon = "aa-Tabler-Edit"

    var body: some View {
        HStack(spacing: 10) {
            tabCapsule
            composeButton
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 8)
    }

    // MARK: - 三 tab 玻璃胶囊

    private var tabCapsule: some View {
        dockSurface(
            shape: Capsule(),
            fallbackFill: Color(UIColor.secondarySystemBackground)
        ) {
            HStack(spacing: 0) {
                ForEach(Self.tabModes) { mode in
                    Button {
                        router.route(to: mode)
                    } label: {
                        Self.dockImage(Self.tabIcon[mode] ?? "aa-Circle")
                            .foregroundStyle(mode == router.mode ? Color.primary : Color.secondary)
                            .frame(width: 58, height: 50)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.a11yLabel(mode))
                    .accessibilityAddTraits(mode == router.mode ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - 分离圆形新建钮（占位与旧系统栏 search-role 圆钮一致：胶囊右侧分离圆）

    private var composeButton: some View {
        Button {
            QuickActionRouter.shared.requestNewChat()
        } label: {
            dockSurface(
                shape: Circle(),
                fallbackFill: Color(UIColor.secondarySystemBackground)
            ) {
                Self.dockImage(Self.composeIcon)
                    .foregroundStyle(Color.primary)
                    .frame(width: 50, height: 50)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.a11yLabel(.compose))
    }

    // MARK: - 面片（玻璃/实底回退，上游 fabCircleSurface 同策略）

    @ViewBuilder
    private func dockSurface(
        shape: some Shape,
        fallbackFill: Color,
        @ViewBuilder content: () -> some View
    ) -> some View {
        if #available(iOS 26.0, *) {
            content()
                .glassEffect(Glass.regular, in: shape)
                .contentShape(shape)
        } else {
            content()
                .background { shape.fill(fallbackFill) }
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                .contentShape(shape)
        }
    }

    // MARK: - 图标渲染（与 RootModeTabsView 同参：27pt 模板栅格 + 缓存防闪）

    /// [FIX-tab-icon-flash 同款] 栅格化结果按 asset 缓存：切 tab 只变
    /// .foregroundStyle 颜色，不换 UIImage，不闪。
    private static var dockImageCache: [String: UIImage] = [:]
    private static func dockImage(_ asset: String) -> Image {
        if let cached = dockImageCache[asset] {
            return Image(uiImage: cached)
        }
        let side: CGFloat = 27
        let ui = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side)
        ).image { _ in
            UIImage(named: asset)?.draw(
                in: CGRect(origin: .zero, size: CGSize(width: side, height: side))
            )
        }.withRenderingMode(.alwaysTemplate)
        dockImageCache[asset] = ui
        return Image(uiImage: ui)
    }

    /// a11y 文本与 RootModeTabsView 的 tabLabel 同 key（xcstrings 已有）。
    private static func a11yLabel(_ mode: AppSourceMode) -> String {
        switch mode {
        case .local: return String(localized: "Local")
        case .remote: return String(localized: "Remote")
        case .works: return String(localized: "Works & Media")
        case .compose: return String(localized: "New Chat")
        }
    }
}

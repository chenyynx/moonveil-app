// BottomDock.swift — [DOCK-ON-PAGE 2026-09-28 pp] 底部导航改「长在页面上」：
// 系统 tab 栏在 RootModeTabsView 的 Tab 内容里侧静态隐藏（旧状态机同挂点，
// iOS 26 实测认这里；挂 TabView 本体不认），本 dock 经各页 safeAreaInset
// 长进页面布局（与上游 fabRow 同机制）——push/pop 时随页面一起滑动，滑一半
// 就跟手；系统从此零次 tab 栏藏/显转场，「新会话四连症 + 滑回 tab 不跟手」
// 那族 bug 的发病路径整体拆除（状态机只是帮凶，藏/显转场本身才是病根；
// 原装 OpenMinis 没有 tab 栏，所以从不走这条路径）。
// 实机验证（pp 2026-09-28）：四步复现消失、滑回跟手 ✓。
//
// [DOCK-GEOMETRY 2026-09-28 pp「变小/按压缩放没了/发亮没了」] 观感逐项对齐
// 原生栏——以下全部来自原生栏截图 photo_EFB55779.png 像素实测（3x，1179px）：
//   item 88×60 / 胶囊内边距 8（反推图标中心 73.5/161.5/249.5pt vs 实测
//   73.7/161.3/249.0 逐点命中）/ 选中 pill 96×52、填充灰度≈236（亮面 =
//   黑 7.5%，非白色高亮——发亮走「灰底片+玻璃高光」两层）/ 圆钮 ⌀58 /
//   胶囊↔圆钮间距 12 / 离屏底 24pt（safeAreaInset 内容 ignoresSafeArea 下探）。
//   按压 = spring(duration 0.35, bounce 0.45) 缩放 0.9 弹回（系统 Liquid
//   Glass 按钮同款「放大缩小」感，图标 27pt 栅格与原生同尺寸不变）。
//
// 产品语义与被替换的系统栏逐条对齐：3 tab 纯图标（选中黑/未选中灰）+ 右侧
// 分离圆形新建钮（永不选中，点按走 QuickActionRouter 发新会话信号——与
// RootModeTabsView tabSelection 的 compose 拦截同一通道）；选择写
// RootTabRouter.route(to:) 单通道（seenRemote 懒挂载/持久化/lastTab 全在
// router，D4 红线不破）。
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

    /// [DOCK-GEOMETRY] pill 透明度随外观走（亮=黑7.5%≈灰236 实测 / 暗=白16%
    /// 估算）；减弱动态效果开启时滑动改瞬现（accessibility 规则）。
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 三个内容 tab（.compose 是动作钮，见 composeButton，不进此列）。
    private static let tabModes: [AppSourceMode] = [.local, .remote, .works]

    /// 图标资产与 RootModeTabsView 同源（pp 2026-09-27 钦定四组）。
    private static let tabIcon: [AppSourceMode: String] = [
        .local: "aa-Tabler-MessageCircle",
        .remote: "aa-Tabler-Cloud",
        .works: "aa-Tabler-Puzzle",
    ]
    private static let composeIcon = "aa-Tabler-Edit"

    // [DOCK-GEOMETRY] 原生栏实测值（pt）：item 88×60 / 胶囊内边距 8 /
    // pill 96×52（item 外扩 4）/ 圆钮 58 / 间距 12 / 离屏底 24。
    private static let itemW: CGFloat = 88
    private static let itemH: CGFloat = 60

    var body: some View {
        HStack(spacing: 12) {
            tabCapsule
            composeButton
        }
        .frame(maxWidth: .infinity, alignment: .center)
        // 离屏底 24pt = 原生实测（原生浮动栏压进 home indicator 区，
        // safeAreaInset 默认让 34pt 安全区会偏高）。
        .padding(.bottom, 24)
        .ignoresSafeArea(edges: .bottom)
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
                            .frame(width: Self.itemW, height: Self.itemH)
                            .contentShape(.rect)
                    }
                    .buttonStyle(DockPressStyle())
                    .accessibilityLabel(Self.a11yLabel(mode))
                    .accessibilityAddTraits(mode == router.mode ? .isSelected : [])
                }
            }
            .padding(.horizontal, 8)
            // [DOCK-SEL-PILL] 单块高光 pill 在三图标间滑动（原生实测 96×52、
            // 亮面填充≈灰236）；兼作颜色之外的选中信号（DifferentiateWithoutColor）。
            // 发亮 = 灰底片 + 自带玻璃高光两层；动画只挂 pill，内容页瞬切不受影响。
            .background {
                if let idx = Self.tabModes.firstIndex(of: router.mode) {
                    Group {
                        // 玻璃高光是 26-only API（#396 教训：可用性必带分支）。
                        if #available(iOS 26.0, *) {
                            selectionPill
                                .glassEffect(Glass.regular, in: Capsule())
                        } else {
                            selectionPill
                        }
                    }
                    .offset(x: CGFloat(idx - 1) * Self.itemW)
                    .animation(reduceMotion ? nil : Animation.snappy(duration: 0.28), value: router.mode)
                }
            }
        }
    }

    // MARK: - 分离圆形新建钮（占位与旧系统栏 search-role 圆钮一致：胶囊右侧分离圆）

    /// [DOCK-GEOMETRY] 选中高光底片：亮面 黑7.5%（≈原生实测灰236）/ 暗面 白16%。
    private var selectionPill: some View {
        Capsule()
            .fill(colorScheme == .dark
                ? Color.white.opacity(0.16)
                : Color.black.opacity(0.075))
            .frame(width: 96, height: 52)
    }

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
                    .frame(width: 58, height: 58)
            }
        }
        .buttonStyle(DockPressStyle())
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

/// [DOCK-GEOMETRY] 按压反馈两件套（系统 Liquid Glass 按钮的触点发光近似）：
/// ① 缩放弹回：按下 0.9、松手 spring 过冲（「放大缩小」感）；
/// ② 点击发亮：按下时按钮面亮起白色高光片（亮面 0.7 + 软阴影描边让白上加白
///    也可见，暗面 0.25），图标经 brightness 同步提亮，松手 easeOut 淡出。
/// 高光走 .background（垫在图标后面不遮图标），Capsule 形随按钮尺寸自适配
///（item=长胶囊、圆钮=圆）。动效只作用于按钮自身，选中 pill 是 HStack 背景层。
private struct DockPressStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.07 : 0)
            .background {
                Capsule()
                    .fill(Color.white.opacity(
                        configuration.isPressed
                            ? (colorScheme == .dark ? 0.25 : 0.7)
                            : 0
                    ))
                    .shadow(
                        color: .black.opacity(
                            configuration.isPressed && colorScheme == .light ? 0.15 : 0
                        ),
                        radius: 6, y: 3
                    )
                    .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            }
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(duration: 0.35, bounce: 0.45), value: configuration.isPressed)
    }
}

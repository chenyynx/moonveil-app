// ModeTabBar.swift — TG 式自绘 tab 栏（一级页常驻件，非系统 TabView 栏）。
//
// [TG-TABBAR 2026-09-30 pp 拍板「用tg的自绘」] 规格提取自 TG-iOS 源码实读
// （~/tg-ref/TabBarComponent.swift 1351 行 + TabBarContollerNode.swift；
// 数值出处逐条标注在下方注释）。复刻要点：
//   · 胶囊高 64 = item 56 + innerInset 4×2（TabBarComponent:664/727）；
//     两侧边距 12（TabBarContollerNode:213-216）；底缘 = 安全区底（:291）
//   · item 等宽平分；圆钮 64×64 独立圆、与胶囊间距 8（:899-901）
//   · 按下瞬间选中透镜即滑动（spring，TG :540/:599），松手才提交（:552+）；
//     按住期间内容放大 1.15（lifted 态，:835）；按住横拖透镜连续跟手
//     （TG :545 currentX = startX + translation.x，钳制在栏内）扫过换项
//   · 选中透镜 = 选中 item 宽 + 8、高 = item 高（:868-875 的 lensSelection
//     按帧计算模型；此处同款直算）；透镜本体 = 系统 Liquid Glass（TG
//     LiquidLens 的观感近似——真正的液态折射变形是 TG 私有渲染器，不逐像素
//     复刻），拖动中微抬升（isLifted 近似）
// 材质：iOS 26 系统 glassEffect（<26 回退 regularMaterial，仓内既有守卫约定，
// 先例 RemoteGlassIfAvailable / SoulProfileHub.circleLiquidGlass）。TG 的玻璃是
// 其私有框架件（GlassBackgroundComponent）——规格级复刻、不逐字搬运（GPL-2.0
// 摩擦规避）。
//
// 架构（治根点）：本栏挂进【每棵 tab 树 NavigationStack 的 root 页】的底边
// （safeAreaInset）——push 从栈内部盖上来整页覆盖（含栏），划回时 root 页
// （含栏）整体随手势平移揭示，没有任何"隐藏/出现"。系统 tab bar 与全部
// toolbar(.hidden, for: .tabBar) 藏显机制随之退役（同批清理）。
// 实例化 = 四处调用点（ContentView 窄窗 stackLayout / 宽窗挂整个 NavigationSplitView
// 且聊天打开时收栏、RemoteRootView、WorksListView），选中态经
// RootTabRouter.shared 单通道同步。
//
// [TG-LENS-PORT 2026-09-30 pp 拍板 B「真·移植 TG」] 26+（且苹果私有
// _UILiquidLensView 可取）时，胶囊区改由 TGLensHost 的透镜岛渲染（TG 源码
// 移植，见 TGLens/ 目录与 docs/tg-lens-port.md）；否则回退本文件的玻璃版
// （legacyItemsCapsule）。同批几何对齐 TG 实测：栏高 64→68、整体下移 12pt；
// 圆钮换 .plain + interactive 玻璃（拉缩发光）。触摸手势保持在 SwiftUI 侧，
// 交互分工：岛内手势（TG 原样，与玻璃触摸响应并行），选中/深色下发，提交回传
// onCommit；legacy 路径保留原 SwiftUI DragGesture。

import SwiftUI
import UIKit

struct ModeTabBar: View {
    /// 本栏所在的 tab 树（调用方注入）。用途：在途手势跨树兜底——若按住期间
    /// 外部 route(to:) 把本树切走，松手不再 commit（对抗复审 [低] 项，2026-09-30）。
    var tabMode: AppSourceMode

    /// 单通道（D4 红线）：选中读这里、切页写这里，与旧 tabSelection binding 同源。
    @ObservedObject private var router = RootTabRouter.shared

    /// 三个页面位（compose 是动作钮，走右侧独立圆位，见 composeButton）。
    private static let selectableTabs: [AppSourceMode] = [.local, .remote, .works]

    /// 按压跟踪（TG selectionGestureState / overrideSelectedItemId 的 SwiftUI 化）：
    /// 手指按住/拖到的 item。nil = 无按压。高亮显示位 = pressed ?? router.mode。
    @State private var pressed: AppSourceMode?
    /// 透镜拖动跟手态（TG selectionGestureState 的 SwiftUI 化，:423/:538-545）：
    /// 拖动期间透镜 x = 起点 + 指尖位移（连续跟手）；松手弹簧落位（归 nil）。
    @State private var lensDragBaseX: CGFloat?
    @State private var lensDragShiftX: CGFloat = 0
    /// item 区实宽（三槽平分用；背景 GeometryReader 测量，不依赖新 API）。
    @State private var itemsWidth: CGFloat = 0
    /// [TG-LENS-PORT] 深浅模式（透镜/玻璃的 isDark 参数与岛内图标着色）。
    @Environment(\.colorScheme) private var colorScheme
    /// [TG-LENS-PORT] 栏高：TG 实测 ≈68（原 64）。底距经 offset(y:) 下移 12pt 对齐
    /// TG 实测（胶囊距屏底 35→23pt，压入 home 指示条区）。
    private static let barHeight: CGFloat = 68

    // MARK: - 资产（自 RootModeTabsView 迁入，逐字保留）

    /// [NATIVE-TABS] 各 tab 的 Tabler 图标（aa-Tabler- 前缀资产，模板渲染），
    /// 纯图标 tab（无文字）；27pt 栅格（光学约 22.5pt），选中/未选 .primary/
    /// .secondary。a11y 朗读文本由 tabLabel 提供。
    /// 2026-09-27：pp 从 Tabler 库四组候选中钦定（tab1 message-circle /
    /// tab2 cloud / tab3 puzzle / tab4 edit）。
    private static let tabIcon: [AppSourceMode: String] = [
        .local: "aa-Tabler-MessageCircle",
        .remote: "aa-Tabler-Cloud",
        .works: "aa-Tabler-Puzzle",
        .compose: "aa-Tabler-Edit",
    ]

    /// Lucide SVG 资产是 24pt viewBox；Muse 的 tab 图标约 19pt，这里栅格化到
    /// 27pt 并保持 template 渲染；颜色由调用处的 .foregroundStyle 按选中态给。
    /// 2026-09-27：22→27 —— Tabler 2px 描边在 22pt 框里光学只有约 18pt，
    /// 在系统浮动 pill 里显小；27pt 光学约 22.5pt，描边约 2.25px。
    /// [FIX-tab-icon-flash] 栅格化结果按 asset 缓存：切 tab 时若每次都 new 出
    /// UIImage，底栏 image view 会闪一下重绘。复用同一张图后，切 tab 只变
    /// .foregroundStyle 颜色，不换图，不闪。
    private static var tabImageCache: [String: UIImage] = [:]
    private static func tabImage(_ asset: String) -> Image {
        if let cached = tabImageCache[asset] {
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
        tabImageCache[asset] = ui
        return Image(uiImage: ui)
    }

    /// 图标颜色：选中 .primary（浅色黑/深色白），未选中 .secondary 灰。
    /// 按压中的项按"选中"着色（TG：overrideSelectedItemId 参与 tintSelectedItem）。
    private static func tabIconColor(_ mode: AppSourceMode, active: Bool) -> Color {
        if mode == .compose { return .primary }
        return active ? .primary : .secondary
    }

    private static func tabLabel(_ mode: AppSourceMode) -> String {
        switch mode {
        case .local: return String(localized: "Local")
        case .remote: return String(localized: "Remote")
        case .works: return String(localized: "Works & Media")
        case .compose: return String(localized: "New Chat")
        }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            itemsCapsule
            composeButton
        }
        .padding(.horizontal, 12)
        // [对抗复审 2026-09-30·中] 键盘豁免：系统栏时代栏钉屏幕底、被键盘盖住；
        // 本栏同理不随键盘避让上浮（本机列表搜索聚焦场景）。生效性装机核验；
        // 若不生效，候选挂点 = 调用点 sessionList 的 safeAreaInset 之前（保 List
        // 自身键盘策略不动——复审 v2 推理：inset 视图落位由父层布局决定）。
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // [TG-LENS-PORT 2026-09-30] 几何对齐 TG 实测（屏截像素测量对比）：TG 栏
        // 底距 ≈23pt，本栏原为安全区底（≈35pt）——整体下移 12pt（纯视觉位移，
        // 不改变 safeAreaInset 的布局占位，内容 inset 不受影响）。
        .offset(y: 12)
    }

    /// [TG-LENS-PORT 2026-09-30 pp 拍板 B] 26+ 且私有类可选器形态完备 → TG 移植
    /// 透镜岛；否则回退既有玻璃版渲染（<26 / 私有类缺失，永不出白屏）。
    /// 交互分工：岛内 = TG 原样的 UIKit 手势（玻璃触摸响应与之并行，见 TGLensHost
    /// 头注）；legacy = 本文件既有的 SwiftUI DragGesture。
    private var itemsCapsule: some View {
        Group {
            if TGLensBar.isSupported {
                TGLensBar(
                    selectedIndex: Self.selectableTabs.firstIndex(of: router.mode) ?? 0,
                    isDark: colorScheme == .dark,
                    onCommit: { index in
                        guard index >= 0, index < Self.selectableTabs.count else { return }
                        // 跨树兜底（同旧 DragGesture onEnded 语义）：按住期间本树被
                        // 外部 route 切走 → 丢弃本次提交。
                        if tabMode == router.mode {
                            commit(Self.selectableTabs[index])
                        }
                    }
                )
            } else {
                legacyItemsCapsule
                    .contentShape(Capsule())
                    .gesture(selectionGesture)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.barHeight)
    }

    /// 三 item 玻璃胶囊（回退渲染路径）——TG GlassBackgroundContainerView +
    /// LiquidLens 的系统件近似：容器 = glassEffect 胶囊；选中透镜 = 独立玻璃胶囊，
    /// 按下弹簧滑到指尖槽位、按住拖动连续跟手、松手弹簧落位并撤销抬升。
    private var legacyItemsCapsule: some View {
        let slot = Self.selectableTabs.firstIndex(of: pressed ?? router.mode) ?? 0
        let slotWidth = itemsWidth / CGFloat(Self.selectableTabs.count)
        let lensWidth = slotWidth + 8
        // 透镜 x：拖动中 = 起点 + 指尖位移连续跟手（TG :545 currentX = startX +
        // translation.x），钳制在栏内（TG :885 lensSelection.x clamp）；否则 =
        // 高亮槽位 x（TG lensSelection 直算 :868-887）。
        let lensX: CGFloat
        if let baseX = lensDragBaseX, itemsWidth > 0 {
            let maxX = max(0, itemsWidth - slotWidth)
            lensX = min(max(baseX + lensDragShiftX, 0), maxX)
        } else {
            lensX = CGFloat(slot) * slotWidth
        }
        let lensLifted = lensDragBaseX != nil
        return HStack(spacing: 0) {
            ForEach(Self.selectableTabs) { mode in
                tabItem(mode)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { itemsWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in itemsWidth = newValue }
            }
        }
        .padding(4)
        // 选中透镜：宽 = 槽宽 + innerInset×2（TG :870-872）、高 = item 高；
        // 本体 = 系统 Liquid Glass（<26 回退 material）；拖动中微抬升（TG isLifted
        // 的近似——真正的液态折射变形是 TG 私有 LiquidLens 渲染，不逐像素复刻）。
        .background(alignment: .topLeading) {
            Capsule()
                .fill(.clear)
                .frame(width: lensWidth, height: 56)
                .selectionLensGlass()
                .scaleEffect(lensLifted ? 1.05 : 1.0)
                .offset(x: lensX, y: 4)
                .opacity(itemsWidth > 0 ? 1 : 0)
        }
        .tabBarGlassCapsule()
    }

    /// 单 item：图标居中（纯图标，无文字）+ 按压放大。
    private func tabItem(_ mode: AppSourceMode) -> some View {
        let active = (pressed ?? router.mode) == mode
        return Self.tabImage(Self.tabIcon[mode] ?? "aa-Circle")
            .foregroundStyle(Self.tabIconColor(mode, active: active))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // TG lifted 态：按住期间内容放大 1.15（:835；透镜本体的抬升另见
            // itemsCapsule 的 scaleEffect）。
            .scaleEffect(pressed != nil && active ? 1.15 : 1.0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(Self.tabLabel(mode)))
            .accessibilityAddTraits(router.mode == mode ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { commit(mode) }
    }

    /// 圆钮（新会话 ＋；TG 的 64×64 独立圆搜索钮同位，:899-901 —— 我们的语义
    /// 是"新建"，pp 2026-09-26 拍板借位）。玻璃圆 + 按压回弹。
    private var composeButton: some View {
        Button {
            // 跨树兜底：同 drag onEnded（按住期间本树被外部 route 切走则丢弃，
            // 对抗复审 v2 [低]）。
            if tabMode == router.mode {
                commit(.compose)
            }
        } label: {
            Self.tabImage(Self.tabIcon[.compose] ?? "aa-Circle")
                .foregroundStyle(Self.tabIconColor(.compose, active: false))
                .frame(width: 64, height: 64)
                .circleLiquidGlass()
                .contentShape(Circle())
        }
        // [TG-LENS-PORT 2026-09-30] 官方 AppGlassButton 配方（.plain + interactive
        // 玻璃）：卡住的"拉缩 + 发光"= 系统液态玻璃触摸响应，替掉原先无观感的手工
        // 0.92 缩放（SpringPressButtonStyle 与 .interactive() 双重缩放会打架）。
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Self.tabLabel(.compose)))
    }

    // MARK: - 手势（TG TabSelectionRecognizer 的 SwiftUI 化）

    /// 按下即动、松手提交、按住横拖透镜连续跟手扫过换项。TG：
    /// began 定起点并弹簧滑到指尖槽位（:530-540）→ changed 跟手 + 更新落点
    /// （:542-551）→ ended 提交并弹簧落位（:552-599）。
    private var selectionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard itemsWidth > 0 else { return }
                let slotWidth = itemsWidth / CGFloat(Self.selectableTabs.count)
                if lensDragBaseX == nil {
                    // TG began：透镜起点 = 指尖下的槽位（按下即弹簧滑到那里）；
                    // 高亮/缩放同帧并入弹簧事务（TG began 即 .spring；对抗复审 v2
                    // [低]——此前 pressed 在事务外，图标缩放跳变不对称）。
                    let beganIndex = slotIndex(forX: value.location.x)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        lensDragBaseX = CGFloat(beganIndex) * slotWidth
                        pressed = Self.selectableTabs[beganIndex]
                    }
                }
                // TG changed：透镜连续跟手（translation 驱动；此处即时刷新，
                // 不包动画，指尖停下的瞬间透镜即停）；高亮槽位随指尖更新
                // （松手落点 = 它）。
                lensDragShiftX = value.translation.width
                let target = Self.selectableTabs[slotIndex(forX: value.location.x)]
                if pressed != target {
                    pressed = target
                }
            }
            .onEnded { _ in
                // 系统中断（来电横幅等）也走本路径——SwiftUI DragGesture 无取消
                // 判别，此处照常提交（TG 的 .cancelled 清零无 SwiftUI 等价；低
                // 概率低后果，留档接受，对抗复审 v2 [记录]）。
                // 跨树兜底：按住期间本树被外部 route(to:) 切走 → 丢弃本次提交
                // （对抗复审 [低] 项，2026-09-30）。
                if tabMode == router.mode, let target = pressed {
                    commit(target)
                }
                // TG ended：弹簧落位（:599）+ 抬升/高亮还原。
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    pressed = nil
                    lensDragBaseX = nil
                    lensDragShiftX = 0
                }
            }
    }

    /// 容器内横向坐标 → 槽位。容器含 4pt 内边距（innerInset），槽位从 x=4 起；
    /// 越界按最近项钳制（同 TG item(at:) 的 ClosestItem 语义，:623-643）。
    private func slotIndex(forX x: CGFloat) -> Int {
        guard itemsWidth > 0 else { return 0 }
        let slotWidth = itemsWidth / CGFloat(Self.selectableTabs.count)
        let raw = Int(floor((x - 4) / slotWidth))
        return min(max(raw, 0), Self.selectableTabs.count - 1)
    }

    // MARK: - 提交

    /// 与旧 tabSelection binding 完全同语义（NavTrace 打点保留，切 tab 追踪
    /// 不断线）。compose 是 ACTION 位：永不选中，点击 = 新建本机会话走
    /// QuickActionRouter 单通道（tab 停在原页，ContentView 接到后切回本机页）。
    private func commit(_ mode: AppSourceMode) {
        NavTrace.mark(mode == .compose ? "composeTab" : "-")
        NavTrace.log("BINDING set=\(mode) mode=\(router.mode) trig=\(NavTrace.trigger)+\(NavTrace.age)")
        if mode == .compose {
            QuickActionRouter.shared.requestNewChat()
        } else {
            router.route(to: mode)
        }
    }
}

// MARK: - 玻璃守卫（仓内既有约定：iOS 26 系统 glassEffect；<26 回退 material。
// 先例 RemoteGlassIfAvailable.remoteGlassCapsule / SoulProfileHub.circleLiquidGlass）

extension View {
    /// bar 容器玻璃胶囊 = TG GlassBackgroundContainerView 的观感等价物。
    @ViewBuilder
    fileprivate func tabBarGlassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self.background { Capsule().fill(.regularMaterial) }
        }
    }

    /// 选中透镜玻璃（TG LiquidLens 观感的系统件近似，"透明的流体"）：
    /// iOS 26 = 独立玻璃层（叠在栏玻璃上）；<26 = ultraThinMaterial 胶囊。
    /// 施加对象 = 尺寸已定的透明 Capsule（fill(.clear).frame(...)）。
    @ViewBuilder
    fileprivate func selectionLensGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background { Capsule().fill(.ultraThinMaterial) }
        }
    }

    /// 圆钮玻璃（同 SoulProfileHub.circleLiquidGlass 的形状换法）。
    /// [TG-LENS-PORT 2026-09-30] 补 `.interactive()`——全仓既有控件（官方
    /// AppGlassButton / 顶栏胶囊 / 聊天输入框）均为 interactive，唯独本批三面
    /// 玻璃漏配。此为圆钮「按下拉缩 + 发光」的来源。
    @ViewBuilder
    fileprivate func circleLiquidGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self.background { Circle().fill(.ultraThinMaterial) }
        }
    }
}

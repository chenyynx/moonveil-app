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
// （legacyItemsCapsule）。几何经对账修正（2026-09-30 源码+实机双证）：栏高 64、
// 整体下移 14pt、边距 20、格宽 68.25（详见 barHeight/offset 注释与 spec §7）；
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

    /// 槽位数 = 4（TG 4 格布局对齐：3 实 tab + 第 4 格设置齿轮；pp 2026-09-30 装机
    /// 「加一个图标占位保持和tg一致大小」——TG 是 4 tab 布局，按 3 格算每格偏大；
    /// 同日「把那个空白占位的 tab 加一个图标」→ 第 4 格 = 设置齿轮，见 settingsSlotItem）。
    /// 与 TGLensHost.slotCount 同值，两处渲染路径几何一致。
    private static let slotCount = 4

    /// 按压跟踪（TG selectionGestureState / overrideSelectedItemId 的 SwiftUI 化）：
    /// 手指按住/拖到的 item。nil = 无按压。高亮显示位 = pressed ?? router.mode。
    @State private var pressed: AppSourceMode?
    /// [第 4 格 · 设置齿轮 2026-09-30 pp「把那个空白占位的 tab 加一个图标」] 设置
    /// 齿轮按压态（动作位不进透镜手势；见 selectionGesture 的 raw 守卫与 onEnded 的
    /// 开设置分支）。只撑齿轮图标自身，不参与 tab 高亮槽位（pressed ?? router.mode）。
    @State private var gearPressed = false
    /// [第 4 格] 本次手势归属齿轮（起点在第 4 格）：手势存续期抑制透镜逻辑——
    /// 对应 TGLensHost.gearPressActive 的手势域语义：移回 tab 区仅撤按压态，
    /// 不启动透镜、不重新武装（与岛侧 .changed 取消分支一字不差）。
    @State private var gearDragActive = false
    /// 透镜拖动跟手态（TG selectionGestureState 的 SwiftUI 化，:423/:538-545）：
    /// 拖动期间透镜 x = 起点 + 指尖位移（连续跟手）；松手弹簧落位（归 nil）。
    @State private var lensDragBaseX: CGFloat?
    @State private var lensDragShiftX: CGFloat = 0
    /// item 区实宽（四格平分用；背景 GeometryReader 测量，不依赖新 API）。
    @State private var itemsWidth: CGFloat = 0
    /// [TG-LENS-PORT] 深浅模式（透镜/玻璃的 isDark 参数与岛内图标着色）。
    @Environment(\.colorScheme) private var colorScheme
    /// 栏高 = 64（TG 源码 TabBarComponent.swift:664：56 + innerInset 4×2；pp 实机
    /// 反演圆钮 192px = 64.0pt 双证）。此前 68 系屏测误差——2026-09-30 装机对账修正。
    private static let barHeight: CGFloat = 64

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

    /// [第 4 格] 设置齿轮资产（与 TGLensHost.settingsAsset / ContentView ≡ 齿轮
    /// 同源 aa-Tabler-Settings，勿另起）。
    private static let settingsAsset = "aa-Tabler-Settings"

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
        // [尺寸对账 2026-09-30] TG sideInset：底距≤28 的档位 = 20（TabBarContollerNode
        // :213-215），pp 实机反演（四列图标中心距 68.0）落于此档 → 12 改 20；格宽
        // 随之 (屏宽−40−圆钮64−间距8−innerInset8)/4 = 68.25 ≈ TG 实测 68。
        .padding(.horizontal, 20)
        // [TG-TABBAR-FIX 2026-09-30 pp 装机实证] 键盘豁免（本处）**无效**：栏落位由
        // 被 safeAreaInset 修饰的整链安全区决定，挂在栏内部的 ignore 改不了插槽
        // 位置——键盘开启从聊天页划回时栏随输入框一起上浮（TG = 钉死底部、被键盘
        // 覆盖）。权威修复 = 挂点整链外侧的 ignoresSafeArea（ContentView.stackLayout /
        // RemoteRootView / WorksListView 三处同款注释）。本行保留（对栏内部布局无
        // 副作用，双保险），勿删。
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // [TG-LENS-PORT 2026-09-30 · 2026-09-30 对账修正] 底距对齐 TG 实机：圆钮
        // 下缘实测 ≈19.7pt；本栏 = 安全区底 34 − offset ⇒ offset = 14（旧值 12 →
        // 底距 22，偏差 2pt）。纯视觉位移，不改变 safeAreaInset 的布局占位。
        .offset(y: 14)
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
                    ownSlot: Self.selectableTabs.firstIndex(of: tabMode) ?? 0,
                    onSettings: {
                        // [第 4 格] 同 compose 的跨树兜底：按住期间本树被切走则丢弃。
                        if tabMode == router.mode {
                            router.showSettings = true   // B16 单通道（≡ 齿轮同款）
                        }
                    },
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
                    // [探针 2026-10-01] 渲染路径判定：岛不可用时打点（定位「底栏点击
                    // 硬落点」是否走了 legacy 玻璃栏；判读后随其它探针一并删除）。
                    .onAppear { NavTrace.log("[LENS] legacy-path appeared (island unsupported)") }
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
        let slotWidth = itemsWidth / CGFloat(Self.slotCount)
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
            // [4 格 · 第 4 格 2026-09-30] 设置齿轮（pp「把那个空白占位的 tab 加一个
            // 图标」）：TG 第 4 tab = 设置的语义；本仓设置是全局 sheet（B16 单通道
            // router.showSettings），故为动作位——点按开设置、透镜永不驻留此格。
            // 前 3 格尺寸随之与 TG 对齐（槽位算法分母 = slotCount(4)，见文件内各处）。
            settingsSlotItem
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
        // 选中透镜**视觉 = item 槽位本身**：TG 的选中矩形 = item 外扩 4（:872
        // minX−innerInset / 宽+8），私有透镜渲染时内收 4（26 路径：LiquidLensView
        // :464 取矩形、:343/:376 以 liftedInset=−inset 内收；legacy blob 分支 :471
        // 同义）→ 视觉 = item 矩形（宽 = 槽宽、距胶囊边 4pt）。本 legacy 件同视觉：
        // 宽 = 槽宽、x = 选中坐标 + 4（2026-09-30 pp 装机「触边」修正：旧式 +8 宽、
        // x 不加 4 → 首格左缘顶到胶囊边）。本体 = 系统 Liquid Glass（<26 回退
        // material）；拖动中微抬升（TG isLifted 近似——真正的液态折射变形是 TG
        // 私有 LiquidLens 渲染，不逐像素复刻）。
        .background(alignment: .topLeading) {
            Capsule()
                .fill(.clear)
                .frame(width: slotWidth, height: 56)
                .selectionLensGlass()
                .scaleEffect(lensLifted ? 1.05 : 1.0)
                .offset(x: lensX + 4, y: 4)
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

    /// [第 4 格 · 设置齿轮] 尾格 item：图标居中 + 按压放大 1.15（同 tabItem 的按压
    /// 语言）。动作位——点按开设置走 selectionGesture 的齿轮分支（同 tab 的「按下
    /// 即动、松手提交」路径，无独立 tap 手势）；透镜永不驻留/提交本格（slotIndex
    /// 钳制 0..2）。资产与岛侧 TGLensHost.settingsAsset 同源；文案沿用 ≡ 齿轮的
    /// "Settings" key（zh-Hans=设置，勿自创）。
    private var settingsSlotItem: some View {
        Self.tabImage(Self.settingsAsset)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(gearPressed ? 1.15 : 1.0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(String(localized: "Settings")))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if tabMode == router.mode { router.showSettings = true }
            }
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
                let slotWidth = itemsWidth / CGFloat(Self.slotCount)
                // [第 4 格·设置齿轮] 手势存续期只维护按压显隐，不启动/不接管透镜
                // （镜像岛侧 .changed 的 gearPressActive 守卫；移回 tab 区 = 撤销
                // 按压、不重新武装）。
                if gearDragActive {
                    if gearPressed, rawSlotIndex(forX: value.location.x) < Self.selectableTabs.count {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            gearPressed = false
                        }
                    }
                    return
                }
                if lensDragBaseX == nil {
                    // [第 4 格] 首次回调定手势归属：起点在第 4 格 = 设置齿轮动作位
                    // （镜像岛侧 .began 的 raw 守卫——按下态给齿轮，松手开设置）。
                    if rawSlotIndex(forX: value.startLocation.x) >= Self.selectableTabs.count {
                        gearDragActive = true
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            gearPressed = true
                        }
                        return
                    }
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
            .onEnded { value in
                // [第 4 格·设置齿轮] 松手落点仍在第 4 格且按压未被撤销 → 开设置
                // （镜像岛侧 .ended 的 onSettings 分支；动作位走开设置、不走 commit）。
                if gearDragActive {
                    let fire = gearPressed
                        && rawSlotIndex(forX: value.location.x) >= Self.selectableTabs.count
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        gearPressed = false
                    }
                    gearDragActive = false
                    // 跨树兜底：按住期间本树被外部 route 切走则丢弃（同 compose 圆钮）。
                    if fire, tabMode == router.mode {
                        router.showSettings = true   // B16 单通道（≡ 齿轮同款）
                    }
                    return
                }
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
    /// [第 4 格 2026-09-30] 钳制上界 = 末个实 tab（0..2）：透镜提交永不落第 4 格
    /// （设置齿轮为动作位；拖过该格仍钳回 works，与岛侧 slotIndex 同义）。
    private func slotIndex(forX x: CGFloat) -> Int {
        guard itemsWidth > 0 else { return 0 }
        return min(max(rawSlotIndex(forX: x), 0), Self.selectableTabs.count - 1)
    }

    /// 未钳制槽位（≥3 = 第 4 格设置齿轮；手势的动作位判别用——与 TGLensHost
    /// rawSlotIndex 同义，两渲染路径语义一致）。
    private func rawSlotIndex(forX x: CGFloat) -> Int {
        guard itemsWidth > 0 else { return 0 }
        let slotWidth = itemsWidth / CGFloat(Self.slotCount)
        return Int(floor((x - 4) / slotWidth))
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

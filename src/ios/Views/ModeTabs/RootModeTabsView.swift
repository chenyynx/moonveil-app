// RootModeTabsView.swift — the single fork point (D4 §2) + 首启入口终案接线:
// 未登录且落在远程 tab → AA 官方登录页全屏盖（扫码/手动/本地三颗胶囊 CTA）；
// 登录成功 → 远程 tab；本地入口 → 本机 tab；lastTab 记忆（RootTabRouter）。
// 恢复：官方 restoreSession 语义（UserDefaults server + keychain token）。
//
// [TG-TABBAR 2026-09-30] 底部导航改 TG 式自绘（pp「用tg的自绘」；规格与数值
// 出处见 ModeTabBar.swift 头注）。系统 TabView 整体退役——原方案「系统栏 +
// toolbar(.hidden, for:.tabBar) 藏显」在 iOS 26 有 hide/reveal 回归，且藏显
// 机制在新会话草稿→正式换视图面前失序（Unbalanced/卡死，见 AIChatView 墓碑）。
// 现在：三棵 tab 树在 ZStack 保活（瞬切），自绘栏挂进各树 NavigationStack 的
// root 页——push 整页覆盖含栏、划回原位揭示，没有任何隐藏/出现（对照 pp 的
// TG 截图语义）。
//
// [NATIVE-TABS 2026-09-26pm 沿革] pp 按 Muse 对齐：纯图标 tab（Lucide 20pt 黑）；
// 搜索在导航栏右上角（SearchEntry.swift）；独立圆钮 = 新建会话 ＋（ModeTabBar
// 右侧圆位）。顶栏身份胶囊在本机页导航栏 principal 位（pp 拍板保留的需求件），
// zoom 转场照旧。≡ 齿轮 = 原生 toolbar 按钮。

import SwiftUI
import UIKit

@MainActor
struct RootModeTabsView: View {
    @StateObject private var router = RootTabRouter.shared
    @StateObject private var remoteService = RemoteService()
    @State private var showsQRLogin = false
    @State private var showsManualLogin = false
    @State private var didRestore = false
    // [TG-TABBAR 2026-09-30] 这里原有一段 [TABBAR-NATIVE 2026-09-28] 说明「显隐改由
    // 目的地页面声明（.toolbar(.hidden, for:.tabBar)），UIKit 在转场里托管」——
    // 该机制本身已随系统栏一并退役（自绘栏是一级页内件，push 天然覆盖；藏显链的
    // 失序病史见 AIChatView 墓碑注释）。
    /// 身份胶囊 → 资料页（zoom 转场对）。NS 挂在胶囊头像的
    /// matchedTransitionSource 上，SoulProfileHub 的 sheet 内容消费同一对。
    @Namespace private var soulProfileNS
    @State private var showsSoulProfile = false
    /// 胶囊名字 —— 与 RemoteRootView 同一真源（SOUL.md name，回退 Moonveil）。
    @State private var soulName: String = {
        let n = SoulStore.cachedMetadata.name
        return n.isEmpty ? "Kite" : n
    }()
    /// B12-GATEFLASH: the full-screen login is the 首启 entry, not a permanent lid on
    /// the remote tab. Once the user leaves it (直接用本地 AI / 关闭), the tab's
    /// 未登录三态卡 takes over and its 去登录 button re-raises the cover — which is
    /// what U1 §6 asked for and what made the old always-on gate unreachable.
    /// B12-GATEFLASH 持久化：这次关过盖（选了本地 AI / 关闭），下次启动不再弹；
    /// 终端卡"点按登录"（onOpenLogin）会清掉重唤。key 命名跟随 aa.* 惯例。
    @AppStorage("aa.remote.login-cover-dismissed") private var loginCoverDismissed = false

    /// [TG-TABBAR] 三树保活挂载表（替代 TabView 的"首次访问才建树、此后保活"
    /// 语义）。初值含 .local（恒挂）与启动落点（lastTab 记忆可能是 .remote/
    /// .works）。remote 另有 seenRemote 门控（B12，在 tabContent 内）；works
    /// 走本表。图标资产与栅格化缓存随 Tab 构建器迁入 ModeTabBar.swift。
    @State private var mountedModes: Set<AppSourceMode> = [.local, RootTabRouter.shared.mode]

    /// [切页转场 v2 2026-09-30] 宽屏（iPad / 横屏 Max）档 TG 不播切页动画
    /// （TabBarController.swift:283-285 widthClass == .regular → animated = false），
    /// 此处同守（溶解淡入不播；缩放侧由 TreeSwitchZoom 内部同款守卫）。
    /// 溶解窗口的「上一棵树」状态在 RootTabRouter（与 mode 同步落定，见其
    /// didSet 注释——视图侧 onChange 写入会有次序不确定导致的旧树闪隐）。
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// [切页转场 v2] 淡入曲线（TG :319-321 数字化：0.1s，CA 默认曲线取 easeOut 近似）。
    /// 缩放曲线与起点缩放随 v2 迁入 TreeSwitchZoom（本文件末尾）；原
    /// switchStartScale / switchScaleAnimation 在此退役——挂在树容器上会破坏
    /// 栈内 safeAreaInset 求值，装机实锤见 tabTree 注释。
    private static let switchAlphaAnimation: Animation = .easeOut(duration: 0.1)

    var body: some View {
        // [TG-TABBAR 2026-09-30] TabView 退役（「系统栏 + 藏显」病根，pp 拍板
        // 「用tg的自绘」）→ ZStack 三树保活：每棵树自带 NavigationStack，自绘栏
        // （ModeTabBar）挂各树 root 页——push 整页覆盖含栏、划回原位揭示。
        // [切页转场 2026-09-30] 原「瞬切」（pp 2026-09-16 的旧拍板）按 pp 装机
        // 反馈修正为 TG 转场（TabBarController.swift:279-330 数字化）：新页
        // 0.1s 淡入 + 从 (高−3)/高 弹簧放到 1（0.15s、延迟 0.1s）；旧页同缩并在
        // 溶解窗口内留于下层（见 tabTree 注释）。
        ZStack {
            tabTree(.local)
            tabTree(.remote)
            tabTree(.works)
        }
        .onChange(of: router.mode) { old, new in
            mountedModes.insert(new)   // [TG-TABBAR] 保活表记账（访问过不卸载）
            NavTrace.log("MODE \(old)→\(new) trig=\(NavTrace.trigger)+\(NavTrace.age)")
        }
        // [TG-TABBAR] 原 TabView 级 .tint(.primary)（治系统栏选中黑）随系统栏
        // 退役；各树与各 sheet 的 tint 均为自带显式声明，不受影响。
        // 原 [TABBAR-NATIVE 2026-09-28] 藏显机制（toolbar(.hidden, for:.tabBar)）
        // 已整批退役：系统栏不存在，ModeTabBar 是一级页内件，push 天然覆盖。
        // Q2: 胶囊 → 资料页 zoom 转场。fullScreenCover + navigationTransition(.zoom)
        // 配对（Apple 文档标准形状；zoom 接管默认转场）。pp 2026-09-27：改全屏。
        .fullScreenCover(isPresented: $showsSoulProfile) {
            SoulProfileHub()
                .navigationTransition(.zoom(sourceID: SoulProfileHub.zoomSourceID, in: soulProfileNS))
                // [TG-TABBAR] 显式钉 App 蓝（原 [TAB-TINT] 的"盖回"使命已随壳层
                // .tint(.primary) 退役；保留为显式声明，等同默认 accent）。
                .tint(Color("AccentColor"))
        }
        .onReceive(NotificationCenter.default.publisher(for: .soulMdChanged)) { _ in
            let n = SoulStore.cachedMetadata.name
            soulName = n.isEmpty ? "Kite" : n
        }
        // B16: ONE settings presentation for both tabs, hosted by the always-visible
        // shell. On the Remote tab ContentView is alive but invisible, and "can an
        // invisible host present a sheet" is not something this should have to prove.
        // `showTerminal` is vestigial inside SettingsSheet (never read), so a constant
        // binding keeps the upstream signature and behaviour intact.
        .sheet(isPresented: $router.showSettings) {
            SettingsSheet(showTerminal: .constant(false))
                // [TG-TABBAR] 同上：显式钉 App 蓝（原 [TAB-TINT] 用途已退役）。
                .tint(Color("AccentColor"))
        }
        .task {
            guard !didRestore else { return }
            didRestore = true
            _ = remoteService.restoreSession()   // official restore; silent no-op if absent
        }
        .fullScreenCover(isPresented: needsLoginGate) {
            NavigationStack {
                ServiceEntryView(
                    service: remoteService,
                    onManualLogin: { showsManualLogin = true },
                    onQRCodeLogin: { showsQRLogin = true },
                    onLocalEntry: {
                        // [FIRST-RUN 2026-09-27] 点本地入口要真正关掉登录页，
                        // 否则 showsLoginGate 仍为 true 盖子关不上。
                        loginCoverDismissed = true
                        router.route(to: .local)
                    }
                )
            }
            // [AA-MONO 2026-09-27 pp] AA 登录流程是官方黑白设计（按钮原样黑色）。
            // 之前为底栏选中变黑加了 TabView 级 .tint(.primary)，批量「盖回 App 蓝」
            // 时把本页也一起染蓝了（pp：「原本是黑色」）。这里钉回 .primary：
            // AppGlassButton.regular 自身无色、跟随环境 tint，黑 = 本来的样子；
            // 里层两个 sheet（扫码/手动登录）一并跟随。
            .tint(.primary)
            .sheet(isPresented: $showsQRLogin) {
                QRCodeLoginView(
                    service: remoteService,
                    onDashboardRequested: { /* state flips .ready → gate closes itself */ }
                )
            }
            .sheet(isPresented: $showsManualLogin) {
                ManualLoginView(service: remoteService)
            }
        }
    }

    /// [TG-TABBAR] 单棵 tab 树壳：挂载门控 + 当前性（opacity/命中/无障碍）。
    /// 保活语义 = 原 TabView 的"首次访问才建树、此后保持"（B16：非当前树仍在
    /// 树上，只是不可见/不可点/不进朗读）。自绘栏挂在各树 NavigationStack 的
    /// root 页内（ContentView/RemoteRootView/WorksListView 三处 safeAreaInset），
    /// 不在本层——push 才能整页盖住含栏的 root 页。
    /// [切页转场 v2 2026-09-30] v1（a13c765）在本容器上挂 .scaleEffect，装机实锤
    /// 打坏栈内 safeAreaInset 求值：root-list 底安全区切页后从 98（栏 64 + Home 34）
    /// 掉到 64、且 64↔98 瞬跳（build 430 日志；旧瞬切版同类操作恒 98）——整页上下
    /// 抖 + 栏被裁出屏幕。修复 = 缩放迁入各树栈内内容层（TreeSwitchZoom，见本文件
    /// 末尾；社区同款结论：缩放/位移修饰符必须作用在栈内内容上，挂栈外包裹层会让
    /// 内容丢 safe area）。本容器只保留 v1 装机中除缩放外未见异常的部分：zIndex
    /// 置顶 + 新页淡入 0.1s（TG :319-321）+ previousMode 溶解窗口（旧页留下层，
    /// 窗口长见 RootTabRouter 注释：v2 收口为 120ms = TG「新页 alpha 完成即 commit」
    /// 的数字化——旧页在 TG 保持全不透明、到点硬移除，不淡出）——注意此三者与
    /// v1 缩放同批（a13c765）引入，瞬切版从未跑过；若装机仍异常，下一手候选 =
    /// 拆溶解窗口 / geometryGroup。
    /// 宽屏 regular 不播（:283-285）。缩放纪律：v2 起栏挂在缩放修饰符之外侧
    /// （TreeSwitchZoom 挂在 safeAreaInset 内侧）——栏不随缩放，TG「栏独立层不缩」
    /// 的 parity 偏差随之消除。
    @ViewBuilder
    private func tabTree(_ mode: AppSourceMode) -> some View {
        let isCurrent = router.mode == mode
        let isDissolvingUnder = router.previousMode == mode && !isCurrent
        let skipSwitchAnimation = horizontalSizeClass == .regular
        Group {
            switch mode {
            case .local:
                tabContent(.local)
            case .remote:
                tabContent(.remote)   // seenRemote 懒挂载门控原样在 tabContent 内
            case .works:
                if mountedModes.contains(.works) || isCurrent {
                    tabContent(.works)
                }
            case .compose:
                // ACTION 位：mode 永不变为 .compose（ModeTabBar.commit 拦截）。
                EmptyView()
            }
        }
        .opacity(isCurrent || isDissolvingUnder ? 1 : 0)
        .animation(skipSwitchAnimation || !isCurrent ? nil : Self.switchAlphaAnimation, value: isCurrent)
        .zIndex(isCurrent ? 1 : 0)
        .allowsHitTesting(isCurrent)
        .accessibilityHidden(!isCurrent)
    }

    /// [NATIVE-TABS] 每个 tab 的根内容。本机 = upstream ContentView 本体（带它的
    /// 原生导航栏：≡ 齿轮 / principal 身份胶囊 / toolbar）；远端 = RemoteRootView
    ///（自带 NavigationStack）；构件影音 = WorksListView（自带 NavigationStack）。
    /// 远端沿用 seenRemote 懒挂载语义（B12：首次访问才建树，此后保活）。
    @ViewBuilder
    private func tabContent(_ mode: AppSourceMode) -> some View {
        switch mode {
        case .local:
            ContentView(soulProfileNS: soulProfileNS)
        case .remote:
            if router.seenRemote {
                if showsLoginGate {
                    // The cover owns the screen — plain surface underneath, so
                    // nothing can flash during presentation (device report: one
                    // frame of the guide card before the cover slid up).
                    Color(UIColor.systemBackground)
                } else {
                    RemoteRootView(
                        service: remoteService,
                        onOpenLogin: { loginCoverDismissed = false }  // 卡片一键回跳登录
                    )
                }
            } else {
                // 未 seen 时给个空底（选择远端即触发 seenRemote 挂出真树；
                // 自绘栏随树挂载，ModeTabBar 在各树 root 页内）。
                Color(UIColor.systemBackground)
            }
        case .works:
            WorksListView(soulProfileNS: soulProfileNS)
        case .compose:
            // ACTION 位：mode 永不变为 .compose（ModeTabBar.commit 拦截），永不渲染。
            EmptyView()
        }
    }

    // [TG-TABBAR] 原 tabSelection binding / tabLabel 随 TabView 退役——等价的
    // 拦截逻辑 + NavTrace 打点已逐字迁入 ModeTabBar.commit（compose 仍是 ACTION
    // 位：永不选中，点击 = QuickActionRouter 新建信号，D4 红线不破）；a11y 文案
    // 迁至栏 item 的 accessibilityLabel。

    /// 远程 tab 且从未配置（.idle）或正在配对（.pairing）、且没关过盖 → 盖登录页。
    // [TABBAR-NATIVE 2026-09-28] syncTabBarVisibility / scheduleTabBarHeal /
    // healTabBarIfDrift / findUITabBar 随状态机制一并退役（见文件头同注释）。

    /// 连接断了（.degraded）不弹盖：走列表页"无设备+提醒连接"（pp 2026-09-20）。
    /// .pairing 必须保留：扫码 sheet 寄生在盖子上，条件收掉会掐死配对流程。
    private var showsLoginGate: Bool {
        guard !loginCoverDismissed else { return false }
        let remoteIdle = remoteService.state == .idle || remoteService.state == .pairing
        // [FIRST-RUN 2026-09-27] 初次打开：本地无服务商 + 远端未连接 → 全屏登录页，
        // 不带 tab。三步引导是点了登录页"本地入口"之后才出现的，不混为一谈。
        let noLocalProviders = ProviderConfigStore.shared.instances.isEmpty
        if noLocalProviders && remoteIdle {
            return true
        }
        // 已有配置时：仅 remote tab 未连接才弹。
        guard router.mode == .remote else { return false }
        return remoteIdle
    }

    private var needsLoginGate: Binding<Bool> {
        Binding(
            get: { showsLoginGate },
            set: { dismissed in
                guard !dismissed, remoteService.state != .ready else { return }
                // Leaving the cover (JO-6 本地入口 / 关闭) arms the tab's empty-state
                // card for the next time the user lands on Remote.
                loginCoverDismissed = true
                router.route(to: .local)
            }
        )
    }
}

// MARK: - [切页转场 v2] 树内容缩放（栈内挂点）

/// [切页转场 v2 2026-09-30] 切页缩放：挂在**各树 NavigationStack 的 root 内容上**、
/// `safeAreaInset(栏)` **内侧**（三个挂点：ContentView.stackLayout / RemoteRootView /
/// WorksListView）。非当前树恒为起点缩放（隐藏不可见），成为当前树时弹簧到 1
/// （TG TabBarController.swift:287-289 数字化：起点 = (视图高−3)/视图高 ≈ 0.9965，
/// 0.15s 弹簧、延迟 0.1s；取不到视图高度用 TG 回退值 0.998）。宽屏 regular 恒 1
/// （TG :283-285 不播）。
///
/// ⚠️ 挂点纪律（v1 装机实锤，勿动）：修饰符必须在**栈内内容**上——v1 曾把
/// `.scaleEffect` 挂在树容器（NavigationStack 外层），切页后 root-list 底安全区
/// 从 98 掉到 64 且 64↔98 瞬跳（栏与整页内容上下跳 34pt = pp「整个页面都在抖 /
/// 栏被截一半」，build 430 日志）。社区同款结论：缩放/位移必须作用在栈内内容上
/// （StackOverflow 77169874），挂栈外包裹层会让栈内内容丢 safe area。
/// 由此栏也天然不参与缩放（TG 栏独立层不缩的 parity 偏差消除）。
///
/// 已知取舍：缩放只覆盖各树 root 内容——若该树停在 push 的页面上切页，不播缩放
/// （目录页绝大多数切页场景在 root；待装机观感再评估是否扩到 push 目的地）。
struct TreeSwitchZoom: ViewModifier {
    let mode: AppSourceMode

    @ObservedObject private var router = RootTabRouter.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// TG :287-289：起点缩放 = (视图高−3)/视图高（缩 3pt）；取不到用回退值 0.998。
    /// 树全屏 ≈ 当前 key window 高。
    private var startScale: CGFloat {
        let height = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.bounds.height ?? 0
        guard height > 0 else { return 0.998 }
        return (height - 3.0) / height
    }

    private var scale: CGFloat {
        if horizontalSizeClass == .regular { return 1.0 }
        return router.mode == mode ? 1.0 : startScale
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            // TG :319-321：新页 0.15s 弹簧、延迟 0.1s。旧页 TG 真值为 :297
            // 「1→起点缩放、0.12s 弹簧、无延迟」——本仓共用新页曲线（0.15s、延迟
            // 0.1s）为 v1 起已知近似：差异段（0~0.1s 旧页不动、0.12~0.25s 缩量残余）
            // 全程被新页 0.1s 淡入 + 旧页移除窗口（120ms）遮蔽，量级 ≤2px，不可辨；
            // 如装机可察再拆方向曲线。宽屏不播（nil）。
            .animation(
                horizontalSizeClass == .regular ? nil : Self.switchScaleAnimation,
                value: router.mode
            )
    }

    private static let switchScaleAnimation: Animation = .spring(response: 0.15, dampingFraction: 1.0).delay(0.1)
}

extension View {
    /// 见 `TreeSwitchZoom`（切页缩放·栈内挂点纪律）。
    func treeSwitchZoom(_ mode: AppSourceMode) -> some View {
        modifier(TreeSwitchZoom(mode: mode))
    }
}

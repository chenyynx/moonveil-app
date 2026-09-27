// RootModeTabsView.swift — the single fork point (D4 §2) + 首启入口终案接线:
// 未登录且落在远程 tab → AA 官方登录页全屏盖（扫码/手动/本地三颗胶囊 CTA）；
// 登录成功 → 远程 tab；本地入口 → 本机 tab；lastTab 记忆（RootTabRouter）。
// 恢复：官方 restoreSession 语义（UserDefaults server + keychain token）。
//
// [NATIVE-TABS 2026-09-26] 底部导航整体换原生 TabView（pp「底部让你用ios原生tab
// 你写的是啥玩意」）：三 tab = 本机 / 远程 / 构件影音，系统 tab 栏样式全托管；
// 自绘 BottomModeDock 删除。顶栏身份胶囊迁入本机页导航栏 principal 位（仍是
// pp 拍板保留的需求件），zoom 转场照旧。≡ 齿轮换原生 toolbar 按钮。
//
// [NATIVE-TABS 2026-09-26pm] pp 按 Muse 对齐：纯图标 tab（Lucide 20pt 黑）；
// 搜索原先是 TabRole.search 独立圆形钮，pp 随后「搜索放右上角」——改为各 tab 页
// 导航栏右上角 🔍（SearchEntry.swift）；独立圆钮改给新建会话 ＋（借 search role
// 的外观）。底栏 = 3 tab 胶囊 + 右侧分离圆钮。

import SwiftUI
import UIKit

@MainActor
struct RootModeTabsView: View {
    @StateObject private var router = RootTabRouter.shared
    @StateObject private var remoteService = RemoteService()
    @State private var showsQRLogin = false
    @State private var showsManualLogin = false
    @State private var didRestore = false
    /// [TABBAR-STATE-DRIVEN 2026-09-27] 底栏显隐的唯一真相源：进聊天页藏。
    /// 由 syncTabBarVisibility() 从 router.localAtRoot / remoteChatPushed /
    /// router.mode 纯函数推导，无动画——push 时聊天页直接盖住，pop 时直接露出
    ///（转场里的 toolbar 显隐在 iOS 26 下卡顿、偶发 trap、还会卡死在列表页）。
    @State private var tabBarHidden = false
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

    /// [NATIVE-TABS] 各 tab 的 Tabler 图标（aa-Tabler- 前缀资产，模板渲染），
    /// 纯图标 tab（无文字），22pt 对齐 Muse，黑色。a11y 朗读文本由 tabLabel 提供。
    /// 2026-09-27：pp 从 Tabler 库四组候选中钦定（tab1 message-circle /
    /// tab2 cloud / tab3 puzzle / tab4 edit）。
    private static let tabIcon: [AppSourceMode: String] = [
        .local: "aa-Tabler-MessageCircle",
        .remote: "aa-Tabler-Cloud",
        .works: "aa-Tabler-Puzzle",
        .compose: "aa-Tabler-Edit",
    ]

    init() {
        Self.configureTabBarAppearance()
    }

    /// [NATIVE-TABS] tab 栏外观：Muse 式黑图标（深浅色自适应）。
    private static func configureTabBarAppearance() {
        let bar = UITabBar.appearance()
        bar.tintColor = .label
        bar.unselectedItemTintColor = .label
    }

    /// Lucide SVG 资产是 24pt viewBox；Muse 的 tab 图标约 19pt，这里栅格化到
    /// 27pt 并保持 template 渲染；颜色由调用处的 .foregroundStyle 按选中态给
    ///（TabView 级 .tint 会透进 tab 内容染黑 accent——pp 2026-09-27）。
    /// 2026-09-27：22→27 —— Tabler 2px 描边在 22pt 框里光学只有约 18pt，
    /// 在 iOS 26 浮动 pill 里显小；27pt 光学约 22.5pt，描边约 2.25px。
    ///
    /// [FIX-tab-icon-flash] 栅格化结果按 asset 缓存：切 tab 时 router.mode 变
    /// 化会重建 4 个 label，若每次都 new 出 UIImage，底栏 image view 会闪一下
    /// 重绘。复用同一张图后，切 tab 只变 .foregroundStyle 颜色，不换图，不闪。
    /// （struct 是 @MainActor，body 内调用，无线程问题。）
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

    /// tab 图标颜色：选中 .primary（浅色黑/深色白），未选中 .secondary 灰。
    /// .compose 是新建动作钮（永不选中），常黑。
    private static func tabIconColor(_ mode: AppSourceMode, selected: AppSourceMode) -> Color {
        if mode == .compose { return .primary }
        return mode == selected ? .primary : .secondary
    }

    var body: some View {
        TabView(selection: tabSelection) {
            ForEach(AppSourceMode.allCases) { mode in
                // .compose 借 TabRole.search 的独立圆形外观（iOS 26 原生唯一能让
                // tab 脱离胶囊的 role；pp 2026-09-26「新会话按钮就改到刚刚tab分离
                // 在右边的圆按钮」）。语义仍是新建：点它走 tabSelection 拦截发
                // 新会话信号，不切页；a11y 朗读的是 tabLabel 的 "New Chat"。
                Tab(value: mode, role: mode == .compose ? .search : nil) {
                    tabContent(mode)
                        // [FIX-tab-zoom] iOS 26 TabView 切 tab 自带缩放过渡
                        //（页面内容轻微放大缩小、组件跟着浮）。identity = 无过渡，
                        // 瞬切（延续 pp 2026-09-16「不带系统 crossfade」的拍板）。
                        // 只作用于内容页，底栏选中 pill 的滑动不受影响。
                        .transition(.identity)
                        // [TAB-TINT] 盖回 App 蓝：TabView 级 .tint(.primary) 只管
                        // 底栏选中黑，内容里的 accent 蓝不能丢。
                        .tint(Color("AccentColor"))
                        // [TABBAR-STATE-DRIVEN 2026-09-27] 底栏显隐纯状态驱动
                        //（进聊天页藏），无动画——push 时新页面直接盖住。
                        // 必须挂在 Tab 内容里侧——挂在 TabView 本体上 iOS 26 不认，
                        // 底栏藏不住。不回 AIChatView.body 的逐项 modifier：它在
                        // 转场协调里动画卡顿、偶发 trap（build 359/363 闪退）、
                        // 隐藏态还会卡死在聊天列表页。
                        .toolbar(tabBarHidden ? .hidden : .visible, for: .tabBar)
                } label: {
                    Self.tabImage(Self.tabIcon[mode] ?? "aa-Circle")
                        // [NATIVE-TABS] 未选中灰图标走这里；选中态黑由 TabView 级
                        // .tint(.primary) 接管（iOS 26 浮动 tab 的选中 tint 会盖掉
                        // label 的 foregroundStyle，UITabBar.appearance 也不吃）。
                        .foregroundStyle(Self.tabIconColor(mode, selected: router.mode))
                        .accessibilityLabel(tabLabel(mode))
                }
            }
        }
        // pp 2026-09-16 拍板延续：tap/横滑切 tab 内容层瞬切，不带系统 crossfade。
        .animation(nil, value: router.mode)
        // [TAB-TINT] 选中 tab 黑图标：iOS 26 浮动 tab 的选中态会被系统 tint
        //（蓝）盖掉 label 上的 foregroundStyle，只能 TabView 级 .tint(.primary)。
        // tint 是 environment，会透进 tab 内容和本层 sheet——下面 4 处用
        // Color("AccentColor")（读资产，不受 tint 影响）把 App 蓝盖回去。
        .tint(.primary)
        // [TABBAR-STATE-DRIVEN] 底栏显隐的 .toolbar 修饰已移到各 Tab 内容里侧
        //（挂 TabView 本体 iOS 26 不认）；状态源 tabBarHidden 不变。
        .onAppear { syncTabBarVisibility() }
        .onChange(of: router.localAtRoot) { _, _ in syncTabBarVisibility() }
        .onChange(of: router.remoteChatPushed) { _, _ in syncTabBarVisibility() }
        .onChange(of: router.mode) { _, _ in syncTabBarVisibility() }
        // Q2: 胶囊 → 资料页 zoom 转场。fullScreenCover + navigationTransition(.zoom)
        // 配对（Apple 文档标准形状；zoom 接管默认转场）。pp 2026-09-27：改全屏。
        .fullScreenCover(isPresented: $showsSoulProfile) {
            SoulProfileHub()
                .navigationTransition(.zoom(sourceID: SoulProfileHub.zoomSourceID, in: soulProfileNS))
                // [TAB-TINT] 本层 sheet 挂在 TabView 下，会吃到 .tint(.primary)，
                // 盖回 App 蓝。
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
                // [TAB-TINT] 同上，盖回 App 蓝。
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
                    onLocalEntry: { router.route(to: .local) }
                )
            }
            // [TAB-TINT] 盖回 App 蓝（挂在 NavigationStack 上，里层两个 sheet 跟着吃到）。
            .tint(Color("AccentColor"))
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
                // 未 seen 时给个空底，tab 栏照常渲染（选择远端即触发 seenRemote）。
                Color(UIColor.systemBackground)
            }
        case .works:
            WorksListView(soulProfileNS: soulProfileNS)
        case .compose:
            // ACTION tab：mode 永不变为 .compose（tabSelection 写拦截），这里永不渲染。
            EmptyView()
        }
    }

    /// TabView selection 双向绑定：读 = router.mode，写 = route(to:)（didSet 持久化
    /// + seenRemote 挂钩全部走 router 单一通道，D4 红线不破）。
    /// `.compose` 是 ACTION tab（新会话按钮）：拦截，不写 router —— tab 停在原页，
    /// QuickActionRouter 发新会话信号（ContentView 接到后切回本机页并打开新会话）。
    private var tabSelection: Binding<AppSourceMode> {
        Binding(
            get: { router.mode },
            set: {
                if $0 == .compose {
                    QuickActionRouter.shared.requestNewChat()
                } else {
                    router.route(to: $0)
                }
            }
        )
    }

    private func tabLabel(_ mode: AppSourceMode) -> String {
        switch mode {
        case .local: return String(localized: "Local")
        case .remote: return String(localized: "Remote")
        case .works: return String(localized: "Works & Media")
        case .compose: return String(localized: "New Chat")
        }
    }

    /// 远程 tab 且从未配置（.idle）或正在配对（.pairing）、且没关过盖 → 盖登录页。
    /// [TABBAR-STATE-DRIVEN 2026-09-27] 底栏显隐纯函数：进聊天页藏。
    /// 本机页看 localAtRoot（push 聊天即非根；iPad 选中会话进 detail 也非根，
    /// 与旧 modifier 行为一致），远端页看 remoteChatPushed（设备详情页不藏，
    /// 延续历史行为）。mode 门控防止把旧 tab 的隐藏态带到新 tab。
    /// [2026-09-27] 不做显隐动画：push 时聊天页滑进来直接盖住 tab 栏，
    /// pop 时列表页滑回来直接露出——跟系统原生一致。之前 0.22s/0.35s 的
    /// 单独动画都是画蛇添足，体感慢。
    private func syncTabBarVisibility() {
        let hidden = (router.mode == .local && !router.localAtRoot)
            || (router.mode == .remote && router.remoteChatPushed)
        tabBarHidden = hidden
    }

    /// 连接断了（.degraded）不弹盖：走列表页"无设备+提醒连接"（pp 2026-09-20）。
    /// .pairing 必须保留：扫码 sheet 寄生在盖子上，条件收掉会掐死配对流程。
    private var showsLoginGate: Bool {
        guard router.mode == .remote, !loginCoverDismissed else { return false }
        return remoteService.state == .idle || remoteService.state == .pairing
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

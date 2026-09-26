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
    /// 身份胶囊 → 资料页（zoom 转场对）。NS 挂在胶囊头像的
    /// matchedTransitionSource 上，SoulProfileHub 的 sheet 内容消费同一对。
    @Namespace private var soulProfileNS
    @State private var showsSoulProfile = false
    /// 胶囊名字 —— 与 RemoteRootView 同一真源（SOUL.md name，回退 Moonveil）。
    @State private var soulName: String = {
        let n = SoulStore.cachedMetadata.name
        return n.isEmpty ? "Moonveil" : n
    }()
    /// B12-GATEFLASH: the full-screen login is the 首启 entry, not a permanent lid on
    /// the remote tab. Once the user leaves it (直接用本地 AI / 关闭), the tab's
    /// 未登录三态卡 takes over and its 去登录 button re-raises the cover — which is
    /// what U1 §6 asked for and what made the old always-on gate unreachable.
    @State private var loginCoverDismissed = false

    /// [NATIVE-TABS] 各 tab 的 Lucide 图标（aa- 前缀资产，模板渲染），纯图标
    /// tab（无文字），22pt 对齐 Muse，黑色。a11y 朗读文本由 tabLabel 提供。
    private static let tabIcon: [AppSourceMode: String] = [
        .local: "aa-MessagesSquare",
        .remote: "aa-Cloud",
        .works: "aa-Blocks",
        .compose: "aa-SquarePen",
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
    /// 22pt 并保持 template 渲染，tab 栏 tint 照常生效。
    private static func tabImage(_ asset: String) -> Image {
        let side: CGFloat = 22
        let ui = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side)
        ).image { _ in
            UIImage(named: asset)?.draw(
                in: CGRect(origin: .zero, size: CGSize(width: side, height: side))
            )
        }
        return Image(uiImage: ui.withRenderingMode(.alwaysTemplate))
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
                } label: {
                    Self.tabImage(Self.tabIcon[mode] ?? "aa-Circle")
                        .accessibilityLabel(tabLabel(mode))
                }
            }
        }
        // pp 2026-09-16 拍板延续：tap/横滑切 tab 内容层瞬切，不带系统 crossfade。
        .animation(nil, value: router.mode)
        // [NATIVE-TABS] 选中态黑图标：iOS 26 新浮动 Tab 不吃 UITabBar.appearance，
        // 用 SwiftUI tint；.primary 深浅色自适应（浅色黑/深色白）。
        .tint(.primary)
        // Q2: 胶囊 → 资料页 zoom 转场。sheet + navigationTransition(.zoom) 配对
        // （Apple 文档标准形状；zoom 接管默认上弹转场）。
        .sheet(isPresented: $showsSoulProfile) {
            SoulProfileHub()
                .navigationTransition(.zoom(sourceID: SoulProfileHub.zoomSourceID, in: soulProfileNS))
        }
        .onReceive(NotificationCenter.default.publisher(for: .soulMdChanged)) { _ in
            let n = SoulStore.cachedMetadata.name
            soulName = n.isEmpty ? "Moonveil" : n
        }
        // B16: ONE settings presentation for both tabs, hosted by the always-visible
        // shell. On the Remote tab ContentView is alive but invisible, and "can an
        // invisible host present a sheet" is not something this should have to prove.
        // `showTerminal` is vestigial inside SettingsSheet (never read), so a constant
        // binding keeps the upstream signature and behaviour intact.
        .sheet(isPresented: $router.showSettings) {
            SettingsSheet(showTerminal: .constant(false))
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

    /// 远程 tab 且未登录且本次启动还没离开过登录盖 → 盖登录页；登录成功(ready)自动收起。
    private var showsLoginGate: Bool {
        router.mode == .remote && remoteService.state != .ready && !loginCoverDismissed
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

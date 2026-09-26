// RootModeTabsView.swift — the single fork point (D4 §2) + 首启入口终案接线:
// 未登录且落在远程 tab → AA 官方登录页全屏盖（扫码/手动/本地三颗胶囊 CTA）；
// 登录成功 → 远程 tab；本地入口 → 本机 tab；lastTab 记忆（RootTabRouter）。
// 恢复：官方 restoreSession 语义（UserDefaults server + keychain token）。
//
// [NATIVE-TABS 2026-09-26] 底部导航整体换原生 TabView（pp「底部让你用ios原生tab
// 你写的是啥玩意」）：三 tab = 本机 / 远程 / 构件影音，系统 tab 栏样式全托管；
// 自绘 BottomModeDock 删除。顶栏身份胶囊迁入本机页导航栏 principal 位（仍是
// pp 拍板保留的需求件），zoom 转场照旧。≡ 齿轮换原生 toolbar 按钮。

import SwiftUI
import UIKit

/// [BOTTOM-BAR-FENCE] 底部操作栏在窗口坐标里的顶边 —— 由 fabRow 的 GeometryReader
/// 上报（.global）。页切手势在 global 坐标下用它精确排除底部操作栏区域。
///
/// `nonisolated(unsafe)`：读写都发生在主线程 UI 路径（布局上报 / 手势判定），与
/// 仓内既有全局共享状态同一模式；ContentView 是 nonisolated struct，这里若加
/// @MainActor 隔离会在其 body / 手势闭包里访问报错。
enum BottomBarFence {
    nonisolated(unsafe) static var topY: CGFloat = 0
}

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

    /// [NATIVE-TABS] 系统各 tab 的 SF Symbol。本机 = 双气泡（对话身份），
    /// 远程 = 终端，构件影音 = 2×2 方块。label 进 xcstrings（tab 无文字诉求由
    /// `.labelStyle(.iconOnly)` 落实，a11y 仍朗读）。
    private static let tabIcon: [AppSourceMode: String] = [
        .local: "bubble.left.and.text.bubble.right",
        .remote: "terminal",
        .works: "square.grid.2x2",
    ]

    var body: some View {
        TabView(selection: tabSelection) {
            ForEach(AppSourceMode.allCases) { mode in
                tabContent(mode)
                    .tabItem {
                        Image(systemName: Self.tabIcon[mode] ?? "circle")
                        Text(tabLabel(mode))
                    }
                    .tag(mode)
            }
        }
        // pp 2026-09-16 拍板延续：tap/横滑切 tab 内容层瞬切，不带系统 crossfade。
        .animation(nil, value: router.mode)
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
        .simultaneousGesture(pageSwipe)   // B12: swipe the page to switch 本机 ⟷ Remote
        .onChange(of: swipeInFlight) { inFlight in
            if !inFlight { resetSwipeState() }   // end AND cancellation both land here
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
            WorksListView()
        }
    }

    /// TabView selection 双向绑定：读 = router.mode，写 = route(to:)（didSet 持久化
    /// + seenRemote 挂钩全部走 router 单一通道，D4 红线不破）。
    private var tabSelection: Binding<AppSourceMode> {
        Binding(
            get: { router.mode },
            set: { router.route(to: $0) }
        )
    }

    private func tabLabel(_ mode: AppSourceMode) -> String {
        switch mode {
        case .local: return String(localized: "Local")
        case .remote: return String(localized: "Remote")
        case .works: return String(localized: "Works & Media")
        }
    }

    /// Page-level horizontal swipe = the same mode switch as the tab bar.
    /// 左滑 → Remote，右滑 → 本机. works 页禁用（点切即可）。
    ///
    /// B16-SWIPE-DIR (2026-09-17, pp「左右滑动还是容易滑成上下」→ 业界调研后拍板动手):
    /// the verdict now follows the UIKit playbook that keeps row-swipe actions and
    /// vertical scrolling coexisting in every list app:
    ///   1. SIMULTANEOUS gesture — a plain `.gesture` gets CANCELLED mid-pan once the
    ///      List's scroll machinery claims the touch (B13-SWIPEFIX-2 already noted
    ///      this); no verdict survives that. `.simultaneousGesture` tracks in parallel
    ///      to the very last event.
    ///   2. VELOCITY, not accumulated translation — translation is polluted by the
    ///      thumb's natural arc (横滑时 dy 也在涨), which is exactly why flat-looking
    ///      swipes kept reading as vertical. SwiftUI has no bare velocity;
    ///      `predictedEndTranslation - translation` IS the velocity vector (scaled).
    ///   3. ONE verdict per gesture + latched/rejected states — horizontal wins →
    ///      armed (page switches, list frozen via scrollDisabled); vertical wins →
    ///      rejected, this gesture never touches the page again and the list scrolls
    ///      untouched. Ambiguous diagonals are forced at 24pt onto the dominant axis.
    private var pageSwipe: some Gesture {
        // [BOTTOM-BAR-FENCE] global 坐标：起点与 BottomBarFence（窗口坐标）可直接比较。
        DragGesture(minimumDistance: 12, coordinateSpace: .global)   // pp 2026-09-16: directionLockDistance = 12pt
            .updating($swipeInFlight) { _, state, _ in state = true }
            .onChanged { value in
                // works 页禁横滑页切（三段下点切即可）。
                guard router.mode != .works else { return }
                if swipeRejected || swipeArmed { return }   // verdict is final per gesture

                let dx = value.translation.width
                let dy = value.translation.height
                let start = value.startLocation

                // [B16-SWIPE-SCOPE] 横滑切页只属于两条线各自的根列表页——
                // 本机 push 进聊天页(localAtRoot == false) / 远端 push 进设备详情页
                // (remoteAtRoot == false) 时整个手势直接退出；push 页内的横滑无消费
                // 场景，误触反而打断阅读。
                if router.mode == .remote {
                    guard router.remoteAtRoot else { return }
                } else {
                    guard router.localAtRoot else { return }
                }
                guard start.y > Self.listAreaTop else { return }
                // [BOTTOM-BAR-FENCE] pp 2026-09-20「滑动底部胶囊/搜索栏也会触发切页」：
                // 底部操作栏整体退出切页判定。优先用 fabRow 实际上报的顶边（精确）；
                // 未上报时退回条带推算。
                let fenceTop = BottomBarFence.topY > 0
                    ? BottomBarFence.topY - Self.bottomBarFenceMargin
                    : Self.screenHeight - Self.bottomBarZoneHeight
                guard start.y < fenceTop else { return }
                let inBubbleZone = start.y > Self.screenHeight - Self.bubbleZoneHeight
                    && start.x > Self.screenWidth - Self.bubbleZoneWidth
                guard !inBubbleZone else { return }

                let travel = max(abs(dx), abs(dy))
                guard travel >= Self.directionDecideDistance else { return }

                // Velocity vector = predicted remaining travel: intent, not arc history.
                let vx = abs(value.predictedEndTranslation.width - dx)
                let vy = abs(value.predictedEndTranslation.height - dy)

                if abs(vx) > abs(vy) * Self.velocityRatio
                    || (travel >= Self.directionForceDistance && vx >= vy) {
                    // Horizontal wins → switch once, freeze the list, latch until lift.
                    swipeArmed = true
                    router.pageSwipeArmed = true
                    let target: AppSourceMode = dx < 0 ? .remote : .local
                    guard target != router.mode else { return }
                    Self.softTick()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        router.route(to: target)
                    }
                } else if abs(vy) > abs(vx) * Self.velocityRatio
                    || travel >= Self.directionForceDistance {
                    // Vertical wins → leave this gesture alone for good.
                    swipeRejected = true
                }
            }
    }

    /// One verdict per gesture; cleared on lift AND on cancellation (a cancelled pan
    /// never delivers onEnded — ModeTabPicker's gestureInFlight lesson, B16).
    private func resetSwipeState() {
        swipeArmed = false
        swipeRejected = false
        router.pageSwipeArmed = false
    }

    /// One verdict per gesture: armed/rejected at the crossing, cleared on lift or
    /// cancellation via the @GestureState watch in body (an onEnded-only reset misses
    /// cancelled pans — one stuck latch made the swipe dead until the next page change).
    @State private var swipeArmed = false
    /// Vertical verdict for the CURRENT gesture: the list owns it, we stay out until lift.
    @State private var swipeRejected = false
    /// True while the pan is in flight; its auto-reset fires on end AND cancellation.
    @GestureState private var swipeInFlight = false

    /// 远程 tab 且未登录且本次启动还没离开过登录盖 → 盖登录页；登录成功(ready)自动收起。
    private var showsLoginGate: Bool {
        router.mode == .remote && remoteService.state != .ready && !loginCoverDismissed
    }

    static func softTick() {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare(); g.impactOccurred()
    }

    /// Fences for the page swipe. The shell is the root view, so these are the window
    /// metrics; no UIKit state is mutated.
    private static let screenWidth: CGFloat = UIScreen.main.bounds.width
    private static let screenHeight: CGFloat = UIScreen.main.bounds.height
    /// B16-SWIPE-DIR: verdict/force distances + velocity ratio.
    private static let directionDecideDistance: CGFloat = 12
    private static let directionForceDistance: CGFloat = 24
    /// pp 2026-09-16 gave 1.2 for the translation test; velocity is a cleaner signal,
    /// so the same 1.2 carries over as the dominance ratio.
    private static let velocityRatio: CGFloat = 1.2
    /// Swipes starting BELOW this y (window coords) are in the list area — exactly
    /// where pp wants the mode switch to live.
    private static let listAreaTop: CGFloat = 210
    private static let bubbleZoneWidth: CGFloat = 120
    private static let bubbleZoneHeight: CGFloat = 160
    /// [BOTTOM-BAR-FENCE] Bottom operation strip fallback (used only when the
    /// bar's own frame has not been reported yet). 160 mirrors bubbleZoneHeight.
    private static let bottomBarZoneHeight: CGFloat = 160
    /// Slack above the reported bar top so a touch on the bar's top edge still
    /// counts as "on the bar".
    private static let bottomBarFenceMargin: CGFloat = 20

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

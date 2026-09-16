// RootModeTabsView.swift — 分叉壳（D4 §2 唯一分叉点）+ 真 pager（两页横向平移）
// + 首启入口终案接线：未登录且落在远程 tab → AA 官方登录页全屏盖（扫码/手动/直接用本地
// AI 三颗 CTA）；登录成功 → 远程 tab；本机入口 → 本机 tab；lastTab 记忆（RootTabRouter）。
// 恢复：官方 restoreSession 语义（UserDefaults server + keychain token）。
//
// B14e (pp 2026-09-16「我要的不是盖住 是平移」+「齿轮不要划走」) 定形：
//   • 两页并排，随手指横向平移：offset = (progress − 当前档) × 页宽。松手 predictedEnd
//     超 0.28 页落位，spring(0.35/0.78)，到头阻尼 0.3，@GestureState 防卡半页
//   • 顶栏整条由本壳画，固定不动：齿轮 · 胶囊（+sync 指示器）· 闹钟 · 终端菜单
//     —— 这是唯一能同时满足「两页都滑」和「齿轮不划走」的结构：齿轮原来住在
//     ContentView 的 toolbar 里，页一动它就动，所以它必须离开那一层
//   • 选择模式（勾选会话）的 Cancel / Select All / "N Selected" 仍留在本机页自己的
//     toolbar：那是只有勾选中才出现的临时态，没人会边勾选边切档，而它的文案要读
//     selectedIds/sessions 这些本机内部状态，搬进外壳就得再镜像两个集合。外壳在这
//     个状态下把自己的齿轮/闹钟/菜单让位（router.localSelecting）
//   • 面板不透明性由两页各自的背景保证，滑动时不会互相透出
//
// 🔴 性能闸门：拖动期间本壳 body 以 60fps 重算。两页各包 EquatableView 把「父级驱动」
// 的重渲染短路 —— ContentView() 无入参，== 恒 true；它自己的 @State/@Published 照常刷新。
//
// 上游接缝（RootTabRouter，全部 presentation-only，无数据流）：
//   ① requestedBarAction —— 固定栏上每颗按钮的动作投递给 ContentView（它的
//      activeToolSheet / showTerminal / showAlarmList / keepScreenAwake 都还在那一层）
//   ② localAtRoot —— 本机线 push 进聊天页时整条固定栏让位（聊天页有自己的导航栏）
//   ③ localSelecting / barHasAlarms / barSyncSubtitle / barKeepScreenAwake —— 固定栏
//      要显示的三个状态位，从本机线的既有真源回传（单向、低频、写完即改即亮）
// B9-LANDING: lastTab 为空（全新安装）时落 .remote —— U1 §6 拍板「首启入口 = AA 官方
// 登录页」，JO-6 灰字按钮才是本机入口。本机路径内部逻辑仍与上游逐字节同。

import SwiftUI
import UIKit

@MainActor
struct RootModeTabsView: View {
    @StateObject private var router = RootTabRouter.shared
    @StateObject private var remoteService = RemoteService()
    @State private var showsQRLogin = false
    @State private var showsManualLogin = false
    @State private var didRestore = false
    /// B12-GATEFLASH: the full-screen login is the 首启 entry, not a permanent lid on
    /// the remote tab. Once the user leaves it (直接用本地 AI / 关闭), the tab's
    /// 未登录三态卡 takes over and its 去登录 button re-raises the cover.
    @State private var loginCoverDismissed = false
    /// 胶囊首档名与上游标题同源（SOUL.md name 回退 Moonveil）。
    @State private var localLabel: String = {
        let n = SoulStore.cachedMetadata.name
        return n.isEmpty ? "Moonveil" : n
    }()

    /// Raw horizontal translation of the live drag, in points (0 when no drag is ours).
    /// `@GestureState`, not `@State`: if the List steals the pan mid-drag the value
    /// auto-resets, so a page can never be left parked half off screen.
    @GestureState private var dragPoints: CGFloat = 0
    /// Which segment already got its detent during this drag (fires once per crossing).
    @State private var detented: AppSourceMode?

    // ── Motion (pp 2026-09-16 给的数值，原样落地) ─────────────────────────────────
    static let settleAnimation = Animation.spring(response: 0.36, dampingFraction: 0.78)
    /// 切换阈值：预测位移超 28% 页宽才换档
    static let releaseThreshold: CGFloat = 0.28
    /// 边缘阻力：到头再拖只走 32%
    static let edgeResistance: CGFloat = 0.32
    /// 方向锁定：滑动超过 12pt 才开始判断方向（以下不认领，列表纵滚才不会被劫持）
    static let directionLockDistance: CGFloat = 12
    /// 横向必须明显大于纵向：|dx| > 1.35·|dy|（1.3~1.4 最接近 Grok）
    static let horizontalRatio: CGFloat = 1.35

    // ── Fences for the list-area swipe (unchanged from B13) ─────────────────────────
    /// Swipes starting BELOW this y are in the list area.
    private static let listAreaTop: CGFloat = 210
    private static let bubbleZoneWidth: CGFloat = 120
    private static let bubbleZoneHeight: CGFloat = 160
    /// Window metrics: the shell is the root view, so these are stable and no UIKit
    /// state is mutated.
    private static let screenWidth: CGFloat = UIScreen.main.bounds.width
    private static let screenHeight: CGFloat = UIScreen.main.bounds.height

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .top) {
                pager(width: w)
                if barVisible {
                    fixedBar(width: w)
                }
            }
            .frame(width: w, height: geo.size.height)
            .gesture(pagerDrag(step: w, band: .list))
        }
        .onReceive(NotificationCenter.default.publisher(for: .soulMdChanged)) { _ in
            let n = SoulStore.cachedMetadata.name
            localLabel = n.isEmpty ? "Moonveil" : n
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

    // MARK: - Pager

    /// Two pages side by side, shifted by (progress − current slot) × page width — the
    /// reference file's own formula, so both pages move together under the fixed bar.
    private func pager(width w: CGFloat) -> some View {
        HStack(spacing: 0) {
            LocalPage()
                .equatable()
                .frame(width: w)

            if router.seenRemote {
                RemotePage(service: remoteService,
                           stateToken: String(describing: remoteService.state),
                           gated: showsLoginGate,
                           onOpenLogin: { loginCoverDismissed = false })
                    .equatable()
                    .frame(width: w)
            } else {
                // Remote tab never opened this launch: keep the slot filled so geometry
                // stays exactly one page per screen and lazy creation still holds.
                Color(UIColor.systemBackground)
                    .frame(width: w)
            }
        }
        .frame(width: w, alignment: .leading)
        .offset(x: (progress(step: w) - router.mode.slot) * w)
    }

    // MARK: - Fixed bar

    /// The whole resting-state top bar: it belongs to no page, so it never slides.
    /// Only hit-testable where its controls are — the gaps pass touches through to the
    /// page underneath (that is what keeps the list scrollable under the bar).
    private func fixedBar(width w: CGFloat) -> some View {
        HStack(spacing: 0) {
            leadingControls
            Spacer(minLength: 0)
            capsule(rowWidth: capsuleRowWidth)
            Spacer(minLength: 0)
            trailingControls
        }
        .padding(.horizontal, Self.barSidePadding)
        .frame(width: w, height: ModeTabPicker.rowHeight)
    }

    /// The system bar insets its items roughly this much on iPhone.
    private static let barSidePadding: CGFloat = 16

    /// A pushed detail (a chat) owns its own navigation bar → the fixed bar steps aside.
    private var barVisible: Bool {
        guard router.mode == .local else { return true }   // remote line: no pushes until batch 9
        return router.localAtRoot
    }

    private var isSelectingLocal: Bool {
        router.mode == .local && router.localSelecting
    }

    @ViewBuilder
    private var leadingControls: some View {
        // While rows are checked, the local page's own toolbar draws Cancel at this
        // edge — the fixed copies stand down so nothing doubles.
        if !isSelectingLocal {
            BarButton(action: { router.requestedBarAction = .toolSheet(.settings) }) {
                Image(systemName: "gear")
            }
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        if !isSelectingLocal, router.mode == .local {
            if router.barHasAlarms {
                BarButton(action: { router.requestedBarAction = .alarmList }) {
                    Image(systemName: "alarm")
                        .font(.system(size: 15, weight: .medium))
                }
            }
            terminalMenu
        }
    }

    /// Upstream's toolbar menu, same five entries, same labels and icons. Its actions
    /// land back in ContentView through the one-shot seam.
    private var terminalMenu: some View {
        Menu {
            Button { router.requestedBarAction = .terminal } label: {
                Label("Shell Terminal", systemImage: "terminal")
            }
            Button { router.requestedBarAction = .toolSheet(.rootfsManagement) } label: {
                Label("Rootfs Management", systemImage: "externaldrive")
            }
            Divider()
            Button { router.requestedBarAction = .toolSheet(.browser) } label: {
                Label("Open Browser", systemImage: "globe")
            }
            Button { router.requestedBarAction = .toolSheet(.browserManagement) } label: {
                Label("Browser Settings", systemImage: "globe.badge.chevron.backward")
            }
            #if DEBUG
            Divider()
            // [debug] Keep Screen Awake — mirrors upstream's behaviour: toggling flips
            // the idle timer for the whole app while foregrounded.
            Button { router.requestedBarAction = .toggleKeepAwake } label: {
                Label("Keep Screen Awake",
                      systemImage: router.barKeepScreenAwake ? "checkmark.circle.fill" : "sun.max")
            }
            #endif
        } label: {
            Image("TerminalCircle")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
        }
        .modifier(SecondaryButtonStyleIfAvailable())
    }

    private var capsuleRowWidth: CGFloat {
        ModeTabPicker.rowWidth(localLabel: localLabel, remoteLabel: "Remote")
    }

    /// The capsule + the sync indicator that hugs its leading edge (upstream's
    /// title-tap entry into the sync migration detail, position unchanged).
    private func capsule(rowWidth: CGFloat) -> some View {
        ModeTabPicker(
            selection: $router.mode,
            localLabel: localLabel,
            onLocalRetap: canOpenSync ? { router.requestedBarAction = .toolSheet(.syncMigrationDetail) } : nil,
            progress: progress(step: ModeTabPicker.slotWidth(localLabel: localLabel,
                                                             remoteLabel: "Remote"))
        )
        .frame(width: rowWidth)
        .overlay(alignment: .leading) {
            if canOpenSync {
                Button {
                    router.requestedBarAction = .toolSheet(.syncMigrationDetail)
                } label: {
                    syncIndicator(for: router.barSyncSubtitle)
                        .contentShape(Rectangle())
                        .padding(4)
                }
                .buttonStyle(.plain)
                .offset(x: -27)
            }
        }
        // Hit band = the capsule row itself, not the whole bar: the Spacers must keep
        // passing touches down to the sliding pages.
        .contentShape(Rectangle())
        .highPriorityGesture(pagerDrag(step: ModeTabPicker.slotWidth(localLabel: localLabel,
                                                                     remoteLabel: "Remote"),
                                       band: .pill))
    }

    /// Tiny indicator next to the capsule showing the sync state — moved here verbatim
    /// from ContentView when the bar became shared chrome.
    @ViewBuilder
    private func syncIndicator(for state: ContentView.SyncSubtitleState?) -> some View {
        switch state {
        case .none, .upToDate:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)
        case .paused:
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
        case .migrating, .syncing:
            PulseRotateIcon()
        case .waiting:
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var canOpenSync: Bool {
        if #available(iOS 17.0, *) { return SyncV2Bootstrap.isEnabled }
        return false
    }

    /// Drag progress in "steps" (one step = one page, or one capsule slot), damped past
    /// the first/last position so an over-drag resists instead of flying away.
    private func progress(step: CGFloat) -> CGFloat {
        guard step > 0 else { return 0 }
        let raw = dragPoints / step
        let index = router.mode.slot + raw
        let last = CGFloat(AppSourceMode.allCases.count - 1)
        if index < 0 || index > last { return raw * Self.edgeResistance }
        return raw
    }

    // MARK: - Drag

    private enum DragBand {
        /// The list area below the tab row: one page per screen width of travel.
        case list
        /// The capsule row itself: one slot per slot width of travel, so a short flick
        /// across the pill flips a tab (the scrub pp has been using).
        case pill
    }

    private func pagerDrag(step: CGFloat, band: DragBand) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)   // SwiftUI default
            .updating($dragPoints) { value, state, _ in
                guard step > 0, accepts(value: value, band: band) else { return }
                state = value.translation.width
            }
            .onChanged { value in
                guard step > 0, accepts(value: value, band: band) else { return }
                let p = value.translation.width / step
                let target: AppSourceMode = p < -0.5 ? .remote : (p > 0.5 ? .local : router.mode)
                guard target != detented else { return }
                detented = target
                if target != router.mode { ModeTabPicker.detent() }
            }
            .onEnded { value in
                detented = nil
                directionLocked = false
                guard step > 0, accepts(value: value, band: band) else { return }
                let predicted = value.predictedEndTranslation.width / step
                var target = router.mode
                if predicted < -Self.releaseThreshold { target = .remote }
                else if predicted > Self.releaseThreshold { target = .local }
                guard target != router.mode else { return }
                ModeTabPicker.softTick()
                withAnimation(Self.settleAnimation) { router.route(to: target) }
            }
    }

    /// Whether THIS drag has been judged horizontal yet. Latched so a finger that
    /// drifts diagonal mid-swipe does not drop the claim and snap the page back — the
    /// 失灵 shape pp keeps hitting. Self-clears: every drag starts below the lock
    /// distance, which also heals a gesture that ended without onEnded (stolen).
    @State private var directionLocked = false

    /// Claim the drag, then apply the fences so this control does not swallow input that
    /// already belongs elsewhere: vertical scrolls, the bar's own buttons, the
    /// draggable chat bubble.
    private func accepts(value: DragGesture.Value, band: DragBand) -> Bool {
        let dx = abs(value.translation.width)
        guard dx >= Self.directionLockDistance else {
            directionLocked = false
            return false
        }
        if !directionLocked {
            guard dx > abs(value.translation.height) * Self.horizontalRatio else { return false }
            directionLocked = true
        }
        guard case .list = band else { return true }
        let start = value.startLocation
        guard start.y > Self.listAreaTop else { return false }
        let inBubbleZone = start.y > Self.screenHeight - Self.bubbleZoneHeight
            && start.x > Self.screenWidth - Self.bubbleZoneWidth
        return !inBubbleZone
    }

    // MARK: - Login gate (B12 semantics unchanged)

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

/// A fixed-bar button wearing the same system glass the toolbar buttons got before the
/// bar became shared chrome (repo shim: `.glass` on iOS 26, `.bordered` below).
private struct BarButton<LabelView: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> LabelView

    var body: some View {
        Button(action: action) { label() }
            .modifier(SecondaryButtonStyleIfAvailable())
    }
}

// MARK: - Pages (parent-driven re-renders short-circuited; see header)

/// The upstream local line. `ContentView()` takes no inputs, so it can never NEED a
/// parent-driven update; skipping them is what keeps a 60fps drag off the session list.
private struct LocalPage: View, Equatable {
    static func == (lhs: LocalPage, rhs: LocalPage) -> Bool { true }
    var body: some View { ContentView() }
}

/// The remote line. Rebuilds when the service identity, its state token, or the gate
/// changes; the closure is deliberately out of the comparison (it only flips a
/// shell-local flag, and its identity changes every render).
private struct RemotePage: View, Equatable {
    let service: RemoteService
    let stateToken: String
    let gated: Bool
    let onOpenLogin: () -> Void

    static func == (lhs: RemotePage, rhs: RemotePage) -> Bool {
        lhs.service === rhs.service
            && lhs.stateToken == rhs.stateToken
            && lhs.gated == rhs.gated
    }

    var body: some View {
        // B12-GATEFLASH: while the cover owns the screen the slot under it is a plain
        // surface, so nothing can flash behind the login (device report: one frame of
        // the guide card before the cover slid up).
        if gated {
            Color(UIColor.systemBackground)
        } else {
            RemoteRootView(service: service, onOpenLogin: onOpenLogin)
        }
    }
}

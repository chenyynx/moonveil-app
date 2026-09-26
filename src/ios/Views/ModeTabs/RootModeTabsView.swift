// RootModeTabsView.swift — the single fork point (D4 §2) + 首启入口终案接线:
// 未登录且落在远程 tab → AA 官方登录页全屏盖（扫码/手动/本地三颗胶囊 CTA）；
// 登录成功 → 远程 tab；本地入口 → 本机 tab；lastTab 记忆（RootTabRouter）。
// 恢复：官方 restoreSession 语义（UserDefaults server + keychain token）。
// 隔离：本机 tab = upstream ContentView 本体零改动；登录盖只在远程侧出现。
// B9-LANDING: lastTab 为空（全新安装）时落 .remote —— U1 §6 拍板「首启入口 =
// AA 官方登录页」，JO-6 灰字按钮才是本机入口。本机路径本身仍与上游逐字节同。

import SwiftUI
import UIKit

/// [BOTTOM-BAR-FENCE] 底部操作栏在窗口坐标里的顶边 —— 由 ContentView 的 `bottomBar`
/// 经 GeometryReader 上报（.global）。页切手势在 global 坐标下用它精确排除「新会话
/// 胶囊 + 搜索栏」区域：不再依赖 `UIScreen` 高度与「局部坐标 == 窗口坐标」的假设
/// （pp 2026-09-20 反馈「拖动新会话胶囊也会切页」时条带推算即为嫌疑点）。
///
/// `nonisolated(unsafe)`：读写都发生在主线程 UI 路径（ContentView 布局上报 /
/// 手势判定），与仓内既有全局共享状态（cachedLockLabel 等）同一模式；ContentView
/// 是 nonisolated struct，这里若加 @MainActor 隔离会在其 body / 手势闭包里访问报错。
enum BottomBarFence {
    nonisolated(unsafe) static var topY: CGFloat = 0
}

// [REMOTE-ROW-FENCE 已撤 2026-09-24] 原「远端卡堆区让位行 swipeActions」的页切
// 排除栅栏（2026-09-20 因 pp「卡片我往右滑怎么切换页了」而设）整套移除——pp 2026-09-24
// 「把左滑右滑的功能改成长按的方式，让滑动卡片区域能滑动页面到本地列表页」：
// swipeActions 已迁长按菜单，排除前提消失，卡片区横滑恢复页切（首卡上报/复位
// 机制同批移除于 RemoteSessionListView）。

@MainActor
struct RootModeTabsView: View {
    @StateObject private var router = RootTabRouter.shared
    @StateObject private var remoteService = RemoteService()
    @State private var showsQRLogin = false
    @State private var showsManualLogin = false
    @State private var didRestore = false
    /// Q2: 身份胶囊 → 资料页（zoom 转场对）。NS 挂在胶囊头像的
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

    var body: some View {
        ZStack {
            ContentView()
                .opacity(router.mode == .local ? 1 : 0)
                .allowsHitTesting(router.mode == .local)
                // [TAB-SWAP-FLASH 2026-09-21] pp「切 tab 搜索栏那一坨和新会话胶囊会闪
                // 一下」：tap/横滑两条路径的 withAnimation 事务把两个 tab 的 opacity
                // 变成 crossfade——两 tab 底部同位置都有深色「新会话胶囊+搜索栏」，
                // 半透明叠影即闪源。内容层瞬切（胶囊动画在 ModeTabPicker 内部显式
                // 绑定，不受影响）。ContentView 不读 router.mode（D4 红线），此修饰
                // 只影响整体 opacity 翻转方式，本机线本体零改动。
                .animation(nil, value: router.mode)

            if router.seenRemote {
                // B12 CI repair: a bare `if/else` is a STATEMENT — trailing view
                // modifiers after its closing brace are invalid Swift ("instance
                // member 'opacity' cannot be used on type 'View'"; swiftc -parse
                // passes it, only typecheck kills it). Group gives the branch a
                // single expression to hang the modifiers on.
                Group {
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
                }
                .opacity(router.mode == .remote ? 1 : 0)
                .allowsHitTesting(router.mode == .remote)
                // [TAB-SWAP-FLASH] 同上：远端内容层瞬切（胶囊动画见 ModeTabPicker）。
                .animation(nil, value: router.mode)
            }

            // Q2: 第三 tab「构件 | 影音内容」。瞬切手法与上两分支一致（ZStack 无
            // 外层动画，if 插拔即瞬变）；离开即拆树，回到本页 .task 重扫。
            if router.mode == .works {
                WorksListView()
            }
        }
        .overlay(alignment: .topLeading) {
            if gearVisible { gearButton }
        }
        // Q2: 顶部身份胶囊（唯一实例，两列表页共用；远端/works 由闸门恒绝）。
        // 与 topLeading 齿轮并存不冲突（此处 alignment: .top 水平居中）。
        .overlay(alignment: .top) {
            if soulCapsuleVisible { soulCapsule }
        }
        // Q2: 底部三段 dock。safeAreaInset 挂在壳层主 ZStack → 作用于整棵子树：
        // 子视图自己的 safeAreaInset（两列表页 bottomBar）会被压缩后的安全区顶到
        // dock 之上，works 页/聊天 push 页同理（常驻是拍板决策）。水平 margin 16
        // 由 BottomModeDock 自带，这里不再加。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomModeDock()
                // 键盘起落不应带着 dock：先按官方口径试 ignoresSafeArea(.keyboard)。
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        // Q2: 胶囊 → 资料页 zoom 转场。sheet + navigationTransition(.zoom) 配对
        // （Apple 文档标准形状；不用默认上弹 —— zoom 会接管转场风格）。
        .sheet(isPresented: $showsSoulProfile) {
            SoulProfileHub()
                .navigationTransition(.zoom(sourceID: SoulProfileHub.zoomSourceID, in: soulProfileNS))
        }
        .onReceive(NotificationCenter.default.publisher(for: .soulMdChanged)) { _ in
            let n = SoulStore.cachedMetadata.name
            soulName = n.isEmpty ? "Moonveil" : n
        }
        // B16: ONE settings presentation for both tabs, hosted by the always-visible
        // shell. On the Remote tab ContentView is alive but `opacity 0`, and "can an
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

    /// Page-level horizontal swipe = the same mode switch as the capsule.
    /// 左滑 → Remote，右滑 → 本机. Two tabs, so the direction maps straight onto
    /// reading order.
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
    ///      This is `gestureRecognizerShouldBegin` + `isDirectionalLockEnabled`, the
    ///      only way SwiftUI lets us have them.
    ///
    /// Fences unchanged: the top bar band (tab control + toolbar slider), the
    /// bottom-right chat bubble (draggable — ContentView:6002), anything above the
    /// list area. B13-SWIPEFIX-5 scope stays: every start point BELOW the tab row is
    /// ours to judge (判定在 onChanged，先于任何"松手才打开"的行内逻辑).
    private var pageSwipe: some Gesture {
        // [BOTTOM-BAR-FENCE] global 坐标：起点与 BottomBarFence（窗口坐标）可直接比较。
        DragGesture(minimumDistance: 12, coordinateSpace: .global)   // pp 2026-09-16: directionLockDistance = 12pt
            .updating($swipeInFlight) { _, state, _ in state = true }
            .onChanged { value in
                // Q2: works 页禁横滑页切（三段下点切即可；左滑右滑语义只属于
                // 本机⟷远程两页）。
                guard router.mode != .works else { return }
                if swipeRejected || swipeArmed { return }   // verdict is final per gesture

                let dx = value.translation.width
                let dy = value.translation.height
                let start = value.startLocation

                // [B16-SWIPE-SCOPE] (pp 2026-09-17「聊天页滑动也能滑到remote页?」+
                // 2026-09-20 远端设备详情页)：横滑切页只属于两条线各自的根列表页——
                // 本机 push 进聊天页(localAtRoot == false) / 远端 push 进设备详情页
                // (remoteAtRoot == false) 时整个手势直接退出；push 页内的横滑无消费
                // 场景，误触反而打断阅读。B13-SWIPEFIX-5 的「列表区」本意就是会话列表。
                if router.mode == .remote {
                    guard router.remoteAtRoot else { return }
                } else {
                    guard router.localAtRoot else { return }
                }
                guard start.y > Self.listAreaTop else { return }
                // [BOTTOM-BAR-FENCE] pp 2026-09-20「滑动底部胶囊/搜索栏也会触发切页」：
                // 底部操作栏（新会话胶囊 + 全宽搜索栏，safeAreaInset 位于屏底 ~150pt 内，
                // 见 ContentView BOTTOM-BAR-ALIGN）整体退出切页判定——旧 bubbleZone 只盖
                // 右下角，搜索栏左半与胶囊左缘都是「洞」。本条带完整覆盖 bubbleZone 的
                // y 范围（后者保留：x 条件语义独立于布局）。
                // 优先用底部栏实际上报的顶边（精确）；未上报时退回条带推算。
                let fenceTop = BottomBarFence.topY > 0
                    ? BottomBarFence.topY - Self.bottomBarFenceMargin
                    : Self.screenHeight - Self.bottomBarZoneHeight
                guard start.y < fenceTop else { return }
                // [REMOTE-ROW-FENCE 已撤 2026-09-24] 卡堆区不再排除（tombstone 见
                // 文件头）：swipeActions 迁长按后排除前提消失，远端卡片区横滑照常
                // 参与页切判定。
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

    // MARK: - Fixed gear (B16)

    // Calibrated off pp's own device screenshot (1179px @3x — the build where the gear
    // still lived in the system toolbar): a radial scan of the glass disc gives diameter
    // 44.0pt and leading edge 15.7pt; the terminal button on the right measures 43.3pt /
    // 17.0pt inset, so those are the system metrics, not my guess. Vertical centre sits
    // at 80.7pt = safe-area top (59) + 21.7 → dead centre of the 44pt bar band.
    // My first pass here used a 30pt circle — 14pt too small, which is precisely the
    // 「形状不对」 complaint.
    private static let gearLeadingInset: CGFloat = 16
    private static let gearBandHeight: CGFloat = 44
    private static let gearDiameter: CGFloat = 44
    /// 22pt = AA's own number for this glyph in its toolbar (not derived from the old
    /// gear's ink box any more). `AppSymbol` wraps the size in @ScaledMetric, so it also
    /// grows with Dynamic Type the way upstream's does.
    private static let gearSymbolSize: CGFloat = 22
    /// Namespace for the gear's morphing glass (AA's `@Namespace private var glass`).
    @Namespace private var gearGlassNS
    /// 12pt = AA's container spacing; glasses closer than this merge like liquid.
    private static let glassSpacing: CGFloat = 12

    /// Hidden when the line on screen is not at its list root (a pushed page owns that
    /// bar) or when rows are checked (the page draws Cancel at this edge).
    /// 远端线自 REMOTE-DEVICE-1 起有 push（设备详情页）——与本地同规则收 ☰。
    private var gearVisible: Bool {
        guard router.mode == .local else { return router.remoteAtRoot }
        return router.localAtRoot && !router.localSelecting
    }

    /// Same glass as the capsule — one material language for the fixed bar, so gear and
    /// pill cannot look like two different systems. Deliberately NOT
    /// `.buttonStyle(.glass)`: that style carries its own light-mode grey fill and
    /// padding, and imitating the system toolbar with it is what made B14e's bar read as
    /// 改坏了 (pp 2026-09-16).
    /// The glass now sits ON the control, inside a `GlassEffectContainer`, and carries a
    /// `glassEffectID` — that is AA's composer recipe verbatim (ChatComposer.swift:21
    /// container / :61 `.regular.interactive()` / :62 `glassEffectID`, plus
    /// `@Namespace private var glass`). It is the CONTAINER that makes `.interactive()`
    /// respond; a glass parked in a `.background` layer never gets a press, which is why
    /// my earlier "draw the emphasis" version looked dead next to the system's.
    private var gearButton: some View {
        // `Group` is load-bearing: chaining `.padding` straight onto a bare
        // `if #available` block inside a `@ViewBuilder` property makes the compiler fall
        // back to the `View` existential, and CI dies one line later with
        // "instance member 'padding' cannot be used on type 'View'"
        // (runs 35067152326 and 35068323175). The repo's own compiling glass code uses
        // either a Group (ModeTabPicker.pill) or a ViewModifier (ContentView
        // SearchBarSurface / FABGlassMorphID) for exactly this reason.
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: Self.glassSpacing) {
                    gearControl
                        .glassEffect(.regular.interactive(), in: Circle())
                        .glassEffectID("settingsGear", in: gearGlassNS)
                }
            } else {
                gearControl
                    .background(Circle().fill(Color(UIColor.secondarySystemBackground)))
                    .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
            }
        }
        .padding(.leading, Self.gearLeadingInset)
        // 44pt disc inside a 44pt band: centring is exact, nothing to fudge.
        .padding(.top, (Self.gearBandHeight - Self.gearDiameter) / 2)
    }

    private var gearControl: some View {
        Button {
            router.showSettings = true
        } label: {
            // AA's own drawer glyph, verbatim: AppSymbol("sidebar.left", size: 22)
            // → asset aa-TextAlignStart (upstream ChatPageToolbar.swift:99-101).
            AppSymbol("sidebar.left", size: Self.gearSymbolSize)
                .foregroundStyle(Color.primary)
                .frame(width: Self.gearDiameter, height: Self.gearDiameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // AppSymbol hides itself from a11y (upstream does too), so the button carries
        // the label — the entry point must not go silent under VoiceOver.
        .accessibilityLabel(Text(String(localized: "Settings")))
    }


    /// 远程 tab 且未登录且本次启动还没离开过登录盖 → 盖登录页；登录成功(ready)自动收起。
    private var showsLoginGate: Bool {
        router.mode == .remote && remoteService.state != .ready && !loginCoverDismissed
    }

    // MARK: - Q2 身份胶囊（顶部，唯一实例）

    /// 闸门四条件：本机线在列表根、非多选、没盖登录盖。mode == .local 已把
    /// 远端与 works 恒绝（pp：远端「暂不显示」）。
    private var soulCapsuleVisible: Bool {
        router.mode == .local && router.localAtRoot && !router.localSelecting && !showsLoginGate
    }

    /// 几何（Muse 实测）：头像 40 圆 + 名字 pill 56×30 r15、15pt semibold，
    /// -6 叠压（头像踩 pill 上沿）；整体水平居中，头像顶 = 安全区顶 +4
    /// （overlay(alignment: .top) 落在 safe area 内，padding(.top, 4) 补足）。
    private var soulCapsule: some View {
        Button {
            showsSoulProfile = true
        } label: {
            VStack(spacing: -6) {
                Image("CaduGhost")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .matchedTransitionSource(id: SoulProfileHub.zoomSourceID, in: soulProfileNS)
                    .accessibilityHidden(true)
                Text(verbatim: soulName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Self.soulPillText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 56, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Self.soulPillSurface)
                    )
            }
            .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .accessibilityLabel(Text(verbatim: soulName))
    }

    /// pill 底：light 纯白 / dark #1C1C1E。
    private static let soulPillSurface = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
            : .white
    })
    /// pill 字色随底反相：light 深字 / dark 白字。
    private static let soulPillText = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .white
            : UIColor(white: 0x11 / 255, alpha: 1)
    })

    /// Same haptic the capsule uses for a mode switch (UIImpactFeedbackGenerator .soft).
    private static func softTick() {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare(); g.impactOccurred()
    }

    /// Fences for the page swipe. The shell is the root view, so these are the window
    /// metrics; no UIKit state is mutated.
    private static let screenWidth: CGFloat = UIScreen.main.bounds.width
    private static let screenHeight: CGFloat = UIScreen.main.bounds.height
    /// B16-SWIPE-DIR: verdict/force distances + velocity ratio. The old 36pt
    /// translation gate is gone — velocity needs no long runway; judged as soon as
    /// the pan has 12pt of travel (its own minimumDistance), forced by 24pt.
    /// Android's pager uses an 8dp slop + half-page/velocity rule; no iOS default.
    private static let directionDecideDistance: CGFloat = 12
    private static let directionForceDistance: CGFloat = 24
    /// pp 2026-09-16 gave 1.2 for the translation test; velocity is a cleaner signal,
    /// so the same 1.2 carries over as the dominance ratio.
    private static let velocityRatio: CGFloat = 1.2
    /// Swipes starting BELOW this y (window coords) are in the list area — exactly
    /// where pp wants the mode switch to live. (Tab row itself stays with the capsule.)
    private static let listAreaTop: CGFloat = 210
    private static let topBarBottom: CGFloat = 170
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

// RootModeTabsView.swift — the single fork point (D4 §2) + 首启入口终案接线:
// 未登录且落在远程 tab → AA 官方登录页全屏盖（扫码/手动/本地三颗胶囊 CTA）；
// 登录成功 → 远程 tab；本地入口 → 本机 tab；lastTab 记忆（RootTabRouter）。
// 恢复：官方 restoreSession 语义（UserDefaults server + keychain token）。
// 隔离：本机 tab = upstream ContentView 本体零改动；登录盖只在远程侧出现。
// B9-LANDING: lastTab 为空（全新安装）时落 .remote —— U1 §6 拍板「首启入口 =
// AA 官方登录页」，JO-6 灰字按钮才是本机入口。本机路径本身仍与上游逐字节同。

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
    /// 未登录三态卡 takes over and its 去登录 button re-raises the cover — which is
    /// what U1 §6 asked for and what made the old always-on gate unreachable.
    @State private var loginCoverDismissed = false

    var body: some View {
        ZStack {
            ContentView()
                .opacity(router.mode == .local ? 1 : 0)
                .allowsHitTesting(router.mode == .local)

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
            }
        }
        .overlay(alignment: .topLeading) {
            if gearVisible { gearButton }
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
        DragGesture(minimumDistance: 12)   // pp 2026-09-16: directionLockDistance = 12pt
            .updating($swipeInFlight) { _, state, _ in state = true }
            .onChanged { value in
                if swipeRejected || swipeArmed { return }   // verdict is final per gesture

                let dx = value.translation.width
                let dy = value.translation.height
                let start = value.startLocation

                // [B16-SWIPE-SCOPE] (pp 2026-09-17「聊天页滑动也能滑到remote页?」)
                // 横滑切页只属于根列表页 —— 本机已 push 进聊天页(localAtRoot == false)
                // 时整个手势直接退出;会话内的横滑无消费场景,误触反而打断阅读。
                // B13-SWIPEFIX-5 的「列表区」本意就是会话列表。Remote 将来上会话页时
                // 同规则适用(仍走这一个栅栏位)。
                guard router.localAtRoot else { return }
                guard start.y > Self.listAreaTop else { return }
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

    /// Hidden when the local line is not at its list root (a pushed chat owns that bar)
    /// or when rows are checked (the page draws Cancel at this edge). The remote line has
    /// no pushes yet, so it is always at root.
    private var gearVisible: Bool {
        guard router.mode == .local else { return true }
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

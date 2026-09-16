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
        .gesture(pageSwipe)   // B12: swipe the page to switch 本机 ⟷ Remote
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
    /// Mostly-horizontal (|dx| > 1.6·|dy|) and past 64pt, evaluated on END so a
    /// vertical scroll never gets hijacked mid-drag. Two tabs, so the direction maps
    /// straight onto reading order: 左滑 → Remote，右滑 → 本机.
    /// Plain `.gesture` on the container: children keep priority, so upstream row
    /// swipe actions, text selection and the capsule's own scrub are unaffected.
    /// Swipe the page to switch 本机 ⟷ Remote.
    ///
    /// B13-SWIPEFIX-2 — the decision moved from onEnded to onChanged. The content here
    /// is a List/ScrollView: an ancestor DragGesture can be CANCELLED mid-pan once the
    /// scroll machinery claims the gesture, so an onEnded-only rule often never fires
    /// at all (that is the 失灵 pp hit). Deciding while the finger is still down makes
    /// the switch land, and makes the page feel like it follows the swipe.
    ///
    /// Fences (kept from the previous pass) so this control does not swallow input that
    /// already belongs elsewhere: the top bar band (tab control + toolbar slider), the
    /// bottom-right chat bubble (draggable — ContentView:6002), and any drag that is
    /// not clearly horizontal.
    private var pageSwipe: some Gesture {
        // 10pt = SwiftUI's own default drag threshold (there is no system default for
        // the two numbers below — SwiftUI ships no swipe-to-switch-page control).
        DragGesture(minimumDistance: 12)   // pp 2026-09-16: directionLockDistance = 12pt
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let start = value.startLocation

                if !swipeArmed {
                    // B13-SWIPEFIX-5 (pp 终案): 列表横滑 = 切本机/Remote。上一版把范围
                    // 收窄到顶栏带，等于把他要的功能关了 —— 撤回。现在接受 tab 行以下
                    // 的所有起点（= 列表区），并且判定在 onChanged，手指还在动就切，
                    // 因此在时机上先于任何"松手才打开"的行内逻辑。
                    guard start.y > Self.listAreaTop else { return }
                    let inBubbleZone = start.y > Self.screenHeight - Self.bubbleZoneHeight
                        && start.x > Self.screenWidth - Self.bubbleZoneWidth
                    guard !inBubbleZone else { return }
                    // Far enough AND clearly (not merely barely) horizontal: 1.0×
                    // misfires on diagonal list scrolls, 2.2× demanded a textbook-perfect
                    // swipe and felt dead. 1.2× is the floor where both complaints stop.
                    guard abs(dx) >= Self.swipeTrigger, abs(dx) > abs(dy) * 1.2 else { return }
                    swipeArmed = true
                    router.pageSwipeArmed = true
                    let target: AppSourceMode = dx < 0 ? .remote : .local
                    guard target != router.mode else { return }
                    Self.softTick()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        router.route(to: target)
                    }
                }
            }
            .onEnded { _ in
                swipeArmed = false
                router.pageSwipeArmed = false
            }
    }

    /// One switch per gesture: armed on the crossing, reset when the finger lifts.
    @State private var swipeArmed = false

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
    /// Horizontal travel (pt) before a page swipe is claimed. Looser than before
    /// (44 → 36) because pp kept hitting the "I have to swipe really flat for it to
    /// register" case. Android's pager uses an 8dp slop + half-page/velocity rule;
    /// there is no system default for this number on iOS.
    private static let swipeTrigger: CGFloat = 36
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

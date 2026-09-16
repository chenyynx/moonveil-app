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
        DragGesture(minimumDistance: 10)
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
                    let target: AppSourceMode = dx < 0 ? .remote : .local
                    guard target != router.mode else { return }
                    Self.softTick()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        router.route(to: target)
                    }
                }
            }
            .onEnded { _ in swipeArmed = false }
    }

    /// One switch per gesture: armed on the crossing, reset when the finger lifts.
    @State private var swipeArmed = false

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

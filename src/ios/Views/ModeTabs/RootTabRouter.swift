// RootTabRouter.swift — the ONLY cross-tab action: pure routing (D4 red line).
// No data flows between tabs; the router just says which one you're looking at.
// Persistence via UserDefaults (lastTab memory, U1 首启入口终案).

import SwiftUI
import Combine

// Moved from ModeTabPicker.swift (bottom-dock batch) — the picker is gone.
/// The app's source modes (D4: the single fork point).
/// CaseIterable order = [.local, .remote, .works, .compose].
enum AppSourceMode: String, CaseIterable, Identifiable {
    case local, remote, works
    /// 新会话按钮（pp 2026-09-26「新会话按钮入口加进tab」→「改到刚刚tab分离
    /// 在右边的圆按钮」。[TG-TABBAR 2026-09-30] 原「借 TabRole.search 的独立圆形
    /// 外观」通道已随系统 TabView 退役——现为 ModeTabBar 自绘栏右侧的独立玻璃圆位）。
    /// ACTION 位，不是页面：点它走 QuickActionRouter 新建本机会话，`mode`
    /// 永不变为 .compose（ModeTabBar.commit 拦截），所以不进 lastTab 记忆、
    /// 不参与横滑（手势已删）、tabContent 永不渲染。
    case compose
    var id: String { rawValue }
}

// NOTE B8-FIX: intentionally NOT @MainActor — ContentView (nonisolated struct)
// initializes it as a stored property; all mutations originate from UI (main).
final class RootTabRouter: ObservableObject {
    static let shared = RootTabRouter()

    static let storageKey = "app.rootSourceMode"

    @Published var mode: AppSourceMode {
        didSet {
            guard oldValue != mode else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.storageKey)
            // First visit marks the remote tab as "seen" so the shell can keep
            // it alive afterwards (lazy-create once, then both tabs persist).
            if mode == .remote { seenRemote = true }

            // [切页转场 2026-09-30] 供 RootModeTabsView 的交叉溶解窗口用：上一棵
            // 树在下层保留 ~0.28s（TG 新页盖旧页淡入）。状态写在这里而非视图
            // onChange = 与 mode 同步落定，视图首个更新帧就能读到正确值（视图侧
            // onChange 先于/后于 body 求值的次序不确定，会造成旧树闪隐一帧）；
            // 窗口结束清空（纯清场，旧树已被新页全盖，无可见变化）。
            previousMode = oldValue
            previousModeClearTask?.cancel()
            previousModeClearTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                self?.previousMode = nil
            }
        }
    }

    /// [切页转场] 上一棵树（溶解窗口用）；由 mode 的 didSet 维护，勿外部写。
    @Published private(set) var previousMode: AppSourceMode?
    private var previousModeClearTask: Task<Void, Never>?

    /// Whether the remote tab has ever been opened — drives lazy instantiation.
    @Published private(set) var seenRemote: Bool = false

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        // U1 §6 (pp 2026-09-15 拍板, 覆盖三页引导案): 首启入口 = AA 官方登录页。
        // No stored value (fresh install) therefore lands on .remote, where
        // RootModeTabsView's needsLoginGate raises the full-screen ServiceEntryView;
        // its JO-6 grey button routes to .local. Once the user has chosen, lastTab
        // memory wins — the local tab itself is upstream ContentView, untouched.
        mode = AppSourceMode(rawValue: stored ?? "") ?? .remote
        seenRemote = (mode == .remote)
    }

    /// Deep-link entry (push / approval tap): switch tab, nothing else.
    /// [T1-ISO-PRESENTED-PUSH 2026-09-28] 同值早退 guard：compose 新建链路会在
    /// push 提交的同一 runloop 调 route(.local)，同值赋值虽不动 mode，但
    /// @Published 赋值仍发 objectWillChange → TabView 子树重求值与 push 同帧
    /// （T0 判读记为共线因子；v3 同款无害，此处顺手消除，留字据非行为修复）。
    func route(to target: AppSourceMode) {
        guard mode != target else { return }
        mode = target
    }

    /// B16: the Settings sheet is presented by RootModeTabsView, not by ContentView.
    /// On the Remote tab ContentView is alive but `opacity 0`, and "can an invisible
    /// host present a sheet" is exactly the kind of thing that should not be load-bearing.
    /// One flag, one visible presenter, both tabs use it.
    @Published var showSettings: Bool = false

    /// B16 mirrors, one-way, presentation-only, written by ContentView from its own
    /// existing sources of truth (never the reverse):
    /// `localAtRoot` — the fixed gear must step aside when the local line pushes a chat
    /// (that chat owns its own navigation bar). Same root test as `goHome()`.
    @Published var localAtRoot: Bool = true
    /// `localSelecting` — while rows are checked the page's own toolbar shows Cancel at
    /// this edge, so the fixed gear stands down instead of doubling it.
    @Published var localSelecting: Bool = false

    /// `remoteAtRoot` — 远端线是否在列表根（REMOTE-DEVICE-1：设备详情页 push 时为 false）。
    @Published var remoteAtRoot: Bool = true

    // [TG-TABBAR 2026-09-30] remoteChatPushed 已删（随藏显机制退役）：底栏 =
    // 自绘 ModeTabBar，是一级页 root 页内件——push 的目的地（聊天/设备详情）
    // 从栈内整页盖住含栏的 root 页，不存在"藏栏标志"可写可卡。
}

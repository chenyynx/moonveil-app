// RootTabRouter.swift — the ONLY cross-tab action: pure routing (D4 red line).
// No data flows between tabs; the router just says which one you're looking at.
// Persistence via UserDefaults (lastTab memory, U1 首启入口终案).

import SwiftUI
import Observation

// Moved from ModeTabPicker.swift (bottom-dock batch) — the picker is gone.
/// The app's source modes (D4: the single fork point).
/// CaseIterable order = [.local, .remote, .works, .compose].
enum AppSourceMode: String, CaseIterable, Identifiable {
    case local, remote, works
    /// 新会话按钮（pp 2026-09-26「新会话按钮入口加进tab」→「改到刚刚tab分离
    /// 在右边的圆按钮」：借 TabRole.search 的独立圆形外观，iOS 26 原生）。
    /// ACTION tab，不是页面：点它走 QuickActionRouter 新建本机会话，`mode`
    /// 永不变为 .compose（tabSelection 写拦截），所以不进 lastTab 记忆、
    /// 不参与横滑（手势已删）、tabContent 永不渲染。
    case compose
    var id: String { rawValue }
}

// [TABNAV-observable 2026-09-28] @MainActor 补上：写主全是 UI 路径；ContentView
// 的 `@Bindable private var tabRouter = RootTabRouter.shared` 在默认 MainActor
// 隔离（pbxproj -default-isolation MainActor）下初始化合法。原 B8-FIX 的
// "intentionally NOT @MainActor" 理由（nonisolated struct 存属性初始化）随
// ObservableObject → @Observable 迁移作废。
@MainActor
@Observable
final class RootTabRouter {
    static let shared = RootTabRouter()

    static let storageKey = "app.rootSourceMode"

    var mode: AppSourceMode {
        didSet {
            guard oldValue != mode else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.storageKey)
            // First visit marks the remote tab as "seen" so the shell can keep
            // it alive afterwards (lazy-create once, then both tabs persist).
            if mode == .remote { seenRemote = true }
        }
    }

    /// Whether the remote tab has ever been opened — drives lazy instantiation.
    private(set) var seenRemote: Bool = false

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
    /// push 提交的同一 runloop 调 route(.local)，同值赋值虽不动 mode，但旧
    /// @Published 时代仍发 objectWillChange → TabView 子树重求值与 push 同帧
    /// （T0 判读记为共线因子；v3 同款无害，此处顺手消除，留字据非行为修复）。
    func route(to target: AppSourceMode) {
        guard mode != target else { return }
        mode = target
    }

    /// B16: the Settings sheet is presented by RootModeTabsView, not by ContentView.
    /// On the Remote tab ContentView is alive but `opacity 0`, and "can an invisible
    /// host present a sheet" is exactly the kind of thing that should not be load-bearing.
    /// One flag, one visible presenter, both tabs use it.
    var showSettings: Bool = false

    /// [TABNAV-DEAD-MIRROR 2026-09-28] localAtRoot / localSelecting 镜像已删：
    /// 全仓无读取方（底栏显隐改由 AIChatView 的 .toolbar(.hidden, for: .tabBar)
    /// 自持），ContentView.syncFixedBarFlags 同批移除。

    /// `remoteAtRoot` — 远端线是否在列表根（REMOTE-DEVICE-1：设备详情页 push 时为 false）。
    /// @ObservationIgnored：镜像写不驱动任何视图（gearVisible 等读取方已随
    /// Observation 迁移退场），留标志仅维持写链，避免写入唤醒观察者整链重渲染。
    @ObservationIgnored var remoteAtRoot: Bool = true

    /// 远端聊天页是否已 push（RemoteSessionListView.showsChat 的一线镜像，
    /// 写法同 remoteAtRoot：只写标志，不反向驱动）。
    /// 注意 remoteAtRoot 在设备详情页 push 时也为 false，但设备详情页不藏底栏
    /// （历史行为），所以这里用独立标志，不复用 remoteAtRoot。
    /// @ObservationIgnored 理由同上：纯镜像写，无读取方。
    @ObservationIgnored var remoteChatPushed: Bool = false
}

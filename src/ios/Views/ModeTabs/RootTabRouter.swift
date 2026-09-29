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
    /// 在右边的圆按钮」：借 TabRole.search 的独立圆形外观，iOS 26 原生）。
    /// ACTION tab，不是页面：点它走 QuickActionRouter 新建本机会话，`mode`
    /// 永不变为 .compose（tabSelection 写拦截），所以不进 lastTab 记忆、
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
        }
    }

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

    // [COVER-SHELL 2026-09-30] localAtRoot / localSelecting 已删（死 flag，全仓无
    // 读方；覆盖式结构后不存在任何「底栏显隐数据源」）。

    /// `remoteAtRoot` — 远端线是否在列表根（REMOTE-DEVICE-1：设备详情页 push 时为 false）。
    @Published var remoteAtRoot: Bool = true

    /// 远端聊天页是否已 push（RemoteSessionListView.showsChat 的一线镜像，
    /// 只写标志，不反向驱动）。
    /// 底栏显隐数据源之一：进远端聊天页藏底栏（pp 2026-09-27「tab不进聊天页」延续）。
    /// 注意 remoteAtRoot 在设备详情页 push 时也为 false，但设备详情页不藏底栏
    /// （历史行为），所以这里用独立标志，不复用 remoteAtRoot。
    @Published var remoteChatPushed: Bool = false
}

// MARK: - LocalNavRouter

/// [COVER-SHELL 2026-09-30] 本机线导航 path 的真源（compact 布局）。
///
/// 结构：壳层 `NavigationStack` 包住 `TabView`（RootModeTabsView），本机线的
/// 会话页 push 发生在这一层 —— 二级页整页盖住「含系统 tab 栏的一级页」，
/// 划回 = 原位揭示；全程没有任何「底栏藏/显」机制参与（pp 2026-09-30
/// Telegram 对照拍板：「tab 就是长在一级页面上」）。iOS 26 的 tab 栏
/// hide/show 协调回归因此完全不适用。
///
/// 为什么 path 住在这里而不是 ContentView 的 `@State`：NavigationStack 现在
/// 在壳层，path 必须活在栈绑定方（RootModeTabsView）和逻辑方（ContentView）
/// 都能读写的共享对象里（同 RootTabRouter.shared 先例；两方都以
/// `@ObservedObject` 接入）。
///
/// 写入纪律（[NAV-WRITE-CONFORM 2026-09-30] 已收口）：程序化写一律走本类的
/// 方法，且一律延迟一个 runloop 提交 —— 脱离 tab 选择器 setter / 通知链 /
/// onChange 回调等外来事务上下文。Build 419 真机日志实锤：外部上下文里的
/// path 写会杀死 NavigationStack↔UIKit 的划回回写账本（视觉退出、path 残留、
/// 计数只增不减），而系统驱动的写回（NavigationLink / 划回手势）全正常。
/// 变更形态遵系统规范：append（空栈）/ 整栈替换（非空）+ 显式动画。
/// 系统驱动的变更（NavigationLink push / 划回手势回写）不经此处。
final class LocalNavRouter: ObservableObject {
    static let shared = LocalNavRouter()
    private init() {}

    /// path 单一真源。读方：壳层 NavigationStack 绑定 / ContentView 各观察器。
    @Published var path: [ChatRoute] = []

    /// 程序化 push（原 pushChat 内的 path 写）。[NAV-WRITE-CONFORM 2026-09-30]
    /// 延迟一个 runloop 提交（见类注释；空栈判定挪进延迟块内——以提交时刻的
    /// 真实状态为准；调用侧后台门在调用时刻判定，落地相隔一个 runloop，竞态
    /// 窗口可忽略）。空栈 → append + 显式标准动画；非空 → 整栈替换为
    /// `[route]` + withAnimation(nil)（「回根再展示」语义，原 MIXED-STACK-BAN
    /// 二合一形态，moveto-transfer-race 防护）。
    func commitPush(_ route: ChatRoute) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.path.isEmpty {
                withAnimation(.default) {
                    self.path.append(route)
                }
            } else {
                withAnimation(nil) {
                    self.path = [route]
                }
            }
        }
    }

    /// 回根（原 popToHomeForQuickAction 内的 path 清空）。同上延迟一个
    /// runloop 提交；调用方（ContentView.popToHomeForQuickAction）的簿记
    /// （currentStackSessionId / pendingChatRoute）仍同步清，观察者按旧语义
    /// 以 path 变化为准（该舞蹈本就等待异步落地，多一 tick 不影响）。
    func clearToRoot() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            withAnimation(nil) {
                self.path = []
            }
        }
    }
}

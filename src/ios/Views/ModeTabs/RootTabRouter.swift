// RootTabRouter.swift — the ONLY cross-tab action: pure routing (D4 red line).
// No data flows between tabs; the router just says which one you're looking at.
// Persistence via UserDefaults (lastTab memory, U1 首启入口终案).

import SwiftUI
import Combine
import QuartzCore   // [C3.2] CACurrentMediaTime（树切换标记窗）

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

// NOTE B8-FIX: 曾注「intentionally NOT @MainActor」——[438 审查校正 2026-09-30]
// 现工程配置 SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor，本类型实际即为 MainActor
// 隔离；全部变更源本就是 UI（main），语义未变，仅注释纠偏。
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

            // [切页转场 2026-09-30；v2 收口 2026-09-30] 供 RootModeTabsView 的溶解
            // 窗口用：上一棵树在下层保留，直到新页 alpha 完成即移除。窗口长 = 120ms：
            // TG 真值 = 新页 alpha 动画（0.1s）完成时执行 commit、旧页才 remove
            // （TabBarController.swift:321-326——commit 在 animateAlpha completion 里；
            // 旧版曾误读为「~0.28s 溶解窗口」，实际 0.28 是旧页曲线与新页全动画的
            // 拼算，TG 旧页视图可见期只有 ~0.1s）；本仓经 Task.sleep 留一帧余量。
            // 状态写在这里而非视图 onChange = 与 mode 同步落定，视图首个更新帧就能
            // 读到正确值（视图侧 onChange 先于/后于 body 求值的次序不确定，会造成
            // 旧树闪隐一帧）；窗口结束清空（纯清场，旧树已被新页全盖，无可见变化）。
            previousMode = oldValue
            previousModeClearTask?.cancel()
            previousModeClearTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
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
        // [C3.2→L3 崩溃修复 2026-09-30] 树切换标记：与「程序化切 tab 同帧写容器栈
        // path」的组合会触发 iOS 26 导航状态机断言（build 436 .ips 实锤：
        // EXC_BREAKPOINT in NavigationColumnState.boundPathChange；装机对照：
        // 本地列表点＋（无切 tab）不崩、跨树点＋崩）。⚠️ build 438 实锤「延后
        // 一拍」不够（SwiftUI 帧末统一结算，一跳仍赶进同一窗）；现 ContainerNav
        // .pushChat 消费本标记改走「窗剩余 + 0.25s 尾巴」的动态落点；窗长 0.5s
        // （不变量与 439 返修见 consumeTreeSwipePendingDelay）。（[收口包 v2
        // 2026-09-30 深夜] 8ed7557 曾令 ＋ 热路径「归位先行」依赖本网拆帧；823a841
        // 装机实证手术治愈崩溃后保险牌撤销，本网回归「残余路径公共兜底」定位。）
        treeSwipeAt = CACurrentMediaTime()
    }

    /// 见 route(to:) 的 [C3.2] 注释。返回「把 path 写推迟到安全落点所需的时长」；
    /// nil = 无在窗标记（可直接写 path）。窗内一次性消费（L3 后为残余路径的公共兜底网；
    /// 8ed7557 曾短暂由 ＋ 热路径主消费，823a841 装机后保险牌撤销、回归兜底位）。
    /// 🔴 不变量（438 审查校正 → **439 判例返修 2026-09-30 晚**）：窗长必须 ≥ 树切换
    /// 转场全长。初值 0.35s 被 build 439 装机实锤否证——works 挂载后的重转场（三树 +
    /// 首访文件扫描 + 原生透镜栏）下，旧「固定 0.25s 延后」会重新落回转场窗内，撞出
    /// NavigationColumnState.boundPathChange 同族断言（.ips 帧栈与 436/438 逐帧相同）。
    /// 现改：窗长 0.5s；落点 = **窗剩余 + 0.25s 尾巴**（保证写发生在窗关闭之后，而不是
    /// 赌固定时长刚好越过）。
    func consumeTreeSwipePendingDelay() -> CFTimeInterval? {
        guard treeSwipeAt > 0 else { return nil }
        let since = CACurrentMediaTime() - treeSwipeAt
        guard since < 0.5 else { return nil }
        treeSwipeAt = 0
        return max(0.3, 0.5 - since + 0.25)
    }

    /// 最近一次树切换时刻（CACurrentMediaTime；0 = 无在窗标记）。
    private var treeSwipeAt: CFTimeInterval = 0

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

    // [R1 审查留档 2026-09-30] `localAtRoot` / `localSelecting` = 零消费死 flag（唯一
    // 读点是 ContentView 的打点日志）——与 remoteAtRoot 同判据，但**不在本批删除**：
    // spec §8 已登记归 C5 统一清理（连同 ContentView 的写点/日志块一起处理，避免把
    // 一条日志劈成两次写）。

    // [去嵌套 2026-09-30] `remoteAtRoot` 已删（零消费退役）：原用途 = 远端 push 时
    // 藏外壳顶栏齿轮；该外壳齿轮早已不在此路由（bottom-dock/藏显批次退役），写主
    // （SWIPE-ROOT-RESET / push 栅栏）随去嵌套整体退役。顶栏内容现在由各树 chrome
    // 按 `mode == 树` 门控单独决定，不再需要每树标志。

    // [TG-TABBAR 2026-09-30] remoteChatPushed 已删（随藏显机制退役）：底栏 =
    // 自绘 ModeTabBar，是一级页 root 页内件——push 的目的地（聊天/设备详情）
    // 从栈内整页盖住含栏的 root 页，不存在"藏栏标志"可写可卡。
}

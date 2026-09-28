// LocalNav.swift — 本地 tab 导航状态的唯一写入口：串行化程序化跳转 + 自愈。
// 不要在 onChange / onAppear / 任何回调里直接改 path，全部走 push(_:)。

import SwiftUI
import Observation

/// 替换/串行化流程的落地留痕：NavLog 是 DEBUG-only print，真机（Release/连接 Console
/// 之外的采集）看不到，而这条链的判读必须有设备日志。走 AppLogger（NSLog + 崩溃日志伴写）。
private let navTrace = AppLogger(category: "NavStage")

@MainActor
@Observable
final class LocalNav {
    /// NavigationStack 的唯一数据源：系统回写（swipe-back）和我们的程序化修改都落在这里。
    var path: [Route] = []

    /// 自愈开关：递增会让 NavigationStack 被整体重建，换掉被污染的 coordinator。
    private(set) var stackEpoch = 0

    @ObservationIgnored weak var uiNav: UINavigationController?
    @ObservationIgnored private var reconcileTask: Task<Void, Never>?
    /// 分两段替换的代数：新的 replace 请求作废仍在等待落地的旧请求，避免叠成两次 push。
    @ObservationIgnored private var stagedGeneration = 0

    /// 转场落地轮询参数：50ms × 40 = 2s 上限。
    private static let settlePollIntervalMs = 50
    private static let settlePollLimit = 40

    // MARK: 程序化跳转

    /// 草稿 / deep link / 任何代码触发的导航，只走这一个入口。
    func push(_ route: Route) {
        runWhenSettled { [self] in
            guard path.last != route else { return } // deep link 重复触发时去重
            NavLog.log("PUSH \(route) depth=\(path.count)")
            navTrace.info("PUSH \(route) depth=\(path.count) uiDepth=\(uiNav?.viewControllers.count ?? -1)")
            path.append(route)
        }
    }

    /// 「不管当前在哪，直接换成 X」的语义（新建会话 / move-to / 通知打开）。
    ///
    /// ❌ 单次整写 `path = [route]`（栈非空时）= coordinator 在**同一轮 update** 里
    ///    既移除旧目的地又装新目的地。真机判例（2026-09-28）：UIKit 报
    ///    `Unbalanced calls to begin/end appearance transitions for
    ///    <NavigationStackHostingController>`，随后 coordinator 的
    ///    `willShow → sanitize/ejectDeferred`（见 ContentView onChange(of: nav.path)
    ///    注释里那条崩溃栈点名的同一个例程）把刚装上的宿主视图拆掉 —— path 仍是
    ///    [route]、UIKit 栈深度也对（所以自愈判据抓不到），但内容是空白页，
    ///    直到重新切 tab 触发一次渲染才恢复。
    /// ✅ 栈空 → 退回 push（纯 append 分支，真机验证安全：远端 tab 点新会话走的就是它）；
    ///    栈非空 → 分两段：先无动画清栈，等 UIKit 真正落到根，再 append。
    ///    两段各自只让 coordinator 做一种操作，永不同轮又删又装。
    func replace(with route: Route) {
        let depth = path.count
        NavLog.log("REPLACE with \(route) depth=\(depth)")
        navTrace.info("REPLACE depth=\(depth) route=\(route)")
        guard depth > 0 else {
            push(route)   // 空栈 = 纯 push 分支（真机验证安全）
            return
        }
        stagedGeneration += 1
        let generation = stagedGeneration
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            path.removeAll()
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.waitUntilAtRoot()
            guard generation == self.stagedGeneration else {
                navTrace.info("STAGED superseded gen=\(generation)→\(self.stagedGeneration)")
                return
            }
            guard self.path.isEmpty else {
                // 罕见：清栈窗口内别的入口又 push 了目的地。重跑整条流程，
                // 别把新会话叠在别人上面（「回根再展示」语义）。
                navTrace.info("STAGED re-entrancy path=\(self.path.count) → restart")
                self.replace(with: route)
                return
            }
            navTrace.info("STAGED PUSH route=\(route) uiDepth=\(self.uiNav?.viewControllers.count ?? -1)")
            self.path.append(route)
        }
    }

    /// 回根：quick-action「ensuringHome」等明确要求撤下聊天页的入口。
    /// 不延后——quick action 状态机靠这次写入触发的 onChange 推进 markHome，
    /// hold 到转场结束会把状态机卡住；调用方需自备禁动画 transaction。
    func popToRoot() {
        guard !path.isEmpty else { return }
        NavLog.log("POP-TO-ROOT from depth=\(path.count)")
        path.removeAll()
    }

    /// UIKit 正在转场（push 动画 / 交互式 pop）时，等转场结束、SwiftUI 完成回写之后再改 path。
    /// 依据：UIKit 驱动的 pop，path 的回写发生在转场结束之后；转场窗口内改 path 是已知的失步来源。
    private func runWhenSettled(_ work: @escaping @MainActor () -> Void) {
        guard uiNav?.transitionCoordinator != nil else { work(); return }
        NavLog.log("defer nav write until transition ends")
        Task { @MainActor [weak self] in
            await self?.waitTransitionIdle()
            work()
        }
    }

    // MARK: 转场落地等待

    /// 无活跃转场（拿不到 UINavigationController 视为空闲）。
    private var isTransitionIdle: Bool { uiNav?.transitionCoordinator == nil }

    /// 三方一致：无转场 && UIKit 栈只剩根 && path 已空 —— 替换流程的第二段必须等这个态。
    private var isAtRoot: Bool {
        isTransitionIdle && path.isEmpty && (uiNav?.viewControllers.count ?? 1) <= 1
    }

    private func waitTransitionIdle() async {
        await pollUntilSettled({ [weak self] in self?.isTransitionIdle ?? true }, tag: "transition-idle")
    }

    private func waitUntilAtRoot() async {
        await pollUntilSettled({ [weak self] in self?.isAtRoot ?? true }, tag: "at-root")
    }

    /// 轮询直到 `settled()` **连续两次**成立（沿用 scheduleReconcile 的二次确认纪律：
    /// 单帧采样可能读到转场回调之间的一帧空档）。
    ///
    /// 为什么不用 `transitionCoordinator.animate(alongsideTransition:)` 的完成回调：
    /// 回调在转场被取消 / App 中途进后台时可能永不触发，挂在上面的写入随之丢失 ——
    /// 表现就是「点了新会话没反应」，与它要修的空白页同样糟。轮询到上限后照常放行。
    private func pollUntilSettled(_ settled: @escaping @MainActor () -> Bool, tag: String) async {
        var consecutive = 0
        for _ in 0..<Self.settlePollLimit {
            if settled() {
                consecutive += 1
                if consecutive >= 2 { return }
            } else {
                consecutive = 0
            }
            try? await Task.sleep(for: .milliseconds(Self.settlePollIntervalMs))
        }
        NavLog.log("⚠️ \(tag) settle timed out — proceeding anyway (uiDepth=\(uiNav?.viewControllers.count ?? -1) path=\(path.count))")
        navTrace.warning("\(tag) settle timed out (uiDepth=\(uiNav?.viewControllers.count ?? -1) path=\(path.count)) — proceeding")
    }

    // MARK: 自愈

    /// 在根视图 onAppear / scenePhase 变 active 时调用。去抖 + 二次确认：
    /// 只有"无转场 && UIKit 栈深度 ≠ path.count"连续两次成立，才重建 NavigationStack。
    func scheduleReconcile() {
        reconcileTask?.cancel()
        reconcileTask = Task { @MainActor [weak self] in
            for _ in 0..<2 {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, let nav = self, nav.isDesynced else { return }
            }
            self?.rebuildStack()
        }
    }

    /// 单通道之后，这个等式才是可靠的不变量：UIKit 栈深度（去掉根）== path.count。
    /// ⚠️ 启用自愈前，先用 NavLog.dump 的日志确认真机上确实成立。
    private var isDesynced: Bool {
        guard let ui = uiNav, ui.transitionCoordinator == nil else { return false }
        return ui.viewControllers.count - 1 != path.count
    }

    private func rebuildStack() {
        let depth = (uiNav?.viewControllers.count ?? 1) - 1
        NavLog.log("⚠️ DESYNC uiDepth=\(depth) path=\(path.count) → rebuild NavigationStack")
        path.removeAll()
        stackEpoch += 1
    }
}

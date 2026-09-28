// LocalNav.swift — 本地 tab 导航状态的唯一写入口：串行化程序化跳转 + 自愈。
// 不要在 onChange / onAppear / 任何回调里直接改 path，全部走 push(_:)。

import SwiftUI
import Observation

@MainActor
@Observable
final class LocalNav {
    /// NavigationStack 的唯一数据源：系统回写（swipe-back）和我们的程序化修改都落在这里。
    var path: [Route] = []

    /// 自愈开关：递增会让 NavigationStack 被整体重建，换掉被污染的 coordinator。
    private(set) var stackEpoch = 0

    @ObservationIgnored weak var uiNav: UINavigationController?
    @ObservationIgnored private var reconcileTask: Task<Void, Never>?

    // MARK: 程序化跳转

    /// 草稿 / deep link / 任何代码触发的导航，只走这一个入口。
    func push(_ route: Route) {
        runWhenSettled { [self] in
            guard path.last != route else { return } // deep link 重复触发时去重
            NavLog.log("PUSH \(route)")
            path.append(route)
        }
    }

    /// UIKit 正在转场（push 动画 / 交互式 pop）时，等转场结束、SwiftUI 完成回写之后再改 path。
    /// 依据：UIKit 驱动的 pop，path 的回写发生在转场结束之后；转场窗口内改 path 是已知的失步来源。
    private func runWhenSettled(_ work: @escaping @MainActor () -> Void) {
        guard let tc = uiNav?.transitionCoordinator else { work(); return }
        NavLog.log("defer nav write until transition ends")
        _ = tc.animate(alongsideTransition: nil) { _ in
            Task { @MainActor in work() }
        }
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

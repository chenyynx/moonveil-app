// NavLog.swift — 导航诊断工具（仅 DEBUG 输出）。

import UIKit

enum NavLog {
    private static let t0 = ProcessInfo.processInfo.systemUptime

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let t = ProcessInfo.processInfo.systemUptime - t0
        print(String(format: "[NAV +%.3f] ", t) + message())
        #endif
    }

    /// 关键诊断：UINavigationController 的 delegate / 侧滑手势 delegate 有没有被换掉、
    /// 栈深度与 path 是否一致、此刻是否处于转场中。
    @MainActor
    static func dump(_ nav: UINavigationController) {
        let d = nav.delegate.map { String(describing: type(of: $0)) } ?? "nil"
        let g = nav.interactivePopGestureRecognizer?.delegate.map { String(describing: type(of: $0)) } ?? "nil"
        log("UINav depth=\(nav.viewControllers.count) delegate=\(d) popGestureDelegate=\(g) transitioning=\(nav.transitionCoordinator != nil)")
    }
}

/// 冷启动窗口的主线程卡顿监视：App 启动时 HitchMonitor().start() 一次即可。
/// 把 HITCH 日志与"点行 / push / 侧滑"的时间戳对齐，判断转场是否被拉长、是否重叠。
@MainActor
final class HitchMonitor: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0

    func start(for seconds: TimeInterval = 8) {
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.link?.invalidate()
            self?.link = nil
        }
    }

    @objc private func tick(_ l: CADisplayLink) {
        defer { last = l.timestamp }
        guard last > 0, l.timestamp - last > 0.05 else { return }
        NavLog.log("HITCH \(Int((l.timestamp - last) * 1000)) ms")
    }
}

import Foundation
import QuartzCore
import SwiftUI

/// [V9-NAVTRACE 2026-09-29] 只读观测：导航卡死漏斗计数 + safe-area 传播读数。
/// 全部 no-op 日志，不改任何行为。真机判读结论后整体删除。
enum NavTrace {
    // All callers are main-thread UI code (SwiftUI bodies, onChange, DispatchQueue.main).
    // nonisolated(unsafe): debug-only counters, no cross-thread access by design.
    nonisolated(unsafe) private static var seq = 0
    private static let t0 = CACurrentMediaTime()
    nonisolated(unsafe) static var trigger = "-"
    static var age: String { String(format: "%.2f", CACurrentMediaTime() - t0) }

    static func log(_ msg: String) {
        seq += 1
        AppLogger(category: "NavTrace").info("[NAV] #\(seq) \(msg)")
    }

    static func mark(_ t: String) { trigger = t }
}

extension View {
    /// [V9-C6] 满尺寸 safe-area 读数探针。挂外层容器，读真实底部安全区。
    func debugSafeBottom(_ tag: String) -> some View {
        background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        let b = geo.safeAreaInsets.bottom
                        AppLogger(category: "NavTrace").info("[SAFE] \(tag) bottom=\(b)")
                    }
                    .onChange(of: geo.safeAreaInsets.bottom) { _, b in
                        AppLogger(category: "NavTrace").info("[SAFE] \(tag) bottom=\(b) (chg)")
                    }
            }
        }
    }
}

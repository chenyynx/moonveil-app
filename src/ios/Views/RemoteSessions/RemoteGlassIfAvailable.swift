// RemoteGlassIfAvailable.swift — 远端线聊天页批（P1）的 iOS 26 glass 守卫。
//
// 背景（铁律④）：官方 origin-cache 部署目标 26.5，glassEffect 全家裸用；本仓主
// target 17.0。先例：AuthGlassCompat / AppGlassButton（B8-FIX）/ ChatComposer
// （COMPOSER-FULL 批）——26+ 用官方 EXACT 参数，<26 用系统最接近物
// （.regularMaterial 圆角/胶囊背景），不发明玻璃。
//
// 逐字对照（官方调用点 → 本文件等价物）：
// - `.glassEffect(.regular, in: .rect(cornerRadius: 24))`  → `remoteGlassCard()`
// - `.glassEffect(.regular.interactive(), in: .capsule)`   → `remoteGlassCapsule(interactive:)`
// - `.buttonStyle(.glass)` → 复用既有 `SecondaryButtonStyleIfAvailable`（AppGlassButton.swift）
// - `.scrollEdgeEffectStyle(.soft, for: .all)` → `aaScrollEdgeSoft()`（iOS 18 守卫，<18 不施加）

import SwiftUI

private struct GlassCardIfAvailable: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

private struct RemoteGlassCapsuleIfAvailable: ViewModifier {
    let interactive: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

extension View {
    /// 官方 `.glassEffect(.regular, in: .rect(cornerRadius: 24))`。
    func remoteGlassCard() -> some View { modifier(GlassCardIfAvailable()) }
    /// 官方 `.glassEffect(.regular[.interactive()], in: .capsule)`。
    func remoteGlassCapsule(interactive: Bool = false) -> some View {
        modifier(RemoteGlassCapsuleIfAvailable(interactive: interactive))
    }
}

/// `onScrollVisibilityChange` 是 iOS 18 API（官方 timeline 分页/尾随状态用）。
/// <18 无对应回调 → 不触发：该状态只被 18+ 的滚动编排消费（旧路径不使用）。
struct ScrollVisibilityIfAvailable: ViewModifier {
    let threshold: CGFloat?
    let action: (Bool) -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            if let threshold {
                content.onScrollVisibilityChange(threshold: threshold) { visible in action(visible) }
            } else {
                content.onScrollVisibilityChange { visible in action(visible) }
            }
        } else {
            content
        }
    }
}

extension View {
    func aaScrollVisibility(threshold: CGFloat? = nil, _ action: @escaping (Bool) -> Void) -> some View {
        modifier(ScrollVisibilityIfAvailable(threshold: threshold, action: action))
    }
}

/// `scrollEdgeEffectStyle` 是 iOS 18 API（官方文件页 List 用 `.soft, for: .all`）。
/// <18 不施加任何效果：这是系统滚动边缘样式的缺失，不是功能缺失，不发明替代模糊层。
private struct ScrollEdgeSoftIfAvailable: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            content
        }
    }
}

extension View {
    /// 官方 `.scrollEdgeEffectStyle(.soft, for: .all)`。
    func aaScrollEdgeSoft() -> some View { modifier(ScrollEdgeSoftIfAvailable()) }
}

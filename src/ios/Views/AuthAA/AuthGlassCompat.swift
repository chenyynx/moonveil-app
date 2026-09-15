// AuthGlassCompat.swift — B8-AUTH availability shim (PATCHES.md B8-AUTH).
// Upstream AA (deployment target 26.5) calls `.glassEffect` ungated; Moonveil's
// floor is iOS 17 (DEP-17), so each call site needs an availability check.
// On iOS 26+ this applies the EXACT upstream parameters. Below that it renders
// nothing extra — the sibling `.background(...)` fill already present at each
// site is the fallback (SearchBarSurface precedent: no custom blur on <26).
import SwiftUI

struct GlassCapsuleIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.glassEffect(.regular, in: .capsule) } else { content }
    }
}

struct GlassRounded28IfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
        } else { content }
    }
}

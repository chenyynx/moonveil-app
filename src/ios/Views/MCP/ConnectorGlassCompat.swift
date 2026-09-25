// ConnectorGlassCompat.swift — iOS 26 glassEffect availability shims for Connectors UI.
// Moonveil's deployment floor is iOS 17, so each `.glassEffect` call site needs
// an `if #available` guard. On iOS 26+ this applies the exact liquid-glass
// parameters (translucent white tint + interactive). Below iOS 26 it falls back
// to a plain translucent white fill in the same shape.
import SwiftUI

struct GlassCircleButtonIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(.white.opacity(0.75)).interactive(), in: Circle())
        } else {
            content.background(Circle().fill(Color.white.opacity(0.75)))
        }
    }
}

struct GlassCapsuleButtonIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(.white.opacity(0.5)).interactive(), in: Capsule())
        } else {
            content.background(Capsule().fill(Color.white.opacity(0.5)))
        }
    }
}

/// Liquid glass in a continuous-corner rounded rectangle (icon wells, hero).
/// Falls back to the same translucent white fill pre-iOS 26.
struct GlassRoundedRectIfAvailable: ViewModifier {
    var cornerRadius: CGFloat
    var tintOpacity: Double = 0.6

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(.white.opacity(tintOpacity)).interactive(), in: shape)
        } else {
            content.background(shape.fill(Color.white.opacity(tintOpacity)))
        }
    }
}

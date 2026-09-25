// ConnectorGlassCompat.swift — iOS 26 glassEffect availability shims for Connectors UI.
// Moonveil's deployment floor is iOS 17, so each `.glassEffect` call site needs
// an `if #available` guard. On iOS 26+ this applies the exact liquid-glass
// parameters (translucent white tint + interactive). Below iOS 26 it falls back
// to a translucent fill in the same shape — white in light mode, elevated gray
// in dark mode so the chrome doesn't glare on the dark canvas.
import SwiftUI

private let glassFillColor = Color(UIColor { trait in
    trait.userInterfaceStyle == .dark
        ? UIColor(white: 1.0, alpha: 0.12)
        : UIColor(white: 1.0, alpha: 0.75)
})

struct GlassCircleButtonIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(Circle().fill(.white))
                .glassEffect(.regular.tint(.white.opacity(0.75)).interactive(), in: Circle())
        } else {
            content.background(Circle().fill(glassFillColor))
        }
    }
}

struct GlassCapsuleButtonIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(Capsule().fill(.white))
                .glassEffect(.regular.tint(.white.opacity(0.5)).interactive(), in: Capsule())
        } else {
            content.background(Capsule().fill(glassFillColor.opacity(0.7)))
        }
    }
}

/// Liquid glass in a continuous-corner rounded rectangle (hero tile).
/// Falls back to the same translucent fill pre-iOS 26.
/// Deliberately NOT `.interactive()` — the hero logo must stay locked on
/// press (no zoom/highlight animation); interactive feedback is reserved
/// for actual buttons (close key, CTA).
struct GlassRoundedRectIfAvailable: ViewModifier {
    var cornerRadius: CGFloat
    var tintOpacity: Double = 0.6

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .background(shape.fill(.white))
                .glassEffect(.regular.tint(glassTint.opacity(tintOpacity)), in: shape)
        } else {
            content.background(shape.fill(glassFillColor.opacity(tintOpacity / 0.75)))
        }
    }
}

/// White glass reads correct in light mode; in dark mode the white tint is
/// pulled way down so surfaces stay dark under the blur.
private let glassTint = Color(UIColor { trait in
    trait.userInterfaceStyle == .dark
        ? UIColor(white: 1.0, alpha: 0.22)
        : UIColor.white
})

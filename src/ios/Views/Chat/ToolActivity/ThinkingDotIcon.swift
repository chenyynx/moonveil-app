import SwiftUI

// MARK: - Thinking Dot Icon (3×3 animated grip dots)
//
// [A2, 报告§图标动画补验, frames/33-35] Grok-style thinking indicator:
// a 2-3 dot lit band departs from the top-right (NE) and patrols the outer
// ring counter-clockwise (NE→N→NW→W→SW→S→SE→E), then slides into the
// center point to collapse → all dots dim and rest → restarts from NE.
// Total cycle ~1.6s (orbit 0.9s + collapse 0.3s + rest 0.4s).
// Lit state = larger + ink; dim state = smaller + light gray.
// Exact diameters/speeds are on-device calibration items (video compression
// smoothed the edges).

struct ThinkingDotIcon: View {
    var size: CGFloat = 16
    /// Lit dot color (follows label color by default — black in light mode).
    var inkColor: Color = .primary
    var dimColor: Color = Color(uiColor: .systemGray4)

    private static let cycle: Double = 1.6
    private static let orbit: Double = 0.9
    private static let collapse: Double = 0.3

    /// Outer-ring grid positions in patrol order (counter-clockwise, starting
    /// NE). Grid coordinates 0...2; center is (1, 1).
    private static let ring: [(CGFloat, CGFloat)] = [
        (2, 0), (1, 0), (0, 0), (0, 1), (0, 2), (1, 2), (2, 2), (2, 1)
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, sz in
                let t = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: Self.cycle)
                let cell = sz.width / 3
                let dimD = cell * 0.30
                let hotD = cell * 0.46

                func pos(_ gx: CGFloat, _ gy: CGFloat) -> CGPoint {
                    CGPoint(x: cell / 2 + gx * cell, y: cell / 2 + gy * cell)
                }
                func dot(_ at: CGPoint, _ d: CGFloat, _ c: Color) {
                    context.fill(
                        Path(ellipseIn: CGRect(x: at.x - d / 2, y: at.y - d / 2, width: d, height: d)),
                        with: .color(c)
                    )
                }

                let center = pos(1, 1)

                if t < Self.orbit {
                    // Orbit: floating head index along the ring; head + decay
                    // tail form the 2-3 dot lit band.
                    let head = Double(t / Self.orbit) * 8
                    for i in 0..<8 {
                        var d = head - Double(i)
                        if d < 0 { d += 8 }
                        let glow: Double
                        if d < 1 { glow = 1 }
                        else if d < 2 { glow = 2 - d }
                        else { glow = 0 }
                        if glow > 0 {
                            let p = pos(Self.ring[i].0, Self.ring[i].1)
                            dot(p, dimD + (hotD - dimD) * CGFloat(glow),
                                dimColor.mix(with: inkColor, by: glow))
                        }
                    }
                } else if t < Self.orbit + Self.collapse {
                    // Collapse: head slides from NE into the center, which
                    // lights up as it arrives.
                    let q = (t - Self.orbit) / Self.collapse
                    let from = pos(Self.ring[0].0, Self.ring[0].1)
                    let p = CGPoint(
                        x: from.x + (center.x - from.x) * CGFloat(q),
                        y: from.y + (center.y - from.y) * CGFloat(q)
                    )
                    dot(p, hotD, inkColor)
                    if q > 0.55 {
                        dot(center, dimD + (hotD - dimD) * CGFloat((q - 0.55) / 0.45),
                            inkColor)
                    }
                }
                // Rest phase: nothing lit — draw the dim grid only.

                // Dim base grid (always, under anything lit).
                for i in 0..<8 {
                    dot(pos(Self.ring[i].0, Self.ring[i].1), dimD, dimColor)
                }
                if t < Self.orbit || t >= Self.orbit + Self.collapse {
                    // Center stays dim except while the collapse head is in.
                    dot(center, dimD, dimColor)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private extension Color {
    /// Linear mix toward another color (amount 0...1). Canvas-safe (no UIKit).
    func mix(with other: Color, by amount: Double) -> Color {
        let a = min(max(amount, 0), 1)
        // Color.Resolved components are Float; `a` is Double. Mixed
        // arithmetic inside one Color(...) init blows the Swift type
        // checker (CI ×2), so each channel is its own statement with an
        // explicit Double conversion.
        let lhs = resolve(in: EnvironmentValues())
        let rhs = other.resolve(in: EnvironmentValues())
        let r = Double(lhs.red) + (Double(rhs.red) - Double(lhs.red)) * a
        let g = Double(lhs.green) + (Double(rhs.green) - Double(lhs.green)) * a
        let b = Double(lhs.blue) + (Double(rhs.blue) - Double(lhs.blue)) * a
        let o = Double(lhs.opacity) + (Double(rhs.opacity) - Double(lhs.opacity)) * a
        return Color(red: r, green: g, blue: b, opacity: o)
    }
}

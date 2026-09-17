import SwiftUI

// MARK: - Thinking Dot Icon (3×3 animated grip dots)
//
// [A2 v2, 2026-09-17 帧级重做] pp 装机判「跟 Grok 天差地别」→ 按
// frames/33/34 帧网格逐帧重做。与 v1 的差异（全部以帧证据为准）：
//   1. 所有点【同尺寸】—— v1 的「亮态大、暗态小」是错的，Grok 只变颜色；
//   2. 亮团 ≈3 点恒定长度：头(新亮)最深、尾渐隐，沿外圈【逆时针】8 站
//      NE→N→NW→W→SW→S→SE→E 平滑巡游；
//   3. 收拢：团头从【右中 E】滑向中心（v1 错从 NE 滑）；
//   4. 中心亮起后有独立【淡出段】，再进入全灰休止；
//   5. 周期 ~2.0s：orbit 1.0 + collapse 0.3 + center-fade 0.45 + rest 0.25
//      （帧网格相对比例推算，绝对值装机校准）。
// 色值：暗点 ≈#C9C9C9，亮点 ≈#1A1A1A（对比强，无尺寸差）。

struct ThinkingDotIcon: View {
    var size: CGFloat = 18
    /// Lit dot color (follows label color by default).
    var inkColor: Color = .primary
    var dimColor: Color = Color(red: 0.788, green: 0.788, blue: 0.788) // ≈#C9C9C9

    private static let cycle: Double = 2.0
    private static let orbit: Double = 1.0      // 8 站巡游
    private static let collapse: Double = 0.3   // E → center 滑入
    private static let centerFade: Double = 0.45 // 中心亮→淡出

    /// 外圈 8 站，逆时针巡游顺序（格坐标 0...2）：NE→N→NW→W→SW→S→SE→E。
    private static let ring: [(CGFloat, CGFloat)] = [
        (2, 0), (1, 0), (0, 0), (0, 1), (0, 2), (1, 2), (2, 2), (2, 1)
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, sz in
                let t = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: Self.cycle)
                let cell = sz.width / 3
                let d = cell * 0.34 // 所有点同尺寸 [帧证据 ①]

                func pos(_ gx: CGFloat, _ gy: CGFloat) -> CGPoint {
                    CGPoint(x: cell / 2 + gx * cell, y: cell / 2 + gy * cell)
                }
                func dot(_ at: CGPoint, _ glow: Double) {
                    let c = glow <= 0 ? dimColor
                        : dimColor.mix(with: inkColor, by: glow)
                    context.fill(
                        Path(ellipseIn: CGRect(x: at.x - d / 2, y: at.y - d / 2, width: d, height: d)),
                        with: .color(c)
                    )
                }

                let center = pos(1, 1)

                // 每个环点的亮量（0=暗 → 1=全黑）。
                var glow = [Double](repeating: 0, count: 8)
                var centerGlow = 0.0
                var headPos: CGPoint? // collapse 阶段的移动头（画在插值位置）

                if t < Self.orbit {
                    // 巡游：head 沿环平滑推进；头深尾渐隐，团长 ~3 点。
                    let head = Double(t / Self.orbit) * 8
                    for i in 0..<8 {
                        var dist = head - Double(i)
                        if dist < 0 { dist += 8 }
                        if dist < 1 {
                            glow[i] = 1 // 头
                        } else if dist < 3 {
                            glow[i] = 1 - (dist - 1) / 2 // 尾部线性渐隐
                        }
                    }
                } else if t < Self.orbit + Self.collapse {
                    // 收拢：头从 E（环末站）滑向中心；环上团整体淡出。
                    let q = (t - Self.orbit) / Self.collapse
                    let from = pos(Self.ring[7].0, Self.ring[7].1) // E = 右中
                    headPos = CGPoint(
                        x: from.x + (center.x - from.x) * CGFloat(q),
                        y: from.y + (center.y - from.y) * CGFloat(q)
                    )
                    centerGlow = q
                    for i in 0..<8 {
                        var dist = Double(8) - Double(i) // 相对环末的尾距
                        if dist < 1 { glow[i] = 1 - q }
                        else if dist < 3 { glow[i] = (1 - (dist - 1) / 2) * (1 - q) }
                    }
                } else if t < Self.orbit + Self.collapse + Self.centerFade {
                    // 中心淡出段 [帧证据 ④]
                    centerGlow = 1 - (t - Self.orbit - Self.collapse) / Self.centerFade
                }
                // rest：全灰（glow 全 0）

                // 底层：先画暗点（全部 9 点同尺寸）。
                for i in 0..<8 {
                    dot(pos(Self.ring[i].0, Self.ring[i].1), glow[i])
                }
                dot(center, centerGlow)
                if let hp = headPos {
                    // 收拢头的移动位置与环末/中心叠加绘制（同色，视觉上是一颗移动点）。
                    context.fill(
                        Path(ellipseIn: CGRect(x: hp.x - d / 2, y: hp.y - d / 2, width: d, height: d)),
                        with: .color(inkColor)
                    )
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private extension Color {
    /// Linear mix toward another color (amount 0...1). Canvas-safe (no UIKit).
    /// 每通道独立语句 + 显式 Double 转换（CI 判例：混合浮点宽度塞一个重载
    /// init 会炸类型检查器）。
    func mix(with other: Color, by amount: Double) -> Color {
        let a = min(max(amount, 0), 1)
        let lhs = resolve(in: EnvironmentValues())
        let rhs = other.resolve(in: EnvironmentValues())
        let r = Double(lhs.red) + (Double(rhs.red) - Double(lhs.red)) * a
        let g = Double(lhs.green) + (Double(rhs.green) - Double(lhs.green)) * a
        let b = Double(lhs.blue) + (Double(rhs.blue) - Double(lhs.blue)) * a
        let o = Double(lhs.opacity) + (Double(rhs.opacity) - Double(lhs.opacity)) * a
        return Color(red: r, green: g, blue: b, opacity: o)
    }
}

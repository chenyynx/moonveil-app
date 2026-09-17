import SwiftUI

// MARK: - Comet Spinner (渐变圆环)
//
// [B7, 报告§2.3/§三] Black head -> light tail comet arc, clockwise, 1.4s/turn.
// 2026-09-18: ToolCardView（Grok 描边卡）随汇聚页改版（Claude Summary 时间线
// 列表，pp 09-18 指令）退役删除；本文件现仅承载运行态使用的 CometSpinner。

// MARK: - Comet Spinner (渐变圆环)
//
// [B7, 报告§2.3/§三] Black head → light tail comet arc, clockwise, 1.4s/turn.

struct CometSpinner: View {
    var size: CGFloat = 14
    var color: Color = .primary
    private static let period: Double = 1.4

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, sz in
                let t = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: Self.period)
                let head = t / Self.period * 2 * .pi
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let r = sz.width / 2 - 1.5
                let segments = 14
                for i in 0..<segments {
                    let a = head - Double(i) * 0.09
                    let fade = 1.0 - Double(i) / Double(segments)
                    var p = Path()
                    p.addArc(center: c, radius: r,
                             startAngle: .radians(a), endAngle: .radians(a + 0.09),
                             clockwise: false)
                    context.stroke(p, with: .color(color.opacity(0.15 + 0.85 * fade)), lineWidth: 1.8)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

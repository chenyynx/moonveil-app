// RemoteSessionIcon.swift — 远端会话卡片统一图标（lucide message-square-quote）
//
// 远端会话行的头像图标统一用 lucide 的 message-square-quote
// (https://lucide.dev/icons/message-square-quote)，替代本机侧的分类图标。
// 由 lucide-static 1.47.0（ISC 协议）的 3 条 path 精确转换：每条 SVG 圆弧
// （端点参数化）经圆心推导拆成 ≤90° 的三次贝塞尔，起点与当前点严格相接，
// 杜绝 addArc 起点不重合导致的 CoreGraphics 补线。

import SwiftUI

struct RemoteSessionIcon: View {
    var size: CGFloat = 20
    var color: Color = .primary

    var body: some View {
        RemoteMessageSquareQuoteShape()
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

/// lucide message-square-quote 的描边形状（viewBox 24×24，stroke 2，round caps/joins）。
struct RemoteMessageSquareQuoteShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let o = CGPoint(x: (rect.width - 24 * s) / 2, y: (rect.height - 24 * s) / 2)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: o.x + x * s, y: o.y + y * s)
        }
        var p = Path()
        // 气泡外框（path 2）：M22 17 a2 2 0 0 1 -2 2 H6.828 a2 2 0 0 0 -1.414 .586
        //   l-2.202 2.202 A.71 .71 0 0 1 2 21.286 V5 a2 2 0 0 1 2 -2 h16 a2 2 0 0 1 2 2 z
        p.move(to: pt(22, 17))
        p.addSVGArc(from: pt(22, 17), to: pt(20, 19), radius: 2 * s, largeArc: false, sweep: true)
        p.addLine(to: pt(6.828, 19))
        p.addSVGArc(from: pt(6.828, 19), to: pt(5.414, 19.586), radius: 2 * s, largeArc: false, sweep: false)
        p.addLine(to: pt(3.212, 21.788))
        p.addSVGArc(from: pt(3.212, 21.788), to: pt(2, 21.286), radius: 0.71 * s, largeArc: false, sweep: true)
        p.addLine(to: pt(2, 5))
        p.addSVGArc(from: pt(2, 5), to: pt(4, 3), radius: 2 * s, largeArc: false, sweep: true)
        p.addLine(to: pt(20, 3))
        p.addSVGArc(from: pt(20, 3), to: pt(22, 5), radius: 2 * s, largeArc: false, sweep: true)
        p.closeSubpath() // 右边：(22,5) → 起点 (22,17)
        // 右引号（path 1）：M14 14 a2 2 0 0 0 2 -2 V8 h-2
        p.move(to: pt(14, 14))
        p.addSVGArc(from: pt(14, 14), to: pt(16, 12), radius: 2 * s, largeArc: false, sweep: false)
        p.addLine(to: pt(16, 8))
        p.addLine(to: pt(14, 8))
        // 左引号（path 3）：M8 14 a2 2 0 0 0 2 -2 V8 H8
        p.move(to: pt(8, 14))
        p.addSVGArc(from: pt(8, 14), to: pt(10, 12), radius: 2 * s, largeArc: false, sweep: false)
        p.addLine(to: pt(10, 8))
        p.addLine(to: pt(8, 8))
        return p
    }
}

private extension Path {
    /// SVG 圆弧（端点参数化：起点/终点/半径/大弧标志/扫掠标志）→ 三次贝塞尔。
    /// 按 ≤90° 分段；圆心由 p1/p2 与标志位推导，贝塞尔首尾严格落在弧端点上。
    /// SVG 与本坐标系同为 y 轴向下，sweep=1 即角度递增，公式直接沿用。
    mutating func addSVGArc(from p1: CGPoint, to p2: CGPoint, radius rIn: CGFloat,
                            largeArc: Bool, sweep: Bool) {
        let dx = (p1.x - p2.x) / 2
        let dy = (p1.y - p2.y) / 2
        let halfChord2 = dx * dx + dy * dy
        guard halfChord2 > 0 else { return }
        var r = rIn
        var r2 = r * r
        if halfChord2 > r2 { // 半径过小容纳不了弦：按 SVG 规范放大到恰好
            r = halfChord2.squareRoot()
            r2 = r * r
        }
        let factor = ((r2 - halfChord2) / halfChord2).squareRoot()
            * (largeArc == sweep ? CGFloat(-1) : CGFloat(1))
        let c = CGPoint(x: (p1.x + p2.x) / 2 + factor * dy,
                        y: (p1.y + p2.y) / 2 - factor * dx)
        let theta1 = atan2(p1.y - c.y, p1.x - c.x)
        var dTheta = atan2(p2.y - c.y, p2.x - c.x) - theta1
        if sweep, dTheta < 0 { dTheta += 2 * .pi }
        if !sweep, dTheta > 0 { dTheta -= 2 * .pi }
        let segs = max(1, Int(ceil(abs(dTheta) / (.pi / 2))))
        let step = dTheta / CGFloat(segs)
        let alpha = (4 / 3) * tan(step / 4) * r
        var t = theta1
        var cur = p1
        for _ in 0..<segs {
            let t2 = t + step
            let end = CGPoint(x: c.x + r * cos(t2), y: c.y + r * sin(t2))
            let b1 = CGPoint(x: cur.x - alpha * sin(t), y: cur.y + alpha * cos(t))
            let b2 = CGPoint(x: end.x + alpha * sin(t2), y: end.y - alpha * cos(t2))
            addCurve(to: end, control1: b1, control2: b2)
            cur = end
            t = t2
        }
    }
}

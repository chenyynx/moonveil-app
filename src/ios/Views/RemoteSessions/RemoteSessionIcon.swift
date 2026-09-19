// RemoteSessionIcon.swift — 远端会话卡片统一图标（lucide message-square-quote）
//
// 远端会话行的头像图标统一用 lucide 的 message-square-quote
// (https://lucide.dev/icons/message-square-quote)，替代本机侧的分类图标。
// SVG 路径从 lucide-static 1.47.0 原样取用（ISC 协议），转 SwiftUI Shape 渲染。

import SwiftUI

struct RemoteSessionIcon: View {
    var size: CGFloat = 20
    var color: Color = .primary

    var body: some View {
        RemoteMessageSquareQuoteShape()
            .stroke(color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

/// lucide message-square-quote 的路径（viewBox 24×24，stroke 2，round caps/joins）。
struct RemoteMessageSquareQuoteShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let o = CGPoint(x: (rect.width - 24 * s) / 2, y: (rect.height - 24 * s) / 2)
        return Path { p in
            // 气泡外框
            p.move(to: pt(4, 3, s, o))
            p.addLine(to: pt(20, 3, s, o))
            p.addArc(center: pt(20, 5, s, o), radius: 2 * s,
                     startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: pt(22, 17, s, o))
            p.addArc(center: pt(20, 17, s, o), radius: 2 * s,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: pt(6.83, 19, s, o))
            p.addArc(center: pt(6.83, 19.83, s, o), radius: 1 * s,
                     startAngle: .degrees(-90), endAngle: .degrees(135), clockwise: false)
            p.addLine(to: pt(2.7, 21.87, s, o))
            p.addArc(center: pt(2.01, 21.58, s, o), radius: 1 * s,
                     startAngle: .degrees(45), endAngle: .degrees(180), clockwise: false)
            p.addLine(to: pt(2, 5, s, o))
            p.addArc(center: pt(4, 5, s, o), radius: 2 * s,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            p.closeSubpath()
            // 右引号
            p.move(to: pt(14, 14, s, o))
            p.addArc(center: pt(16, 12, s, o), radius: 2 * s,
                     startAngle: .degrees(90), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: pt(16, 8, s, o))
            p.addLine(to: pt(14, 8, s, o))
            // 左引号
            p.move(to: pt(8, 14, s, o))
            p.addArc(center: pt(10, 12, s, o), radius: 2 * s,
                     startAngle: .degrees(90), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: pt(10, 8, s, o))
            p.addLine(to: pt(8, 8, s, o))
        }
    }

    private func pt(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ o: CGPoint) -> CGPoint {
        CGPoint(x: o.x + x * s, y: o.y + y * s)
    }
}

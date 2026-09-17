import SwiftUI

// MARK: - Slow Shimmer (breathing dim)
//
// [A7/B5, 09-17 帧级实测] Grok sheet 内「思考中……」与「思考结果」标题的扫光：
// 整行文字变浅→恢复（呼吸型，非亮带横掠）。实测：~0.5s/波、波峰周期 ~2.6s、
// 打开后首扫延迟 ~3.0s。全部参数列入装机校准清单（H.264 抹平了精确曲线）。
// 聊天内 Thinking 文字实测无扫光 —— 本修饰器仅用于汇聚页（sheet）。

// MARK: - Claude Text Sweep Shimmer [pp 09-18：1:1 复刻 cds-shimmer-text-shine]
//
// 参数实抓自 claude.ai 生产 CSS（assets-proxy.anthropic.com c6a992d55 bundle）：
//   @keyframes cds-shimmer-text-shine {
//     0%,15%   { background-position: 83.333% 0; timing: cubic-bezier(.714,.121,.211,.888) }
//     85%,100% { background-position: 16.667% 0 } }
//   应用 = 3s linear infinite；峰色 = color-mix(in srgb, <text> 30%, white)
// ⇒ 方向【右→左】、3s 周期、每圈前 15%/后 15% 静止、S 曲线缓动、
//   亮带 ≈ 文字宽 16%、峰色 = 基色 ×30% + 白 ×70%。

struct SweepTextShimmerModifier: ViewModifier {
    var base: Color
    var period: Double = 3.0

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let center = shimmerCenter(timeline.date.timeIntervalSinceReferenceDate)
            content
                .foregroundStyle(
                    LinearGradient(stops: Self.stops(base: base, center: center),
                                   startPoint: .leading, endPoint: .trailing)
                )
        }
    }

    /// 归一化相位 → 亮带中心（0=左 1=右；0.9 → 0.1 对应 CSS 83.333%→16.667%）。
    private func shimmerCenter(_ t: Double) -> Double {
        let p = t.truncatingRemainder(dividingBy: period) / period
        // 每圈前 15% / 后 15% 停在端点 [CSS 0%,15% / 85%,100%]
        let q = min(1.0, max(0.0, (p - 0.15) / 0.7))
        let e = Self.cubicBezierY(q, x1: 0.714, y1: 0.121, x2: 0.211, y2: 0.888)
        return 0.9 - 0.8 * e
    }

    /// 基色 + 窄峰带（半宽 0.08 ≈ 带宽 16%）渐变 stops；中心∈[0.1,0.9] 恒递增。
    private static func stops(base: Color, center: Double) -> [Gradient.Stop] {
        // 峰色 = color-mix(in srgb, base 30%, white) —— 逐通道显式 Double [混合浮点判例]
        var r0: CGFloat = 0; var g0: CGFloat = 0; var b0: CGFloat = 0; var a0: CGFloat = 0
        UIColor(base).getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
        let r = Double(r0) * 0.3 + 1.0 * 0.7
        let g = Double(g0) * 0.3 + 1.0 * 0.7
        let b = Double(b0) * 0.3 + 1.0 * 0.7
        let peak = Color(red: r, green: g, blue: b)
        let w = 0.08
        return [
            .init(color: base, location: 0),
            .init(color: base, location: center - w),
            .init(color: peak, location: center),
            .init(color: base, location: center + w),
            .init(color: base, location: 1),
        ]
    }

    /// 标准 cubic-bezier y(t)：x 单调，二分求参再取 y（20 轮 ≈ 1e-6 精度）。
    private static func cubicBezierY(_ t: Double, x1: Double, y1: Double, x2: Double, y2: Double) -> Double {
        func bez(_ a: Double, _ b: Double, _ s: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
        }
        var lo = 0.0
        var hi = 1.0
        for _ in 0..<20 {
            let mid = (lo + hi) / 2
            if bez(x1, x2, mid) < t { lo = mid } else { hi = mid }
        }
        let s = (lo + hi) / 2
        return bez(y1, y2, s)
    }
}

extension View {
    /// Claude 文字扫光 [cds-shimmer-text-shine 1:1]：3s 周期、右→左亮带、端点停顿。
    func sweepShimmer(base: Color, period: Double = 3.0) -> some View {
        modifier(SweepTextShimmerModifier(base: base, period: period))
    }
}

struct ShimmerTextModifier: ViewModifier {
    /// Fully-lit opacity.
    var baseOpacity: Double = 1.0
    /// Dimmed opacity at the wave trough.
    var troughOpacity: Double = 0.55
    /// Seconds per wave (down + up).
    var waveDuration: Double = 0.5
    /// Peak-to-peak period (wave + still).
    var period: Double = 2.6
    /// Delay before the first sweep.
    var firstDelay: Double = 3.0

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            content
                .opacity(baseOpacity - (baseOpacity - troughOpacity) * dimAmount(timeline.date.timeIntervalSinceReferenceDate))
        }
    }

    private func dimAmount(_ t: Double) -> Double {
        var p = t - firstDelay
        // Not started yet → fully lit.
        if p < 0 { return 0 }
        p = p.truncatingRemainder(dividingBy: period)
        if p < waveDuration {
            let q = p / waveDuration
            return easeInOut(q)
        } else if p < waveDuration * 2 {
            let q = (p - waveDuration) / waveDuration
            return 1 - easeInOut(q)
        }
        return 0
    }

    private func easeInOut(_ x: Double) -> Double {
        x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
    }
}

extension View {
    /// Grok-style slow shimmer for sheet titles / thinking rows [A7/B5].
    @ViewBuilder
    func shimmerText(
        baseOpacity: Double = 1.0,
        troughOpacity: Double = 0.55,
        waveDuration: Double = 0.5,
        period: Double = 2.6,
        firstDelay: Double = 3.0
    ) -> some View {
        modifier(ShimmerTextModifier(
            baseOpacity: baseOpacity,
            troughOpacity: troughOpacity,
            waveDuration: waveDuration,
            period: period,
            firstDelay: firstDelay
        ))
    }
}

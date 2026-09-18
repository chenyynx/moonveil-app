import SwiftUI

// MARK: - Slow Shimmer (breathing dim)
//
// [A7/B5, 09-17 帧级实测] Grok sheet 内「思考中……」与「思考结果」标题的扫光：
// 整行文字变浅→恢复（呼吸型，非亮带横掠）。实测：~0.5s/波、波峰周期 ~2.6s、
// 打开后首扫延迟 ~3.0s。全部参数列入装机校准清单（H.264 抹平了精确曲线）。
// 聊天内 Thinking 文字实测无扫光 —— 本修饰器仅用于汇聚页（sheet）。

// MARK: - Claude Text Sweep Shimmer [pp 09-18 v2：mask 位移 + repeatForever 纯 CA 驱动]
//
// 参数实抓自 claude.ai 生产 CSS（cds-shimmer-text-shine）：3s 周期、右→左亮带、
// 峰色 = color-mix(in srgb, base 30%, white)（alpha 语义 0.3a+0.7）。
//
// v1（TimelineView 每帧换 foregroundStyle 渐变）在聊天流 cell（UIHostingConfiguration）
// 里不驱动——pp 装机反馈「thinking 还是没有扫光」：文字滑入等 withAnimation 系动画
// 均正常，唯独 TimelineView 帧驱动无效。v2 改为 [峰色文字层 + 移动窄带 mask] +
// withAnimation(.linear.repeatForever)——与已验证工作的出现动画同一条 SwiftUI/CA
// 动画管线，不依赖 TimelineView。「每圈端点停 15%」用带子滑出视野外的空程近似。

private struct SweepWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SweepTextShimmerModifier: ViewModifier {
    var base: Color
    var period: Double = 3.0

    @State private var textWidth: CGFloat = 0
    @State private var sweeping = false

    func body(content: Content) -> some View {
        let bandW = max(textWidth * 0.5, 28)          // 亮带渐变矩形宽（有效峰区≈其一半）
        let travel = textWidth / 2 + bandW / 2 + 4    // 带子中心：右缘外 → 左缘外
        return content
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: SweepWidthKey.self, value: g.size.width)
                }
            )
            .onPreferenceChange(SweepWidthKey.self) { textWidth = $0 }
            .overlay {
                content
                    .foregroundStyle(Self.peak(base)) // 峰色文字层（被 mask 裁成移动亮带）
                    .mask(
                        Rectangle()
                            .fill(LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white, location: 0.5),
                                .init(color: .clear, location: 1),
                            ], startPoint: .leading, endPoint: .trailing))
                            .frame(width: bandW, height: 64)
                            .offset(x: sweeping ? -travel : travel)
                    )
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                    sweeping = true
                }
            }
    }

    /// 峰色 = color-mix(in srgb, base 30%, white)；alpha 混合同式（0.3a + 0.7）。
    /// 逐通道显式 Double [混合浮点判例]。
    private static func peak(_ base: Color) -> Color {
        var r0: CGFloat = 0; var g0: CGFloat = 0; var b0: CGFloat = 0; var a0: CGFloat = 0
        UIColor(base).getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
        return Color(red: Double(r0) * 0.3 + 0.7,
                     green: Double(g0) * 0.3 + 0.7,
                     blue: Double(b0) * 0.3 + 0.7,
                     opacity: Double(a0) * 0.3 + 0.7)
    }
}

extension View {
    /// Claude 文字扫光 [cds-shimmer-text-shine]：3s 周期、右→左亮带。
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

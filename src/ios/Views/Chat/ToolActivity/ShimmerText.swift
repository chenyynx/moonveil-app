import SwiftUI

// MARK: - Slow Shimmer (breathing dim)
//
// [A7/B5, 09-17 帧级实测] Grok sheet 内「思考中……」与「思考结果」标题的扫光：
// 整行文字变浅→恢复（呼吸型，非亮带横掠）。实测：~0.5s/波、波峰周期 ~2.6s、
// 打开后首扫延迟 ~3.0s。全部参数列入装机校准清单（H.264 抹平了精确曲线）。
// 聊天内 Thinking 文字实测无扫光 —— 本修饰器仅用于汇聚页（sheet）。

// MARK: - Claude Text Sweep Shimmer [pp 09-18 v3：GeometryReader 同步量宽 + 启动门]
//
// 参数实抓自 claude.ai 生产 CSS（cds-shimmer-text-shine）：3s 周期、右→左亮带、
// 峰色 = color-mix(in srgb, base 30%, white)（alpha 语义 0.3a+0.7）。
//
// v1（TimelineView 每帧换渐变）失效真因是峰色 alpha 计算丢 alpha——「TimelineView
// 在 cell 里不驱动」的旧判例不成立（ThinkingDotIcon 同用 TimelineView(.animation)
// 在同 cell 一直工作）；v2（preference 回传量宽）失效真因：onPreferenceChange 触发
// 的 body 重算不在动画事务里，offset 目标从 ±travel(0) 跳到 ±travel(真实宽度) →
// repeatForever 循环被替换、带子静止在左缘外 → 永久不可见。
// v3：GeometryReader 在 body 内同步读尺寸（不经过 @State/preference 回传）+
// w>1 启动门——循环启动时 travel 已是真实值，此后尺寸不再变化 → 循环永续。

struct SweepTextShimmerModifier: ViewModifier {
    var base: Color
    var period: Double = 3.0

    @State private var sweeping = false

    func body(content: Content) -> some View {
        content
            .overlay {
                // overlay 尺寸 = content 尺寸；GeometryReader greedy 吃满提案 →
                // g.size 同步 = 文字真实尺寸。GR 内孩子 topLeading 放置，峰色层
                // （content 副本）理想尺寸 = 文字尺寸 = GR 尺寸 → 与底层文字完全重叠。
                GeometryReader { g in
                    let w = g.size.width
                    if w > 1 {
                        let bandW = max(w * 0.5, 28)          // 亮带渐变矩形宽（有效峰区≈其一半）
                        let travel = w / 2 + bandW / 2 + 4    // 带子中心：右缘外 → 左缘外
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
                            .onAppear {
                                // 启动门：w 已是真实值才启动 repeatForever——首帧
                                // 布局未定（w≈0）时不渲染本分支，布局完成后 GR 重算
                                // 进入分支、此时才 onAppear → 循环不被后续尺寸回传
                                // 跳变替换。guard 防 w 抖动重复启动。
                                guard !sweeping else { return }
                                withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                                    sweeping = true
                                }
                            }
                    }
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

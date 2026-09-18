import SwiftUI

// MARK: - Claude Text Sweep Shimmer
//
// [v10 09-19] 一次解决两个根因：聊天流完全不显示 + 汇聚页灰块。
//
// 根因 1（聊天流完全不显示）：v9.1 只改了注释没改方法名，Timeline 版
//   (sweepShimmerTimeline) 从未被调用 = 死代码；实际跑库版（隐式动画），
//   被 cell 宿主 .transaction { disablesAnimations = true }（防 ViewGraph
//   use-after-free 护栏）吞到不动。git show 30f4376 实锤：两行只有注释差异。
//   → 本版合并成单一 modifier，Timeline 驱动，调用点方法名 sweepShimmer 不变，
//     死代码自动激活，两处调用点零改动。
//
// 根因 2（灰块）：亮带占字宽 0.7~1.0（v9 bandSize=1.0 / v9.1 渐变跨度=1.0w），
//   大半行文字同时被点亮 → 视觉是「整行变色横移」不是「光带掠过」。经典版
//   ShimmerOverlay 同比例几何（亮带≈0.56×载体宽）在宽胶囊上正常、在窄文字
//   上必灰 —— 扫光的「光带感」要求亮带明显窄于载体。
//   → 亮带砍到 0.3×字宽 + 峰值 20% 硬过渡（锐利，不软塌塌）。
//
// 渲染机制：foregroundStyle(LinearGradient) —— 渐变直接当文字前景色，天然
// 只画在文字像素上，无 overlay 层、无 blendMode、无 GeometryReader。
//   · stops 固定一次构建（v6 每帧重建 stops → colorspace teardown 崩溃，已避）；
//   · TimelineView 每帧只移动 startPoint/endPoint 两个 UnitPoint（廉价值更新）；
//   · 暗处 stop 用不透明 base 色（非 clear）→ 文字全程完整可见，不是「整行变淡」。
//
// markiv SwiftUI-Shimmer 包几何上不适合窄亮带（亮带 = 渐变全跨度 (1+2×bandSize)
// 对角单位，bandSize 只改端点延伸、不改亮带占比，数学上压不到 0.3×字宽）→
// 弃用于扫光；包仍挂在 pbxproj（零开销保留）。sheet 与 cell 共用同一实现。

// MARK: - 共享：峰色与渐变

enum ShimmerStyle {
    /// 峰色 = color-mix(in srgb, base 30%, white)；alpha 混合同式（0.3a + 0.7）。
    /// 逐通道显式 Double [混合浮点判例]。
    static func peak(_ base: Color) -> Color {
        var r0: CGFloat = 0; var g0: CGFloat = 0; var b0: CGFloat = 0; var a0: CGFloat = 0
        UIColor(base).getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
        return Color(red: Double(r0) * 0.3 + 0.7,
                     green: Double(g0) * 0.3 + 0.7,
                     blue: Double(b0) * 0.3 + 0.7,
                     opacity: Double(a0) * 0.3 + 0.7)
    }

    /// 亮带宽度（单位 = 视图宽）。0.3×字宽：经典版 0.56 在宽胶囊正常、在窄文字
    /// 上是灰块，砍到约一半让「局部点亮」明显。[v10 治灰块]
    static let bandWidth: CGFloat = 0.3
    /// 渐变跨度（单位 = 视图宽）：端点延伸到视图外，亮带从左外扫到右外、两端无硬切。
    static let span: CGFloat = 1.5

    /// 扫光渐变：暗处 = 不透明 base 色（文字全程完整可见），亮处 = 半透明峰色
    /// （浅色模式文字变浅 =「亮带掠过」）。亮带只占渐变中段 bandWidth/span → 0.3×字宽。
    static func sweepGradient(base: Color, peakOpacity: CGFloat) -> Gradient {
        let peakColor = peak(base)
        let bandFrac = bandWidth / span
        let lo = 0.5 - bandFrac / 2
        let hi = 0.5 + bandFrac / 2
        return Gradient(stops: [
            .init(color: base, location: 0),
            .init(color: base, location: lo),
            .init(color: peakColor.opacity(Double(peakOpacity)), location: 0.5),
            .init(color: base, location: hi),
            .init(color: base, location: 1),
        ])
    }
}

// MARK: - 统一扫光（sheet 标题 + 聊天流 cell 共用）

struct SweepTextShimmerModifier: ViewModifier {
    var base: Color
    /// 一个完整循环时长（对齐经典版 ShimmerOverlay 的 2.8s）。
    var period: Double = 2.8
    /// 可见度：浅 0.75 / 深 0.25（对齐经典版 peakOpacity）。
    @Environment(\.colorScheme) private var colorScheme
    private var peakOpacity: CGFloat { colorScheme == .light ? 0.75 : 0.25 }

    func body(content: Content) -> some View {
        // TimelineView 相位驱动：纯时间函数，无 @State 无事务 —— cell 宿主的
        // disablesAnimations 管不到（ThinkingDotIcon 同管线实证可动）。
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let phase = Self.phase(timeline.date.timeIntervalSinceReferenceDate, period: period)
            let span = ShimmerStyle.span
            // 渐变映射区间 [startX, startX+span]：phase 0→1 时从左外扫到右外。
            let startX = -span + phase * (1 + span)
            content
                .foregroundStyle(
                    LinearGradient(
                        gradient: ShimmerStyle.sweepGradient(base: base, peakOpacity: peakOpacity),
                        startPoint: UnitPoint(x: startX, y: 0.5),
                        endPoint: UnitPoint(x: startX + span, y: 0.5)
                    )
                )
        }
    }

    /// 相位 0→1，纯时间函数。
    private static func phase(_ t: TimeInterval, period: Double) -> Double {
        t.truncatingRemainder(dividingBy: period) / period
    }
}

extension View {
    /// Claude 文字扫光 [v10 统一版]：2.8s 一圈、亮带 0.3×字宽、左→右。
    /// sheet 标题与聊天流 cell 共用同一 Timeline 驱动实现（两端都能动）。
    /// ⚠️ 调用方都不传 period → **默认值必须与 SweepTextShimmerModifier 的一致**，
    /// 否则改结构体的默认值不生效（v5 踩点）。
    func sweepShimmer(base: Color, period: Double = 2.8) -> some View {
        modifier(SweepTextShimmerModifier(base: base, period: period))
    }
}

// MARK: - Slow Shimmer (breathing dim)  [保留：Grok 呼吸式，另一条产品线]

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

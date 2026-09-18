import SwiftUI
import Shimmer

// MARK: - Claude Text Sweep Shimmer
//
// [v9 09-18 pp 拍板「用这个」: https://github.com/markiv/SwiftUI-Shimmer]
// v1~v8 自研路线连续踩坑（TimelineView 每帧重建渐变 / preference 回传跳变 /
// GeometryReader 量宽 / withAnimation repeatForever 被 cell 宿主
// disablesAnimations 吞 / v8 最外层 GR 被 sheet 拉伸成跨屏大竖渐变带），
// 根因都是「自己重新发明渐变扫描的几何与动画」。直接改用 markiv 的成熟实现：
//   · 渐变端点 = 依赖 @State 的 UnitPoint 计算属性,隐式 .animation(_:value:)
//     驱动插值 —— 无 GeometryReader(不会被父容器拉伸)、无 offset 状态;
//   · 端点延伸到视图外(min=-bandSize / max=1+bandSize),亮带从视图外扫入、
//     扫出,两端无硬切;
//   · mode = .overlay(.sourceAtop) 渐变只画在文字像素上 = 「文字上亮带横扫」,
//     而非 mask 模式的「整行变淡」。
// 周期/峰色/可见度沿用我们装机实测的参数(2.8s 对齐经典版 ShimmerOverlay;
// 峰色 = color-mix(base 30%, white); 浅 0.75 / 深 0.25)。
//
// ⚠️ 隐式 .animation(_:value:) 在聊天流 cell 宿主(.transaction{disablesAnimations})
// 会被吞,与旧 withAnimation 同理 —— 本修饰器仍只用于汇聚页(sheet)标题;
// 聊天流 Thinking 行的扫光见 ToolActivityGroupView 调用点注释。

struct SweepTextShimmerModifier: ViewModifier {
    var base: Color
    /// 一个完整循环时长 [pp 09-18 要求跟经典版一致：ShimmerOverlay 用 2.8s]
    var period: Double = 2.8
    /// 可见度跟经典版一致：浅 0.75 / 深 0.25（对齐 ShimmerOverlay.peakOpacity）。
    @Environment(\.colorScheme) private var colorScheme
    private var peakOpacity: CGFloat { colorScheme == .light ? 0.75 : 0.25 }

    func body(content: Content) -> some View {
        let peak = Self.peak(base)
        content.shimmering(
            active: true,
            animation: .linear(duration: period).repeatForever(autoreverses: false),
            gradient: Gradient(stops: [
                .init(color: peak.opacity(0), location: 0),
                .init(color: peak.opacity(Double(peakOpacity)), location: 0.5),
                .init(color: peak.opacity(0), location: 1),
            ]),
            bandSize: 0.3,
            mode: .overlay()
        )
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
    /// Claude 文字扫光 [v9 = 直接引 SwiftUI-Shimmer 包，pp 09-18 拍板]：
    /// 2.8s 一圈、左→右、可见度 0.75/0.25。
    /// ⚠️ 调用方都不传 period → **默认值必须与 SweepTextShimmerModifier 的一致**，
    /// 否则改结构体的默认值不生效（v5 踩点：两处默认值都要改）。
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

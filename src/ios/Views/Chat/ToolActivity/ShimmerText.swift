import SwiftUI
import Shimmer

// MARK: - Claude Text Sweep Shimmer
//
// [v9 09-18 pp 拍板「用这个」: https://github.com/markiv/SwiftUI-Shimmer]
// v1~v8 自研路线连续踩坑（TimelineView 每帧重建渐变 / preference 回传跳变 /
// GeometryReader 量宽 / withAnimation repeatForever 被 cell 宿主
// disablesAnimations 吞 / v8 最外层 GR 被 sheet 拉伸成跨屏大竖渐变带），
// 根因都是「自己重新发明渐变扫描的几何与动画」。改用 markiv 的成熟实现：
//   · 渐变端点 = 依赖 @State 的 UnitPoint 计算属性,隐式 .animation(_:value:)
//     驱动插值 —— 无 GeometryReader(不会被父容器拉伸)、无 offset 状态;
//   · 端点延伸到视图外(min=-bandSize / max=1+bandSize),亮带从视图外扫入、
//     扫出,两端无硬切;
//   · mode = .overlay(.sourceAtop) 渐变只画在文字像素上 = 「文字上亮带横扫」,
//     而非 mask 模式的「整行变淡」。
// 周期/峰色/可见度沿用我们装机实测的参数(2.8s 对齐经典版 ShimmerOverlay;
// 峰色 = color-mix(base 30%, white); 浅 0.75 / 深 0.25)。
//
// [v9.1 09-18 pp:「聊天流你也要给我实现啊」]
// 聊天流 Thinking 行所在 cell 宿主挂 `.transaction { $0.disablesAnimations = true }`
// (CollectionViewMessageListV3 4 处,防 ViewGraph use-after-free 护栏),库的隐式
// .animation(_:value:) 在那里被吞 → 扫光不动。故聊天流那条路用
// SweepTextShimmerTimeline(同几何、同配色,但驱动换 TimelineView 相位 ——
// 与同 cell 的 ThinkingDotIcon 同管线,实证可动)。两个实现共享
// shimmerGradient/peak,参数一处调两处同效。

// MARK: - 共享:峰色与渐变

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

    /// 亮带渐变:clear → 峰色 → clear(峰色乘 peakOpacity 控制可见度)。
    static func shimmerGradient(base: Color, peakOpacity: CGFloat) -> Gradient {
        let peakColor = peak(base)
        return Gradient(stops: [
            .init(color: peakColor.opacity(0), location: 0),
            .init(color: peakColor.opacity(Double(peakOpacity)), location: 0.5),
            .init(color: peakColor.opacity(0), location: 1),
        ])
    }

    /// 亮带相对宽度(单位 = 视图宽):v5 装机实测 App 亮带 ≈ 文字宽一半。
    static let bandSize: CGFloat = 1.0
}

// MARK: - sheet 版:直接调 SwiftUI-Shimmer 包(隐式动画,sheet 宿主可用)

struct SweepTextShimmerModifier: ViewModifier {
    var base: Color
    /// 一个完整循环时长 [pp 09-18 要求跟经典版一致：ShimmerOverlay 用 2.8s]
    var period: Double = 2.8
    /// 可见度跟经典版一致：浅 0.75 / 深 0.25（对齐 ShimmerOverlay.peakOpacity）。
    @Environment(\.colorScheme) private var colorScheme
    private var peakOpacity: CGFloat { colorScheme == .light ? 0.75 : 0.25 }

    func body(content: Content) -> some View {
        content.shimmering(
            active: true,
            animation: .linear(duration: period).repeatForever(autoreverses: false),
            gradient: ShimmerStyle.shimmerGradient(base: base, peakOpacity: peakOpacity),
            bandSize: ShimmerStyle.bandSize,
            mode: .overlay()
        )
    }
}

// MARK: - 聊天流 cell 版:TimelineView 驱动同一几何(cell 宿主 disablesAnimations 吞隐式动画)

struct SweepTextShimmerTimeline: ViewModifier {
    var base: Color
    var period: Double = 2.8
    @Environment(\.colorScheme) private var colorScheme
    private var peakOpacity: CGFloat { colorScheme == .light ? 0.75 : 0.25 }

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let phase = Self.phase(timeline.date.timeIntervalSinceReferenceDate, period: period)
            let band = ShimmerStyle.bandSize
            // markiv 同款端点几何:渐变长度恒 = band,中心从 -band/2 扫到 1+band/2,
            // 水平方向(y 恒 0.5,适配单行文字;markiv 原版对角扫适合方块视图)。
            let startX = -band + phase * (1 + band)
            content
                .overlay {
                    LinearGradient(
                        gradient: ShimmerStyle.shimmerGradient(base: base, peakOpacity: peakOpacity),
                        startPoint: UnitPoint(x: startX, y: 0.5),
                        endPoint: UnitPoint(x: startX + band, y: 0.5)
                    )
                    .blendMode(.sourceAtop)
                    .allowsHitTesting(false)
                }
        }
    }

    /// 相位 0→1,纯时间函数,无 @State 无事务 —— disablesAnimations 管不到。
    private static func phase(_ t: TimeInterval, period: Double) -> Double {
        t.truncatingRemainder(dividingBy: period) / period
    }
}

extension View {
    /// Claude 文字扫光 [v9 = 直接引 SwiftUI-Shimmer 包, pp 09-18 拍板]:
    /// 2.8s 一圈、左→右、可见度 0.75/0.25。**仅用于 sheet 宿主**(隐式动画);
    /// 聊天流 cell 用 sweepShimmerTimeline。
    /// ⚠️ 调用方都不传 period → **默认值必须与 SweepTextShimmerModifier 的一致**，
    /// 否则改结构体的默认值不生效（v5 踩点：两处默认值都要改）。
    func sweepShimmer(base: Color, period: Double = 2.8) -> some View {
        modifier(SweepTextShimmerModifier(base: base, period: period))
    }

    /// 聊天流 cell 版扫光:TimelineView 驱动同一几何/配色(cell 宿主 disablesAnimations
    /// 吞隐式动画,库的 .shimmering() 在 cell 内动不了 —— ThinkingDotIcon 同管线实证)。
    func sweepShimmerTimeline(base: Color, period: Double = 2.8) -> some View {
        modifier(SweepTextShimmerTimeline(base: base, period: period))
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

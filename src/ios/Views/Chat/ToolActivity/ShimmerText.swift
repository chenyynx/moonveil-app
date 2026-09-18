import SwiftUI

// MARK: - Claude Text Sweep Shimmer
//
// [v11 09-19] CA 驱动亮带（现行）。v10.1 的"TimelineView 每帧移 SwiftUI mask
//   渐变"装机后 sheet 标题与聊天流双双不可见（pp 实机，SwiftUI 侧每帧重算
//   渐变/mask 路线两次证伪）→ 按判例走最后一条路：mask 层改 CABasicAnimation
//   自驱（render server 时间线，不经 SwiftUI 事务、不要求 body 重算）。
//   分层结构沿用 v10.1（底=实体色 + 顶=峰色副本从移动亮带露出）。
//   若本版仍不出 → 停止盲修，先要 5s 录屏抽帧定死失败环节。
//
// [v10.1 09-19 已被 v11 覆盖] mask 分层版。v10（foregroundStyle 渐变当文字
//   前景）装机后深浅色都完全不可见。当时诊断出两个缺陷并一次绕开：
//   ① 峰色 .opacity(0.25) 半透明 = 文字变透明透出底色，不是提亮，暗色下与
//     base 对比仅 1.7:1 ≈ 数学上不存在（0.75/0.25 参数搬自经典版
//     white-opacity overlay 用法，跨机制未换算）；② 调用点 Text 自带
//     foregroundStyle，外层渐变是否穿透未证。→ 分层：底 = content 原样
//     （实体灰全程可见）；上 = content 峰色副本，仅亮带处露出（实心提亮）。
//
// [v10 09-19 历史] 聊天流完全不显示根因：v9.1 只改注释没改方法名，Timeline
//   版从未被调用 = 死代码；实际跑库版（隐式动画），被 cell 宿主
//   .transaction { disablesAnimations = true }（防 ViewGraph use-after-free
//   护栏）吞到不动。git show 30f4376 实锤。→ 合并成单一 modifier。
//
// 渲染机制 [v11]：ZStack 两层（base + CA-masked peak），见 CABandMaskView。

// MARK: - 共享：峰色与亮带 mask

enum ShimmerStyle {
    /// 峰色 = color-mix(in srgb, base 30%, white)；alpha 混合同式（0.3a + 0.7）。
    /// 逐通道显式 Double [混合浮点判例]。实心不透明 [v10.1]——v10 在此再乘
    /// peakOpacity 把"提亮"错做成"变透明"（暗色下 1.7:1 不可见，浅色系值被砍
    /// 到 1/4），已废；提亮量由 mix 本身控制（#7A7974 → ≈#D1D0CD，深 4.7:1）。
    static func peak(_ base: Color) -> Color {
        var r0: CGFloat = 0; var g0: CGFloat = 0; var b0: CGFloat = 0; var a0: CGFloat = 0
        UIColor(base).getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
        return Color(red: Double(r0) * 0.3 + 0.7,
                     green: Double(g0) * 0.3 + 0.7,
                     blue: Double(b0) * 0.3 + 0.7,
                     opacity: Double(a0))
    }

    /// 亮带宽度（单位 = 视图宽）。0.3×字宽：经典版 0.56 在宽胶囊正常、在窄文字
    /// 上是灰块，砍到约一半让「局部点亮」明显。[v10 治灰块]
    static let bandWidth: CGFloat = 0.3
    /// 渐变跨度（单位 = 视图宽）：端点延伸到视图外，亮带从左外扫到右外、两端无硬切。
    /// [v11] CA mask 层宽 = span × 视图宽（CABandMaskView 内以 1.5 硬编码同源值）。
    static let span: CGFloat = 1.5
}

// MARK: - 统一扫光（sheet 标题 + 聊天流 cell 共用）

/// [v11 09-19 CA 驱动亮带] v10.1（TimelineView 每帧移 SwiftUI mask 渐变）装机
/// sheet 标题与聊天流**双双不可见**（pp 06:11 实机）——连同此前 sheet 上曾出过
/// 灰块的记录，SwiftUI 侧"每帧重算渐变/mask"路线已两次证伪，按判例走 CA：
/// 一个 UIView，其 mask 是 CAGradientLayer（clear→白→clear，亮带 0.3×宽），
/// CABasicAnimation 平移 mask 层，repeatForever。CA 动画挂在 render server
/// 独立时间线上，不经 SwiftUI 事务、不要求 body 重算——cell 宿主
/// disablesAnimations 与 TimelineView 失效两种死法都绕开。
/// 亮带几何（0.3×宽 / 1.5×跨度 / 2.8s 周期 / 左→右）沿用 v10 标定值。
private struct CABandMaskView: UIViewRepresentable {
    var period: Double

    func makeUIView(context: Context) -> ShimmerBandHost {
        let v = ShimmerBandHost()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false

        let band = CAGradientLayer()
        band.type = .axial
        band.colors = [UIColor.clear.cgColor,
                       UIColor.white.cgColor,
                       UIColor.clear.cgColor]
        // 层宽 = 2×视图宽（restartIfNeeded 内设置），亮带中心在层 0.5 处、
        // 占层 0.15 → 恰 0.3×视图宽（v10 标定值）。两侧全透明。
        band.locations = [0.425, 0.5, 0.575]
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        v.mask = band
        v.band = band
        return v
    }

    func updateUIView(_ uiView: ShimmerBandHost, context: Context) {
        uiView.period = CGFloat(period)
    }

    static func dismantleUIView(_ uiView: ShimmerBandHost, coordinator: ()) {
        uiView.band?.removeAllAnimations()
    }

    /// UIView 子类承载 period + 幂等启动动画（bounds 有效后才建，layout 后帧宽正确）。
    final class ShimmerBandHost: UIView {
        var band: CAGradientLayer?
        var period: CGFloat = 2.8
        private var animating = false

        override func layoutSubviews() {
            super.layoutSubviews()
            restartIfNeeded()
        }

        private func restartIfNeeded() {
            guard !animating, let band, bounds.width > 1, bounds.height > 1 else { return }
            animating = true
            band.frame = CGRect(x: 0, y: 0, width: bounds.width * 2, height: bounds.height)
            band.position = CGPoint(x: bounds.width, y: bounds.height / 2)
            // 亮带中心 = 层中心 = position.x。从 -0.15w（带右缘恰在视图左缘）
            // 扫到 1.15w（带左缘恰在视图右缘）→ 全程无硬切进出。
            let anim = CABasicAnimation(keyPath: "position.x")
            anim.fromValue = Double(-bounds.width) * 0.15
            anim.toValue = Double(bounds.width) * 1.15
            anim.duration = CFTimeInterval(period)
            anim.repeatCount = .infinity
            anim.isRemovedOnCompletion = false
            band.add(anim, forKey: "sweep")
        }
    }
}

struct SweepTextShimmerModifier: ViewModifier {
    var base: Color
    /// 一个完整循环时长（对齐经典版 ShimmerOverlay 的 2.8s）。
    var period: Double = 2.8

    func body(content: Content) -> some View {
        // 分层保持 v10.1（底=实体色全程可见，顶=峰色副本仅亮带处露出），
        // 只把"带怎么动"从 SwiftUI 每帧重算换成 CA 自驱。
        ZStack(alignment: .leading) {
            content
            content
                .foregroundStyle(ShimmerStyle.peak(base))
                .mask(
                    CABandMaskView(period: period)
                        .frame(height: 44)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Claude 文字扫光 [v11 CA 驱动版]：2.8s 一圈、亮带 0.3×字宽、左→右。
    /// sheet 标题与聊天流 cell 共用同一实现。
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

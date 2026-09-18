import SwiftUI

// MARK: - Claude Text Sweep Shimmer
//
// [v10.1 09-19] mask 分层版。v10（foregroundStyle 渐变当文字前景）装机后
//   深浅色都完全不可见（pp 实机）。根因未闭环（缺帧证据），但 v10 的可见性
//   依赖两个未验证前提：① 渐变前景在 cell 宿主里被正确解析（调用点 Text 已
//   自带 .foregroundStyle(headlineGray)，层级式 foregroundStyle 对已设色 Text
//   不穿透）；② 峰色 .opacity(0.25) 半透明——实算是把文字变透明透出底色，
//   暗色下与 base 对比仅 1.7:1 ≈ 数学上不存在。本版对两点都免疫：
//   · 分层：底 = content 原样（实体灰，全程可见）；上 = 同一 content 的峰色
//     副本，仅亮带处露出 → 亮带是实心提亮色，不再靠 alpha 混合底色。
//   · mask 只决定副本可见度，与文字前景解析路径无关。
//   驱动保持 TimelineView 纯值更新（不走事务 → cell 宿主 disablesAnimations
//   管不到；ThinkingDotIcon 同宿主实证可动）。无 GeometryReader（v2 跳变 /
//   v8 拉伸两坑绕开）、stops 一次构建（v6 colorspace teardown 绕开）。
//   若本版仍不出 → 不再猜第五条，按 Bug 经验库判例走 CA
//   （CABasicAnimation 位移 mask），并先要 5s 录屏抽帧定死失败环节。
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
// 渲染机制 [v10.1]：ZStack 两层（base + masked peak），见文件头。

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
    static let span: CGFloat = 1.5

    /// 亮带 mask（[v10.1] 只用于 peak 副本）：透明底 + 中段不明白带。
    /// lo→0.5→hi 三角过渡，带外全透明 = base 层原样显示。
    static func bandMask() -> Gradient {
        let bandFrac = bandWidth / span
        let lo = 0.5 - bandFrac / 2
        let hi = 0.5 + bandFrac / 2
        return Gradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: lo),
            .init(color: .white, location: 0.5),
            .init(color: .clear, location: hi),
            .init(color: .clear, location: 1),
        ])
    }
}

// MARK: - 统一扫光（sheet 标题 + 聊天流 cell 共用）

struct SweepTextShimmerModifier: ViewModifier {
    var base: Color
    /// 一个完整循环时长（对齐经典版 ShimmerOverlay 的 2.8s）。
    var period: Double = 2.8

    func body(content: Content) -> some View {
        // TimelineView 相位驱动：纯时间函数，无 @State 无事务 —— cell 宿主的
        // disablesAnimations 管不到（ThinkingDotIcon 同管线实证可动）。
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let phase = Self.phase(timeline.date.timeIntervalSinceReferenceDate, period: period)
            let span = ShimmerStyle.span
            // mask 映射区间 [startX, startX+span]：phase 0→1 时亮带从左外扫到右外。
            let startX = -span + phase * (1 + span)
            ZStack(alignment: .leading) {
                content
                content
                    .foregroundStyle(ShimmerStyle.peak(base))
                    .mask(
                        LinearGradient(
                            gradient: ShimmerStyle.bandMask(),
                            startPoint: UnitPoint(x: startX, y: 0.5),
                            endPoint: UnitPoint(x: startX + span, y: 0.5)
                        )
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// 相位 0→1，纯时间函数。
    private static func phase(_ t: TimeInterval, period: Double) -> Double {
        t.truncatingRemainder(dividingBy: period) / period
    }
}

extension View {
    /// Claude 文字扫光 [v10.1 mask 分层版]：2.8s 一圈、亮带 0.3×字宽、左→右。
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

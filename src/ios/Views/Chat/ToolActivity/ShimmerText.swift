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
//
// v4 [pp 09-18 装机：聊天流 Thinking 没有循环扫光] v3 的结论只在汇聚页（sheet）
// 成立，聊天流那条路没被覆盖。真因：聊天 cell 宿主挂
// `.transaction { $0.disablesAnimations = true }`（CollectionViewMessageListV3
// 4 处，防 ViewGraph use-after-free 的护栏），而 `.transaction` 作用于该视图内
// **所有**事务 → 子视图里 withAnimation 建的 repeatForever 循环同样被禁用，
// offset 一帧跳到终点（-travel，文字左缘外）→ 带子停在文字外面，整行不扫。
// 同 cell 的 ThinkingDotIcon 一直能动，正是因为它是 TimelineView 驱动、不走动画
// 事务 —— 故本版改用同一驱动：相位取自绝对时间，无需 onAppear 启动门，
// GeometryReader 只负责量宽。

// v5 [pp 09-18 装机：「扫光不对」→ 按 App 抽帧实测改参数]
// 来源变了：v1~v4 一直照的是 **claude.ai 网页版生产 CSS**（cds-shimmer-text-shine:
// 3s / 每圈两端各停 15% / 右→左）。pp 的参照物一直是 **iOS App**，用他录的 14s
// 屏幕录制（60fps）抽帧逐帧量亮带质心，实测三处都不同：
//   · 周期 120 帧 ≈ **2.0s**（14s 录到 7 圈，自相关 0.80；网页 CSS 是 3s）
//   · 方向 **左→右**（网页 CSS 换算也是左→右，我们此前实现反了）
//   · 节奏**不对称**：慢扫过去 ~1.6s（S 曲线：中间快两端慢）+ 快扫回来 ~0.4s
//     （网页 CSS 是"两端各停 15%"，App 不是停，是快速回扫）
// 本版 = 周期 2.0s / 左→右 / 去 1.6s + 回 0.4s / 两端 smoothstep 缓动；
// 带宽与峰色算法不动（App 亮带 ≈ 文字宽一半，与我们一致）。

struct SweepTextShimmerModifier: ViewModifier {
    var base: Color
    /// 一个完整循环（去 + 回）时长 [pp 09-18 App 实测 2.0s]
    var period: Double = 2.0
    /// 去程（左→右）时长；回程 = period − outbound [实测 ~1.6s / ~0.4s]
    var outbound: Double = 1.6

    func body(content: Content) -> some View {
        // [v6 全链路审查 09-18 pp：「扫光依旧没有，修了很多遍」] 前 5 版全部依赖
        // mask + overlay + GeometryReader 这套系统层机制——在聊天流 cell
        // （UIHostingConfiguration + `.transaction { $0.disablesAnimations = true }`
        // 宿主）里不被渲染，所以真机永远看不到。同一 cell 里 ThinkingDotIcon 一直
        // 能动，前提是 **TimelineView 每帧重算 body + Canvas 命令式重绘**（纯值更新，
        // 不依赖系统视图层/mask）。本版借同一个可靠前提：把扫光直接做成文字的
        // foregroundStyle 渐变色——亮色位置随 phase 移动，无 mask、无 overlay、
        // 无 GeometryReader，必然渲染。频率 30Hz 与点阵一致。
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = Self.phase(date: timeline.date, period: period, outbound: outbound)
            content
                .foregroundStyle(
                    LinearGradient(
                        stops: Self.shimmerStops(base: base, phase: phase),
                        startPoint: .leading, endPoint: .trailing
                    )
                )
        }
    }

    /// 扫光渐变的 stop 集：亮带（peak）位置随 phase 在 0（左）→1（右）间移动，两端 base，
    /// 形成"亮光扫过文字"。带宽 ≈ 文字宽 45%（App 实测亮带 ≈ 文字宽一半）。
    /// stops locations 必须升序且 clamp 到 [0,1]——亮带贴边时 lo/hi 会重合，LinearGradient
    /// 允许同 location 的 stop（顺序渐变）。
    static func shimmerStops(base: Color, phase: Double) -> [Gradient.Stop] {
        let peak = Self.peak(base)
        let bw = 0.45
        let center = min(max(phase, 0), 1)
        let lo = max(0, center - bw / 2)
        let hi = min(1, center + bw / 2)
        let lo2 = min(lo, hi)
        let hi2 = max(lo, hi)
        return [
            .init(color: base, location: 0),
            .init(color: peak, location: lo2),
            .init(color: peak, location: hi2),
            .init(color: base, location: 1),
        ]
    }

    /// 循环内的位置 0（左缘外）→ 1（右缘外）。
    /// 去程占 outbound 秒（左→右），回程占剩下（右→左，快）。
    /// 独立成函数而非写进 ViewBuilder：builder 里的 if 会被当成视图分支。
    private static func phase(date: Date, period: Double, outbound: Double) -> Double {
        let cycle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        let back = max(period - outbound, 0.01)
        if cycle < outbound { return ease(cycle / outbound) }
        return 1 - ease((cycle - outbound) / back)
    }

    /// 平滑 S 曲线（慢起-快中-慢收）[App 实测两端减速，匀速会显得"急"]
    private static func ease(_ x: Double) -> Double {
        let q = min(max(x, 0), 1)
        return q * q * (3 - 2 * q)
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
    /// Claude 文字扫光 [v5 = App 抽帧实测参数]：2s 一圈（左→右去 1.6s + 回 0.4s）。
    /// ⚠️ 调用方都不传 period → **默认值必须与 SweepTextShimmerModifier 的一致**，
    /// 否则改结构体的默认值不生效（v5 踩点：两处默认值都要改）。
    func sweepShimmer(base: Color, period: Double = 2.0) -> some View {
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

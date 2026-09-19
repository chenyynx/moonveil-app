import SwiftUI
import UIKit

// MARK: - Claude Text Sweep Shimmer
//
// [v12 09-19 现行] 移植 Facebook Shimmer（FBShimmeringLayer）十年验证的机制：
//   **不给文字重新上色**——UILabel 用底色正常渲染，其上盖一条白色渐变亮带，
//   亮带的 mask = 文字自身的渲染副本 alpha。亮带只在字的像素上显形，
//   CABasicAnimation 平移 startPoint/endPoint（frame 恒等于文字矩形，mask
//   全程对齐），动画挂在 render server 独立时间线。
//   对照两大已实锤死法：①不依赖 SwiftUI 事务/每帧重算（cell 宿主
//   disablesAnimations 管不着 CA）；②不依赖 foregroundStyle 穿透（颜色直接
//   写进 UILabel，v10 根因②从此与本实现无关）。SwiftUI 系开源库（Exyte 等）
//   全部用 withAnimation(.repeatForever) 驱动，死法①必踩，已考察淘汰。
//
// [v11.1 09-19 已废] band 挂宿主 layer.mask→addSublayer 修了"构造性不可见"
//   第一层（band 画不画得出），但仍压着第二层：峰色副本的 .foregroundStyle
//   被调用点 Text 自带样式挡住 → 两层同色 → mask 动了也看不见。装机复现。
// [v11 09-19 已废] layer.mask 裁空白宿主 = 恒全遮（构造性死因一）。
// [v10.1/v10/v9.1…v1 历史见 PATCHES.md SHIMMER-* 各条目。]

// MARK: - v12: ShimmerLabel（UILabel + 文字 alpha 掩膜亮带，FB 机制）

/// 扫光文字（替代 SwiftUI Text + sweepShimmer 组合）。
/// 视觉参数与标定一致：亮带 0.3×字宽、2.8s 一圈、左→右、白色峰值盖色。
struct ShimmerLabel: View {
    var text: String
    var uiFont: UIFont
    var baseColor: Color
    var textAlignment: NSTextAlignment = .left
    /// 一个完整循环时长。
    var period: Double = 2.8

    var body: some View {
        ShimmerLabelHost.Representable(uiFont: uiFont, baseColor: UIColor(baseColor),
                                       textAlignment: textAlignment, period: period,
                                       text: text)
    }
}

private final class ShimmerLabelHost: UIView {
    private let label = UILabel()
    private let band = CAGradientLayer()
    private let textMask = CALayer()
    /// 亮带峰值盖色透明度：mix(#7A7974, white, 0.62) ≈ #CDCDCB，
    /// 对齐 v10 标定的峰色 ≈#D1D0CD。
    private let bandOpacity: Float = 0.62
    private var maskKey = ""
    private var animating = false
    var period: Double = 2.8

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false

        label.backgroundColor = .clear
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        band.type = .axial
        band.colors = [UIColor.clear.cgColor,
                       UIColor.white.cgColor,
                       UIColor.clear.cgColor]
        // 亮带占字宽 0.3：白峰居中 0.5，非零 alpha 只在 [0.35, 0.65]。
        band.locations = [0.35, 0.5, 0.65]
        band.opacity = bandOpacity
        // span 恒 1.0（起终点距离不变，整体平移）：初始 s=-0.65/e=0.35
        // 时亮带 [-0.30, 0] 恰在框外左侧 → 未动画时不可见，无跳变。
        band.startPoint = CGPoint(x: -0.65, y: 0.5)
        band.endPoint = CGPoint(x: 0.35, y: 0.5)
        band.mask = textMask          // 用"字的渲染 alpha"裁亮带 = 亮带只显字形
        textMask.contentsGravity = .center
        layer.addSublayer(band)       // 在 label.layer 之上（label 已先挂载）
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize { label.intrinsicContentSize }

    func configure(text: String, font: UIFont, color: UIColor,
                   alignment: NSTextAlignment, period: Double) {
        let dirty = label.text != text || label.font != font
            || label.textColor != color || label.textAlignment != alignment
        label.text = text
        label.font = font
        label.textColor = color
        label.textAlignment = alignment
        self.period = period
        if dirty {
            invalidateIntrinsicContentSize()
            maskKey = ""        // 强制 layoutSubviews 重建掩膜
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
        band.frame = bounds
        textMask.frame = CGRect(origin: .zero, size: bounds.size)
        rebuildMaskIfNeeded()
        startIfNeeded()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        maskKey = ""            // 深浅色切换 → 字色变了，掩膜重渲
        setNeedsLayout()
    }

    /// 把 label 当前渲染画成图片，喂给 band.mask（FB 的 content-layer-copy 思路）。
    private func rebuildMaskIfNeeded() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let key = "\(label.text ?? "")|\(label.font)|\(bounds.size)"
            + "|\(traitCollection.userInterfaceStyle.rawValue)"
        if key == maskKey { return }
        maskKey = key
        let format = UIGraphicsImageRendererFormat()
        format.scale = 0        // 跟随屏幕 scale
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { ctx in
            traitCollection.performAsCurrent {
                label.layer.render(in: ctx.cgContext)
            }
        }
        // 给 UIImage 本体而非 cgImage：layer 直接持 UIImage 才认它的 scale，
        // 裸 CGImage 在 contentsScale=1 下会按 1pt=1px 放大 N 倍（经典坑）。
        textMask.contents = image
    }

    /// 平移渐变端点（frame 固定 → mask 恒对齐；对比 v11 平移整层的另一条路）。
    private func startIfNeeded() {
        guard !animating, bounds.width > 1 else { return }
        animating = true
        let sweeps: [(String, CGPoint, CGPoint)] = [
            ("startPoint", CGPoint(x: -0.65, y: 0.5), CGPoint(x: 0.65, y: 0.5)),
            ("endPoint", CGPoint(x: 0.35, y: 0.5), CGPoint(x: 1.65, y: 0.5))
        ]
        for (key, from, to) in sweeps {
            let a = CABasicAnimation(keyPath: key)
            a.fromValue = from
            a.toValue = to
            a.duration = CFTimeInterval(period)
            a.repeatCount = .infinity
            a.isRemovedOnCompletion = false
            band.add(a, forKey: "sweep.\(key)")
        }
    }

    func stopAnimating() {
        band.removeAllAnimations()
        animating = false
    }

    // MARK: Representable 桥

    struct Representable: UIViewRepresentable {
        var uiFont: UIFont
        var baseColor: UIColor
        var textAlignment: NSTextAlignment
        var period: Double
        var text: String

        func makeUIView(context: Context) -> ShimmerLabelHost {
            let v = ShimmerLabelHost()
            v.configure(text: text, font: uiFont, color: baseColor,
                        alignment: textAlignment, period: period)
            return v
        }

        func updateUIView(_ uiView: ShimmerLabelHost, context: Context) {
            uiView.configure(text: text, font: uiFont, color: baseColor,
                             alignment: textAlignment, period: period)
        }

        static func dismantleUIView(_ uiView: ShimmerLabelHost, coordinator: ()) {
            uiView.stopAnimating()
        }
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

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
    private let diag = AppLogger(category: "ShimmerDiag")
    private var didMoveToWindowProbeCount = 0
    private var layoutFirstBoundsProbeDone = false

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
            let prefix = String(text.prefix(24)).replacingOccurrences(of: "\n", with: "↵")
            diag.info("[ShimmerDiag] configure dirty text=\"\(prefix)…\" font=\(font) color=\(color)")
            invalidateIntrinsicContentSize()
            maskKey = ""        // 强制 layoutSubviews 重建掩膜
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !layoutFirstBoundsProbeDone, bounds.width > 1 {
            layoutFirstBoundsProbeDone = true
            diag.info("[ShimmerDiag] layoutSubviews first bounds=\(bounds.size)")
        }
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
    /// [v12.1 09-19] 弃 label.layer.render(in:) —— 该 API 依赖 label 已上屏渲染状态，
    /// 首帧/重建时可能输出全透明 → mask 全空 → 亮带被全裁 → 全场景不显示。
    /// 改用 textRect(forBounds:) 取 UILabel 自身排版矩形（含垂直居中/截断），
    /// 再以 NSAttributedString 直绘；不依赖渲染状态，字形与 label 一致。
    private func rebuildMaskIfNeeded() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let key = "\(label.text ?? "")|\(label.font)|\(bounds.size)"
            + "|\(traitCollection.userInterfaceStyle.rawValue)"
        if key == maskKey { return }
        maskKey = key
        let format = UIGraphicsImageRendererFormat()
        format.scale = 0        // 跟随屏幕 scale
        let bounds = self.bounds
        let drawRect = label.textRect(forBounds: bounds, limitedToNumberOfLines: 1)
        let ps = NSMutableParagraphStyle()
        ps.alignment = label.textAlignment
        ps.lineBreakMode = label.lineBreakMode
        let attr = NSAttributedString(string: label.text ?? "", attributes: [
            .font: label.font as Any,
            .foregroundColor: label.textColor ?? UIColor.black,
            .paragraphStyle: ps
        ])
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { _ in
            traitCollection.performAsCurrent {
                attr.draw(in: drawRect)
            }
        }
        // [v12.2 09-19] 改标准姿势：CGImage + 显式 contentsScale。
        // CALayer.contents 期望 CGImage；此前直接赋 UIImage（声称“才认 scale”）
        // 在手动创建的 CALayer 上不可靠——若 UIImage 不被解释则 mask 全空、
        // 亮带被 100% 裁掉（与“全场景从不显示”吻合）；且不设 contentsScale 时
        // mask 像素↔pt 映射错误（字形被按 1x 放大/错位）。contentsScale 取图的
        // 实际 scale（与 FBShimmeringLayer 同款处理）。
        textMask.contentsScale = image.scale
        textMask.contents = image.cgImage

        // [ShimmerDiag] 重建后：size + alphaCoverage
        let sizeDesc = "\(Int(bounds.size.width))x\(Int(bounds.size.height))"
        let alphaDesc: String
        if let cg = image.cgImage {
            let w = cg.width, h = cg.height
            let total = w * h
            // alphaOnly + DeviceGray（Swift 导入的 space 非可选，C API 的 NULL 配法不可用；免位运算）
            if let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) {
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                if let buf = ctx.data {
                    let ptr = buf.bindMemory(to: UInt8.self, capacity: total)
                    var hit = 0
                    let step = 16
                    var sampled = 0
                    var i = 0
                    while i < total {
                        if ptr[i] > 8 { hit += 1 }
                        sampled += 1
                        i += step
                    }
                    let pct = sampled > 0 ? Double(hit) / Double(sampled) * 100.0 : 0.0
                    alphaDesc = String(format: "alphaCoverage=%.1f%%", pct)
                } else {
                    alphaDesc = "alphaCoverage=NO_BUF"
                }
            } else {
                alphaDesc = "alphaCoverage=NO_CTX"
            }
        } else {
            alphaDesc = "alphaCoverage=N/A"
        }
        diag.info("[ShimmerDiag] rebuildMask size=\(sizeDesc) \(alphaDesc) imgScale=\(image.scale) maskContents=\(textMask.contents != nil) maskScale=\(textMask.contentsScale)")
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
        diag.info("[ShimmerDiag] startIfNeeded bounds=\(bounds.size) intrinsic=\(intrinsicContentSize) maskAttached=\(band.mask != nil) keys=\(band.animationKeys() ?? [])")
        // [ShimmerDiag] 动画存活心跳：0.7s / 1.4s 读 presentation().startPoint.x
        // 两次值不同 = 动画在推进；相同或 nil = 动画死/没加。
        let heartbeat: (Double) -> Void = { [weak self] delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let self = self, self.window != nil else { return }
                let v = self.band.presentation()?.value(forKey: "startPoint")
                let desc: String
                if let p = v as? NSValue {
                    desc = "\(p.cgPointValue.x)"
                } else {
                    desc = "nil"
                }
                self.diag.info("[ShimmerDiag] heartbeat@\(String(format: "%.1f", delay))s startPoint.x=\(desc)")
            }
        }
        heartbeat(0.7)
        heartbeat(1.4)
    }

    func stopAnimating() {
        band.removeAllAnimations()
        animating = false
    }

    /// [09-19] 回屏恢复：view 移出 window 时系统会清掉 layer 上的 CA 动画，
    /// 若 animating 标志不清零，startIfNeeded 会永久短路（扫光死）。回屏时
    /// 重置标志并触发一次布局重启动画。
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if didMoveToWindowProbeCount < 10 {
            didMoveToWindowProbeCount += 1
            diag.info("[ShimmerDiag] didMoveToWindow window=\(window == nil ? "nil" : "non-nil") animating=\(animating)")
        }
        if window == nil {
            stopAnimating()
        } else {
            animating = false
            setNeedsLayout()
        }
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

import SwiftUI

/// Resolved configuration for the `line` family.
struct LineBeamConfig {
    let variant: BeamColorVariant
    let theme: String
    let staticColors: Bool
    let duration: Double
    let borderRadius: Double?
    let brightness: Double?
    let saturation: Double?
    let hueRange: Double // already capped at 13 by BorderBeam
    let strength: Double

    let spec = BeamSpec.shared

    var isDark: Bool { theme == "dark" }
    var themeConfig: BeamSpec.ThemeColors { spec.sizeThemePresets["line"]![theme]! }
    var sizeConfig: BeamSpec.SizeConfig { spec.sizePresets["line"]! }
    var radius: Double { borderRadius ?? sizeConfig.borderRadius }
    var finalBrightness: Double { brightness ?? themeConfig.brightness ?? spec.defaults.brightnessFallback }
    var finalSaturation: Double { saturation ?? themeConfig.saturation }
}

/// The three `line` layers: inner glow (z1), stroke band (z2), bloom (z3).
struct LineBeamLayers: View {
    let config: LineBeamConfig
    let fade: BeamFade

    @Environment(\.beamFrozenTime) private var frozenTime

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = frozenTime ?? timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                layers(
                    at: t, size: geo.size,
                    fade: frozenTime != nil ? 1 : fade.value(at: timeline.date)
                )
            }
        }
    }

    @ViewBuilder
    private func layers(at t: Double, size: CGSize, fade: Double) -> some View {
        let spec = config.spec
        let v = BeamAnimation.lineFrameValues(spec.line.keyframes, at: t, duration: config.duration)
        let hue = config.staticColors
            ? 0
            : -config.hueRange + 2 * config.hueRange * PulseDriver.pingPong(t / spec.defaults.rotateHueShiftPeriod)
        let bloomRange = config.hueRange + spec.defaults.lineBloomHueRangeBonus
        let bloomHue = config.staticColors
            ? 0
            : -bloomRange + 2 * bloomRange * PulseDriver.pingPong(t / spec.defaults.lineBloomHueShiftPeriod)
        // Web parity: with staticColors the line layers carry no filter (the
        // brightness/saturate live only in the hue-shift keyframes); mono's
        // bloom keeps just its 6px blur, applied below.
        let identity: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
        let cm = config.staticColors ? identity : BeamColorMatrix.composed(
            hueDegrees: hue, brightness: config.finalBrightness, saturation: config.finalSaturation
        )
        let bloomCM = config.staticColors ? identity : BeamColorMatrix.composed(
            hueDegrees: bloomHue, brightness: config.finalBrightness, saturation: config.finalSaturation
        )

        let W = size.width
        let H = size.height
        let bx = v.x * W
        let base = fade * v.edge * config.strength

        // [PATCH-BB1] 比例适配元素实际尺寸（pp 2026-09-23「这个动画的尺寸你应该
        // 要调一下吧 因为我们这个搜索栏很长」，拍板方案 B=直接改包按比例缩放）。
        // 基准 157×42 = libraries.dev/beam 的 r2 Search 胶囊——与本 beam-spec 同源
        // 渲染、pp 指认的目标观感；官方 demo 站 beam.jakubantalik.com 当时 TLS/连接
        // 失败无法直量，故取该胶囊为参考几何。
        // 为什么必须缩：spec 的 line 几何全是为该基准调的**绝对 px**（mask.w=78 →
        // 在 157 宽上占 50%，本仓 ~350pt 全宽搜索栏上只剩 22%，相对细一半；同
        // 3.1s 走完全程＝视觉速度快 2.2×）。X 轴量 ×(W/157)、Y 轴量 ×(H/42)。
        // Y 不跟 X：栏高只 42→47（×1.12），若也乘 2.23 光斑会糊满整条胶囊。
        // 有意不缩放：`bx = v.x×W`（本就宽度比例）、`xPct`（本就百分比）、
        // `borderWidth`（1pt 绝对值，缩了就错）、全部关键帧分数、hue/brightness/
        // saturation（色彩属性与尺寸无关）。duration 3.1s 本轮不动——一次只动一个
        // 变量，装机看速度感再决定要不要放慢。
        // 上游同步须重打此补丁：见仓库 PATCHES.md「BB1」。
        let sx = Double(W) / 157.0
        let sy = Double(H) / 42.0

        let mask = spec.line.beamMaskEllipse
        let bloomMask = spec.line.bloomMaskEllipse
        let radial: [Float] = [
            Float(bx), Float(H),
            Float(mask.w * v.w * sx), Float(mask.h * v.h * sy),
            Float(mask.softStop[0] / 100), Float(mask.softStop[1]), 1,
        ]
        let bloomRadial: [Float] = [
            Float(bx), Float(H),
            Float(bloomMask.w * v.w * sx), Float(bloomMask.h * v.h * sy),
            Float(bloomMask.softStop[0] / 100), Float(bloomMask.softStop[1]), 1,
        ]

        // Web parity: the animated bloom filter includes blur(8px); mono with
        // static colors gets base blur(6px); other static variants none.
        let bloomBlur: Double = config.staticColors
            ? (config.variant == .mono ? spec.line.monoBloomExtraBlurPx : 0)
            : spec.line.bloomBlurPx

        ZStack {
            shaderLayer(
                size: size, geomKind: 1, edgeMaskPx: spec.rotate.innerEdgeMaskPx,
                radial: radial, blobs: innerBlobs(v: v, bx: bx, height: H, sx: sx, sy: sy),
                matrix: cm, opacity: base * config.themeConfig.innerOpacity
            )
            shaderLayer(
                size: size, geomKind: 0, edgeMaskPx: 0,
                radial: radial, blobs: strokeBlobs(v: v, bx: bx, height: H, sx: sx, sy: sy),
                matrix: cm, opacity: base * config.themeConfig.strokeOpacity
            )
            let bloom = shaderLayer(
                size: size, geomKind: 1, edgeMaskPx: 0,
                radial: bloomRadial, blobs: bloomBlobs(v: v, bx: bx, width: W, height: H, sx: sx, sy: sy),
                matrix: bloomCM, opacity: base * config.themeConfig.bloomOpacity
            )
            if bloomBlur > 0 {
                bloom.blur(radius: bloomBlur)
            } else {
                bloom
            }
        }
    }

    // ── Blob construction (mirrors border-beam-native LineBeam.tsx) ──

    private func strokeBlobs(v: BeamAnimation.LineFrameValues, bx: Double, height: Double, sx: Double, sy: Double) -> [Float] {
        let spec = config.spec
        var blobs: [Float] = []
        // White traveling highlight first (on top).
        if let wh = spec.line.whiteHighlight[config.theme] {
            let c = (wh.onBlack ?? false) ? 0.0 : 1.0
            let stops = wh.stops.map {
                BeamSpec.BloomStop(r: c * 255, g: c * 255, b: c * 255, a: $0[1], pos: $0[0] / 100)
            }
            blobs += BlobEncoder.stops(
                rx: wh.w * v.w * sx, ry: wh.h * v.h * sy,
                cx: bx, cy: height + wh.yOffset * sy, stops: stops
            )
        }
        for e in spec.palettes.line[config.variant.rawValue]![config.theme]! {
            guard let c = BeamRGBA(css: e.color) else { continue }
            blobs += BlobEncoder.simple(
                rx: e.sizeW * v.w * sx, ry: e.sizeH * v.h * sy,
                cx: bx + e.offsetX * sx, cy: height + e.offsetY * sy, color: c
            )
        }
        return blobs
    }

    private func innerBlobs(v: BeamAnimation.LineFrameValues, bx: Double, height: Double, sx: Double, sy: Double) -> [Float] {
        var blobs: [Float] = []
        for e in config.spec.palettes.lineInner[config.variant.rawValue]! {
            guard let c = BeamRGBA(css: e.color) else { continue }
            blobs += BlobEncoder.simple(
                rx: e.sizeW * v.w * sx, ry: e.sizeH * v.h * sy,
                cx: bx + e.offsetX * sx, cy: height - abs(e.offsetY) * sy, color: c
            )
        }
        return blobs
    }

    private func bloomBlobs(v: BeamAnimation.LineFrameValues, bx: Double, width: Double, height: Double, sx: Double, sy: Double) -> [Float] {
        var blobs: [Float] = []
        let grads = config.spec.line.bloomGradients[config.variant.rawValue]![config.theme]!
        for g in grads {
            let cx = g.xPct.map { $0 / 100 * width } ?? bx
            // [PATCH-BB1] xPct cx unscaled — already a fraction of the actual width.
            blobs += BlobEncoder.stops(
                rx: g.w.base * BeamAnimation.multValue(g.w.mult, v) * sx,
                ry: g.h.base * BeamAnimation.multValue(g.h.mult, v) * sy,
                cx: cx, cy: height + g.yOffPx * sy, stops: g.stops
            )
        }
        return blobs
    }

    private func shaderLayer(
        size: CGSize,
        geomKind: Double,
        edgeMaskPx: Double,
        radial: [Float],
        blobs: [Float],
        matrix: [Float],
        opacity: Double
    ) -> some View {
        let shader = ShaderLibrary.bundle(.module).beamBlobLayer(
            .float2(0, 0),
            .float2(size),
            .float(config.radius),
            .float(config.sizeConfig.borderWidth),
            .float(geomKind),
            .float(edgeMaskPx),
            // Corner-wrap: the line family's blobs all anchor to the bottom
            // border, so evaluating them in border-path space bends the
            // traveling streak around the corner radius as it reaches the
            // ends. Identical along the straight bottom edge; iOS deviation
            // from the web renderer (see the pulse-inner layer note).
            .float(1),
            .floatArray(radial),
            .floatArray(blobs),
            .floatArray(matrix),
            .float(opacity)
        )
        return Rectangle().fill(Color.white).colorEffect(shader)
    }
}

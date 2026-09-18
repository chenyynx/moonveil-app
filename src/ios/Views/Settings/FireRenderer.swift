//
//  FireRenderer.swift
//  Metal render engine for the Effort slider "Ultracode" fire layer.
//
//  4-pass pipeline per frame:
//    1. SIM    — fire simulation, feeds back on itself (ping-pong)
//    2. BLUR H — horizontal 7-tap blur, dark pixels culled (bloom threshold)
//    3. BLUR V — vertical 7-tap blur, keeps dark pixels
//    4. COMP   — HDR tone-mapped composite of SIM + BLUR V onto the drawable
//

import MetalKit
import QuartzCore

final class FireRenderer: NSObject, MTKViewDelegate {

    // MARK: Public API (driven from FireCanvasView)

    /// 0...100. Setting this derives `isActive`; on a Low/Medium/High <->
    /// Ultracode transition the simulation textures are cleared so the
    /// flame always restarts cleanly, matching the reference behavior.
    var sliderValue: Double = 70 {
        didSet {
            let wasActive = isActive
            isActive = sliderValue >= 100
            if isActive != wasActive, isActive {
                // Only reset on the rising edge, matching the WebGL version:
                // on the falling edge the sim textures keep their contents so
                // the embers fade out naturally via the shader's decay term
                // (the canvas opacity fade covers the visual transition).
                activeStartTime = CACurrentMediaTime()
                clearSimTextures()
                startDisplayLink()
            }
        }
    }

    private(set) var isActive: Bool = false

    /// Set by FireCanvasView right after creating the MTKView.
    weak var mtkView: MTKView?

    let device: MTLDevice

    // MARK: Metal objects

    private let commandQueue: MTLCommandQueue
    private var simPipeline: MTLRenderPipelineState!
    private var blurPipeline: MTLRenderPipelineState!
    private var compPipeline: MTLRenderPipelineState!

    private var simA: MTLTexture?
    private var simB: MTLTexture?
    private var blurH: MTLTexture?
    private var blurV: MTLTexture?
    private var textureSize: CGSize = .zero

    // MARK: Timing / idle handling

    private var displayLink: CADisplayLink?
    private let bootTime = CACurrentMediaTime()
    private var activeStartTime: CFTimeInterval = 0
    /// Timestamp of the previous tick, for frame-rate-independent simulation.
    private var lastFrameTimestamp: CFTimeInterval = CACurrentMediaTime()
    private var idleFrameCount = 0
    private let idleFrameLimit = 180 // ~3s at 60fps after leaving Ultracode

    // MARK: Init

    init(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("FireRenderer: unable to create a Metal command queue")
        }
        self.commandQueue = queue
        super.init()
        buildPipelines()
    }

    deinit {
        displayLink?.invalidate()
    }

    private func buildPipelines() {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("FireRenderer: unable to load the default Metal library")
        }
        let vertexFn = library.makeFunction(name: "vertex_fullscreen")

        func pipeline(_ fragmentName: String, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vertexFn
            desc.fragmentFunction = library.makeFunction(name: fragmentName)
            desc.colorAttachments[0].pixelFormat = pixelFormat
            do {
                return try device.makeRenderPipelineState(descriptor: desc)
            } catch {
                fatalError("FireRenderer: failed to build pipeline '\(fragmentName)': \(error)")
            }
        }

        // Sim/blur render into offscreen HDR (rgba16Float) textures. The sim
        // shader intentionally writes values above 1.0 (see
        // `min(decay + col, float3(1.5))` in Shaders.metal) so the final
        // tone-mapping pass has real headroom to compress — an 8-bit target
        // would silently clip that and flatten the glow. This is the one
        // deliberate deviation from the "RGBA8" note in the spec.
        simPipeline = pipeline("fragment_sim", pixelFormat: .rgba16Float)
        blurPipeline = pipeline("fragment_blur", pixelFormat: .rgba16Float)
        // Tone-mapped composite to the screen: write through the sRGB transfer
        // function so the glow hue is not washed out by the linear write.
        compPipeline = pipeline("fragment_comp", pixelFormat: .bgra8Unorm_srgb)
    }

    // MARK: Texture management (ResizeObserver equivalent)

    func rebuildTextures(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        textureSize = size

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: max(Int(size.width), 1),
            height: max(Int(size.height), 1),
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private

        simA = device.makeTexture(descriptor: desc)
        simB = device.makeTexture(descriptor: desc)
        blurH = device.makeTexture(descriptor: desc)
        blurV = device.makeTexture(descriptor: desc)

        clearSimTextures()
    }

    private func clearSimTextures() {
        guard let simA, let simB,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        for tex in [simA, simB] {
            let passDesc = MTLRenderPassDescriptor()
            passDesc.colorAttachments[0].texture = tex
            passDesc.colorAttachments[0].loadAction = .clear
            passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
            passDesc.colorAttachments[0].storeAction = .store
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc)
            encoder?.endEncoding()
        }
        commandBuffer.commit()
    }

    // MARK: Display-link driven render loop

    func startDisplayLink() {
        guard displayLink == nil else { return }
        idleFrameCount = 0
        let link = CADisplayLink(target: self, selector: #selector(tick))
        // ProMotion displays can run the sim at 120Hz for a smoother flame;
        // the decay term is dt-scaled so this stays visually identical.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard let mtkView else { return }
        if isActive {
            idleFrameCount = 0
        } else {
            idleFrameCount += 1
            if idleFrameCount > idleFrameLimit {
                stopDisplayLink()
                return
            }
        }
        mtkView.draw()
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        rebuildTextures(size: size)
    }

    func draw(in view: MTKView) {
        guard let curSimA = simA, let curSimB = simB,
              let curBlurH = blurH, let curBlurV = blurV,
              let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let now = CACurrentMediaTime()
        let uTime = Float(now - bootTime)
        let uSlider = Float(sliderValue / 100.0)
        let uElapsed: Float = isActive ? Float(now - activeStartTime) : -1.0
        // Clamp dt so a long re-boot pause (e.g. app background) doesn't make
        // the decay pow() explode; 1/120 is the max trusted refresh interval.
        let uDt = Float(max(now - lastFrameTimestamp, 1.0 / 120.0))
        lastFrameTimestamp = now
        let resolution = SIMD2<Float>(Float(textureSize.width), Float(textureSize.height))

        // Pass 1 — SIM: curSimA (previous frame) -> curSimB (this frame)
        encodeSim(commandBuffer, source: curSimA, destination: curSimB,
                  uTime: uTime, uSlider: uSlider, uElapsed: uElapsed, uDt: uDt)

        // Pass 2 — BLUR H: curSimB -> curBlurH, culling dark pixels (bloom threshold)
        encodeBlur(commandBuffer, source: curSimB, destination: curBlurH,
                   direction: SIMD2<Float>(1, 0), resolution: resolution, ext: 1.0)

        // Pass 3 — BLUR V: curBlurH -> curBlurV, keeping dark pixels
        encodeBlur(commandBuffer, source: curBlurH, destination: curBlurV,
                   direction: SIMD2<Float>(0, 1), resolution: resolution, ext: 0.0)

        // Pass 4 — COMP: curSimB + curBlurV -> drawable
        passDescriptor.colorAttachments[0].loadAction = .dontCare
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) {
            encoder.setRenderPipelineState(compPipeline)
            encoder.setFragmentTexture(curSimB, index: 0)
            encoder.setFragmentTexture(curBlurV, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()

        // Ping-pong swap: this frame's SIM output becomes next frame's "u_back"
        swap(&simA, &simB)
    }

    private func encodeSim(_ commandBuffer: MTLCommandBuffer,
                            source: MTLTexture, destination: MTLTexture,
                            uTime: Float, uSlider: Float, uElapsed: Float, uDt: Float) {
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = destination
        passDesc.colorAttachments[0].loadAction = .dontCare
        passDesc.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else { return }
        encoder.setRenderPipelineState(simPipeline)
        encoder.setFragmentTexture(source, index: 0)
        var uniforms = SimUniforms(u_time: uTime, u_slider: uSlider, u_elapsed: uElapsed, u_dt: uDt)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SimUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func encodeBlur(_ commandBuffer: MTLCommandBuffer,
                             source: MTLTexture, destination: MTLTexture,
                             direction: SIMD2<Float>, resolution: SIMD2<Float>, ext: Float) {
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = destination
        passDesc.colorAttachments[0].loadAction = .dontCare
        passDesc.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else { return }
        encoder.setRenderPipelineState(blurPipeline)
        encoder.setFragmentTexture(source, index: 0)
        var uniforms = BlurUniforms(u_dir: direction, u_res: resolution, u_ext: ext)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BlurUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

// MARK: - Uniform layouts (must match Shaders.metal exactly)

private struct SimUniforms {
    var u_time: Float
    var u_slider: Float
    var u_elapsed: Float
    var u_dt: Float
}

private struct BlurUniforms {
    var u_dir: SIMD2<Float>
    var u_res: SIMD2<Float>
    var u_ext: Float
}
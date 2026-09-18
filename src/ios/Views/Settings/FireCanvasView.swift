//
//  FireCanvasView.swift
//  SwiftUI bridge for the Metal fire layer (FireRenderer).
//
//  The MTKView is owned by this representable; all simulation state lives in
//  FireRenderer. The view is transparent and non-interactive — it is meant to
//  sit underneath the slider thumb inside the track and be composited with
//  `.blendMode(.screen)` by the parent.
//

import SwiftUI
import MetalKit

struct FireCanvasView: UIViewRepresentable {

    /// 0...100. Drives the flame front position and the Ultracode on/off
    /// transition inside FireRenderer.
    @Binding var sliderValue: Double

    // The renderer is the coordinator so its lifetime matches the view's.
    func makeCoordinator() -> FireRenderer {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("FireCanvasView: Metal is not supported on this device")
        }
        return FireRenderer(device: device)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.delegate = context.coordinator
        // Must match the comp pipeline's pixel format (.bgra8Unorm).
        view.colorPixelFormat = .bgra8Unorm
        // Transparent: the track background shows through, fire adds on top.
        view.isOpaque = false
        view.backgroundColor = .clear
        // We drive draw() from FireRenderer's own CADisplayLink, so the
        // MTKView's built-in timer stays off.
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.isUserInteractionEnabled = false
        context.coordinator.mtkView = view
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.sliderValue = sliderValue
    }

    static func dismantleUIView(_ view: MTKView, coordinator: FireRenderer) {
        coordinator.stopDisplayLink()
        coordinator.mtkView = nil
    }
}

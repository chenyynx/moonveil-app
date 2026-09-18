//
//  EffortCardView.swift
//  Claude-style Effort slider card with the "Ultracode" fire layer.
//
//  Visual spec ported from https://github.com/254558/claude-range-slider
//  (itself a replica of Claude's Effort card). All colors, sizes, spacing
//  and animation parameters follow the reference implementation.
//
//  Layout:
//  ┌─────────────────────────────────────┐
//  │  Effort  [StatusLabel]          ?   │
//  │  Faster                    Smarter  │
//  │  ┌─────────────────────────────────┐│
//  │  │ dots  [fire canvas]   [thumb]   ││
//  │  └─────────────────────────────────┘│
//  └─────────────────────────────────────┘
//

import SwiftUI
import UIKit

// Dot marker positions along the track (10% / 30% / 50% / 70% / 90%).
private let effortDotPositions: [CGFloat] = [0.1, 0.3, 0.5, 0.7, 0.9]

struct EffortCardView: View {

    @State private var sliderValue: Double = 70
    /// Drives the flip-up entrance of the status label when entering Ultracode.
    @State private var statusAppeared = true

    // MARK: Derived state (mirrors useSliderState.js)

    private var isActive: Bool { sliderValue >= 100 }
    private var isFull: Bool { sliderValue >= 100 }

    private var statusLabel: String {
        if sliderValue < 33 { return "Low" }
        if sliderValue < 66 { return "Medium" }
        if sliderValue < 100 { return "High" }
        return "Ultracode"
    }

    // MARK: Colors (exact values from the reference CSS)

    private var statusColor: Color {
        if isActive {
            // #c084fc
            return Color(red: 192 / 255, green: 132 / 255, blue: 252 / 255)
        }
        // #a1a1aa
        return Color(red: 161 / 255, green: 161 / 255, blue: 170 / 255)
    }

    private var glowColor: Color {
        // rgba(168,85,247,0.6)
        Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255).opacity(0.6)
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 14)
            scaleLabels
                .padding(.bottom, 7)
            track
        }
        .padding(.top, 18)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: 376)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        // Card drop shadow: 0 12px 28px 20% + 0 4px 12px 10%
        .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 12)
        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 4)
        .onChange(of: statusLabel) { _, newValue in
            handleStatusChange(newValue)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 7) {
            Text("Effort")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(red: 176 / 255, green: 176 / 255, blue: 199 / 255))

            statusText

            Spacer(minLength: 0)

            Image(systemName: "questionmark.circle")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color(red: 161 / 255, green: 161 / 255, blue: 170 / 255))
        }
    }

    /// Status label with glow + flip-up entrance on entering Ultracode.
    /// Reference: rotateX(-80°) translateY(18px) blur(4px) -> identity,
    /// 0.42s cubic-bezier(0.33, 1, 0.68, 1), transform-origin center bottom.
    private var statusText: some View {
        Text(statusLabel)
            .font(.system(size: 16, weight: isActive ? .semibold : .medium))
            .foregroundStyle(statusColor)
            .shadow(color: isActive ? glowColor : .clear, radius: 6)
            .opacity(statusAppeared ? 1 : 0)
            .offset(y: statusAppeared ? 0 : 18)
            .blur(radius: statusAppeared ? 0 : 4)
            .rotation3DEffect(
                .degrees(statusAppeared ? 0 : -80),
                axis: (x: 1, y: 0, z: 0),
                anchor: .bottom,
                perspective: 0.7
            )
            .animation(.easeInOut(duration: 0.3), value: isActive)
    }

    private func handleStatusChange(_ newValue: String) {
        if newValue == "Ultracode" {
            // Reset to the hidden pose without animation, then animate in.
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                statusAppeared = false
            }
            DispatchQueue.main.async {
                withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.42)) {
                    statusAppeared = true
                }
            }
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                statusAppeared = true
            }
        }
    }

    // MARK: Scale labels

    private var scaleLabels: some View {
        HStack {
            Text("Faster")
            Spacer(minLength: 0)
            Text("Smarter")
        }
        .font(.system(size: 14, weight: .heavy))
        .tracking(0.56) // 0.04em at 14pt
        .foregroundStyle(Color(red: 176 / 255, green: 176 / 255, blue: 184 / 255))
    }

    // MARK: Track

    private var track: some View {
        ZStack {
            // Background gradient: linear-gradient(135deg, #111113, #0a0a0b)
            LinearGradient(
                colors: [
                    Color(red: 17 / 255, green: 17 / 255, blue: 19 / 255),
                    Color(red: 10 / 255, green: 10 / 255, blue: 11 / 255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            dotsLayer

            // Fire layer: screen-blended, only visible while active, and
            // hard-masked at (sliderValue + 2)% like the reference canvas.
            FireCanvasView(sliderValue: $sliderValue)
                .blendMode(.screen)
                .opacity(isActive ? 1 : 0)
                .mask(fireMask)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.3), value: isActive)

            EffortSlider(value: $sliderValue, glowing: isActive)
        }
        .frame(height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(red: 26 / 255, green: 26 / 255, blue: 30 / 255), lineWidth: 1)
        )
    }

    private var dotsLayer: some View {
        GeometryReader { geo in
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(Color(red: 73 / 255, green: 73 / 255, blue: 80 / 255))
                    .frame(width: 5, height: 5)
                    .position(
                        x: geo.size.width * effortDotPositions[i],
                        y: geo.size.height / 2
                    )
            }
        }
        .opacity(isFull ? 0 : (isActive ? 0.25 : 1))
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.6), value: isActive)
        .animation(.easeInOut(duration: 0.6), value: isFull)
    }

    /// Hard-edged mask: fully visible up to (sliderValue + 2)%, clear after.
    private var fireMask: some View {
        let p = CGFloat(min(sliderValue + 2, 100) / 100)
        return LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: p),
                .init(color: .clear, location: p)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - UISlider wrapper (custom thumb needs UIKit)

/// SwiftUI's `Slider` cannot customize the thumb's appearance, so this wraps
/// `UISlider` and supplies rendered thumb images (white rounded square with
/// drop shadows; purple glow while in Ultracode; 0.95 scale while pressed,
/// matching the reference `:active` state).
private struct EffortSlider: UIViewRepresentable {

    @Binding var value: Double
    var glowing: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, glowing: glowing)
    }

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 100
        slider.value = Float(value)
        // The track visuals come from the layers underneath; UIKit's own
        // track rendering stays fully transparent.
        slider.minimumTrackTintColor = .clear
        slider.maximumTrackTintColor = .clear
        EffortSlider.applyThumbImages(to: slider, glowing: glowing)
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.changed(_:)),
            for: .valueChanged
        )
        return slider
    }

    func updateUIView(_ uiView: UISlider, context: Context) {
        let v = Float(value)
        if abs(uiView.value - v) > 0.01 {
            uiView.value = v
        }
        if context.coordinator.glowing != glowing {
            context.coordinator.glowing = glowing
            EffortSlider.applyThumbImages(to: uiView, glowing: glowing)
        }
    }

    private static func applyThumbImages(to slider: UISlider, glowing: Bool) {
        slider.setThumbImage(makeThumbImage(glowing: glowing, highlighted: false),
                             for: .normal)
        slider.setThumbImage(makeThumbImage(glowing: glowing, highlighted: true),
                             for: .highlighted)
    }

    // MARK: Thumb rendering

    /// Renders the 29x29 white rounded-square thumb (corner radius 10) with
    /// the reference drop shadows. `highlighted` renders the 0.95 pressed
    /// scale; `glowing` adds the Ultracode purple halo:
    ///   0 0 28px rgba(168,85,247,0.5), 0 0 50px rgba(168,85,247,0.25)
    /// The 50px layer is intentionally cropped by the canvas edge — its
    /// visible falloff beyond 28pt is negligible, and a bigger canvas would
    /// inflate the thumb's hit area past the track's neighbours.
    static func makeThumbImage(glowing: Bool, highlighted: Bool) -> UIImage {
        let scale: CGFloat = highlighted ? 0.95 : 1.0
        let thumb: CGFloat = 29 * scale
        let pad: CGFloat = glowing ? 36 : 8
        let canvas = thumb + pad * 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvas, height: canvas))
        return renderer.image { ctx in
            let rect = CGRect(x: pad, y: pad, width: thumb, height: thumb)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 10 * scale)
            let c = ctx.cgContext

            UIColor.white.setFill()

            // Ultracode glow: 0 0 28px 50% + 0 0 50px 25%
            if glowing {
                c.setShadow(offset: .zero, blur: 28,
                            color: UIColor(red: 168 / 255, green: 85 / 255,
                                           blue: 247 / 255, alpha: 0.5).cgColor)
                path.fill()
                c.setShadow(offset: .zero, blur: 50,
                            color: UIColor(red: 168 / 255, green: 85 / 255,
                                           blue: 247 / 255, alpha: 0.25).cgColor)
                path.fill()
            }

            // Reference drop shadows:
            //   0 0.5px 1px rgba(0,0,0,0.18)
            //   0 2px 6px rgba(0,0,0,0.25)
            //   0 6px 16px rgba(0,0,0,0.12)
            c.setShadow(offset: CGSize(width: 0, height: 0.5), blur: 1,
                        color: UIColor.black.withAlphaComponent(0.18).cgColor)
            path.fill()
            c.setShadow(offset: CGSize(width: 0, height: 2), blur: 6,
                        color: UIColor.black.withAlphaComponent(0.25).cgColor)
            path.fill()
            c.setShadow(offset: CGSize(width: 0, height: 6), blur: 16,
                        color: UIColor.black.withAlphaComponent(0.12).cgColor)
            path.fill()

            // Body gradient: linear-gradient(170deg, #fff 0%, #f0f0f2 40%, #e4e4e6 100%)
            c.setShadow(offset: .zero, blur: 0, color: nil)
            c.saveGState()
            path.addClip()
            let colors = [
                UIColor(red: 1, green: 1, blue: 1, alpha: 1).cgColor,
                UIColor(red: 240 / 255, green: 240 / 255, blue: 242 / 255, alpha: 1).cgColor,
                UIColor(red: 228 / 255, green: 228 / 255, blue: 230 / 255, alpha: 1).cgColor
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.4, 1]
            ) {
                // 170deg is almost straight down, tilted slightly left.
                c.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.midX + 2.6, y: rect.minY),
                    end: CGPoint(x: rect.midX - 2.6, y: rect.maxY),
                    options: []
                )
            }
            c.restoreGState()

            // Hairline border: 0.5px rgba(0,0,0,0.08)
            UIColor.black.withAlphaComponent(0.08).setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>
        var glowing: Bool

        init(value: Binding<Double>, glowing: Bool) {
            self.value = value
            self.glowing = glowing
        }

        @objc func changed(_ slider: UISlider) {
            value.wrappedValue = Double(slider.value)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(white: 0.13).ignoresSafeArea()
        EffortCardView()
            .padding(.horizontal)
    }
}

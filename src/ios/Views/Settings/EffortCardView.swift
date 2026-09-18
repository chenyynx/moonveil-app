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
    /// `.fixedSize()` pins the text to its natural width so it can never be
    /// compressed to an ellipsis inside the `HStack` (the `Spacer` takes the
    /// slack — there is plenty of room for "Ultracode").
    private var statusText: some View {
        Text(statusLabel)
            .font(.system(size: 16, weight: isActive ? .semibold : .medium))
            .foregroundStyle(statusColor)
            .fixedSize()
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
        GeometryReader { geo in
            let tw = geo.size.width
            // UISlider centers its thumb at:
            //   thumbWidth/2 + progress * (trackWidth - thumbWidth)
            let thumbX = EffortSlider.thumbSize / 2
                + CGFloat(sliderValue / 100.0) * (tw - EffortSlider.thumbSize)
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

                dotsLayer(width: tw)

                // Fire layer: screen-blended, only visible while active, and
                // hard-masked at (sliderValue + 2)% like the reference canvas.
                FireCanvasView(sliderValue: $sliderValue)
                    .blendMode(.screen)
                    .opacity(isActive ? 1 : 0)
                    .mask(fireMask)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.3), value: isActive)

                // Ultracode halo, drawn SwiftUI-side (under the thumb) so the
                // thumb image itself stays small — a large canvas would leave
                // the knob visibly short of the track's right edge and inflate
                // its hit area past the track.
                if isActive {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255))
                        .frame(width: 29, height: 29)
                        .blur(radius: 14)
                        .opacity(0.55)
                        .position(x: thumbX, y: 15)
                        .allowsHitTesting(false)
                }

                EffortSlider(value: $sliderValue, width: tw)
            }
        }
        .frame(height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(red: 26 / 255, green: 26 / 255, blue: 30 / 255), lineWidth: 1)
        )
    }

    private func dotsLayer(width: CGFloat) -> some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(Color(red: 73 / 255, green: 73 / 255, blue: 80 / 255))
                    .frame(width: 5, height: 5)
                    .position(
                        x: width * effortDotPositions[i],
                        y: 15
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

// MARK: - Effort slider (self-drawn)

/// SwiftUI's `Slider` cannot customize the thumb's shape, and the UIKit
/// `UISlider` on iOS 26 draws its own round glass thumb regardless of a
/// custom `setThumbImage` — so the thumb is drawn by hand. A `DragGesture`
/// drives the value; horizontal drags move the thumb, vertical drags are
/// left to the enclosing `ScrollView` so page scrolling still works.
private struct EffortSlider: View {

    /// Side length of the rounded-square thumb (corner radius 10).
    static let thumbSize: CGFloat = 29

    @Binding var value: Double
    /// Track width, passed in from the parent `GeometryReader` so the thumb
    /// centre and the SwiftUI halo are computed from the same width.
    var width: CGFloat
    /// Horizontal-drag latch: set once this gesture is horizontal, cleared
    /// on release. Prevents vertical swipes (page scroll) from nudging the
    /// value through the touch's X coordinate.
    @State private var horizontalDrag = false

    var body: some View {
        let usable = width - Self.thumbSize
        let progress = min(max(value, 0), 100) / 100
        // Thumb centre travels from thumbSize/2 (left end) to
        // width - thumbSize/2 (right end), so at 100 its right edge is
        // flush with the track's right end.
        let thumbCenterX = Self.thumbSize / 2 + CGFloat(progress) * usable

        ZStack {
                // Interactivity layer covering the whole track.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { g in
                                let dx = abs(g.translation.width)
                                let dy = abs(g.translation.height)
                                if !horizontalDrag {
                                    // Vertical swipe: leave it to the enclosing
                                    // ScrollView and never latch onto it.
                                    if dy > 6 && dy > dx { return }
                                    // Wait for a little travel before locking, so
                                    // a pure tap never sets the value.
                                    if dx < 2 && dy < 2 { return }
                                    horizontalDrag = true
                                }
                                let p = (g.location.x - Self.thumbSize / 2) / usable
                                value = Double(min(max(p, 0), 1)) * 100
                            }
                            .onEnded { _ in
                                horizontalDrag = false
                            }
                    )

                // Thumb: white rounded square with drop shadows (reference:
                //   0 0.5px 1px rgba(0,0,0,0.18)
                //   0 2px 6px rgba(0,0,0,0.25)
                //   0 6px 16px rgba(0,0,0,0.12)
                // Body gradient 170deg #fff -> #f0f0f2 -> #e4e4e6).
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color(red: 240 / 255, green: 240 / 255, blue: 242 / 255),
                                Color(red: 228 / 255, green: 228 / 255, blue: 230 / 255)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                    )
                    .frame(width: Self.thumbSize, height: Self.thumbSize)
                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
                    .position(x: thumbCenterX, y: 15)
                    .allowsHitTesting(false)  // gestures handled by the layer above
            }
        }
        .frame(height: 30)
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

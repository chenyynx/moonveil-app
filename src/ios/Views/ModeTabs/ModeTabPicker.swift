// ModeTabPicker.swift — Grok-style top capsule (U1 政策件; pp 2026-09-15 定稿:
// 坐列表顶栏标题位，两档 = [SOUL name 回退 Moonveil] / Remote，首档随本地 agent 名).
//
// B13-TABGLASS (pp 2026-09-16, device screenshot): the surface must be the SAME
// liquid glass the neighbouring toolbar buttons get — the gear at the leading edge
// has NO custom material in our code, it is a plain `ToolbarItem` Button wearing the
// system's iOS 26 glass. So the segments are now real Buttons wearing that system
// glass, and the slide is the system's own glass morph:
//   • `GlassEffectContainer` + `.glassEffectID(_:in:)` — Apple's documented mechanism
//     for morphing liquid-glass elements between each other (their own samples use it
//     exactly this way). Selection changes morph the capsule instead of my hand-rolled
//     matchedGeometry pill, and a scrub drives it live → 跟手.
//   • `.buttonStyle(.glass)` on the selected segment → press brightens/scales by
//     itself, same as the gear → 发光 + 变大.
//   • both labels are `.primary` (black in light mode) — pp: 「tab有没有选择都是黑色字体」.
//
// Material lineage (all verified in-tree or in Apple docs, zero invented glass):
//   • system glass button = SwiftUI `PrimitiveButtonStyle.glass(_:)` (iOS 26+);
//     AA's own `AppGlassButton` already uses `.glass` / `.glassProminent` behind an
//     availability shim (AuthGlassCompat.swift) — same house recipe, not a new one.
//   • fallback < iOS 26 = `.regularMaterial` capsule + hairline (system material, NOT
//     a hand-rolled blur; U1 禁自造 blur, gate `grep .blur(` stays empty).
//   • geometry     = GrokModePicker reference (shared/fusion/refs/): 36pt, 14pt
//                    semibold, inner 3pt, spring(0.28/0.82), soft haptic on switch,
//                    selection detents on scrub, self-supplied 200pt width (B9-LANDING).
//   • retap        = tapping the already-selected local segment keeps the upstream
//                    title-tap action (open sync migration detail) — the capsule
//                    replaces the title WITHOUT losing that entry.

import SwiftUI
import UIKit

/// The app's two source modes (D4: the single fork point).
enum AppSourceMode: String, CaseIterable, Identifiable {
    case local, remote
    var id: String { rawValue }
}

struct ModeTabPicker: View {
    @Binding var selection: AppSourceMode
    /// First segment label — SAME source as the upstream sidebar title
    /// (SOUL.md name, fallback "Moonveil"). Never a parallel naming channel.
    var localLabel: String
    var remoteLabel: String = "Remote"
    /// Tap on the already-selected local segment (upstream title-tap action).
    var onLocalRetap: (() -> Void)?

    @Namespace private var glass

    private static let trackHeight: CGFloat = 36
    private static let innerPadding: CGFloat = 3
    /// B9-LANDING: the capsule owns its width — a GeometryReader has no intrinsic
    /// size and collapsed to ~10pt inside `ToolbarItem(.principal)`.
    private static let trackWidth: CGFloat = 200
    private static var slotWidth: CGFloat {
        (trackWidth - innerPadding * 2) / CGFloat(AppSourceMode.allCases.count)
    }

    private var label: (AppSourceMode) -> String {
        { $0 == .local ? localLabel : remoteLabel }
    }

    var body: some View {
        // NOTE (B12 CI lesson): availability branches are wrapped in Group — a bare
        // if/else is a statement block and cannot carry trailing modifiers.
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: Self.innerPadding * 2) {
                    segments
                }
            } else {
                segments
            }
        }
        .frame(width: Self.trackWidth, height: Self.trackHeight)
        // B13-SWIPEFIX: hit band is WIDER than the visual capsule (fills the top bar),
        // and it is a highPriority gesture because `.glass` buttons consume the touch
        // first — with a plain `.gesture` the scrub silently stopped working (the
        // 失灵 pp hit). Tapping a segment still works: a short press never reaches the
        // drag's translation threshold, so it falls through to the Button.
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .highPriorityGesture(scrubGesture())
    }

    private var segments: some View {
        HStack(spacing: Self.innerPadding * 2) {
            ForEach(AppSourceMode.allCases) { mode in
                segment(mode)
            }
        }
    }

    @ViewBuilder
    private func segment(_ mode: AppSourceMode) -> some View {
        if #available(iOS 26.0, *) {
            if mode == selection {
                segmentButton(mode)
                    .buttonStyle(.glass)
                    .glassEffectID(mode.id, in: glass)
            } else {
                segmentButton(mode)
                    .buttonStyle(.plain)
                    .glassEffectID(mode.id, in: glass)
            }
        } else {
            segmentButton(mode)
                .buttonStyle(.plain)
                .background {
                    if mode == selection {
                        Capsule()
                            .fill(.regularMaterial)
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                    }
                }
        }
    }

    private func segmentButton(_ mode: AppSourceMode) -> some View {
        Button {
            tap(mode)
        } label: {
            Text(label(mode))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.primary)     // 两段都黑字（pp 09-16）
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: Self.trackHeight - Self.innerPadding * 2)
                .contentShape(Capsule())
        }
    }

    private func tap(_ mode: AppSourceMode) {
        if mode == selection {
            if mode == .local { onLocalRetap?() }
            return
        }
        // Grok spec (DESIGN.md Motion): mode switch = soft haptic.
        Self.softTick()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            selection = mode
        }
    }

    /// Scrub by translation, not by absolute x: we do not know the band's pixel width
    /// (the toolbar proposes it), so mapping a finger position onto a slot was the
    /// wrong tool. Drag direction relative to where THIS drag started decides:
    /// 右滑 → 本机，左滑 → Remote. Threshold is small so it feels immediate; the glass
    /// morph then follows the selection = 跟手.
    private func scrubGesture() -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)   // SwiftUI default
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                let target: AppSourceMode = value.translation.width < 0 ? .remote : .local
                guard target != selection else { return }
                guard abs(value.translation.width) >= Self.slideThreshold else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    selection = target
                }
                // System selection detent on each crossing (native-segmented idiom).
                Self.detent()
            }
    }

    /// Points of horizontal travel needed to flip the segment while scrubbing.
    private static let slideThreshold: CGFloat = 24

    private static func softTick() {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare(); g.impactOccurred()
    }

    private static func detent() {
        let g = UISelectionFeedbackGenerator()
        g.prepare(); g.selectionChanged()
    }
}

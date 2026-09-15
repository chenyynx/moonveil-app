// ModeTabPicker.swift — Grok-style top capsule (U1 政策件; pp 2026-09-15 定稿:
// 坐列表顶栏标题位，两档 = [SOUL name 回退 Moonveil] / Remote，首档随本地 agent 名).
//
// Material lineage (all verified in-tree, zero invented glass):
//   • glass track  = AA ChatComposer.swift:61 / SessionChatView:210 recipe
//                    `.glassEffect(.regular.interactive(), in: .capsule)`
//                    — "brightens + follows the drag" IS the system interactive
//                    variant; we do not reimplement it.
//   • fallback     = upstream OpenMinis SearchBarSurface house style:
//                    secondarySystemBackground fill + capsule on < iOS 26.
//                    NO custom .blur (upstream scroll-perf precedent).
//   • geometry     = GrokModePicker reference (shared/fusion/refs/): 36pt,
//                    3pt inner, 14pt semibold, white selected pill,
//                    matchedGeometry slide, spring(0.28/0.82), light haptic.
//   • retap        = tapping the already-selected local segment keeps the
//                    upstream title-tap behaviour (open sync detail) — the
//                    capsule replaces the title WITHOUT losing that entry.

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

    @Namespace private var pill

    private static let trackHeight: CGFloat = 36
    private static let innerPadding: CGFloat = 3
    /// B9-LANDING: the capsule must own its width. It lives in
    /// `ToolbarItem(placement: .principal)`, where the proposal is unspecified —
    /// and a GeometryReader has NO intrinsic size, so it collapsed to ~10pt and
    /// the whole control rendered as a sliver pill (device report 2026-09-16).
    /// Fixing the track here makes every call site correct; segments split it.
    private static let trackWidth: CGFloat = 200

    private var label: (AppSourceMode) -> String {
        { $0 == .local ? localLabel : remoteLabel }
    }

    var body: some View {
        GeometryReader { geo in
            let slot = (geo.size.width - Self.innerPadding * 2) / CGFloat(AppSourceMode.allCases.count)

            HStack(spacing: 0) {
                ForEach(AppSourceMode.allCases) { mode in
                    Text(label(mode))
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(selection == mode ? Color.primary : Color.secondary)
                        .frame(width: slot, height: Self.trackHeight - Self.innerPadding * 2)
                        .contentShape(Rectangle())
                        .onTapGesture { tap(mode) }
                        .background {
                            // B11-TABSTYLE (pp 2026-09-16, Grok 实机图): the ONLY
                            // surface is the selected segment itself — a system glass
                            // capsule. The track behind it stays transparent. (The
                            // previous shape — glass track + solid white pill — is the
                            // 实色 look that was rejected.)
                            if selection == mode {
                                selectedGlassCapsule
                                    .matchedGeometryEffect(id: "modeTabSelected", in: pill)
                            }
                        }
                }
            }
            .padding(Self.innerPadding)
            .frame(width: geo.size.width, height: Self.trackHeight, alignment: .leading)
            // No track fill at all (Grok): the row is invisible until a segment is
            // selected. contentShape keeps the whole capsule area live for taps and
            // the scrub gesture, so removing the paint costs no hit target.
            .contentShape(Capsule())
            .gesture(scrubGesture(slotWidth: slot, in: geo.size.width))
        }
        .frame(width: Self.trackWidth, height: Self.trackHeight)
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

    /// Selection surface: iOS 26+ = system glass, interactive variant (brightens and
    /// follows the drag — the effect pp asked for). Below 26 = `.regularMaterial`,
    /// a system material, NOT a hand-rolled blur (U1 禁自造 blur).
    @ViewBuilder
    private var selectedGlassCapsule: some View {
        if #available(iOS 26.0, *) {
            Capsule().glassEffect(.regular.interactive(), in: .capsule)
        } else {
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        }
    }

    /// Scrub: dragging past a segment boundary moves the selection live.
    private func scrubGesture(slotWidth: CGFloat, in totalWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                let inner = max(0, min(value.location.x - Self.innerPadding, totalWidth - Self.innerPadding * 2))
                let idx = min(AppSourceMode.allCases.count - 1, Int(inner / slotWidth))
                let mode = AppSourceMode.allCases[idx]
                guard mode != selection else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    selection = mode
                }
                // Scrub boundary crossings = system selection detents (the
                // native-segmented idiom Grok's control rides on).
                Self.detent()
            }
    }

    private static func softTick() {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare(); g.impactOccurred()
    }

    private static func detent() {
        let g = UISelectionFeedbackGenerator()
        g.prepare(); g.selectionChanged()
    }
}

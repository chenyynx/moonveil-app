// ModeTabPicker.swift — Grok 顶部胶囊（U1 政策件；pp 2026-09-15 定稿：坐列表顶栏标题位，
// 两档 = [SOUL name 回退 Moonveil] / Remote，首档名与上游标题同源）.
//
// B15-PILL (pp 2026-09-16 11:4x，看预览逐条确认后定稿：「对 就是这样」)：
//   ① **无轨道**。以前是「玻璃轨道 + 白实色药丸」两层，现在拆成单层。
//   ② 玻璃贴在**选中段自己的形状**上：`Capsule().glassEffect(.regular.interactive(), in: .capsule)`。
//      不是 `.buttonStyle(.glass)` —— 那是按钮样式，浅色态自带灰底和自己的内边距，
//      ac9b9d0 那颗发灰发胖就是用它（判例：两个 API 不是一回事，不能互为证据）。
//      也不是 `.ultraThinMaterial`（B14e 用它渲成灰块，同样废）。
//   ③ 拖动**跟手**，且胶囊宽度在两档之间**插值形变**（"Moonveil" 比 "Remote" 宽 → 中间被拉长）。
//      提亮 + 放大由 interactive 变体自带，不自己加 scale。
//   ④ 松手**就近吸附**：胶囊中心离哪档近就吸回哪档（`round`），不是"过 28% 阈值才换档"。
//   ⑤ 贴字定宽：每段 = 自身文字宽 + 12pt 内边距，不再平分轨道。
//
// 字色两段都黑（pp 09-16 明示）；字号 15；选中 semibold / 未选 regular。
// iOS < 26 没有 glassEffect：降级 secondarySystemBackground 实色胶囊 + 1pt 细描边
// （upstream SearchBarSurface 家规：不自造模糊效果，降级只用系统实色材质）。
//
// 行为面零删减（完整性铁律）：点档切换 + soft 触感、越界 detent 触感、点已选本机段仍开
// sync 迁移详情 (onLocalRetap)、整条顶栏宽热区 + highPriorityGesture（B13 判例：普通
// .gesture 会被按钮吞掉 = 真机失灵）。
//
// 本文件仍是"住在页面自己的顶栏里"。固定栏上提（齿轮 + 胶囊进外壳）与两页平移是下一批，
// 分开走：一次只动一层，坏了能立刻知道是哪一层。

import SwiftUI
import UIKit

/// The app's two source modes (D4: the single fork point).
enum AppSourceMode: String, CaseIterable, Identifiable {
    case local, remote
    var id: String { rawValue }
    /// Position along the capsule row. Never a force-unwrap: fall back to 0.
    var slot: CGFloat {
        CGFloat(Self.allCases.firstIndex(of: self) ?? 0)
    }
}

struct ModeTabPicker: View {
    @Binding var selection: AppSourceMode
    /// First segment label — SAME source as the upstream sidebar title
    /// (SOUL.md name, fallback "Moonveil"). Never a parallel naming channel.
    var localLabel: String
    var remoteLabel: String = "Remote"
    /// Tap on the already-selected local segment (upstream title-tap action).
    var onLocalRetap: (() -> Void)?

    /// Live drag position in slot units (0 = parked on `selection`). @State rather than
    /// @GestureState because the pill must ANIMATE into its snapped home, and the
    /// GestureState auto-reset does not join our transaction. `onChange(of: selection)`
    /// below is the safety net if a pan is stolen and onEnded never arrives.
    @State private var progress: CGFloat = 0
    @State private var isDragging = false

    // ── Geometry (measured off pp's Grok frames: pill hugs the label, no track) ─────
    private static let pillHeight: CGFloat = 26
    private static let labelHPadding: CGFloat = 12
    private static let segmentSpacing: CGFloat = 2
    private static let labelSize: CGFloat = 15
    private static let rowHeight: CGFloat = 36

    // ── Motion ────────────────────────────────────────────────────────────────────
    private static let settle = Animation.spring(response: 0.36, dampingFraction: 0.78)
    /// Travel (pt) before a scrub counts as a drag at all — SwiftUI's own default is 10.
    private static let dragSlop: CGFloat = 10

    private var label: (AppSourceMode) -> String {
        { $0 == .local ? localLabel : remoteLabel }
    }

    private func slotWidth(_ mode: AppSourceMode) -> CGFloat {
        ceil(Self.textWidth(label(mode))) + Self.labelHPadding * 2
    }

    /// Left edge of each segment inside the row (the row is centered by the toolbar).
    private func edge(_ mode: AppSourceMode) -> CGFloat {
        var x: CGFloat = 0
        for m in AppSourceMode.allCases {
            if m == mode { return x }
            x += slotWidth(m) + Self.segmentSpacing
        }
        return x
    }

    private var rowWidth: CGFloat {
        AppSourceMode.allCases.map { slotWidth($0) }.reduce(0, +)
            + Self.segmentSpacing * CGFloat(AppSourceMode.allCases.count - 1)
    }

    private static func textWidth(_ string: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: labelSize, weight: .semibold)   // widest weight
        return (string as NSString).size(withAttributes: [.font: font]).width
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // ORDER IS A SPEC: the glass goes in FIRST (behind), the labels on top.
            // B14e had this inverted and the pill painted over the selected label —
            // on device that read as an empty grey capsule (CI was green; only eyes
            // catch it).
            pill
            HStack(spacing: Self.segmentSpacing) {
                ForEach(AppSourceMode.allCases) { mode in
                    segment(mode)
                        .frame(width: slotWidth(mode), height: Self.rowHeight)
                }
            }
        }
        .frame(width: rowWidth, height: Self.rowHeight)
        // Hit band stays WIDER than the visual row (fills the top bar) and stays a
        // highPriorityGesture: a plain `.gesture` here was eaten by the segment buttons
        // and read as 失灵 on device (B13).
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .highPriorityGesture(scrubGesture())
        .onChange(of: selection) { _ in
            // Safety net for a stolen pan that never delivered onEnded.
            progress = 0
            isDragging = false
        }
    }

    private func segment(_ mode: AppSourceMode) -> some View {
        Button {
            tap(mode)
        } label: {
            Text(label(mode))
                .font(.system(size: Self.labelSize,
                              weight: mode == selection ? .semibold : .regular))
                .foregroundStyle(Color.primary)     // 两段都黑字（pp 09-16）
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(SegmentButtonStyle())
    }

    /// The single glass layer: position AND width interpolate with the finger, so a
    /// wider label stretches it on the way over — that is the 形变 pp confirmed.
    @ViewBuilder
    private var pill: some View {
        // No GeometryReader: every number here is computed from the labels, so the
        // glass cannot be laid out greedily and cannot flash on the first frame.
        let f = interpolatedRect()
        Group {
            if #available(iOS 26.0, *) {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: .capsule)
            } else {
                Capsule()
                    .fill(Color(UIColor.secondarySystemBackground))
                    .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
            }
        }
        .frame(width: f.width, height: Self.pillHeight)
        .offset(x: f.minX, y: (Self.rowHeight - Self.pillHeight) / 2)
        .allowsHitTesting(false)
    }

    /// Pill rect at `selection.slot + progress`, clamped to the row and eased by the
    /// edge resistance so an over-drag resists instead of flying away.
    private func interpolatedRect() -> CGRect {
        let index = min(max(selection.slot + dampedProgress, 0),
                        CGFloat(AppSourceMode.allCases.count - 1))
        let lower = Int(index.rounded(.down))
        let upper = min(lower + 1, AppSourceMode.allCases.count - 1)
        let a = rect(of: AppSourceMode.allCases[lower])
        let b = rect(of: AppSourceMode.allCases[upper])
        let t = index - CGFloat(lower)
        return CGRect(x: a.minX + (b.minX - a.minX) * t,
                      y: 0,
                      width: a.width + (b.width - a.width) * t,
                      height: Self.pillHeight)
    }

    private func rect(of mode: AppSourceMode) -> CGRect {
        CGRect(x: edge(mode), y: 0, width: slotWidth(mode), height: Self.pillHeight)
    }

    private var dampedProgress: CGFloat {
        guard isDragging else { return 0 }
        let index = selection.slot + progress
        if index < 0 || index > CGFloat(AppSourceMode.allCases.count - 1) {
            return progress * Self.edgeResistance
        }
        return progress
    }

    /// Distance the finger covers to move one segment (centre to centre).
    private var slotStride: CGFloat {
        let a = edge(.local) + slotWidth(.local) / 2
        let b = edge(.remote) + slotWidth(.remote) / 2
        return max(abs(b - a), 1)
    }

    private static let edgeResistance: CGFloat = 0.32

    private func tap(_ mode: AppSourceMode) {
        if mode == selection {
            if mode == .local { onLocalRetap?() }
            return
        }
        // Grok spec (DESIGN.md Motion): mode switch = soft haptic.
        Self.softTick()
        withAnimation(Self.settle) {
            selection = mode
            progress = 0
        }
    }

    /// Scrub: follow the finger, then SNAP TO NEAREST on release (pp ④) — no 28% gate.
    private func scrubGesture() -> some Gesture {
        DragGesture(minimumDistance: Self.dragSlop, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.35 else { return }
                isDragging = true
                progress = value.translation.width / slotStride
                let target = nearestMode
                if target != detented {
                    detented = target
                    if target != selection { Self.detent() }
                }
            }
            .onEnded { _ in
                let target = nearestMode
                detented = nil
                withAnimation(Self.settle) {
                    isDragging = false
                    progress = 0
                    if target != selection {
                        selection = target
                        Self.softTick()
                    }
                }
            }
    }

    /// 就近吸附：把当前（含拖动）位置四舍五入到最近的一档。
    private var nearestMode: AppSourceMode {
        let index = min(max(selection.slot + dampedProgress, 0),
                        CGFloat(AppSourceMode.allCases.count - 1))
        return AppSourceMode.allCases[Int(index.rounded())]
    }

    /// Which segment already got its detent during THIS drag (fires once per crossing).
    @State private var detented: AppSourceMode?

    static func softTick() {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare(); g.impactOccurred()
    }

    static func detent() {
        let g = UISelectionFeedbackGenerator()
        g.prepare(); g.selectionChanged()
    }
}

/// Press feedback for the labels. The glass pill itself brightens and scales through
/// its `interactive` variant; the text still needs a hint that it is the thing under
/// the finger, and Grok's own pressed scale is 0.92.
private struct SegmentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

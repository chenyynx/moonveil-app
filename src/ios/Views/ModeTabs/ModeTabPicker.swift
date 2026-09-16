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
// 行为面（完整性铁律）：点档切换 + soft 触感、点已选本机段仍开 sync 迁移详情
// (onLocalRetap)、整条顶栏宽热区 + highPriorityGesture（B13 判例：普通 .gesture 会被
// 按钮吞掉 = 真机失灵）、越界阻尼（视觉，非触感）。
// pp 明示弃用（2026-09-16，铁律的唯一出口，留字据）：**拖动吸附路径的触觉反馈**全部去掉
// —— 中途越档的 selection detent 触感与松手的 tick 都不要了，吸附逻辑回到历史第一版
// （跟手 + 松手就近吸附，静默）。点按路径的 soft 触感不在其列，保留。
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
    /// True from the moment a scrub starts until 0.15s after the finger lifts (claudio's
    /// exact window) so the trailing tap of a drag cannot switch a second time.
    @State private var didScrub = false
    /// B16: direction is decided ONCE per gesture and then latched. The old code
    /// re-tested "more horizontal than vertical" on every event, so any mid-drag
    /// vertical drift made the guard bail out, `progress` stopped updating and the pill
    /// froze under the finger and then lurched — that is 「卡卡的」. Once claimed, the
    /// gesture is ours until the finger lifts.
    @State private var directionLocked = false
    /// Set when the first real travel was clearly vertical: the list owns this gesture,
    /// and we stay out of it until the finger lifts.
    @State private var directionRejected = false
    /// True while a scrub gesture is actually in flight. @GestureState auto-resets when
    /// the gesture ends OR IS CANCELLED — the @State latches above do not, which is
    /// exactly how one cancelled drag could leave `directionRejected` stuck on and make
    /// the pill undraggable until the next selection change (pp:「拖都拖不了了大哥」).
    @GestureState private var gestureInFlight = false
    /// Namespace for the selected segment's morphing glass (AA: `@Namespace private var glass`).
    @Namespace private var glassNS

    // ── Geometry — calibrated off pp's Grok screenshot (photo_33EAEE5C, 1179px@3x) ──
    // Vertical scan through the pill's centre column: white disc runs 67.7pt → 99.0pt,
    // i.e. height ≈ 30pt. Horizontal scan through its centre row: 103.7 → 155.0pt =
    // 51.3pt wide around a 25.0pt-wide 提问 ink box → side padding ≈ 13pt.
    // Ink heights (提问 12.3pt, Imagine 13.0pt incl. descender) put the label at 14pt,
    // so the pill is deliberately tall relative to the text — that is what mine lacked
    // (26pt pill / 15pt text read as 「有点窄」).
    private static let pillHeight: CGFloat = 30
    private static let labelHPadding: CGFloat = 13
    private static let segmentSpacing: CGFloat = 2
    private static let labelSize: CGFloat = 14
    /// Both segments carry the SAME colour and the SAME weight (pp 2026-09-16:「两段都
    /// 黑」then「未选中也要一样的粗细」) — the glass pill alone marks the selection.
    /// Grok differentiates by colour (选中黑/未选中灰); we deliberately do not, so if a
    /// future pass wants the cue back, this one constant is the only place to split.
    private static let labelWeight: Font.Weight = .semibold
    private static let rowHeight: CGFloat = 40

    // ── Motion ────────────────────────────────────────────────────────────────────
    /// internal on purpose: the fixed bar's gear wears the SAME emphasis and the SAME
    /// spring, so the numbers live in one place (B16).
    static let settle = Animation.spring(response: 0.36, dampingFraction: 0.78)
    /// 12pt = AA's container spacing (ChatComposer.swift:21): glasses closer than this
    /// merge like liquid.
    private static let glassSpacing: CGFloat = 12
    /// Travel (pt) before a scrub counts as a drag at all. Was 10 (SwiftUI's default),
    /// and that dead zone is half of 「不跟手」: the finger moves, nothing moves, then it
    /// jumps in. 3pt is enough to distinguish a scrub from a tap.
    private static let dragSlop: CGFloat = 3
    /// Same source: active state is `scale(0.97)`, not the 0.92 I invented.
    /// internal, not private: `private` would only be visible inside THIS type, and
    /// SegmentButtonStyle / the fixed bar's gear are separate types in this file — CI
    /// caught exactly that ('pressScale' is inaccessible, run 35059803697).
    static let pressScale: CGFloat = 0.97
    /// pp's own tuning (2026-09-16, verbatim): horizontal beats vertical by 1.35×.
    private static let horizontalRatio: CGFloat = 1.35
    /// Travel needed before we are allowed to judge direction at all (pt). Small enough
    /// that the verdict happens almost immediately, so an arcing drag still reads as
    /// horizontal — the ratio only has to hold for these first few points.
    private static let directionDecideDistance: CGFloat = 6
    /// Clearly-vertical threshold: |dy| this many times bigger than |dx| hands the
    /// gesture to the list.
    private static let verticalRatio: CGFloat = 1.5
    /// Ambiguous diagonal is allowed to stay undecided this far; past it we simply take
    /// the dominant axis instead of refusing (that refusal was 「拖都拖不了」).
    private static let directionForceDistance: CGFloat = 20

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
        rowContent
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        // highPriorityGesture: a plain `.gesture` here was eaten by the segment buttons
        // and read as 失灵 on device (B13).
        .highPriorityGesture(scrubGesture())
        .onChange(of: selection) { _ in
            // Safety net for a stolen pan that never delivered onEnded.
            progress = 0
            isDragging = false
            directionLocked = false
            directionRejected = false
        }
        .onChange(of: gestureInFlight) { inFlight in
            // Fires on end AND on cancellation. Without this a single cancelled drag
            // leaves the latches stuck and the pill refuses every later drag.
            if !inFlight {
                directionLocked = false
                directionRejected = false
                isDragging = false
                progress = 0
            }
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: Self.glassSpacing) { bar }
        } else {
            bar
        }
    }

    private var bar: some View {
        ZStack(alignment: .topLeading) {
            // Ghost while scrubbing: a plain translucent tint, deliberately NOT glass.
            // A glass piece inside GlassEffectContainer composites ABOVE sibling views —
            // a glass pill behind the labels hid the selected label's text on device
            // (「看不到字了」, build 114541b). A plain tint renders under the labels and
            // is cheap enough to track every finger event 1:1, which is the whole point:
            // the real glass lives on the selected segment, stays static during a drag,
            // and only the SYSTEM morphs it to the next segment on release.
            if isDragging {
                let r = interpolatedRect()
                Capsule()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: r.width, height: Self.pillHeight)
                    .offset(x: r.minX, y: (Self.rowHeight - Self.pillHeight) / 2)
                    .allowsHitTesting(false)
                    .animation(Self.settle, value: isDragging)
            }
            HStack(spacing: Self.segmentSpacing) {
                ForEach(AppSourceMode.allCases) { mode in
                    segment(mode)
                }
            }
        }
        .frame(width: rowWidth, height: Self.rowHeight)
    }

    private func segment(_ mode: AppSourceMode) -> some View {
        let selected = mode == selection
        return Button {
            tap(mode)
        } label: {
            Text(label(mode))
                .font(.system(size: Self.labelSize, weight: Self.labelWeight))
                .foregroundStyle(Color.primary)     // 两段都黑字（pp 09-16）
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                // glass wraps THIS 30pt band, not the whole 40pt row: applying it to the
                // row-sized segment made the capsule 10pt too tall and it read as a fat
                // white sticker (pp: 「顶部tab又变这样了」). Same 30pt the calibration
                // measured off Grok — the pill's height must not grow just because the
                // system draws it now.
                .frame(height: Self.pillHeight)
                .contentShape(Rectangle())
                .modifier(TabGlass(isSelected: selected, namespace: glassNS))
        }
        .buttonStyle(SegmentButtonStyle())
        // Tap area stays the full row height; only the material hugs the label.
        .frame(width: slotWidth(mode), height: Self.rowHeight)
    }

    /// Ghost rect while scrubbing: `selection.slot + progress`, with the overhang past
    /// the two slots RESISTED by edgeResistance but never frozen. The old version
    /// clamped the whole index to 0...1, so once the finger passed one slot the pill
    /// stopped dead, and on the way back there was a dead zone before it moved again —
    /// that is the remaining 「还是卡」 pp felt. Resist, don't freeze.
    private func interpolatedRect() -> CGRect {
        let last = CGFloat(AppSourceMode.allCases.count - 1)
        let raw = selection.slot + progress
        let index: CGFloat
        if raw < 0 {
            index = -(-raw * Self.edgeResistance)
        } else if raw > last {
            index = last + (raw - last) * Self.edgeResistance
        } else {
            index = raw
        }
        let clamped = min(max(index, 0), last)
        let lower = Int(clamped.rounded(.down))
        let upper = min(lower + 1, AppSourceMode.allCases.count - 1)
        let a = rect(of: AppSourceMode.allCases[lower])
        let b = rect(of: AppSourceMode.allCases[upper])
        let t = clamped - CGFloat(lower)
        return CGRect(x: a.minX + (b.minX - a.minX) * t,
                      y: 0,
                      width: a.width + (b.width - a.width) * t,
                      height: Self.pillHeight)
    }

    private func rect(of mode: AppSourceMode) -> CGRect {
        CGRect(x: edge(mode), y: 0, width: slotWidth(mode), height: Self.pillHeight)
    }

    /// Distance the finger covers to move one segment (centre to centre).
    private var slotStride: CGFloat {
        let a = edge(.local) + slotWidth(.local) / 2
        let b = edge(.remote) + slotWidth(.remote) / 2
        return max(abs(b - a), 1)
    }

    private static let edgeResistance: CGFloat = 0.32

    private func tap(_ mode: AppSourceMode) {
        // claudio's DraggableFAB pattern (ContentView.swift:6743-6793): a tap that lands
        // right after a scrub is the tail of that drag, not an intent to switch again.
        // Without this guard a drag that ends over a segment can also fire that segment's
        // Button — the double-step pp described as 吸附做的有问题.
        if didScrub { return }
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
            .updating($gestureInFlight) { _, state, _ in state = true }
            .onChanged { value in
                if !directionLocked {
                    // A rejected gesture stays rejected — otherwise a thumb that arcs
                    // back sideways mid-drag would suddenly re-claim and the pill would
                    // lurch after the list already started scrolling.
                    if directionRejected { return }
                    let dx = abs(value.translation.width), dy = abs(value.translation.height)
                    guard max(dx, dy) > Self.directionDecideDistance else { return }
                    if dx > dy * Self.horizontalRatio {
                        // Clearly sideways → ours.
                        directionLocked = true
                    } else if dy > dx * Self.verticalRatio {
                        // Clearly vertical → the list owns it, for good.
                        directionRejected = true
                        return
                    } else if max(dx, dy) > Self.directionForceDistance {
                        // Diagonal and past the point of no return: take the dominant
                        // axis. Rejecting on the FIRST ambiguous sample is what made the
                        // pill feel undraggable — real thumbs almost never start at a
                        // perfect angle.
                        if dx >= dy { directionLocked = true } else { directionRejected = true; return }
                    } else {
                        return
                    }
                }
                // Emphasis starts the instant we claim the gesture — not after the
                // finger has travelled further.
                isDragging = true
                didScrub = true
                progress = value.translation.width / slotStride
            }
            .onEnded { _ in
                // Snap logic back to the first version: follow the finger, and on release
                // settle onto whichever segment is nearest. NO haptics on this path —
                // pp 2026-09-16「这个拖动tab吸附不用做触屏反馈」. A TAP still ticks
                // (Grok DESIGN.md: soft haptic on switch); the scrub stays silent.
                let target = nearestMode
                directionLocked = false
                directionRejected = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { didScrub = false }
                withAnimation(Self.settle) {
                    isDragging = false
                    progress = 0
                    if target != selection { selection = target }
                }
            }
    }

    /// 就近吸附：把当前（含拖动）位置四舍五入到最近的一档。取 raw 位置再钳制，
    /// 而不是钳制后再取整 —— 越界阻尼不影响吸附判定。
    private var nearestMode: AppSourceMode {
        let last = CGFloat(AppSourceMode.allCases.count - 1)
        let raw = selection.slot + progress
        let clamped = min(max(raw, 0), last)
        return AppSourceMode.allCases[Int(clamped.rounded())]
    }

    static func softTick() {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare(); g.impactOccurred()
    }

}

/// Press feedback for the labels. The glass pill itself brightens and scales through
/// its `interactive` variant; the text still needs a hint that it is the thing under
/// the finger, and Grok's own pressed scale is 0.92.
/// Plain press feedback for a segment (the system `.glass` style used upstream brought
/// its own scale+dim; we draw the pill, so we bring the feedback). Also reports
/// `isPressed` outward so the pill can light up while a segment is held.
private struct SegmentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? ModeTabPicker.pressScale : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The SELECTED segment wears the system glass on ITSELF — the text is the glass's own
/// content, so it always shows through (the sibling-pill design covered it). Both
/// segments share ONE `glassEffectID`, so when the selection changes the system morphs
/// the glass from the old segment to the new one: the 拉长延伸, drawn by the system
/// instead of faked. `.interactive()` works here because the glass is on a real control.
private struct TabGlass: ViewModifier {
    let isSelected: Bool
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if isSelected {
                content
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .glassEffectID("modePill", in: namespace)
            } else {
                content
            }
        } else {
            if isSelected {
                content
                    .background(Capsule().fill(Color(UIColor.secondarySystemBackground)))
                    .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
            } else {
                content
            }
        }
    }
}

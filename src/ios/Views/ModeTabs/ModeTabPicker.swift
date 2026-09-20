// ModeTabPicker.swift — Grok 顶部胶囊（U1 政策件；pp 2026-09-15 定稿：坐列表顶栏标题位，
// 两档 = [SOUL name 回退 Moonveil] / Remote，首档名与上游标题同源）.
//
// B15-PILL (pp 2026-09-16 11:4x，看预览逐条确认后定稿：「对 就是这样」)：
//   ① **无轨道**。以前是「玻璃轨道 + 白实色药丸」两层，现在拆成单层。
//   ② 玻璃 = **独立的胶囊层**（B16-DRAG-GLASS，pp 2026-09-17「拖动的那个做玻璃效果发光
//      放大」）：`Capsule().glassEffect(.regular, in: .capsule)` 挂在自驱位置的空宿主上；
//      文字层是 GlassEffectContainer 外的兄弟视图、永远画在玻璃之上 —— 容器只把玻璃合成
//      在**内部**兄弟之上（114541b 盖字事故），够不着容器外的文字。不是 `.buttonStyle(.glass)`
//      （浅色态自带灰底内边距，ac9b9d0 判例）、不是 `.ultraThinMaterial`（B14e 灰块）。
//   ③ 拖动 = 玻璃本体跟手（宽度两档间插值），发光+放大自己画（`.interactive()` 只在真
//      控件按压态生效，装饰层用不了——B16-PILL-FEEL 判例）；松手 spring 吸附。单颗玻璃
//      自驱位置后，系统 glassEffectID 形变不再需要（@Namespace 已随之移除）。
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
    /// Light/dark for the drag sheen (the glass itself adapts; the extra glow is ours).
    @Environment(\.colorScheme) private var colorScheme

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

    // The pill is ONE glass capsule whose position WE drive (selection.slot + progress,
    // edge-resisted while scrubbing, springing home on release). The labels live in a
    // SIBLING layer AFTER the container in the ZStack, so they always composite ABOVE
    // the glass — the container lifts its internal glass over its internal siblings
    // (114541b), but it cannot touch views OUTSIDE it. This is what lets the drag
    // follow the finger 1:1 with real glass instead of the old tint ghost.
    @ViewBuilder
    private var rowContent: some View {
        if #available(iOS 26.0, *) {
            ZStack(alignment: .topLeading) {
                GlassEffectContainer(spacing: Self.glassSpacing) { pillLayer }
                labelRow
            }
            .frame(width: rowWidth, height: Self.rowHeight)
        } else {
            ZStack(alignment: .topLeading) {
                legacyPillLayer
                labelRow
            }
            .frame(width: rowWidth, height: Self.rowHeight)
        }
    }

    private var labelRow: some View {
        HStack(spacing: Self.segmentSpacing) {
            ForEach(AppSourceMode.allCases) { mode in
                segment(mode)
            }
        }
    }

    /// The real glass, following the finger. `.regular` not `.interactive()`: that
    /// variant only reacts to a REAL control's pressed state (B16-PILL-FEEL), and this
    /// layer is decoration — the glow and scale are ours. allowsHitTesting stays off so
    /// the buttons underneath keep every tap.
    /// Availability lives HERE, not at call sites: `if #available` around the caller
    /// does NOT protect APIs used inside the callee body (lexically scoped check).
    @available(iOS 26.0, *)
    @ViewBuilder
    private var pillLayer: some View {
        let r = interpolatedRect()
        // [B16-PILL-WHITE] pp 2026-09-17「顶部胶囊还是灰色啊」的双重修复:
        // ① content 从裸 `Capsule()` 换成 `Color.clear` —— 裸 Shape 作为视图会吃默认
        //    前景填充,半透明玻璃下面垫一层默认色 = 玻璃被压暗成「实色灰」;
        //    显式透明后玻璃材质才是原本的亮度。
        // ② 浅色加 `.tint(.white)` 把玻璃推向白(仓内先例:ContentView:4321
        //    `fabCircleSurface` 的 `Glass.regular.tint($0)`);深色不 tint,防止泛白刺眼。
        Color.clear
            .frame(width: r.width, height: Self.pillHeight)
            .glassEffect(colorScheme == .light ? .regular.tint(.white) : .regular, in: .capsule)
            .overlay(dragSheen)
            .scaleEffect(isDragging ? Self.dragScale : 1)
            .offset(x: r.minX, y: (Self.rowHeight - Self.pillHeight) / 2)
            .allowsHitTesting(false)
            .animation(Self.settle, value: isDragging)
            // [TAB-SWAP-FLASH 2026-09-21] 胶囊滑动动画显式化：tab 内容层改为瞬切
            // （RootModeTabsView 对 opacity 加 .animation(nil, value: mode) 断开
            // crossfade 叠影）后，滑动仍由这条显式绑定保证（scrub 跟手不受影响：
            // 跟手由 progress 驱动，不在绑定值里；吸附/点切由 selection 驱动 → settle）。
            .animation(Self.settle, value: selection)
    }

    /// <26 fallback: solid capsule (upstream SearchBarSurface 家规 — no homemade blur).
    @ViewBuilder
    private var legacyPillLayer: some View {
        let r = interpolatedRect()
        Capsule()
            .fill(Color(UIColor.secondarySystemBackground))
            .frame(width: r.width, height: Self.pillHeight)
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .overlay(dragSheen)
            .scaleEffect(isDragging ? Self.dragScale : 1)
            .offset(x: r.minX, y: (Self.rowHeight - Self.pillHeight) / 2)
            .allowsHitTesting(false)
            .animation(Self.settle, value: isDragging)
            // [TAB-SWAP-FLASH 2026-09-21] 胶囊滑动动画显式化：tab 内容层改为瞬切
            // （RootModeTabsView 对 opacity 加 .animation(nil, value: mode) 断开
            // crossfade 叠影）后，滑动仍由这条显式绑定保证（scrub 跟手不受影响：
            // 跟手由 progress 驱动，不在绑定值里；吸附/点切由 selection 驱动 → settle）。
            .animation(Self.settle, value: selection)
    }

    @ViewBuilder
    private var dragSheen: some View {
        if isDragging {
            Capsule()
                .fill(Color.white)
                .opacity(colorScheme == .light ? Self.sheenLight : Self.sheenDark)
                .allowsHitTesting(false)
        }
    }

    private func segment(_ mode: AppSourceMode) -> some View {
        Button {
            tap(mode)
        } label: {
            Text(label(mode))
                .font(.system(size: Self.labelSize, weight: Self.labelWeight))
                .foregroundStyle(Color.primary)     // 两段都黑字（pp 09-16）
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                // The 30pt band keeps button geometry identical to the era when glass
                // lived here; pillLayer interpolates over the same rects.
                .frame(height: Self.pillHeight)
                .contentShape(Rectangle())
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
    /// Drag emphasis (pp 2026-09-17:「拖动的那个做玻璃效果发光放大」— supersedes the
    /// 2026-09-16「拖动吸附不用触感」which only ever covered HAPTICS). The glass pill
    /// scales up and gains a white sheen while following the finger.
    static let dragScale: CGFloat = 1.06
    /// Sheen strength, light/dark. The glass already carries its own specular; this is
    /// the extra 发光 on top, deliberately conservative (tune on device).
    private static let sheenLight: CGFloat = 0.22
    private static let sheenDark: CGFloat = 0.14

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


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
    /// True while a segment is held down — the pill lights up for a tap too, not only a
    /// scrub (otherwise a tap reads as dead until the switch lands).
    @State private var pressedMode: AppSourceMode?
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
    }

    @ViewBuilder
    private var rowContent: some View {
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
    }

    private func segment(_ mode: AppSourceMode) -> some View {
        Button {
            tap(mode)
        } label: {
            Text(label(mode))
                .font(.system(size: Self.labelSize, weight: Self.labelWeight))
                .foregroundStyle(Color.primary)     // 两段都黑字（pp 09-16）
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(SegmentButtonStyle { down in
            // The pill lights up for a held-down segment too, not only for a scrub —
            // otherwise a tap looks dead until the switch lands. The style reports its
            // own `isPressed` back here because ButtonStyle cannot otherwise talk to us.
            // Async write: `isPressed` can flip inside a SwiftUI transaction, and
            // mutating state there is the "Publishing changes from within view updates"
            // warning we already hit twice in this module.
            DispatchQueue.main.async {
                pressedMode = down ? mode : (pressedMode == mode ? nil : pressedMode)
            }
        })
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
        // 提亮和放大是**画出来的**，不是 `.interactive()` 给的：那个变体只在"真控件"的
        // 按压态上生效，而这一层是装饰层、还 `allowsHitTesting(false)`，所以它永远不亮
        // （上游 AA 的同类装饰层用的就是不带 interactive 的 `.regular`，同一个道理）。
        // 手指按住/拖动 → 轻微长大 + 一层白色高光淡入，走同一条 spring。
        // 不加投影：iOS 26 的玻璃自己带边缘与折射，再套一层 drop shadow 就变成贴在
        // 白底上的实心贴纸，不是玻璃了（pp 2026-09-16「系统原生的没有阴影」）。
        // 我原来那 0.06/r3/y1 是照 Grok 的**网页** CSS token（box-shadow: 0 1px 3px
        // rgba(0,0,0,.06)）搬的 —— 网页 token 不是 iOS 材质规格，同族第三次踩（前两次：
        // B15-CODE 字体、B16-PILL-SIZE 盘高）。
        .scaleEffect(emphasised ? Self.dragScale : 1)
        .overlay {
            Capsule()
                .fill(Color.white.opacity(emphasised ? (colorScheme == .dark ? Self.sheenDark : Self.sheenLight) : 0))
        }
        // The snap spring is bound to `selection.slot` EXPLICITLY. Relying on the
        // `withAnimation` around the assignment was not enough once the emphasis
        // modifiers went on — the pill teleported instead of settling (pp 2026-09-16
        // 「弹簧效果也没了」). During a scrub `slot` does not change, so the pill still
        // tracks the finger 1:1 with no animation lag.
        .animation(Self.settle, value: selection.slot)
        .animation(Self.settle, value: emphasised)
        .allowsHitTesting(false)
    }

    /// Either input lights the pill up: the finger scrubbing it, or a held-down segment.
    private var emphasised: Bool { isDragging || pressedMode != nil }

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
    /// Emphasis while the finger owns the pill (dragging) or is down on a segment.
    static let dragScale: CGFloat = 1.06
    static let sheenLight: Double = 0.26
    static let sheenDark: Double = 0.16

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
            .onChanged { value in
                if !directionLocked {
                    // A rejected gesture stays rejected — otherwise a thumb that arcs
                    // back sideways mid-drag would suddenly re-claim and the pill would
                    // lurch after the list already started scrolling.
                    if directionRejected { return }
                    let dx = abs(value.translation.width), dy = abs(value.translation.height)
                    // 🔴 Judge the direction ONCE, at the first meaningful travel, then
                    // stick with it. The old code re-tested the ratio on EVERY event, so
                    // a thumb dragging in a natural arc (dx 60 / dy 50 by the end) never
                    // passed 1.35 → no follow AND no emphasis. That is the
                    // 「时而能发光放大时而不能」 pp saw: it depended on the arc of the
                    // finger, not on the control.
                    guard max(dx, dy) > Self.directionDecideDistance else { return }
                    guard dx > dy * Self.horizontalRatio else {
                        directionRejected = true
                        return
                    }
                    directionLocked = true
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

    /// 就近吸附：把当前（含拖动）位置四舍五入到最近的一档。
    private var nearestMode: AppSourceMode {
        let index = min(max(selection.slot + dampedProgress, 0),
                        CGFloat(AppSourceMode.allCases.count - 1))
        return AppSourceMode.allCases[Int(index.rounded())]
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
    let onPressChange: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? ModeTabPicker.pressScale : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { down in onPressChange(down) }
    }
}

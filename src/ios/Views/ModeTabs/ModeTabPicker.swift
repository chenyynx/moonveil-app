// ModeTabPicker.swift — Grok 顶部胶囊（U1 政策件；pp 2026-09-15 定稿：坐列表顶栏标题位，
// 两档 = [SOUL name 回退 Moonveil] / Remote，首档名与上游标题同源）.
//
// B14b (pp 2026-09-16「用这个」+ 贴参考件): 表面 = 他给的那份，逐条照抄——
//   • 胶囊 = Capsule().fill(.ultraThinMaterial) + 0.8pt 白高光描边 + shadow(黑0.12, r8, y3)
//   • 轨道 = Capsule().fill(.thinMaterial).opacity(0.6)，内容内缩 4pt，整行 44pt
//   • 等分槽位 slot = 最宽标签 + 14*2；胶囊宽 = slot - 6；x = (index + progress)·slot + 3
//   • 字号 15，选中 semibold / 未选 regular
// 一处没照抄：未选文字他写 .secondary，他上午明说「tab 有没有选择都是黑色字体」→ 留 .primary。
//
// B14c (pp 2026-09-16「我要的就是平移」): 胶囊不再住在某一页的 toolbar 里，改由
// RootModeTabsView 画一条固定顶栏，两页在它下面横向滑。所以这个视图变成纯显示 + 点击：
//   • `progress` 由外壳喂（已含边缘阻尼），本视图不再自持拖动状态
//   • 拖动/落位/触感全部在外壳的 pagerDrag 里，胶囊与页面共用同一个进度 → 天然同步
//   • 宽度自供（ToolbarItem(.principal) 里 GeometryReader 会塌成 ~10pt 那条老坑仍在，
//     现在外壳给的是全屏宽，仍按标签算定宽，不撑满）
//
// 行为面零删减（完整性铁律）：点档切换 + soft 触感、越界 detent、点已选本机段仍开
// sync 迁移详情（onLocalRetap 经 RootTabRouter.requestedToolSheet 回传上游）。

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
    /// Live pager progress in slots, already damped by the shell. 0 = parked.
    var progress: CGFloat = 0

    // ── Geometry (the reference file's numbers) ─────────────────────────────────────
    static let rowHeight: CGFloat = 44
    static let innerPadding: CGFloat = 4
    static let pillInset: CGFloat = 3
    static let labelSize: CGFloat = 15
    static let labelHPadding: CGFloat = 14

    private var label: (AppSourceMode) -> String {
        { $0 == .local ? localLabel : remoteLabel }
    }

    /// Equal slot width, sized to the widest label (see B9-LANDING note in the header
    /// about why the row supplies its own width instead of filling what is proposed).
    static func slotWidth(localLabel: String, remoteLabel: String) -> CGFloat {
        let widest = max(textWidth(localLabel), textWidth(remoteLabel))
        return ceil(widest) + labelHPadding * 2
    }

    static func rowWidth(localLabel: String, remoteLabel: String) -> CGFloat {
        slotWidth(localLabel: localLabel, remoteLabel: remoteLabel) * CGFloat(AppSourceMode.allCases.count)
            + innerPadding * 2
    }

    private var slot: CGFloat {
        Self.slotWidth(localLabel: localLabel, remoteLabel: remoteLabel)
    }

    private static func textWidth(_ string: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: labelSize, weight: .semibold)   // widest weight
        return ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(AppSourceMode.allCases) { mode in
                    segment(mode)
                        .frame(width: slot)
                }
            }
            capsule
        }
        .frame(width: Self.rowWidth(localLabel: localLabel, remoteLabel: remoteLabel),
               height: Self.rowHeight - Self.innerPadding * 2)
        .padding(Self.innerPadding)
        .background(Capsule().fill(.thinMaterial).opacity(0.6))
    }

    private func segment(_ mode: AppSourceMode) -> some View {
        Button {
            tap(mode)
        } label: {
            Text(label(mode))
                .font(.system(size: Self.labelSize,
                              weight: mode == selection ? .semibold : .regular))
                .foregroundStyle(Color.primary)     // 两段都黑字（pp 09-16 明示，覆盖参考件的 .secondary）
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(SegmentButtonStyle())
    }

    /// The 液态 capsule: one capsule whose x follows the shell's progress.
    private var capsule: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
            .frame(width: slot - Self.pillInset * 2,
                   height: Self.rowHeight - Self.innerPadding * 2)
            .offset(x: (selection.slot + progress) * slot + Self.pillInset)
            .allowsHitTesting(false)
    }

    private func tap(_ mode: AppSourceMode) {
        if mode == selection {
            if mode == .local { onLocalRetap?() }
            return
        }
        // Grok spec (DESIGN.md Motion): mode switch = soft haptic.
        Self.softTick()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
            selection = mode
        }
    }

    static func softTick() {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare(); g.impactOccurred()
    }

    static func detent() {
        let g = UISelectionFeedbackGenerator()
        g.prepare(); g.selectionChanged()
    }
}

/// Press feedback. `.glass` used to give this for free (brighten + scale); with the
/// reference's material capsule the segments would go dead under the finger, so the
/// same affordance is explicit: Grok's own pressed scale is 0.92.
private struct SegmentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

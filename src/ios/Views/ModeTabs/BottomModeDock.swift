// BottomModeDock.swift — Q2 底部三段 dock（本机 / 远程 / 构件影音），纯图标无文字
// 标签（pp 拍板）。选中段填充动态圆角块 + spring；点段 = RootTabRouter.route(to:)。
// 水平 margin 16 由本视图自带（壳层 safeAreaInset 直接放 BottomModeDock() 即可，
// 不要再加水平 padding）。

import SwiftUI
import UIKit

struct BottomModeDock: View {
    @ObservedObject private var router = RootTabRouter.shared

    // MARK: - 终稿尺寸
    private static let dockHeight: CGFloat = 60
    private static let dockCornerRadius: CGFloat = 34
    private static let horizontalMargin: CGFloat = 16
    private static let touchSide: CGFloat = 48
    private static let touchCornerRadius: CGFloat = 28
    private static let iconSide: CGFloat = 26

    private struct Segment {
        let mode: AppSourceMode
        let asset: String
        let template: Bool
        let labelKey: LocalizedStringKey
    }

    /// 三段顺序 = 路由顺序。CaduGhost 彩色原样（不 template）；线性图标 template +
    /// Color.primary 自动双模式。
    private static let segments: [Segment] = [
        Segment(mode: .local,  asset: "CaduGhost",         template: false, labelKey: "Local"),
        Segment(mode: .remote, asset: "aa-SquareTerminal", template: true,  labelKey: "Remote"),
        Segment(mode: .works,  asset: "aa-Blocks",         template: true,  labelKey: "Works & Media"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.segments, id: \.mode) { seg in
                // 三段等宽均分（spaceAround 语义：图标落在各自 1/3 段中心）。
                segmentView(seg)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Self.dockHeight)
        .background(
            RoundedRectangle(cornerRadius: Self.dockCornerRadius, style: .continuous)
                .fill(Self.dockSurface)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 2)
        .padding(.horizontal, Self.horizontalMargin)
    }

    @ViewBuilder
    private func segmentView(_ seg: Segment) -> some View {
        let selected = router.mode == seg.mode
        Button {
            // 已选段再点 = 无动作（也不响触感）。
            guard !selected else { return }
            Self.softTick()
            router.route(to: seg.mode)
        } label: {
            iconView(seg)
                .frame(width: Self.touchSide, height: Self.touchSide)
                .background(
                    RoundedRectangle(cornerRadius: Self.touchCornerRadius, style: .continuous)
                        .fill(selected ? Self.selectionFill : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.36, dampingFraction: 0.78), value: selected)
        .accessibilityLabel(Text(seg.labelKey))
    }

    @ViewBuilder
    private func iconView(_ seg: Segment) -> some View {
        if seg.template {
            Image(seg.asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.primary)
                .frame(width: Self.iconSide, height: Self.iconSide)
        } else {
            Image(seg.asset)
                .resizable()
                .scaledToFit()
                .frame(width: Self.iconSide, height: Self.iconSide)
        }
    }

    // MARK: - 动态色（light / dark）

    /// 底：light #FDFDFC / dark #232220。
    private static let dockSurface = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x23 / 255, green: 0x22 / 255, blue: 0x20 / 255, alpha: 1)
            : UIColor(red: 0xFD / 255, green: 0xFD / 255, blue: 0xFC / 255, alpha: 1)
    })

    /// 选中填充：light #E4EAEC / dark #3A3833。
    private static let selectionFill = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x3A / 255, green: 0x38 / 255, blue: 0x33 / 255, alpha: 1)
            : UIColor(red: 0xE4 / 255, green: 0xEA / 255, blue: 0xEC / 255, alpha: 1)
    })

    /// 与 ModeTabPicker / RootModeTabsView 同一 soft 触感写法。
    private static func softTick() {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare(); g.impactOccurred()
    }
}

// SoulProfileCapsule.swift — [NATIVE-TABS] 本机页导航栏 principal 位身份胶囊。
// Muse 形制复刻（2026-09-26）：白圆盘 44pt 托住绒毛头像 38pt，
// 整体压在液态玻璃胶囊（min 57×36pt）顶部约 15pt，三层水平同中心。
// 放在原生 ToolbarItem(.principal) 里。
//
// 转场：头像挂 matchedTransitionSource（zoom 源），点击由壳层/本机页呈现
// SoulProfileHub（.navigationTransition(.zoom)）——打开从胶囊放大长出、关闭缩回。
//
// 头像两态：isWorking=true 时切 SoulPlushWorking（耳机+笔记本版）；
// 默认 SoulPlush 小老鼠 IP（2026-09-26 用户指定，星空睡帽灰老鼠）。
// SoulPlushGreeting / SoulPlushStar 已入库备用，位置待定。
//
// 列表下移：胶囊总高 ~65pt 超出标准 44pt 导航栏带，principal 内容会自然撑高
// UINavigationBar（系统行为，List 的 contentInsetAdjustment 自动跟随）；若
// 实机验证撑高不足，用 `topOverscrollCompensation` 常量在列表侧补
// .contentMargins(.top, …)（见 ContentView stackList/splitList 注释锚）。

import SwiftUI
import UIKit

struct SoulProfileCapsule: View {
    let soulName: String
    /// zoom 转场 namespace —— 与呈现侧 `.navigationTransition(.zoom(in:))` 同源。
    /// 可空：nil 时只显示胶囊不挂转场源（防御态；正常路径壳层必传）。
    let namespace: Namespace.ID?
    let onOpen: () -> Void
    /// 同步指示器视图（iCloud 启用时显示绿勾/暂停圈，原 titleSyncIndicator 语义）。
    /// nil = 不显示（iCloud 未启用）。点击 = 打开 sync 迁移详情。
    var syncIndicator: AnyView? = nil
    var onSyncTap: (() -> Void)? = nil
    /// 工作态头像：isWorking=true 时切耳机+笔记本版。
    var isWorking: Bool = false

    // Muse 参考实测（@3x 截图换算，估算值）
    private static let discDiameter: CGFloat = 44    // 白圆盘
    private static let avatarSize: CGFloat = 38     // 绒毛头像
    private static let discPillOverlap: CGFloat = 15 // 圆盘压住胶囊顶部的量
    private static let pillMinWidth: CGFloat = 57
    private static let pillHeight: CGFloat = 36

    var body: some View {
        Button {
            onOpen()
        } label: {
            VStack(spacing: -Self.discPillOverlap) {
                // 头像组：白圆盘打底 + 绒毛头像（纯白底 PNG，切圆坐进圆盘）。
                // zIndex(1)：VStack 里后出现的 view 默认盖在上面，圆盘必须压住胶囊。
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: Self.discDiameter, height: Self.discDiameter)
                        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
                    Image(isWorking ? "SoulPlushWorking" : "SoulPlush")
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.avatarSize, height: Self.avatarSize)
                        .clipShape(Circle())
                        // [MUSE-1:1] 站立式 idle：呼吸起伏，不飘浮不摇摆
                        .modifier(PlushIdleMotion())
                        .modifier(ProfileZoomSource(namespace: namespace))
                        .accessibilityHidden(true)
                }
                .zIndex(1)
                // 胶囊：iOS 26+ 液态玻璃，低版本磨砂白降级。宽度内容自适应。
                Text(verbatim: soulName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Self.pillText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
                    .frame(minWidth: Self.pillMinWidth, minHeight: Self.pillHeight)
                    .capsuleLiquidGlass()
                    .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 2)
                    .overlay(alignment: .leading) {
                        if let syncIndicator {
                            Button {
                                onSyncTap?()
                            } label: {
                                syncIndicator
                                    .contentShape(Rectangle())
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .offset(x: -18)
                        }
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: soulName))
    }

    /// pill 字色：light #11 / dark 白（玻璃底自适应深浅，字色随之反相）。
    private static let pillText = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .white
            : UIColor(white: 0x11 / 255, alpha: 1)
    })

    /// 低版本磨砂降级的白 tint：light 加白提亮到参考的霜白，dark 轻提。
    fileprivate static let frostTint = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.10)
            : UIColor(white: 1, alpha: 0.45)
    })
}

private extension View {
    /// 胶囊液态玻璃底：iOS 26+ 原生 glassEffect；iOS 18–25 用
    /// ultraThinMaterial + 白 tint 降级（视觉近似，不断结构）。
    @ViewBuilder
    func capsuleLiquidGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.clear, in: Capsule())
        } else {
            self.background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(SoulProfileCapsule.frostTint))
            }
        }
    }
}

/// 绒毛头像 idle 动画：站立式呼吸——原地轻微起伏 + 挤压拉伸，
/// 脚不离地，不飘浮不摇摆。Reduce Motion 开启时静止。
struct PlushIdleMotion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .phaseAnimator([0, 1, 2, 3]) { view, phase in
                    view
                        .offset(y: [0, 1.0, 0, -1.0][phase])
                        .scaleEffect(
                            x: [1.0, 1.03, 1.0, 0.98][phase],
                            y: [1.0, 0.97, 1.0, 1.02][phase]
                        )
                } animation: { _ in
                    .easeInOut(duration: 1.1)
                }
        }
    }
}

/// matchedTransitionSource 的 Optional-namespace 适配（@ViewBuilder 内不能直接
/// if-let 修饰符链，抽 modifier 保持编译器泛型推断健康）。
struct ProfileZoomSource: ViewModifier {
    let namespace: Namespace.ID?
    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: SoulProfileHub.zoomSourceID, in: namespace)
        } else {
            content
        }
    }
}

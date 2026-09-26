// SoulProfileCapsule.swift — [NATIVE-TABS] 本机页导航栏 principal 位身份胶囊。
// pp 拍板保留的需求件（Muse 形制）：幽灵头像 40pt 圆 + SOUL 名 pill 56×30。
// 放在原生 ToolbarItem(.principal) 里（替代上一版壳层 overlay 悬浮——与原生
// 标题互遮、push 不让位，全部是 overlay 挂法的病）。
//
// 转场：头像挂 matchedTransitionSource（zoom 源），点击由壳层/本机页呈现
// SoulProfileHub（.navigationTransition(.zoom)）——打开从胶囊放大长出、关闭缩回。
//
// 列表下移：胶囊总高 ~70pt 超出标准 44pt 导航栏带，principal 内容会自然撑高
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

    var body: some View {
        Button {
            onOpen()
        } label: {
            VStack(spacing: -6) {
                Image("CaduGhost")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .modifier(ProfileZoomSource(namespace: namespace))
                    .accessibilityHidden(true)
                Text(verbatim: soulName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Self.pillText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 56, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Self.pillSurface)
                    )
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
            .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: soulName))
    }

    /// pill 底：light 纯白 / dark #1C1C1E；字色随底反相。
    private static let pillSurface = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
            : .white
    })
    private static let pillText = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .white
            : UIColor(white: 0x11 / 255, alpha: 1)
    })
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

// ProfileInfoCard.swift — 资料页 SOUL/记忆卡片。
//
// [REDSIGN 2026-09-27] pp：要 Pezi 文件夹前脸那种毛玻璃白卡质感。
// 实现（iOS 原生）：
//   - 底层 .thinMaterial：实时虚化卡片背后的真实背景（比手画渐变更真）；
//   - 白色纵向渐变罩（顶 55% → 底 25%）：Pezi 前脸的釉面感；
//   - 极淡身份 tint（SOUL 暖棕 / 记忆薰衣草紫）：保留卡片身份；
//   - 顶部 catchlight 弧形高光 + 1px 白内描边 + 柔投影 + 胶片噪点；
//   - 深色文字（primary/secondary）：自动适配深浅色；
//   - 循环动画：符号浮动（3s）+ 流光扫过（4.5s），跟随 reduceMotion。

import SwiftUI

/// 卡片设计常量（swiftui-pro：共享设计常量，集中调整）。
enum ProfileInfoCardDesign {
    static let cornerRadius: CGFloat = 22
    static let height: CGFloat = 132
    static let titleSize: CGFloat = 20
    static let subtitleSize: CGFloat = 11
    static let dateSize: CGFloat = 11
    static let symbolSize: CGFloat = 32
    static let padding: CGFloat = 12
    static let floatDistance: CGFloat = 4
    static let floatDuration: Double = 3.0
    static let shimmerDuration: Double = 4.5
}

/// 资料页信息卡片：Pezi 式毛玻璃白卡。
struct ProfileInfoCard: View {
    let title: String
    let subtitle: String
    /// 身份染色（极淡）：SOUL 暖棕 / 记忆薰衣草紫。
    let tint: Color
    let symbol: String
    let date: Date
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floatOffset: CGFloat = 0
    @State private var shimmerX: CGFloat = -1.5

    var body: some View {
        Button(action: action) {
            ZStack {
                // 0. 背后柔色：供毛玻璃虚化取样（背后是纯色时 material 会发空）
                backDecoration
                    .clipShape(RoundedRectangle(cornerRadius: ProfileInfoCardDesign.cornerRadius, style: .continuous))

                ZStack(alignment: .topLeading) {
                    // 1. 毛玻璃底：实时虚化背后的柔色
                    RoundedRectangle(cornerRadius: ProfileInfoCardDesign.cornerRadius, style: .continuous)
                        .fill(.thinMaterial)

                    // 2. 白釉罩：顶 40% → 底 18%（别太厚，露出背后的柔色）
                    LinearGradient(
                        colors: [.white.opacity(0.40), .white.opacity(0.18)],
                        startPoint: .top, endPoint: .bottom
                    )

                    // 3. 身份 tint（极淡）
                    tint.opacity(0.10)

                    // 4. 顶部反光 wash
                    LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0)],
                        startPoint: .top, endPoint: .center
                    )

                    // 5. 胶片噪点
                    Image("NoiseTile")
                        .resizable()
                        .opacity(0.12)
                        .blendMode(.overlay)

                    // 6. 流光扫过（白卡上用亮白光带）
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.5), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.55)
                        .blur(radius: 10)
                        .offset(x: shimmerX * geo.size.width)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: ProfileInfoCardDesign.cornerRadius, style: .continuous))

                    // 7. 顶部 catchlight 高光线
                    RoundedRectangle(cornerRadius: ProfileInfoCardDesign.cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.9), .white.opacity(0)],
                                startPoint: .top, endPoint: .center
                            ),
                            lineWidth: 1.5
                        )
                        .mask(
                            // 只保留顶部弧线
                            LinearGradient(
                                colors: [.black, .black, .clear],
                                startPoint: .top, endPoint: .center
                            )
                        )

                    // 8. 文字（深色，印在玻璃上）
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: title)
                            .font(.system(size: ProfileInfoCardDesign.titleSize))
                            .bold()
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.system(size: ProfileInfoCardDesign.subtitleSize))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(Self.cardDateFormatter.string(from: date))
                            .font(.system(size: ProfileInfoCardDesign.dateSize))
                            .foregroundStyle(.secondary)
                    }
                    .padding(ProfileInfoCardDesign.padding)

                    // 9. 符号：深色半透明 + 浮动
                    Image(systemName: symbol)
                        .font(.system(size: ProfileInfoCardDesign.symbolSize, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.35))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(ProfileInfoCardDesign.padding)
                        .offset(y: floatOffset)
                }
            }
            .frame(height: ProfileInfoCardDesign.height)
            .clipShape(RoundedRectangle(cornerRadius: ProfileInfoCardDesign.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: ProfileInfoCardDesign.cornerRadius, style: .continuous))
            // 10. 柔投影
            .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: ProfileInfoCardDesign.floatDuration)
                    .repeatForever(autoreverses: true)
            ) {
                floatOffset = -ProfileInfoCardDesign.floatDistance
            }
            withAnimation(
                .linear(duration: ProfileInfoCardDesign.shimmerDuration)
                    .repeatForever(autoreverses: false)
            ) {
                shimmerX = 1.5
            }
        }
    }

    /// 背后柔色块：给毛玻璃提供虚化取样，避免背后纯色时发空。
    private var backDecoration: some View {
        ZStack {
            Circle()
                .fill(tint)
                .frame(width: 120, height: 120)
                .offset(x: 48, y: -38)
            Circle()
                .fill(tint.opacity(0.65))
                .frame(width: 76, height: 76)
                .offset(x: -58, y: 34)
            Circle()
                .fill(.white)
                .frame(width: 54, height: 54)
                .offset(x: -8, y: -44)
        }
        .blur(radius: 16)
    }

    /// 卡片左下日期：Muse 格式 MM.dd.yy（如 09.24.26）。
    private static let cardDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM.dd.yy"
        return f
    }()
}

import SwiftUI

// MARK: - Tool Card (Grok 描边卡)
//
// 2026-09-17 pp 装机改判（对照 photo_800AE8C8）→ 白卡版。
// 2026-09-18 pp 第三轮改判（对照 photo_353E81A2 逐像素实测）：
//   ① 描边卡：底 = sheet 同色 #F5F5F5（不浮起）+ 1px 描边 #EBEBEB + 圆角 28
//   ② 标题 13pt semibold 近黑、图标近黑（视觉 15pt）、copy 16pt 视觉
//   ③ 完成态右侧只有 copy（无 chevron；折叠手势保留：点标题行折叠）
//   ④ 分隔线 #DCDCDC、mono 内容 #111
// 折叠交互保留（标题行点击 + clip）。无输出工具的 ✓ 完成行由
// ThinkingDetailOverlay.itemRow 渲染（仅"有输出/运行中"走本卡）。

struct ToolCardView: View {
    let title: String
    let subtitle: String?
    let content: String
    let iconName: String      // AppSymbol key (语义复用聊天内映射)
    let usesSFSymbol: Bool
    var isInFlight: Bool = false

    @State private var isCollapsed = false
    @State private var copied = false

    private static let cardFill = Color(red: 0.961, green: 0.961, blue: 0.961)    // #F5F5F5 = sheet 底 [Grok 实测]
    private static let cardStroke = Color(red: 0.922, green: 0.922, blue: 0.922)  // #EBEBEB hairline [Grok 实测]
    private static let divider = Color(red: 0.863, green: 0.863, blue: 0.863)     // #DCDCDC [Grok 实测]
    private static let titleInk = Color(red: 0.082, green: 0.082, blue: 0.082)    // ≈#151515
    private static let monoInk = Color(red: 0.067, green: 0.067, blue: 0.067)     // #111 [Grok 实测：纯黑]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow
            if !isCollapsed {
                Rectangle()
                    .fill(Self.divider)
                    .frame(height: 1)
                contentArea
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Self.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(Self.cardStroke, lineWidth: 1) // 内描边：卡底 = sheet 底，靠描边勾轮廓 [Grok 实测]
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private var titleRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { // B6 折叠 0.2-0.5s 区间（装机复测）
                isCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                if usesSFSymbol {
                    Image(systemName: iconName)
                        .font(.system(size: 15))
                        .foregroundStyle(Self.titleInk)
                } else {
                    AppSymbol(iconName, size: 17) // Lucide 内边距补偿：视觉 ≈15 [Grok 实测 45px/3]
                        .foregroundStyle(Self.titleInk)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Self.titleInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isInFlight {
                    CometSpinner(size: 20)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 48) // 给 copy 按钮留位
            .padding(.vertical, 12) // 标题行高 ≈42pt [Grok 实测 42.3]
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Copy affordance: 16pt 视觉 / 32pt 热区，右缘固定 [Grok 实测 48px/3]
        .overlay(alignment: .trailing) {
            copyButton
                .padding(.trailing, 14)
        }
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = content
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            AppSymbol("doc.on.doc", size: 18) // copy [Grok 实测 16pt 视觉]
                .foregroundStyle(copied ? Color.green : Self.titleInk)
                .frame(width: 32, height: 32) // 热区
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalized("Copy"))
    }

    private var contentArea: some View {
        Group {
            if content.isEmpty {
                EmptyView()
            } else {
                Text(content)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Self.monoInk)
                    // [pp 09-18] 工具内容完整显示（原 lineLimit(12) 截断）——聚合页外层
                    // ScrollView 负责滚动，卡内不再限行。
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)    // [Grok 实测 17.3pt]
                    .padding(.bottom, 14) // [Grok 实测 13.7pt]
            }
        }
    }
}

// MARK: - Comet Spinner (渐变圆环)
//
// [B7, 报告§2.3/§三] Black head → light tail comet arc, clockwise, 1.4s/turn.

struct CometSpinner: View {
    var size: CGFloat = 14
    var color: Color = .primary
    private static let period: Double = 1.4

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, sz in
                let t = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: Self.period)
                let head = t / Self.period * 2 * .pi
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let r = sz.width / 2 - 1.5
                let segments = 14
                for i in 0..<segments {
                    let a = head - Double(i) * 0.09
                    let fade = 1.0 - Double(i) / Double(segments)
                    var p = Path()
                    p.addArc(center: c, radius: r,
                             startAngle: .radians(a), endAngle: .radians(a + 0.09),
                             clockwise: false)
                    context.stroke(p, with: .color(color.opacity(0.15 + 0.85 * fade)), lineWidth: 1.8)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

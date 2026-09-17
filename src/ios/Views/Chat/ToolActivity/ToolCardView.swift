import SwiftUI

// MARK: - Tool Card (白卡)
//
// 2026-09-17 pp 装机改判（对照 Grok 实拍 photo_800AE8C8）：白底卡（浮在 #F3F3F3
// sheet 上）+ 无描边 + 圆角 16pt + 大 copy 按钮（视觉 22pt / 热区 32pt）+ 16pt 标题
// 字 + 全宽分隔线 + mono 深灰内容。折叠交互保留（chevron 旋转 + clip）。

struct ToolCardView: View {
    let title: String
    let subtitle: String?
    let content: String
    let iconName: String      // AppSymbol key (语义复用聊天内映射)
    let usesSFSymbol: Bool
    let accentColor: Color
    var isInFlight: Bool = false

    @State private var isCollapsed = false
    @State private var copied = false

    private static let cardFill = Color.white                                    // 白卡 [Grok 对照]
    private static let divider = Color(red: 0.925, green: 0.925, blue: 0.925)    // #ECECEC
    private static let titleInk = Color(red: 0.082, green: 0.082, blue: 0.082)   // ≈#151515
    private static let monoInk = Color(red: 0.24, green: 0.24, blue: 0.24)       // 深灰

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
            RoundedRectangle(cornerRadius: 16)
                .fill(Self.cardFill)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                        .foregroundStyle(accentColor)
                } else {
                    AppSymbol(iconName, size: 16)
                        .foregroundStyle(accentColor)
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Self.titleInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isInFlight {
                    CometSpinner(size: 16)
                } else {
                    AppSymbol("chevron.down", size: 14)
                        .foregroundStyle(Color.secondary)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0)) // B6 v↔› 同步旋转
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 60) // 给 copy 按钮留位（chevron 之外）
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Copy affordance: 大号纯黑按钮，右缘固定 [Grok 对照 ~22pt]
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
            AppSymbol("doc.on.doc", size: 22) // copy [Grok 对照：大按钮]
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
                    .lineLimit(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
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

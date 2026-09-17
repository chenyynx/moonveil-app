import SwiftUI

// MARK: - Tool Card (描线卡)
//
// [B8/B+, 报告§2.4 修正版] NOT a white card: fill #F3F3F3 (same as sheet
// background) + 1px #E8E8E8 stroke + 13pt corner + title row (near-black
// semibold + copy icon) + full-width divider + mono near-black content.
// Collapsible title row: chevron rotates 90°, content clips [B6].
// 任务卡（#E6E6E6）无对应物 → 不做（待 pp 确认后如需再加）。

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

    private static let cardFill = Color(red: 0.953, green: 0.953, blue: 0.953) // #F3F3F3
    private static let cardStroke = Color(red: 0.910, green: 0.910, blue: 0.910) // #E8E8E8
    private static let titleInk = Color(red: 0.082, green: 0.082, blue: 0.082)   // ≈#151515
    private static let monoInk = Color(red: 0.051, green: 0.051, blue: 0.051)    // ≈#0D0D0D

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow
            if !isCollapsed {
                Rectangle()
                    .fill(Self.cardStroke)
                    .frame(height: 0.67)
                contentArea
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(Self.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Self.cardStroke, lineWidth: 0.67)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private var titleRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { // B6 折叠 0.2-0.5s 区间（装机复测）
                isCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                if usesSFSymbol {
                    Image(systemName: iconName)
                        .font(.system(size: 12))
                        .foregroundStyle(accentColor)
                } else {
                    AppSymbol(iconName, size: 13)
                        .foregroundStyle(accentColor)
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Self.titleInk)
                    .lineLimit(1)
                if let sub = subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if isInFlight {
                    CometSpinner(size: 13)
                } else {
                    AppSymbol("chevron.down", size: 13)
                        .foregroundStyle(Color.secondary)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0)) // B6 v↔› 同步旋转
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Copy affordance sits right of the title (Grok: copy icon per card).
        .overlay(alignment: .trailing) {
            copyButton
                .padding(.trailing, 34)
        }
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = content
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            AppSymbol("doc.on.doc", size: 13) // copy [SELECTION.md §五]
                .foregroundStyle(copied ? Color.green : Self.titleInk)
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
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

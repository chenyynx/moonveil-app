// GrokSettingsComponents.swift — Grok-style settings list UI, 1:1 visual.
//
// Canvas 393x852pt. Measured from the Grok iOS settings reference (2026-09-25):
// page bg #F5F5F5, white cards (24pt continuous radius, 16pt side margins),
// 50pt rows, 20pt Lucide line icons (#858585, 18pt leading), 14pt black titles,
// 20pt chevrons (#C3C3C3, 22pt trailing), #E7E7E9 1px dividers inset 63pt
// (aligned to label x), 13pt #7B7B7B section headers (32pt leading,
// 30pt top / 13pt bottom), 17pt semibold nav title, floating search pill
// (51pt, 30pt side margins, 14pt #727272 text).
import SwiftUI

enum GrokSettingsStyle {
    static let pageBg = Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF5 / 255)
    static let iconGray = Color(red: 0x85 / 255, green: 0x85 / 255, blue: 0x85 / 255)
    static let chevronGray = Color(red: 0xC3 / 255, green: 0xC3 / 255, blue: 0xC3 / 255)
    static let sectionGray = Color(red: 0x7B / 255, green: 0x7B / 255, blue: 0x7B / 255)
    static let dividerGray = Color(red: 0xE7 / 255, green: 0xE7 / 255, blue: 0xE9 / 255)
    static let searchGray = Color(red: 0x72 / 255, green: 0x72 / 255, blue: 0x72 / 255)

    static let cardRadius: CGFloat = 24
    static let cardSideMargin: CGFloat = 16
    static let rowHeight: CGFloat = 50
    static let iconSize: CGFloat = 20
    static let iconLeading: CGFloat = 18
    static let titleIconGap: CGFloat = 9
    static let dividerInset: CGFloat = 63 // aligned to label x: 16 + 18 + 20 + 9
    static let chevronTrailing: CGFloat = 22
}

/// One settings row spec. Titles are pre-localized by the caller.
struct GrokSettingsRowSpec: Identifiable {
    enum Kind {
        case navigate(() -> AnyView) // lazy destination
        case openURL(URL)
        case action(() -> Void)
    }

    let id: String
    let title: String
    let iconAsset: String // "aa-*" Lucide asset name
    let kind: Kind
}

/// Row content: 20pt Lucide line icon, 12pt title, chevron.
private struct GrokSettingsRowContent: View {
    let spec: GrokSettingsRowSpec

    var body: some View {
        HStack(spacing: 0) {
            Image(spec.iconAsset)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: GrokSettingsStyle.iconSize, height: GrokSettingsStyle.iconSize)
                .foregroundStyle(GrokSettingsStyle.iconGray)
                .padding(.leading, GrokSettingsStyle.iconLeading)
            Text(spec.title)
                .font(.system(size: 14))
                .foregroundStyle(.black)
                .padding(.leading, GrokSettingsStyle.titleIconGap)
            Spacer(minLength: 0)
            Image("aa-ChevronRight")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundStyle(GrokSettingsStyle.chevronGray)
                .padding(.trailing, GrokSettingsStyle.chevronTrailing)
        }
        .frame(height: GrokSettingsStyle.rowHeight)
        .contentShape(Rectangle())
    }
}

/// Wraps a row spec in the right navigation container.
struct GrokSettingsRow: View {
    let spec: GrokSettingsRowSpec

    var body: some View {
        switch spec.kind {
        case .navigate(let makeDestination):
            NavigationLink {
                makeDestination()
            } label: {
                GrokSettingsRowContent(spec: spec)
            }
        case .openURL(let url):
            Link(destination: url) {
                GrokSettingsRowContent(spec: spec)
            }
        case .action(let fn):
            Button(action: fn) {
                GrokSettingsRowContent(spec: spec)
            }
            .buttonStyle(.plain)
        }
    }
}

/// A section: 13pt gray header + white 24pt card with 1px dividers between rows.
struct GrokSettingsSection: View {
    let title: String
    let rows: [GrokSettingsRowSpec]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(GrokSettingsStyle.sectionGray)
                .padding(.leading, 32)
                .padding(.top, 30)
                .padding(.bottom, 13)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    GrokSettingsRow(spec: row)
                    if index < rows.count - 1 {
                        GrokSettingsStyle.dividerGray
                            .frame(height: 1 / UIScreen.main.scale)
                            .padding(.leading, GrokSettingsStyle.dividerInset)
                    }
                }
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: GrokSettingsStyle.cardRadius, style: .continuous))
            .padding(.horizontal, GrokSettingsStyle.cardSideMargin)
        }
    }
}

/// Floating "Search settings" pill, 51pt tall.
struct GrokSettingsSearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 0) {
            Image("aa-Search")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 15, height: 15)
                .foregroundStyle(.black)
                .padding(.leading, 18)
            TextField(AppLocalized("Search settings"), text: $text)
                .font(.system(size: 14))
                .foregroundStyle(.black)
                .tint(.black)
                .padding(.leading, 12)
                .padding(.trailing, 20)
        }
        .frame(height: 51)
        .background(.white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 2)
        .padding(.horizontal, 30)
    }
}

/// 44pt glass X close button for the sheet header (iOS 26 liquid glass,
/// translucent-white fallback below — shared ConnectorGlassCompat shim).
struct GrokSettingsCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .modifier(GlassCircleButtonIfAvailable())
        }
        .buttonStyle(.plain)
    }
}

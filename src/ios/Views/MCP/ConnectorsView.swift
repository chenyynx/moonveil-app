//
//  ConnectorsView.swift
//  MinisApp
//
//  Connectors list page — a 1:1 native replica of Grok's connectors screen.
//  A #F5F5F5 canvas carries a custom header (centered 15pt bold title plus a
//  white circular back key, no system navigation bar) and three stacked groups
//  of inset white cards: Connected, Recommended and Custom Connectors.
//
//  Row states: unconnected → a "Connect" pill that opens the detail sheet;
//  connected → chevron, the whole row opens the sheet; broken credentials
//  (expired token / revoked grant) → warning badge, the row opens the sheet.
//

import SwiftUI
// UIKit is referenced only to ask the asset catalog whether a connector logo
// actually ships (see ConnectorLogoProbe); nothing here draws with UIKit views.
import UIKit

struct ConnectorsView: View {
    @ObservedObject private var store = MCPStore.shared

    /// Connector ids whose backing server exists but can no longer
    /// authenticate. TODO(connectors): feed from the real reauth signal.
    var needsReauthConnectorIDs: Set<String> = []

    /// Detail sheet placeholder — qoder-3 replaces it with ConnectorDetailSheet.
    @State private var selectedConnector: ConnectorDefinition?
    /// Custom-connector form placeholder — qoder-3 owns CustomConnectorForm.
    @State private var showCustomForm = false

    var body: some View {
        ZStack(alignment: .top) {
            ConnectorPalette.canvas
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        let connected = ConnectorCatalog.all.filter { isConnected($0) }
                        // Existing custom MCP servers (not from the catalog) that are enabled.
                        let customServers = store.servers.filter { !$0.id.hasPrefix("connector-") && $0.enabled }
                        if !connected.isEmpty || !customServers.isEmpty {
                            groupTitle(AppLocalized("Connected"))
                            if !connected.isEmpty {
                                card(connected)
                            }
                            if !customServers.isEmpty {
                                ConnectorCard {
                                    ForEach(Array(customServers.enumerated()), id: \.element.id) { index, server in
                                        ConnectorRowView(
                                            title: server.id,
                                            glyph: .lucide("aa-Blocks"),
                                            state: .connected,
                                            open: { }
                                        )
                                        if index < customServers.count - 1 {
                                            ConnectorDivider()
                                        }
                                    }
                                }
                            }
                        }

                        let recommended = ConnectorCatalog.all.filter { !isConnected($0) }
                        if !recommended.isEmpty {
                            groupTitle(AppLocalized("Recommended"))
                            card(recommended)
                        }

                        groupTitle(AppLocalized("Custom Connectors"))
                        ConnectorCard {
                            ConnectorRowView(
                                title: AppLocalized("Custom Connector"),
                                glyph: .lucide("aa-Blocks"),
                                state: .unconnected,
                                open: { showCustomForm = true }
                            )
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(item: $selectedConnector) { connector in
            ConnectorDetailSheet(connector: connector)
        }
        .sheet(isPresented: $showCustomForm) {
            CustomConnectorForm()
        }
        .navigationTitle(AppLocalized("Connectors"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Groups

    private func groupTitle(_ title: String) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ConnectorPalette.groupTitle)
            Spacer(minLength: 0)
        }
        .padding(.leading, ConnectorMetrics.groupTitleLeading)
        .padding(.top, ConnectorMetrics.groupTitleTop)
        .padding(.bottom, ConnectorMetrics.groupTitleBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(_ definitions: [ConnectorDefinition]) -> some View {
        ConnectorCard {
            ForEach(Array(definitions.enumerated()), id: \.element.id) { index, definition in
                ConnectorRowView(
                    title: displayName(definition),
                    glyph: glyph(for: definition),
                    state: rowState(for: definition),
                    open: { selectedConnector = definition }
                )
                if index < definitions.count - 1 {
                    ConnectorDivider()
                }
            }
        }
    }

    // MARK: - Row data

    private func isConnected(_ definition: ConnectorDefinition) -> Bool {
        ConnectorCatalog.isConnected(connectorId: definition.id, in: store)
    }

    private func rowState(for definition: ConnectorDefinition) -> ConnectorRowState {
        if needsReauthConnectorIDs.contains(definition.id) { return .needsReauth }
        return isConnected(definition) ? .connected : .unconnected
    }

    private func glyph(for definition: ConnectorDefinition) -> ConnectorGlyph {
        ConnectorLogoProbe.isPresent(definition.logoAssetName)
            ? .asset(definition.logoAssetName)
            : .symbol("app.dashed")
    }

    /// Brand names arrive as catalog keys; until those keys ship in the string
    /// catalog the id reads better in the row than an unresolved key.
    private func displayName(_ definition: ConnectorDefinition) -> String {
        let resolved = String(localized: String.LocalizationValue(definition.nameKey), bundle: AppBundle.current)
        return resolved == definition.nameKey ? definition.id.capitalized : resolved
    }
}

// MARK: - Row

private enum ConnectorRowState { case connected, needsReauth, unconnected }

private enum ConnectorGlyph {
    case asset(String)
    case lucide(String)
    case symbol(String)
}

private struct ConnectorRowView: View {
    let title: String
    let glyph: ConnectorGlyph
    let state: ConnectorRowState
    let open: () -> Void

    var body: some View {
        let row = HStack(spacing: ConnectorMetrics.glyphToTitle) {
            iconWell
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(.black)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.leading, ConnectorMetrics.wellLeading)
        .padding(.trailing, ConnectorMetrics.rowTrailing)
        .frame(height: ConnectorMetrics.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        // An unconnected row is inert — only its pill is a control.
        if state == .unconnected {
            row
        } else {
            Button(action: open) { row }
                .buttonStyle(.plain)
        }
    }

    private var iconWell: some View {
        ZStack {
            switch glyph {
            case .asset(let name):
                Image(name)
                    .resizable()
                    .scaledToFit()
                    .frame(width: ConnectorMetrics.glyph, height: ConnectorMetrics.glyph)
            case .lucide(let name):
                Image(name)
                    .resizable()
                    .scaledToFit()
                    .frame(width: ConnectorMetrics.glyph, height: ConnectorMetrics.glyph)
                    .foregroundStyle(ConnectorPalette.placeholderGlyph)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: ConnectorMetrics.glyph))
                    .foregroundStyle(ConnectorPalette.placeholderGlyph)
                    .frame(width: ConnectorMetrics.glyph, height: ConnectorMetrics.glyph)
            }
        }
        .frame(width: ConnectorMetrics.well, height: ConnectorMetrics.well)
        .background(
            ConnectorPalette.iconWell,
            in: RoundedRectangle(cornerRadius: ConnectorMetrics.wellCorner, style: .continuous)
        )
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .unconnected:
            Button(action: open) {
                Text(AppLocalized("Connect"))
                    .font(.system(size: 11))
                    .foregroundStyle(.black)
                    .frame(width: ConnectorMetrics.pillWidth, height: ConnectorMetrics.pillHeight)
                    .modifier(GlassCapsuleButtonIfAvailable())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        case .connected:
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(ConnectorPalette.chevron)
        case .needsReauth:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(ConnectorPalette.warning)
        }
    }
}

private struct ConnectorDivider: View {
    var body: some View {
        ConnectorPalette.divider
            .frame(height: ConnectorMetrics.hairline)
            .padding(.leading, ConnectorMetrics.dividerInset)
    }
}

private struct ConnectorCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(ConnectorPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: ConnectorMetrics.cardCorner, style: .continuous))
        .padding(.horizontal, ConnectorMetrics.cardInset)
    }
}

// MARK: - Metrics and palette

private enum ConnectorMetrics {
    static let rowHeight: CGFloat = 68
    static let cardInset: CGFloat = 16
    static let cardCorner: CGFloat = 26
    static let groupTitleLeading: CGFloat = 33
    static let groupTitleTop: CGFloat = 20
    static let groupTitleBottom: CGFloat = 8
    static let well: CGFloat = 44
    static let wellCorner: CGFloat = 12.5
    static let wellLeading: CGFloat = 12
    static let glyph: CGFloat = 26
    static let glyphToTitle: CGFloat = 12
    static let rowTrailing: CGFloat = 16
    static let dividerInset: CGFloat = 68
    static let backButton: CGFloat = 44
    static let pillWidth: CGFloat = 48
    static let pillHeight: CGFloat = 26
    /// The spec's 1px rule: one device pixel, not one point.
    static let hairline: CGFloat = 1 / 3
}

private enum ConnectorPalette {
    static let canvas = Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF5 / 255)
    static let card = Color.white
    static let groupTitle = Color(red: 0x7E / 255, green: 0x7D / 255, blue: 0x82 / 255)
    static let divider = Color(red: 0xC6 / 255, green: 0xC6 / 255, blue: 0xC6 / 255)
    static let iconWell = Color(red: 0xEB / 255, green: 0xEB / 255, blue: 0xEB / 255)
    static let pill = Color(red: 0xEA / 255, green: 0xEA / 255, blue: 0xEA / 255)
    static let chevron = Color(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xC9 / 255)
    static let warning = Color(red: 0xE0 / 255, green: 0x32 / 255, blue: 0x37 / 255)
    static let placeholderGlyph = Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255)
}

// MARK: - Logo availability

/// The brand imagesets land after the layout, so a row can only pick its glyph
/// by asking whether the asset exists. Missing logos would otherwise leave an
/// empty well.
private enum ConnectorLogoProbe {
    static func isPresent(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return UIImage(named: name) != nil
    }
}

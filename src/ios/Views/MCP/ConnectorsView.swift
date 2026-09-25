//
//  ConnectorsView.swift
//  MinisApp
//
//  Connectors list page — native system styling: an inset-grouped List with
//  system section headers, default row typography, and stock separators.
//  Row chrome follows the Grok reference measurements: 44pt logo well
//  (R12.5, ~20pt logo) and a 48×26 connect capsule in #EAEAEA.
//
//  Row states: unconnected → a 48×26 display-only connect capsule;
//  connected → chevron; broken credentials → warning badge. The whole row
//  opens the detail sheet in every state.
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

    /// Detail sheet for a catalog connector.
    @State private var selectedConnector: ConnectorDefinition?
    /// Custom-connector creation form.
    @State private var showCustomForm = false

    var body: some View {
        let connected = ConnectorCatalog.all.filter { isConnected($0) }
        // Existing custom MCP servers (not from the catalog) that are enabled.
        let customServers = store.servers.filter { !$0.id.hasPrefix("connector-") && $0.enabled }
        let recommended = ConnectorCatalog.all.filter { !isConnected($0) }

        List {
            if !connected.isEmpty || !customServers.isEmpty {
                Section(AppLocalized("Connected")) {
                    ForEach(connected, id: \.id) { definition in
                        ConnectorRowView(
                            title: displayName(definition),
                            glyph: glyph(for: definition),
                            state: rowState(for: definition),
                            open: { selectedConnector = definition }
                        )
                    }
                    ForEach(customServers, id: \.id) { server in
                        ConnectorRowView(
                            title: server.id,
                            glyph: .lucide("aa-Blocks"),
                            state: .connected,
                            open: { }
                        )
                    }
                }
            }

            if !recommended.isEmpty {
                Section(AppLocalized("Recommended")) {
                    ForEach(recommended, id: \.id) { definition in
                        ConnectorRowView(
                            title: displayName(definition),
                            glyph: glyph(for: definition),
                            state: rowState(for: definition),
                            open: { selectedConnector = definition }
                        )
                    }
                }
            }

            Section(AppLocalized("Custom Connectors")) {
                ConnectorRowView(
                    title: AppLocalized("Custom Connector"),
                    glyph: .lucide("aa-Blocks"),
                    state: .unconnected,
                    open: { showCustomForm = true }
                )
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $selectedConnector) { connector in
            ConnectorDetailSheet(
                connector: connector,
                needsReauth: needsReauthConnectorIDs.contains(connector.id)
            )
        }
        .sheet(isPresented: $showCustomForm) {
            CustomConnectorForm()
        }
        .navigationTitle(AppLocalized("Connectors"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing
        }
        .contentShape(Rectangle())

        // The whole card is the control in every state — tapping anywhere
        // (connect pill included) opens the detail sheet.
        Button(action: open) { row }
            .buttonStyle(.plain)
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
            // Grok's connect pill: 48×26 capsule, #EAEAEA fill, 11pt black
            // label (measured from the reference screenshots). The pill keeps
            // its light look in dark mode (like Apple's own tinted capsules);
            // display only — the whole row behind it is the button.
            Text(AppLocalized("Connect"))
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.12))
                .frame(width: ConnectorMetrics.pillWidth, height: ConnectorMetrics.pillHeight)
                .background(ConnectorPalette.pill, in: Capsule())
        case .connected:
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        case .needsReauth:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ConnectorPalette.warning)
        }
    }
}

// MARK: - Metrics and palette

private enum ConnectorMetrics {
    /// Measured from Grok's list (3x screenshots, run-length scan):
    /// well 44pt square, corner R 12.5 (fitted to the edge curve), logo ≈20pt,
    /// title gap ≈22pt, connect pill 48×26 capsule.
    static let well: CGFloat = 44
    static let wellCorner: CGFloat = 12.5
    static let glyph: CGFloat = 20
    static let glyphToTitle: CGFloat = 22
    static let pillWidth: CGFloat = 48
    static let pillHeight: CGFloat = 26
}

enum ConnectorPalette {
    /// Light values are the Grok-measured hexes; dark counterparts keep the
    /// same hierarchy on the dark canvas (system-style adaptation).
    static let canvas = dynamic(0xF5, 0xF5, 0xF5, dark: 0x0B, 0x0B, 0x0C)
    static let card = dynamic(0xFF, 0xFF, 0xFF, dark: 0x1C, 0x1C, 0x1E)
    static let groupTitle = dynamic(0x7E, 0x7D, 0x82, dark: 0x98, 0x98, 0x9E)
    static let divider = dynamic(0xC6, 0xC6, 0xC6, dark: 0x38, 0x38, 0x3C)
    static let iconWell = dynamic(0xEB, 0xEB, 0xEB, dark: 0x2C, 0x2C, 0x2E)
    static let pill = dynamic(0xEA, 0xEA, 0xEA, dark: 0x2C, 0x2C, 0x2E)
    static let chevron = dynamic(0xC7, 0xC7, 0xC9, dark: 0x48, 0x48, 0x4E)
    static let warning = Color(red: 0xE0 / 255, green: 0x32 / 255, blue: 0x37 / 255)
    static let placeholderGlyph = dynamic(0x8E, 0x8E, 0x93, dark: 0x98, 0x98, 0x9E)
    /// Detail-sheet surfaces: hero tile / close key / info cards stay white in
    /// light (Grok look), lift to elevated dark grays in dark mode.
    static let sheetSurface = dynamic(0xFF, 0xFF, 0xFF, dark: 0x1C, 0x1C, 0x1E)
    static let sheetSecondaryText = dynamic(0x8E, 0x8E, 0x93, dark: 0x98, 0x98, 0x9E)
    static let sheetHairline = dynamic(0xC7, 0xC7, 0xC9, dark: 0x38, 0x38, 0x3C)
    static let sheetCloseFill = dynamic(0xFF, 0xFF, 0xFF, dark: 0x2C, 0x2C, 0x2E)

    /// UIColor trait-aware color: same hue family, tuned dark variants.
    private static func dynamic(_ lr: UInt8, _ lg: UInt8, _ lb: UInt8,
                                dark dr: UInt8, _ dg: UInt8, _ db: UInt8) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: CGFloat(dr) / 255, green: CGFloat(dg) / 255, blue: CGFloat(db) / 255, alpha: 1)
                : UIColor(red: CGFloat(lr) / 255, green: CGFloat(lg) / 255, blue: CGFloat(lb) / 255, alpha: 1)
        })
    }
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

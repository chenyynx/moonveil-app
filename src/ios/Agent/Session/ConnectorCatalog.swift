//
//  ConnectorCatalog.swift
//  MinisApp
//
//  Data layer for the Connectors module: pre-built connector definitions
//  (catalog, auth type, brand tint, about items) plus the bridge to
//  MCPStore for connection state. No UI code here — views consume this
//  catalog and resolve localized strings via AppLocalized at render time.
//
//  A connected pre-built connector is represented in MCPStore as a server
//  whose id is "connector-<definition.id>" (e.g. "connector-github").
//

import Foundation
import SwiftUI

// MARK: - ConnectorAuthType

/// How a pre-built connector authenticates the user.
enum ConnectorAuthType: Hashable {
    /// OAuth flow against the named provider ("google", "microsoft", "slack").
    case oauth(provider: String)
    /// Personal Access Token entered by the user.
    case pat
    /// No credentials needed.
    case none
}

// MARK: - ConnectorAboutItem

/// One row in the detail sheet's "About this connector" card.
struct ConnectorAboutItem: Hashable {
    /// Lucide icon name (folder, lock, shield-check, mail, hash).
    var iconName: String
    /// Localization key for the row title.
    var titleKey: String
    /// Localization key for the row description.
    var descriptionKey: String
}

// MARK: - ConnectorDefinition

/// Static definition of a pre-built connector. All user-visible strings
/// are localization keys resolved by the view layer with AppLocalized.
struct ConnectorDefinition: Identifiable, Hashable {
    /// Stable id: github, outlook, slack, drive, gmail.
    var id: String
    /// Localization key for the display name, e.g. "connector.name.github".
    var nameKey: String
    /// Asset catalog image name, e.g. "logo-github".
    var logoAssetName: String
    /// Hex string for the detail sheet's subtle background tint.
    var tintColorHex: String
    var authType: ConnectorAuthType
    /// Localization key for the permission grant text.
    var permissionTextKey: String
    var aboutItems: [ConnectorAboutItem]

    /// SwiftUI Color parsed from tintColorHex.
    var tintColor: Color {
        Color(hex: tintColorHex)
    }

    /// The MCPStore server id backing this connector's connection.
    var serverId: String { "connector-\(id)" }
}

// MARK: - Color hex helper

private extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r, g, b: Double
        if h.count == 6 {
            r = Double((rgb & 0xFF0000) >> 16) / 255
            g = Double((rgb & 0x00FF00) >> 8) / 255
            b = Double(rgb & 0x0000FF) / 255
        } else {
            r = 0.96; g = 0.96; b = 0.96 // fallback #F5F5F5
        }
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - ConnectorCatalog

/// Pre-built connector catalog.
enum ConnectorCatalog {
    static let all: [ConnectorDefinition] = [
        ConnectorDefinition(
            id: "github",
            nameKey: "connector.name.github",
            logoAssetName: "logo-github",
            tintColorHex: "#F5F5F5",
            authType: .pat,
            permissionTextKey: "connector.permission.github",
            aboutItems: [
                ConnectorAboutItem(iconName: "folder", titleKey: "connector.about.github.files.title", descriptionKey: "connector.about.github.files.desc"),
                ConnectorAboutItem(iconName: "lock", titleKey: "connector.about.notrain.title", descriptionKey: "connector.about.github.notrain.desc"),
                ConnectorAboutItem(iconName: "shield-check", titleKey: "connector.about.control.title", descriptionKey: "connector.about.control.desc"),
            ]
        ),
        ConnectorDefinition(
            id: "outlook",
            nameKey: "connector.name.outlook",
            logoAssetName: "logo-outlook",
            tintColorHex: "#EDF1F5",
            authType: .oauth(provider: "microsoft"),
            permissionTextKey: "connector.permission.outlook",
            aboutItems: [
                ConnectorAboutItem(iconName: "mail", titleKey: "connector.about.outlook.mail.title", descriptionKey: "connector.about.outlook.mail.desc"),
                ConnectorAboutItem(iconName: "lock", titleKey: "connector.about.notrain.title", descriptionKey: "connector.about.outlook.notrain.desc"),
                ConnectorAboutItem(iconName: "shield-check", titleKey: "connector.about.control.title", descriptionKey: "connector.about.control.desc"),
            ]
        ),
        ConnectorDefinition(
            id: "slack",
            nameKey: "connector.name.slack",
            logoAssetName: "logo-slack",
            tintColorHex: "#F1EEEF",
            authType: .oauth(provider: "slack"),
            permissionTextKey: "connector.permission.slack",
            aboutItems: [
                ConnectorAboutItem(iconName: "hash", titleKey: "connector.about.slack.channels.title", descriptionKey: "connector.about.slack.channels.desc"),
                ConnectorAboutItem(iconName: "lock", titleKey: "connector.about.notrain.title", descriptionKey: "connector.about.slack.notrain.desc"),
                ConnectorAboutItem(iconName: "shield-check", titleKey: "connector.about.control.title", descriptionKey: "connector.about.control.desc"),
            ]
        ),
        ConnectorDefinition(
            id: "drive",
            nameKey: "connector.name.drive",
            logoAssetName: "logo-drive",
            tintColorHex: "#F5F3ED",
            authType: .oauth(provider: "google"),
            permissionTextKey: "connector.permission.drive",
            aboutItems: [
                ConnectorAboutItem(iconName: "folder", titleKey: "connector.about.drive.files.title", descriptionKey: "connector.about.drive.files.desc"),
                ConnectorAboutItem(iconName: "lock", titleKey: "connector.about.notrain.title", descriptionKey: "connector.about.drive.notrain.desc"),
                ConnectorAboutItem(iconName: "shield-check", titleKey: "connector.about.control.title", descriptionKey: "connector.about.control.desc"),
            ]
        ),
        ConnectorDefinition(
            id: "gmail",
            nameKey: "connector.name.gmail",
            logoAssetName: "logo-gmail",
            tintColorHex: "#F6EFEE",
            authType: .oauth(provider: "google"),
            permissionTextKey: "connector.permission.gmail",
            aboutItems: [
                ConnectorAboutItem(iconName: "mail", titleKey: "connector.about.gmail.mail.title", descriptionKey: "connector.about.gmail.mail.desc"),
                ConnectorAboutItem(iconName: "lock", titleKey: "connector.about.notrain.title", descriptionKey: "connector.about.gmail.notrain.desc"),
                ConnectorAboutItem(iconName: "shield-check", titleKey: "connector.about.control.title", descriptionKey: "connector.about.control.desc"),
            ]
        ),
    ]

    static func definition(id: String) -> ConnectorDefinition? {
        all.first { $0.id == id }
    }

    // MARK: - MCPStore bridge

    /// Whether the connector has a backing server in the store that is enabled.
    @MainActor
    static func isConnected(connectorId: String, in store: MCPStore) -> Bool {
        guard let def = definition(id: connectorId) else { return false }
        return store.servers.first { $0.id == def.serverId }?.enabled == true
    }

    /// The backing MCPServerConfig for a connector, if one exists.
    @MainActor
    static func server(for connectorId: String, in store: MCPStore) -> MCPServerConfig? {
        guard let def = definition(id: connectorId) else { return nil }
        return store.servers.first { $0.id == def.serverId }
    }
}

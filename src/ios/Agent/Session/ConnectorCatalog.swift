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
//  Real-connection wiring: GitHub ships a working remote MCP endpoint
//  (api.githubcopilot.com, PAT header auth — zero registration). OAuth
//  providers need a per-app client id (see registeredOAuthClient) which is
//  injected at build/config time; until then their connect() falls back to
//  a clear "not configured" alert instead of a fake connected state.
//

import Foundation
import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

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
    /// MCP tool names surfaced in the detail sheet's "Tools" chip list.
    /// Placeholder data pending real MCP tool discovery (see connect()).
    var toolNames: [String] = []

    /// SwiftUI Color parsed from tintColorHex.
    var tintColor: Color {
        Color(hex: tintColorHex)
    }

    /// The MCPStore server id backing this connector's connection.
    var serverId: String { "connector-\(id)" }

    /// Real remote MCP endpoint for this connector (HTTP transport), when
    /// the provider hosts one. GitHub's official remote server authenticates
    /// with a PAT header — no OAuth app registration needed.
    var remoteMCPURL: String? {
        // GitHub's official remote MCP server (PAT header or OAuth token).
        if id == "github" { return "https://api.githubcopilot.com/mcp/" }
        return nil
    }

    /// OAuth providers need a client id registered in OUR developer app
    /// (Google/Microsoft/Slack consoles — free, but per-app and must be
    /// embedded at build time). Returns the configured id or nil when the
    /// provider isn't wired up yet; nil ⇒ connect() shows "not configured".
    static func registeredOAuthClient(provider: String) -> MCPOAuthConfig? {
        switch provider {
        case "github":
            // GitHub OAuth App (registered 2026-09-26, callback
            // moonveil://oauth/callback). Public-client style: no secret.
            // GitHub's OAuth endpoints are fixed and well-known.
            var cfg = MCPOAuthConfig()
            cfg.mode = "static"
            cfg.clientId = "Ov23liTiQBZ9hlS9T9fl"
            cfg.authorizationEndpoint = "https://github.com/login/oauth/authorize"
            cfg.tokenEndpoint = "https://github.com/login/oauth/access_token"
            cfg.scopes = "repo read:org"
            cfg.redirectURI = "moonveil://oauth/callback"
            return cfg
        default:
            // Google/Microsoft/Slack — pending app registration.
            return nil
        }
    }
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
            tintColorHex: "#D9DCE0",
            authType: .oauth(provider: "github"),
            permissionTextKey: "connector.permission.github",
            aboutItems: [
                ConnectorAboutItem(iconName: "folder", titleKey: "connector.about.github.files.title", descriptionKey: "connector.about.github.files.desc"),
                ConnectorAboutItem(iconName: "lock", titleKey: "connector.about.notrain.title", descriptionKey: "connector.about.github.notrain.desc"),
                ConnectorAboutItem(iconName: "shield-check", titleKey: "connector.about.control.title", descriptionKey: "connector.about.control.desc"),
            ],
            toolNames: ["github_list_repositories", "github_read_file", "github_search_code", "github_list_issues", "github_create_issue", "github_create_pull_request"]
        ),
        ConnectorDefinition(
            id: "outlook",
            nameKey: "connector.name.outlook",
            logoAssetName: "logo-outlook",
            tintColorHex: "#B1C1CF",
            authType: .oauth(provider: "microsoft"),
            permissionTextKey: "connector.permission.outlook",
            aboutItems: [
                ConnectorAboutItem(iconName: "mail", titleKey: "connector.about.outlook.mail.title", descriptionKey: "connector.about.outlook.mail.desc"),
                ConnectorAboutItem(iconName: "lock", titleKey: "connector.about.notrain.title", descriptionKey: "connector.about.outlook.notrain.desc"),
                ConnectorAboutItem(iconName: "shield-check", titleKey: "connector.about.control.title", descriptionKey: "connector.about.control.desc"),
            ],
            toolNames: ["outlook_list_messages", "outlook_read_message", "outlook_search_mail", "outlook_send_message", "outlook_create_draft", "outlook_move_message"]
        ),
        ConnectorDefinition(
            id: "slack",
            nameKey: "connector.name.slack",
            logoAssetName: "logo-slack",
            tintColorHex: "#DCD3DA",
            authType: .oauth(provider: "slack"),
            permissionTextKey: "connector.permission.slack",
            aboutItems: [
                ConnectorAboutItem(iconName: "hash", titleKey: "connector.about.slack.channels.title", descriptionKey: "connector.about.slack.channels.desc"),
                ConnectorAboutItem(iconName: "lock", titleKey: "connector.about.notrain.title", descriptionKey: "connector.about.slack.notrain.desc"),
                ConnectorAboutItem(iconName: "shield-check", titleKey: "connector.about.control.title", descriptionKey: "connector.about.control.desc"),
            ],
            toolNames: ["slack_list_channels", "slack_read_history", "slack_send_message", "slack_search_messages", "slack_upload_file"]
        ),
        ConnectorDefinition(
            id: "drive",
            nameKey: "connector.name.drive",
            logoAssetName: "logo-drive",
            tintColorHex: "#E7E1D2",
            authType: .oauth(provider: "google"),
            permissionTextKey: "connector.permission.drive",
            aboutItems: [
                ConnectorAboutItem(iconName: "folder", titleKey: "connector.about.drive.files.title", descriptionKey: "connector.about.drive.files.desc"),
                ConnectorAboutItem(iconName: "lock", titleKey: "connector.about.notrain.title", descriptionKey: "connector.about.drive.notrain.desc"),
                ConnectorAboutItem(iconName: "shield-check", titleKey: "connector.about.control.title", descriptionKey: "connector.about.control.desc"),
            ],
            toolNames: ["drive_list_files", "drive_read_file", "drive_search_files", "drive_share_file", "drive_create_folder"]
        ),
        ConnectorDefinition(
            id: "gmail",
            nameKey: "connector.name.gmail",
            logoAssetName: "logo-gmail",
            tintColorHex: "#E8D6D4",
            authType: .oauth(provider: "google"),
            permissionTextKey: "connector.permission.gmail",
            aboutItems: [
                ConnectorAboutItem(iconName: "mail", titleKey: "connector.about.gmail.mail.title", descriptionKey: "connector.about.gmail.mail.desc"),
                ConnectorAboutItem(iconName: "lock", titleKey: "connector.about.notrain.title", descriptionKey: "connector.about.gmail.notrain.desc"),
                ConnectorAboutItem(iconName: "shield-check", titleKey: "connector.about.control.title", descriptionKey: "connector.about.control.desc"),
            ],
            toolNames: ["gmail_list_messages", "gmail_read_message", "gmail_search_mail", "gmail_send_message", "gmail_create_draft"]
        ),
    ]

    static func definition(id: String) -> ConnectorDefinition? {
        all.first { $0.id == id }
    }

    // MARK: - Brand tint derivation (logo → gradient)

    /// Alpha-weighted average of the connector's logo, lightened and pulled
    /// toward neutral — the soft brand wash Grok paints the detail sheet with.
    ///
    /// Native Core Image path (per Apple's CIAreaAverage practice): the area
    /// filter returns premultiplied RGBA, so RGB ÷ alpha gives the average of
    /// the *opaque* pixels only — transparent logo padding contributes nothing.
    /// Cached per connector id; falls back to the static tintColorHex tint.
    static func brandTint(for id: String) -> Color {
        if let cached = tintCache[id] { return cached }
        guard let def = definition(id: id) else { return Color(hex: "#F5F5F5") }
        guard let avg = opaqueAverageColor(of: def.logoAssetName) else {
            return def.tintColor
        }
        // Step 1 — lighten 55% toward white (logos read far too vivid raw).
        var r = avg.r * 0.45 + 255 * 0.55
        var g = avg.g * 0.45 + 255 * 0.55
        var b = avg.b * 0.45 + 255 * 0.55
        // Step 2 — pull 30% toward luminance gray (Grok's wash is desaturated).
        let lum = 0.299 * r + 0.587 * g + 0.114 * b
        let m: CGFloat = 0.30
        r += (lum - r) * m
        g += (lum - g) * m
        b += (lum - b) * m
        let color = Color(red: r / 255, green: g / 255, blue: b / 255)
        tintCache[id] = color
        return color
    }

    // nonisolated(unsafe): written only from the main thread (sheet body)
    // and guarded by id-keyed immutability; silences Swift 6 strict mode.
    nonisolated(unsafe) private static var tintCache: [String: Color] = [:]

    /// Premultiplied-unbiased average color of an asset image, or nil.
    /// SVG-backed imagesets may not expose cgImage, so redraw through a
    /// 64×64 bitmap first (also keeps the reduction cheap).
    private static func opaqueAverageColor(of assetName: String) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let logo = UIImage(named: assetName) else { return nil }
        let side: CGFloat = 64
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            logo.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let cg = rendered.cgImage else { return nil }

        let context = CIContext()
        let input = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: input.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        context.render(output, toBitmap: &px, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: cs)
        let avgA = CGFloat(px[3]) / 255
        guard avgA > 0.004 else { return nil } // fully transparent logo
        let unmult: (UInt8) -> CGFloat = { CGFloat($0) / 255 / avgA * 255 }
        return (min(unmult(px[0]), 255), min(unmult(px[1]), 255), min(unmult(px[2]), 255))
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

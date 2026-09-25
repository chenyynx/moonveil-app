//
//  ConnectorDetailSheet.swift
//  MinisApp
//
//  Connector detail sheet — Grok-aligned replica. Tinted gradient canvas
//  (connector brand tint fading to neutral), white glass hero tile, 19pt
//  bold title, black "Connect" CTA (glass "Disconnect" when linked),
//  optional reauth warning card, permission text, the "About this
//  connector" info card, and the "Tools" chip list. White surfaces carry
//  soft shadows per the iOS 26 Liquid Glass language — never flat.
//

import SwiftUI
import UIKit

/// Resolves a runtime localization key (e.g. "connector.name.github") against
/// the String Catalog. `AppLocalized("\(key)")` does NOT work — the string
/// interpolation turns the key into a format pattern. This does the lookup
/// directly, falling back to the key itself if untranslated.
private func dynamicLocalized(_ key: String) -> String {
    let resolved = String(localized: String.LocalizationValue(key), bundle: AppBundle.current)
    return resolved
}

struct ConnectorDetailSheet: View {
    let connector: ConnectorDefinition

    /// Broken-credentials state — shows the reauth warning card. Fed from
    /// the list's needsReauthConnectorIDs (data signal still TODO there).
    var needsReauth: Bool = false

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MCPStore.shared

    @State private var errorMessage: String?
    @State private var showError: Bool = false
    /// GitHub PAT collection prompt.
    @State private var patPrompt: PATPrompt?
    /// OAuth provider that has no client id configured yet.
    @State private var notConfiguredProvider: String = ""
    @State private var showNotConfigured: Bool = false

    /// Parameters for the PAT collection sheet.
    struct PATPrompt: Identifiable {
        let id = UUID()
        let title: String
        let endpoint: String
    }

    private var isConnected: Bool {
        ConnectorCatalog.isConnected(connectorId: connector.id, in: store)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // The canvas itself lives in presentationBackground (logo-derived
            // gradient) — only the soft top-center highlight sits here; a flat
            // fill would cover the gradient.
            RadialGradient(
                gradient: Gradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0)]),
                center: .top,
                startRadius: 60,
                endRadius: 420
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        hero
                            .padding(.top, 4)

                        Text(dynamicLocalized(connector.nameKey))
                            .font(.system(size: 19, weight: .bold))
                            .padding(.top, 14)

                        ctaButton
                            .padding(.top, 22)

                        if needsReauth {
                            reauthCard
                                .padding(.horizontal, 16)
                                .padding(.top, 44)
                        }

                        Text(dynamicLocalized(connector.permissionTextKey))
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.57))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 33)
                            .padding(.trailing, 24)
                            .padding(.top, needsReauth ? 35 : 26)

                        Text(AppLocalized("About This Connector"))
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 0.494, green: 0.49, blue: 0.51))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 33)
                            .padding(.top, 20)

                        infoCard
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, connector.toolNames.isEmpty ? 40 : 0)

                        if !connector.toolNames.isEmpty {
                            toolsSection
                        }
                    }
                }
                // The hero's 24pt shadow bleeds ~14pt above the tile; with
                // only 4pt top padding the scroll view's default clipping
                // chopped the top of the shadow off (iOS17 fixes it without
                // giving back the Grok-aligned spacing).
                .scrollClipDisabled()
            }
        }
        // Detents matched to Grok's observed sheet heights (3x screenshots):
        // small detent tops out at 52.0% of screen (ours was 57.0% at
        // fraction 0.62 → 0.565), expanded at 86.5% (0.94 instead of .large).
        .presentationDetents([.fraction(0.565), .fraction(0.94)])
        .presentationCornerRadius(36)
        .presentationBackground(sheetBackground)
        .presentationDragIndicator(.hidden)
        .sheet(item: $patPrompt) { prompt in
            PATEntrySheet(prompt: prompt) { pat in
                connectWithPAT(pat)
            }
        }
        .alert(AppLocalized("connector.oauth.notconfigured"), isPresented: $showNotConfigured) {
            Button(AppLocalized("OK"), role: .cancel) {}
        } message: {
            Text(String(format: AppLocalized("connector.oauth.notconfigured.body"), notConfiguredProvider))
        }
    }

    /// Grok-style sheet background: the logo-derived brand wash at the top
    /// fading to the neutral canvas. Extraction is Core Image CIAreaAverage
    /// over the connector logo (see ConnectorCatalog.brandTint), cached.
    private var sheetBackground: LinearGradient {
        let tint = ConnectorCatalog.brandTint(for: connector.id)
        return LinearGradient(
            gradient: Gradient(stops: [
                .init(color: tint, location: 0),
                .init(color: tint.opacity(0.5), location: 0.30),
                .init(color: ConnectorPalette.canvas, location: 0.62),
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Header (grabber + liquid-glass close, no band — matches Grok)

    private var header: some View {
        ZStack(alignment: .top) {
            // Grabber 35x5 #7D7D7F, centered
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(red: 0.49, green: 0.49, blue: 0.498))
                .frame(width: 35, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            HStack {
                // Close: white circle (explicit fill — see hero note) + glass.
                Button(action: { dismiss() }) {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 44, height: 44)
                            .modifier(GlassCircleButtonIfAvailable())
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                Spacer()
            }
            .padding(.top, 8)
        }
        .frame(height: 60)
    }

    // MARK: - Hero (100pt white tile, soft shadow — white fill is mandatory:
    // a bare Shape paints black under the glass tint and reads muddy gray.)

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white)
                .frame(width: 100, height: 100)
                .modifier(GlassRoundedRectIfAvailable(cornerRadius: 24, tintOpacity: 0.7))
                .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 10)
            connectorLogo
        }
    }

    @ViewBuilder
    private var connectorLogo: some View {
        if let uiImage = UIImage(named: connector.logoAssetName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
        } else {
            // Asset not bundled yet — neutral placeholder until logos land.
            Image(systemName: "app.dashed")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(Color(red: 0.56, green: 0.56, blue: 0.58))
                .frame(width: 56, height: 56)
        }
    }

    // MARK: - CTA

    @ViewBuilder
    private var ctaButton: some View {
        if isConnected {
            // Liquid-glass "Disconnect": translucent white capsule, no status text.
            Button(action: disconnect) {
                Text(AppLocalized("Disconnect"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 238, height: 43)
                    .modifier(GlassCapsuleButtonIfAvailable())
            }
        } else {
            // Solid black "Connect" with a faint top inner highlight.
            Button(action: connect) {
                Text(AppLocalized("Connect"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 238, height: 43)
                    .background(Color.black)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                            .padding(0.75)
                            .mask(
                                LinearGradient(
                                    gradient: Gradient(colors: [.white, .clear]),
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    )
                    .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 6)
            }
        }
    }

    // MARK: - About card

    private var infoCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(connector.aboutItems.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 12) {
                    Image(lucideAsset(for: item.iconName))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundColor(Color(red: 0.537, green: 0.537, blue: 0.553))
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(dynamicLocalized(item.titleKey))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(dynamicLocalized(item.descriptionKey))
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 0.557, green: 0.557, blue: 0.576))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 13)
                .padding(.horizontal, 16)

                if index < connector.aboutItems.count - 1 {
                    Divider()
                        .background(Color(red: 0.78, green: 0.78, blue: 0.79))
                        .padding(.leading, 48)
                }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    /// Lucide asset name for the about-item icon (aa- prefix, template rendering).
    private func lucideAsset(for lucideName: String) -> String {
        switch lucideName {
        case "folder": return "aa-Folder"
        case "lock": return "aa-Lock"
        case "shield-check": return "aa-ShieldCheck"
        case "mail": return "aa-Mail"
        case "hash": return "aa-Hash"
        default: return "aa-Info"
        }
    }

    // MARK: - Reauth warning card (Grok's broken-credentials state)

    private var reauthCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundColor(ConnectorPalette.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalized("connector.reauth.title"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text(AppLocalized("connector.reauth.subtitle"))
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.557, green: 0.557, blue: 0.576))
            }
            Spacer(minLength: 8)
            Button(action: reauth) {
                Text(AppLocalized("connector.reauth.button"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 24)
                    .background(Color.black, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    // MARK: - Tools chip list

    private var toolsSection: some View {
        Group {
            Text(AppLocalized("connector.tools.header"))
                .font(.system(size: 13))
                .foregroundColor(Color(red: 0.494, green: 0.49, blue: 0.51))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 33)
                .padding(.top, 26)

            ToolChipFlow(spacing: 8) {
                ForEach(connector.toolNames, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Actions

    /// Real connection: write url (+ PAT header) / oauth config into
    /// MCPStore, then the in-guest CLI daemon handles initialize +
    /// tools/list on next refresh. GitHub = PAT prompt (zero registration);
    /// OAuth providers = MCPOAuthController.authorize when a client id is
    /// configured; otherwise an honest "not configured" alert — never a
    /// fake connected state.
    private func connect() {
        // 1) PAT connector with a real remote endpoint → collect the token.
        if case .pat = connector.authType, let endpoint = connector.remoteMCPURL {
            patPrompt = PATPrompt(
                title: AppLocalized("connector.pat.prompt.github"),
                endpoint: endpoint
            )
            return
        }
        // 2) OAuth connector → real flow when configured, honest alert when not.
        if case .oauth(let provider) = connector.authType {
            if let oauth = ConnectorCatalog.registeredOAuthClient(provider: provider) {
                Task { await oauthConnect(oauth: oauth) }
            } else {
                notConfiguredProvider = provider
                showNotConfigured = true
            }
            return
        }
        // 3) Anything else (shouldn't happen in the catalog) — plain register.
        registerPlain()
    }

    private func registerPlain() {
        var cfg = MCPServerConfig(id: connector.serverId, enabled: true)
        cfg.note = connector.id
        if let endpoint = connector.remoteMCPURL { cfg.url = endpoint }
        store.add(cfg)
    }

    /// OAuth handshake via the shared controller, then register the server.
    private func oauthConnect(oauth: MCPOAuthConfig) async {
        do {
            try await MCPOAuthController.shared.authorize(server: connector.serverId, oauth: oauth)
            var cfg = MCPServerConfig(id: connector.serverId, enabled: true)
            cfg.note = connector.id
            cfg.oauth = oauth
            store.add(cfg)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    /// Persist the PAT the user entered and flip the connector on.
    private func connectWithPAT(_ pat: String) {
        guard let endpoint = connector.remoteMCPURL else { return }
        var cfg = MCPServerConfig(id: connector.serverId, enabled: true)
        cfg.note = connector.id
        cfg.url = endpoint
        cfg.headers = ["Authorization": "Bearer \(pat)"]
        store.add(cfg)
        // Fire the real handshake + tools/list in the guest daemon.
        Task {
            _ = try? await store.refreshTools(server: connector.serverId)
        }
    }

    private func disconnect() {
        // Purges the backing server and its OAuth credentials (see
        // MCPStore.delete), matching Grok's "Disconnect" semantics.
        MCPOAuthController.purge(server: connector.serverId)
        store.delete(id: connector.serverId)
        dismiss()
    }

    private func reauth() {
        // Reset credentials so isAuthorized flips false and connect() can
        // run the full flow again.
        MCPOAuthController.purge(server: connector.serverId)
        if case .pat = connector.authType {
            connect()
        }
    }
}

// MARK: - PAT entry sheet

/// Secure-text prompt for PAT-connector setup (GitHub). Shows the target
/// endpoint, validates non-empty, hands the token to the caller.
private struct PATEntrySheet: View {
    let prompt: ConnectorDetailSheet.PATPrompt
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var token: String = ""

    private var valid: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Text(AppLocalized("Token"))
                            .foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .leading)
                        SecureField("ghp_…", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text(prompt.title)
                } footer: {
                    Text(prompt.endpoint)
                }

                Section {
                    Button(action: submit) {
                        Text(AppLocalized("Connect"))
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .foregroundStyle(valid ? Color.white : Color(red: 0.6, green: 0.6, blue: 0.62))
                    .background(
                        valid ? Color.black : Color(red: 0.92, green: 0.92, blue: 0.93),
                        in: Capsule()
                    )
                    .disabled(!valid)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(AppLocalized("Connect"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func submit() {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard valid else { return }
        onSubmit(trimmed)
        dismiss()
    }
}

// MARK: - Tool chip flow layout

/// Left-to-right wrapping chip row for the Tools list (iOS16+ Layout;
/// SwiftUI has no built-in flow container).
private struct ToolChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var positions: [CGPoint] = []
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight), positions)
    }
}

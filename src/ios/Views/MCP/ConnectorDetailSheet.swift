//
//  ConnectorDetailSheet.swift
//  MinisApp
//
//  Connector detail sheet — a 1:1 native replica of Grok's connector detail
//  sheet. Custom chrome (67pt top offset, 36pt top radius, #BABABA 47pt
//  header, liquid-glass close button), 100pt hero, black "Connect" CTA or
//  liquid-glass "Disconnect" CTA, permission text, and the "About this
//  connector" info card. All white surfaces carry soft shadows / inner
//  highlights per the iOS 26 Liquid Glass material language — never flat.
//

import SwiftUI
import UIKit

struct ConnectorDetailSheet: View {
    let connector: ConnectorDefinition

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MCPStore.shared

    private var isConnected: Bool {
        ConnectorCatalog.isConnected(connectorId: connector.id, in: store)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Tinted canvas + whisper of texture.
            connector.tintColor
                .ignoresSafeArea()
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
                            .padding(.top, 28)

                        Text(AppLocalized("\(connector.nameKey)"))
                            .font(.system(size: 20, weight: .bold))
                            .padding(.top, 14)

                        ctaButton
                            .padding(.top, 22)

                        Text(AppLocalized("\(connector.permissionTextKey)"))
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.57))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 33)
                            .padding(.trailing, 24)
                            .padding(.top, 26)

                        Text(AppLocalized("About This Connector"))
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 0.494, green: 0.49, blue: 0.51))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 33)
                            .padding(.top, 18)

                        infoCard
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 40)
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.92)])
        .presentationCornerRadius(36)
        .presentationBackground(connector.tintColor)
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Header (47pt #BABABA band, grabber, liquid-glass close)

    private var header: some View {
        ZStack(alignment: .top) {
            Color(red: 0.729, green: 0.729, blue: 0.729)
                .frame(height: 47)

            // Grabber 35x5 #7D7D7F
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(red: 0.49, green: 0.49, blue: 0.498))
                .frame(width: 35, height: 5)
                .padding(.top, 8)

            HStack {
                // Liquid-glass close: translucent white circle + blur + highlight.
                Button(action: { dismiss() }) {
                    ZStack {
                        Circle()
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.tint(.white.opacity(0.55)).interactive(), in: Circle())
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
                .padding(.leading, 16)
                Spacer()
            }
            .padding(.top, 1)
        }
        .frame(height: 47)
    }

    // MARK: - Hero (100pt white, soft shadow, inner highlight)

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20.5)
                .fill(Color.white)
                .frame(width: 100, height: 100)
                .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 8)
                .overlay(
                    // Whisper of top inner highlight so the white isn't dead flat.
                    RoundedRectangle(cornerRadius: 20.5)
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                        .mask(
                            LinearGradient(
                                gradient: Gradient(colors: [.white, .clear]),
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )
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
                    .glassEffect(.regular.tint(.white.opacity(0.5)).interactive(), in: Capsule())
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
                    .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
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
                        .frame(width: 14, height: 14)
                        .foregroundColor(Color(red: 0.537, green: 0.537, blue: 0.553))
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppLocalized("\(item.titleKey)"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.primary)
                        Text(AppLocalized("\(item.descriptionKey)"))
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 0.745, green: 0.745, blue: 0.753))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 13)
                .padding(.horizontal, 16)

                if index < connector.aboutItems.count - 1 {
                    Divider()
                        .background(Color(red: 0.78, green: 0.78, blue: 0.79))
                        .padding(.leading, 16)
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

    // MARK: - Actions

    private func connect() {
        // TODO(connectors): wire the real credential flow — OAuth via
        // MCPOAuthController for .oauth connectors, PAT prompt for .pat.
        // For now, register an enabled backing server so the connector
        // flips to the connected state.
        var cfg = MCPServerConfig(id: connector.serverId, enabled: true)
        cfg.note = connector.id
        store.add(cfg)
    }

    private func disconnect() {
        // Purges the backing server and its OAuth credentials (see
        // MCPStore.delete), matching Grok's "Disconnect" semantics.
        store.delete(id: connector.serverId)
        dismiss()
    }
}

import SwiftUI

struct ServiceEntryView: View {
    @ObservedObject private var service: RemoteService
    @State private var showsPrivacyPolicy = false
    var onManualLogin: () -> Void = {}
    var onQRCodeLogin: () -> Void = {}
    /// JO-6（首启入口终案）：直接用本地，灰字小按钮不抢两颗登录 CTA。
    var onLocalEntry: () -> Void = {}

    // Upstream's appState was @EnvironmentObject (never in the memberwise
    // init); our 8a rebind made `service` an injected @ObservedObject, and
    // `private` dragged the synthesized init to private — inaccessible across
    // files. Explicit init, same defaults, access repaired, behavior identical.
    init(service: RemoteService,
         onManualLogin: @escaping () -> Void = {},
         onQRCodeLogin: @escaping () -> Void = {},
         onLocalEntry: @escaping () -> Void = {}) {
        self.service = ObservedObject(wrappedValue: service)
        self.onManualLogin = onManualLogin
        self.onQRCodeLogin = onQRCodeLogin
        self.onLocalEntry = onLocalEntry
    }

    var body: some View {
        NavigationStack {
            AuthWelcomeLayout {
                AuthBrandLockup()

                VStack(spacing: 12) {
                    AuthPrimaryButton(title: String(localized: "QR Code Login"), systemImage: "qrcode.viewfinder") {
                        onQRCodeLogin()
                    }

                    AuthGlassButton(String(localized: "Manual Login"), systemImage: "link") {
                        onManualLogin()
                    }

                    Button(action: onLocalEntry) {
                        Text(String(localized: "Use local AI directly"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
                .frame(maxWidth: 340)

                if let error = service.authErrorText {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }
            }
            .navigationTitle("")
            .safeAreaInset(edge: .bottom) {
                Button(String(localized: "privacyPolicy.title")) { showsPrivacyPolicy = true }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 24)
                    .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showsPrivacyPolicy) {
            PrivacyPolicySheet()
        }
    }
}


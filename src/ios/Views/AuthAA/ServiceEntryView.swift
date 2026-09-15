import SwiftUI
import RemoteKit

struct ServiceEntryView: View {
    @ObservedObject private var service: RemoteService
    @State private var showsPrivacyPolicy = false
    var onManualLogin: () -> Void = {}
    var onQRCodeLogin: () -> Void = {}
    /// JO-6（首启入口终案）：直接用本地，灰字小按钮不抢两颗登录 CTA。
    var onLocalEntry: () -> Void = {}

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


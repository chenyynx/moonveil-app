import SwiftUI
import UIKit

struct ManualLoginView: View {
    @ObservedObject var service: RemoteService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var oauthLogin = OAuthLoginCoordinator()
    @State private var path: [ServerLoginRoute] = []
    @State private var isClosing = false
    @State private var loginRequest: WebLoginRequest?
    @State private var statusMessage: String?
    @State private var alertMessage: String?
    @State private var alertTitle = String(localized: "Sign In Failed")
    /// [AUTH-LOG 2026-09-27] 这条链路此前 0 日志，静默退回无从定位。
    private let log = AppLogger(category: "AuthAA")

    private static let cloudServer = "https://web.agents-anywhere.com"

    var onDashboardRequested: () -> Void = {}

    var body: some View {
        NavigationStack(path: $path) {
            AuthScreen(title: String(localized: "Manual Login"), onCancel: close) {
                VStack(spacing: 16) {
                    AuthPrimaryButton(
                        title: String(localized: "Connect to Anywhere Cloud"),
                        systemImage: "cloud",
                        isLoading: isSigningIn,
                        disabled: isSigningIn,
                    ) {
                        startSignIn(server: Self.cloudServer)
                    }

                    AuthGlassButton(String(localized: "Connect to your self-hosted instance"), systemImage: "server.rack") {
                        statusMessage = nil
                        path.append(.selfHosted)
                    }
                    .disabled(isSigningIn)

                    loginStatus
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .navigationDestination(for: ServerLoginRoute.self) { route in
                switch route {
                case .selfHosted:
                    ServerAddressView(
                        isSigningIn: isSigningIn,
                        onCancel: close,
                        onConnect: { startSignIn(server: $0) },
                    ) {
                        loginStatus
                    }
                case .success:
                    AuthResultView(
                        title: String(localized: "Login Success"),
                        message: String(localized: "Your iPhone is signed in. Go to your dashboard to continue."),
                        buttonTitle: String(localized: "Go to Dashboard"),
                        buttonSystemImage: "arrow.right",
                        symbolName: "checkmark.circle.fill",
                        symbolColor: .green,
                        isLoading: isClosing,
                    ) {
                        guard !isClosing else { return }
                        isClosing = true
                        onDashboardRequested()
                    }
                    .navigationBarBackButtonHidden(true)
                }
            }
        }
        .task(id: loginRequest?.id) {
            if let request = loginRequest { await signIn(request) }
        }
        .onChange(of: path) { previous, next in
            if next.count < previous.count {
                cancelSignIn("path-pop")
                statusMessage = nil
            }
        }
        .onDisappear { cancelSignIn("onDisappear") }
        .alert(alertTitle, isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } },
        )) {
            if service.needsLocalNetworkSettings {
                Button(String(localized: "Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? String(localized: "The server could not be reached."))
        }
        .appSheetPresentation(.compact)
    }

    private var isSigningIn: Bool { loginRequest != nil }

    @ViewBuilder private var loginStatus: some View {
        if isSigningIn {
            Button(String(localized: "Cancel Sign In")) { cancelSignIn("user-tap") }
                .font(.subheadline)
        }
        if let statusMessage { Text(statusMessage).font(.footnote).foregroundStyle(.secondary) }
    }

    private func startSignIn(server: String) {
        guard loginRequest == nil else { return }
        statusMessage = nil
        alertMessage = nil
        loginRequest = WebLoginRequest(server: server)
    }

    private func cancelSignIn(_ reason: String) {
        log.warning("cancelSignIn(\(reason)) — aborting any in-flight auth")
        loginRequest = nil
        oauthLogin.cancel()
    }

    private func close() {
        cancelSignIn("close")
        dismiss()
    }

    private func signIn(_ request: WebLoginRequest) async {
        // Snapshot the chosen server. Closing, going Back, or starting another
        // attempt invalidates late results before they can open a browser.
        defer { if loginRequest?.id == request.id { loginRequest = nil } }
        log.info("signIn begin: \(request.server)")
        guard let url = await service.checkServer(request.server) else {
            guard isCurrent(request) else { return }
            log.warning("checkServer failed: \(service.authErrorText ?? "unknown")")
            alertTitle = service.needsLocalNetworkSettings ? String(localized: "Local Network Access") : String(localized: "Server Unavailable")
            alertMessage = service.authErrorText ?? String(localized: "The server could not be reached.")
            return
        }
        guard isCurrent(request) else { return }
        do {
            let token = try await oauthLogin.authenticate(serverURL: url)
            log.info("oauth authenticate returned")
            guard isCurrent(request) else {
                log.warning("result dropped — request superseded or cancelled")
                return
            }
            await service.completeManualLogin(serverURL: url, token: token)
            guard isCurrent(request) else { return }
            if service.authErrorText == nil, service.profile != nil {
                log.info("manual login complete")
                path.append(.success)
            } else {
                log.error("completeManualLogin failed: \(service.authErrorText ?? "unknown")")
                alertTitle = String(localized: "Sign In Failed"); alertMessage = service.authErrorText ?? String(localized: "The login could not be completed.")
            }
        } catch is CancellationError {
            log.warning("signIn: CancellationError — task/session cancelled mid-flight (silent branch)")
        } catch OAuthLoginError.cancelled {
            log.warning("signIn: OAuthLoginError.cancelled (canceledLogin or access_denied)")
            if isCurrent(request) { statusMessage = OAuthLoginError.cancelled.localizedDescription }
        } catch {
            log.error("signIn failed: \(error.localizedDescription)")
            guard isCurrent(request) else {
                log.warning("error dropped — request superseded or cancelled")
                return
            }
            alertTitle = String(localized: "Sign In Failed"); alertMessage = error.localizedDescription
        }
    }

    private func isCurrent(_ request: WebLoginRequest) -> Bool {
        !Task.isCancelled && loginRequest?.id == request.id
    }
}

private struct WebLoginRequest {
    let id = UUID()
    let server: String
}

private enum ServerLoginRoute: Hashable {
    case selfHosted
    case success
}

private struct ServerAddressView<Status: View>: View {
    let isSigningIn: Bool
    let onCancel: () -> Void
    let onConnect: (String) -> Void
    @ViewBuilder let status: Status
    @State private var serverText = ""

    var body: some View {
        AuthScreen(
            title: String(localized: "Enter Server"),
            subtitle: String(localized: "Enter your server address, then sign in with the server's web login."),
            onCancel: onCancel,
        ) {
            VStack(alignment: .leading, spacing: 16) {
                UnderlinedTextField(
                    placeholder: "https://your-server.example.com",
                    text: $serverText,
                    keyboardType: .URL,
                    textContentType: .URL,
                    submitLabel: .continue,
                    onSubmit: connect,
                )
                .disabled(isSigningIn)

                AuthPrimaryButton(
                    title: String(localized: "Continue in Browser"),
                    isLoading: isSigningIn,
                    disabled: !canContinue,
                    action: connect,
                )

                status
                Text(String(localized: "The server login opens in a secure web session. You can use password login or any OAuth provider configured on that server."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var canContinue: Bool {
        !isSigningIn && !serverText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func connect() {
        guard canContinue else { return }
        onConnect(serverText)
    }
}


private struct UnderlinedTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var submitLabel: SubmitLabel = .done
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .textInputAutocapitalization(.never)
            .keyboardType(keyboardType)
            .autocorrectionDisabled()
            .textContentType(textContentType)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
            .font(.title3)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Divider()
            }
    }
}

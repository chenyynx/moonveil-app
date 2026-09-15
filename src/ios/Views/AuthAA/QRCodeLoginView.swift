import SwiftUI
import RemoteKit

struct QRCodeLoginView: View {
    @ObservedObject var service: RemoteService
    @Environment(\.dismiss) private var dismiss
    @State private var path: [QRLoginRoute] = []
    @State private var isClosing = false

    var onDashboardRequested: () -> Void = {}

    var body: some View {
        NavigationStack(path: $path) {
            QRScanStepView(
                service: service,
                onCancel: { dismiss() },
                onPayload: { payload in
                    path.append(.confirm(payload))
                },
            )
            .navigationDestination(for: QRLoginRoute.self) { route in
                switch route {
                case let .confirm(payload):
                    QRConfirmStepView(
                        service: service,
                        payload: payload,
                        onCancel: { dismiss() },
                        onWaiting: {
                            path.append(.waiting(payload))
                        },
                    )
                case let .waiting(payload):
                    QRWaitingStepView(
                        service: service,
                        payload: payload,
                        onCancel: { dismiss() },
                        onSignedIn: {
                            path.append(.success)
                        },
                    )
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
        .appSheetPresentation(.expanded)
    }
}

private enum QRLoginRoute: Hashable {
    case confirm(RemotePairingPayload)
    case waiting(RemotePairingPayload)
    case success
}

private struct QRScanStepView: View {
    @ObservedObject var service: RemoteService
    @Environment(\.colorScheme) private var colorScheme

    let onCancel: () -> Void
    let onPayload: (RemotePairingPayload) -> Void

    @State private var parseError: String?
    @State private var didReadPayload = false

    var body: some View {
        AuthScreen(
            title: String(localized: "QR Code Login"),
            subtitle: String(localized: "Scan the login QR code from the web console."),
            onCancel: onCancel,
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .bottom) {
                    QRCodeScannerView(
                        onCode: { value in
                            guard !didReadPayload else { return }
                            parsePayload(value)
                        },
                        onError: { message in
                            parseError = message
                        },
                    )
                    .frame(height: 380)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

                    Text(String(localized: "Point the camera at the web QR code"))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(AppTheme.glassScrim(colorScheme), in: Capsule())
                        .modifier(GlassCapsuleIfAvailable())
                        .padding(.bottom, 18)
                }

                if let parseError {
                    Text(parseError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = service.authErrorText {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func parsePayload(_ value: String) {
        parseError = nil
        // Type/version gate + field validation live in RemotePairingPayload.init
        // (the official MobileLoginPayload wire contract, verbatim constants).
        guard let decoded = RemotePairingPayload(qrJSON: Data(value.utf8)) else {
            parseError = String(localized: "This QR code is not a valid Moonveil login code.")
            return
        }
        didReadPayload = true
        onPayload(decoded)
    }
}

private struct QRConfirmStepView: View {
    @ObservedObject var service: RemoteService
    @Environment(\.colorScheme) private var colorScheme

    let payload: RemotePairingPayload
    let onCancel: () -> Void
    let onWaiting: () -> Void

    @State private var isRequesting = false
    @State private var alertMessage: String?
    @State private var requestTask: Task<Void, Never>?

    var body: some View {
        AuthScreen(
            title: String(localized: "Confirm Login"),
            subtitle: String(localized: "Do you want to sign in as \(payload.userId)?"),
            onCancel: onCancel,
        ) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Server"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(payload.webUrl)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.groupedFill(colorScheme), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .modifier(GlassRounded28IfAvailable())

                AuthPrimaryButton(
                    title: String(localized: "Log In"),
                    isLoading: isRequesting,
                ) {
                    requestTask = Task { await requestWebConfirmation() }
                }
            }
        }
        .onDisappear { requestTask?.cancel(); requestTask = nil }
        .alert(String(localized: "Login Request Failed"), isPresented: Binding(
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
            Text(alertMessage ?? String(localized: "The login request could not be started."))
        }
    }

    private func requestWebConfirmation() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        if await service.requestPairing(payload: payload, deviceName: UIDevice.current.name) {
            if !Task.isCancelled { onWaiting() }
        } else if !Task.isCancelled {
            alertMessage = service.authErrorText ?? String(localized: "The login request could not be started.")
        }
    }
}

private struct QRWaitingStepView: View {
    @ObservedObject var service: RemoteService
    @Environment(\.colorScheme) private var colorScheme

    let payload: RemotePairingPayload
    let onCancel: () -> Void
    let onSignedIn: () -> Void

    @State private var statusText = String(localized: "Waiting for confirmation")
    @State private var isFinishing = false
    @State private var alertMessage: String?
    @State private var pollingTask: Task<Void, Never>?

    var body: some View {
        AuthScreen(
            title: String(localized: "Confirm on Web"),
            subtitle: String(localized: "Click confirm in the web console, then return here."),
            showsCancel: !isFinishing,
            onCancel: onCancel,
        ) {
            VStack(spacing: 24) {
                AppSymbol("desktopcomputer.and.arrow.down", size: 58)
                    .foregroundStyle(AppTheme.primaryText(colorScheme))

                Text(statusText)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                ProgressView()
                    .controlSize(.large)
                    .tint(AppTheme.primaryText(colorScheme))
                    .padding(.top, 4)
            }
            .padding(.vertical, 24)
        }
        .onAppear {
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
        .navigationBarBackButtonHidden(isFinishing)
        .alert(String(localized: "Login Status"), isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } },
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? String(localized: "Confirm the login on the web console and try again."))
        }
    }

    private func startPolling() {
        stopPolling()
        statusText = String(localized: "Waiting for confirmation")
        pollingTask = Task {
            while !Task.isCancelled {
                let shouldContinue = await pollApprovalOnce()
                if !shouldContinue {
                    return
                }
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    @MainActor
    private func pollApprovalOnce() async -> Bool {
        guard let status = await service.pairingStatus(payload: payload) else {
            alertMessage = service.authErrorText ?? String(localized: "Could not check the login status.")
            return false
        }

        switch status.status {
        case "approved":
            await finishLogin()
            return false
        case "pending_web_confirm":
            statusText = String(localized: "Waiting for confirmation")
            return true
        case "rejected":
            alertMessage = String(localized: "This login request was rejected.")
            return false
        case "expired":
            alertMessage = String(localized: "This login request expired. Scan a new QR code.")
            return false
        case "consumed":
            alertMessage = String(localized: "This login request has already been used.")
            return false
        default:
            alertMessage = String(localized: "Current login status: \(status.status)")
            return false
        }
    }

    private func finishLogin() async {
        guard !isFinishing else { return }
        isFinishing = true
        await service.completePairing(payload: payload)
        if service.profile != nil {
            onSignedIn()
        } else {
            isFinishing = false
            alertMessage = service.authErrorText ?? String(localized: "The login could not be completed.")
        }
    }
}


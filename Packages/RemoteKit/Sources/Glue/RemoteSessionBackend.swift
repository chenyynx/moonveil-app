import Foundation
import Combine

/// Composition root for the remote line: holds official AAV2 clients, nothing else.
/// Zero state duplication — sessions/timelines live server-side; the only
/// mutable Glue state is the connection phase + the clients themselves.
@MainActor
final class RemoteSessionBackend: ObservableObject, RemoteSessionServing {

    @Published private(set) var connectionState: RemoteConnectionState = .idle

    /// Identity carried on every realtime ticket (official clientId field).
    let clientId: String

    // Official pieces — created lazily per phase, never mirrored.
    private var authClient: APIClient?
    private var tokenProvider: MutableAuthTokenProvider?
    private var api: V2APIClient?
    private var creationService: V2SessionCreationService?
    private var lastServerURL: URL?

    init(clientId: String = UUID().uuidString) {
        self.clientId = clientId
    }

    // MARK: - Phase 0/1: configure + pairing

    func configure(serverURL: URL) {
        authClient = APIClient(serverURL: serverURL)
        lastServerURL = serverURL
        connectionState = .pairing
    }

    func beginPairing(deviceName: String, payload: MobileLoginPayload) async throws -> MobileLoginStatusResponse {
        try await requireAuth().requestMobileLogin(payload: payload, deviceName: deviceName)
    }

    func pollPairing(payload: MobileLoginPayload) async throws -> MobileLoginStatusResponse {
        try await requireAuth().mobileLoginStatus(payload: payload)
    }

    func completePairing(payload: MobileLoginPayload) async throws {
        let exchange = try await requireAuth().exchangeMobileLogin(payload: payload)
        bootstrap(serverURL: try requireServerURL(), accessToken: exchange.auth.accessToken)
    }

    // MARK: - Phase 2: bootstrap (also the re-auth path)

    func bootstrap(serverURL: URL, accessToken: String) {
        let provider = MutableAuthTokenProvider(token: accessToken)
        let client = V2APIClient(serverURL: serverURL, tokenProvider: provider)
        tokenProvider = provider
        api = client
        creationService = V2SessionCreationService(sessionAPI: client.sessions)
        lastServerURL = serverURL
        connectionState = .ready
    }

    /// Rotate the access token without tearing down clients (official
    /// MutableAuthTokenProvider semantics: refresh never resets repos/drafts).
    func updateToken(_ accessToken: String) {
        tokenProvider?.update(accessToken)
    }

    // MARK: - Session lifecycle (thin pass-throughs)

    func startSession(
        connectorId: V2ConnectorID,
        projectId: String,
        runtime: V2RuntimeID,
        runtimeId: V2RuntimeID?,
        title: String?,
        cwd: String?,
        content: String,
        clientMessageId: String
    ) async throws -> V2SessionCreateResponse {
        try await requireCreation().createAndStart(
            connectorId: connectorId,
            projectId: projectId,
            runtime: runtime,
            runtimeId: runtimeId,
            title: title,
            cwd: cwd,
            content: content,
            selections: [:],
            attachments: [],
            clientMessageId: clientMessageId
        )
    }

    func send(sessionId: V2SessionID, content: String, clientMessageId: String) async throws -> V2RuntimeActionResponse {
        try await requireAPI().runtime.sendMessage(
            sessionId: sessionId,
            request: V2RuntimeMessageSendRequest(content: content, attachments: [], clientMessageId: clientMessageId)
        )
    }

    @discardableResult
    func interrupt(sessionId: V2SessionID) async throws -> V2RuntimeActionResponse {
        try await requireAPI().runtime.interrupt(sessionId: sessionId)
    }

    // MARK: - Out-seam: events + recovery

    func events(sessionId: V2SessionID) async throws -> AsyncThrowingStream<V2SessionEvent, Error> {
        let ticket = try await requireAPI().realtime.ticket(clientId: clientId, scope: .session(sessionId))
        return try requireAPI().realtime.sessionEvents(sessionId: sessionId, ticket: ticket.ticket)
    }

    func recover(sessionId: V2SessionID, after cursor: String) async throws -> V2EventRecoveryResponse {
        try await requireAPI().realtime.recover(sessionId: sessionId, after: cursor)
    }

    // MARK: - Notices

    func noticeSnapshot(sessionId: V2SessionID) async throws -> V2RuntimeNoticeSnapshot {
        try await requireAPI().runtime.notices(sessionId: sessionId)
    }

    func respondToNotice(
        sessionId: V2SessionID,
        noticeId: V2NoticeID,
        request: V2RuntimeNoticeRespondRequest
    ) async throws -> V2RuntimeActionResponse {
        try await requireAPI().runtime.respondToNotice(
            sessionId: sessionId, noticeId: noticeId, request: request
        )
    }

    // MARK: - Reset

    func reset() {
        // Zero the token before dropping refs (best effort; the provider is
        // the only holder of the secret inside this module).
        tokenProvider?.update(nil)
        authClient = nil
        tokenProvider = nil
        api = nil
        creationService = nil
        connectionState = .idle
    }

    // MARK: - Guards

    private func requireAuth() throws -> APIClient {
        guard let authClient else { throw RemoteBackendError.notConfigured }
        return authClient
    }

    private func requireServerURL() throws -> URL {
        guard let lastServerURL else { throw RemoteBackendError.notConfigured }
        return lastServerURL
    }

    private func requireAPI() throws -> V2APIClient {
        guard case .ready = connectionState, let api else { throw RemoteBackendError.notReady }
        return api
    }

    private func requireCreation() throws -> V2SessionCreationService {
        guard let creationService else { throw RemoteBackendError.notReady }
        return creationService
    }
}

enum RemoteBackendError: Error, LocalizedError {
    case notConfigured
    case notReady

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Remote backend: no server configured"
        case .notReady:      return "Remote backend: not paired yet"
        }
    }
}

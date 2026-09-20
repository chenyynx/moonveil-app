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
        profile = try? await fetchProfile()   // upstream gate: me != nil means signed in
    }

    private(set) var profile: AuthMe?

    // MARK: - Phase 2: bootstrap (also the re-auth path)

    func bootstrap(serverURL: URL, accessToken: String) {
        // Official persistence: keychain "accessToken" + UserDefaults server
        // (AppState tokenAccount/serverDefaultsKey), so restoreSession works
        // across launches. KeychainStore is the verbatim official service.
        try? keychain.saveString(accessToken, account: Self.tokenAccount)
        UserDefaults.standard.set(serverURL.absoluteString, forKey: Self.serverDefaultsKey)
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
        lastAccessToken = accessToken
    }

    /// In-memory only (D3): kept so `me()` can be re-fetched after exchange;
    /// never written to disk here — persistence is the app's KeychainStore call.
    private(set) var lastAccessToken: String?

    /// Official checkServer chain (AppState.swift:147-157 verbatim semantics):
    /// LocalNetworkAccess.prepare → health → authConfig. Throws like upstream so
    /// the facade can set needsLocalNetworkSettings on permission denial.
    func probeServer(_ url: URL) async throws {
        try await LocalNetworkAccess.prepare(for: url)
        let client = APIClient(serverURL: url)
        _ = try await client.health()
        _ = try await client.authConfig()
    }

    /// Official /auth/me with the in-memory token (profile mirror for the UI).
    func fetchProfile() async throws -> AuthMe {
        guard let token = lastAccessToken else { throw RemoteBackendError.notReady }
        return try await requireAuth().me(token: token)
    }

    func fetchProfile(serverURL: URL, accessToken: String) async throws -> AuthMe {
        try await APIClient(serverURL: serverURL).me(token: accessToken)
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

    // New-session drawer lists: thin pass-throughs, no local cache — the
    // server is the single source of truth for inventory (same rule as above).

    func listConnectors() async throws -> V2ConnectorListResponse {
        try await requireAPI().connectors.listConnectors()
    }

    func listProjects() async throws -> V2ProjectListResponse {
        try await requireAPI().projects.list()
    }

    // Session reads: dashboard list (archived split + paging), meta, bulk actions.
    func listSessions(archived: Bool, cursor: String?) async throws -> V2SessionListResponse {
        try await requireAPI().sessions.listSessions(archived: archived, cursor: cursor)
    }
    func sessionInventory() async throws -> V2SessionInventoryResponse {
        try await requireAPI().sessions.sessionInventory()
    }
    func sessionMeta(sessionId: V2SessionID) async throws -> V2SessionMetaResponse {
        try await requireAPI().sessions.sessionMeta(sessionId: sessionId)
    }
    func patchSessionMeta(sessionId: V2SessionID, request: V2SessionMetaPatchRequest) async throws -> V2SessionMetaResponse {
        try await requireAPI().sessions.patchSessionMeta(sessionId: sessionId, request: request)
    }
    func markRead(sessionIds: [V2SessionID]) async throws -> V2SessionBulkActionResponse {
        try await requireAPI().sessions.markRead(sessionIds: sessionIds)
    }
    func archive(sessionIds: [V2SessionID]) async throws -> V2SessionBulkActionResponse {
        try await requireAPI().sessions.archive(sessionIds: sessionIds)
    }
    func unarchive(sessionIds: [V2SessionID]) async throws -> V2SessionBulkActionResponse {
        try await requireAPI().sessions.unarchive(sessionIds: sessionIds)
    }
    func listProjectSessions(projectId: String, archived: Bool, cursor: String?) async throws -> V2SessionListResponse {
        try await requireAPI().projects.sessions(projectId, archived: archived, cursor: cursor)
    }

    // Workspace files: one directory listing through the connector RPC boundary
    // （官方 V2WorkspaceFilesService.directory 同款；home 解析与目录浏览共用）。
    func workspaceDirectory(connectorId: V2ConnectorID, root: String, path: String) async throws -> V2WorkspaceDirectoryResponse {
        try await requireAPI().connectors.listWorkspaceFiles(
            connectorId: connectorId,
            request: V2WorkspaceFilesListRequest(root: root, path: path)
        )
    }

    // Project creation（官方 V2WorkspaceProjectResolver 的创建步）。
    func createProject(name: String, connectorId: V2ConnectorID, workspacePath: String, manuallyCreated: Bool) async throws -> V2ProjectResponse {
        try await requireAPI().projects.create(V2ProjectCreateRequest(
            name: name, connectorId: connectorId, workspacePath: workspacePath, manuallyCreated: manuallyCreated
        ))
    }

    func runtimeTypes(connectorId: V2ConnectorID) async throws -> V2RuntimeTypeListResponse {
        try await requireAPI().connectors.runtimeTypes(connectorId: connectorId)
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

    static let tokenAccount = "accessToken"                 // upstream AppState:51
    static let serverDefaultsKey = "agentsAnywhere.serverURL"  // upstream AppState:50 (verified)
    private let keychain = KeychainStore()

    /// Upstream restoreSession semantics (AppState:75-83): stored server +
    /// keychain token ⇒ re-bootstrap silently; missing either ⇒ stay signed out.
    static func restore() -> (URL, String)? {
        guard let serverValue = UserDefaults.standard.string(forKey: serverDefaultsKey),
              let url = URL(string: serverValue),
              let token = try? KeychainStore().readString(account: tokenAccount),
              !token.isEmpty else { return nil }
        return (url, token)
    }

    func forgetSession() {
        // upstream logout: keychain delete (AppState:656); we also drop our
        // RemoteRootView mirror key so the guide shows fresh.
        try? keychain.delete(account: Self.tokenAccount)
        UserDefaults.standard.removeObject(forKey: Self.serverDefaultsKey)
        UserDefaults.standard.removeObject(forKey: "remote.serverURL")
    }

    func reset() {
        // Zero the token before dropping refs (best effort; the provider is
        // the only holder of the secret inside this module).
        tokenProvider?.update(nil)
        authClient = nil
        tokenProvider = nil
        api = nil
        creationService = nil
        profile = nil
        lastAccessToken = nil
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

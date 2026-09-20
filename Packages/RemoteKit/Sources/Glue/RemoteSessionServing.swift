import Foundation
import Combine

// Glue — the only seam layer of RemoteKit (D4 §white-list; JO ledger items).
// NOTE (batch5, 2026-09-15): everything here is intentionally `internal`.
// AAV2 frozen types are internal (upstream app-target code, verbatim zone —
// we never edit them), so no public surface may carry them across the module
// boundary. App integration (batch6) will expose a public facade with
// Glue-owned value types (String ids / JSON passthrough per the D1
// no-second-schema rule). Until then this file's job is to prove the official
// pieces compose.

/// U2 connection state matrix, runtime projection for one remote account.
/// `degraded` carries a human-readable reason; UI maps it to the yellow state.
enum RemoteConnectionState: Equatable {
    case idle        // no serverURL configured
    case pairing     // APIClient live, awaiting mobile-login exchange
    case ready       // V2APIClient bootstrapped with a token
    case degraded(String)
}

/// The remote half of the SessionBackend seam (D4's single fork).
/// Vocabulary is 1:1 with official AA request/response types — Glue must never
/// invent a parallel schema (双事实源禁令, D1/D2 纲).
@MainActor
protocol RemoteSessionServing: AnyObject {
    var connectionState: RemoteConnectionState { get }

    /// Phase 0: point the backend at a server (ours or self-hosted).
    func configure(serverURL: URL)

    /// QR pairing trio (official /auth/mobile-login flow).
    func beginPairing(deviceName: String, payload: MobileLoginPayload) async throws -> MobileLoginStatusResponse
    func pollPairing(payload: MobileLoginPayload) async throws -> MobileLoginStatusResponse
    /// Completes pairing: exchanges the scan payload for tokens and bootstraps V2.
    func completePairing(payload: MobileLoginPayload) async throws

    /// Direct bootstrap for an already-held access token (self-host / re-auth).
    func bootstrap(serverURL: URL, accessToken: String)

    /// One-shot profile fetch with an EXPLICIT server+token, no engine state
    /// required (upstream completeOAuthLogin: client = APIClient(serverURL);
    /// client.me(token:)). Used by the manual OAuth login completion path.
    func fetchProfile(serverURL: URL, accessToken: String) async throws -> AuthMe

    /// Session lifecycle — thin pass-throughs onto official services.
    @discardableResult
    func startSession(
        connectorId: V2ConnectorID,
        projectId: String,
        runtime: V2RuntimeID,
        runtimeId: V2RuntimeID?,
        title: String?,
        cwd: String?,
        content: String,
        clientMessageId: String,
        selections: [V2RuntimeSelectionScope: V2SelectionID],
        attachments: [V2LocalAttachment]
    ) async throws -> V2SessionCreateResponse

    @discardableResult
    func send(sessionId: V2SessionID, content: String, clientMessageId: String) async throws -> V2RuntimeActionResponse
    @discardableResult
    func interrupt(sessionId: V2SessionID) async throws -> V2RuntimeActionResponse

    /// Out-seam: live events + gap recovery (official WS ticket + HTTP recovery).
    func events(sessionId: V2SessionID) async throws -> AsyncThrowingStream<V2SessionEvent, Error>
    func recover(sessionId: V2SessionID, after cursor: String) async throws -> V2EventRecoveryResponse

    /// Notices (approvals/questions) — official catalog passthroughs.
    func noticeSnapshot(sessionId: V2SessionID) async throws -> V2RuntimeNoticeSnapshot
    @discardableResult
    func respondToNotice(
        sessionId: V2SessionID,
        noticeId: V2NoticeID,
        request: V2RuntimeNoticeRespondRequest
    ) async throws -> V2RuntimeActionResponse

    /// Logout-equivalent: drop all in-memory clients/tokens (D3: cache wipe is a separate call).
    func reset()
}

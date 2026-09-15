import Foundation
import Combine

// ════════════════════════════════════════════════════════════════════
// PUBLIC SURFACE (batch6) — what the app sees via `import RemoteKit`.
// AAV2 frozen types stay internal-by-design (claudio precedent: same-module
// compilation); everything crossing this line is Glue-owned: String ids
// (official V2*ID typealiases ARE String) + wire payloads as JSON Data
// passthrough (D1 不发明第二 schema).
// Staging with deadlines (完整性铁律): notices / steer / timeline-page public
// methods land with batch7 (审批 UI) — engine already serves them internally.
// No stubs, no fake returns: every method delegates to the real engine.
// ════════════════════════════════════════════════════════════════════

/// Public mirror of RemoteConnectionState (app never imports internal types).
public enum RemoteServiceState: Equatable {
    case idle
    case pairing
    case ready
    case degraded(String)
}

public enum RemoteServiceError: Error, LocalizedError {
    case notConfigured
    case notReady
    case rejected(code: String?, message: String)
    case transport(Error)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:        return "Remote: no server configured"
        case .notReady:             return "Remote: not paired yet"
        case .rejected(_, let m):   return m
        case .transport(let e):     return e.localizedDescription
        }
    }
}

/// /auth/mobile-login status — official string status verbatim (UI interprets
/// the documented values; Glue must not re-encode enums the server owns).
public struct RemotePairingStatus: Sendable {
    public let status: String
    public let deviceName: String?
    public let expiresAt: String?
}

/// One live realtime event: official envelope fields + payload as raw JSON.
public struct RemoteWireEvent: Sendable {
    public let eventId: String
    public let sequence: Int
    public let cursor: String
    public let type: String
    public let sessionId: String
    public let emittedAt: String
    public let payloadJSON: Data
}

/// Gap-recovery page (official snapshotRequired semantics verbatim).
public struct RemoteRecovery: Sendable {
    public let events: [RemoteWireEvent]
    public let nextCursor: String
    public let snapshotRequired: Bool
}

public struct RemoteSessionCreated: Sendable {
    public let sessionId: String
    /// V2SessionMeta re-encoded verbatim (Codable passthrough).
    public let sessionMetaJSON: Data
}

// MARK: - Notices public surface (batch7 promise — delivered with the shell)

public struct RemoteNoticeActionInput: Sendable {
    public let required: Bool
    public let schemaJSON: Data?
    public let uiSchemaJSON: Data?
}

public struct RemoteNoticeAction: Sendable, Identifiable {
    public let id: String          // official actionId
    public let label: String
    public let style: String?
    public let input: RemoteNoticeActionInput
}

public struct RemoteNotice: Sendable, Identifiable {
    public let id: String          // official noticeId
    public let sessionId: String
    public let type: String
    public let title: String
    public let message: String?
    public let severity: String
    public let status: String      // official V2RuntimeNoticeStatus rawValue verbatim
    public let responseRequired: Bool
    public let actions: [RemoteNoticeAction]
    public let revision: Int
    public let expiresAt: String?
    /// Full wire object (official `raw` JSONValue re-encoded). Anything beyond
    /// the typed fields (blocking/context/metadata) stays reachable here —
    /// D2: no invented second schema, this IS the payload.
    public let rawJSON: Data
}

@MainActor
public final class RemoteService: ObservableObject {

    @Published public private(set) var state: RemoteServiceState = .idle

    private let engine: RemoteSessionBackend
    private let encoder = JSONEncoder()

    public init(clientId: String = UUID().uuidString) {
        engine = RemoteSessionBackend(clientId: clientId)
    }

    // MARK: Wiring (engine observation without exposing internal types)

    /// Poll-free state sync helper: engine state is @Published; we mirror on
    /// every public mutation point rather than importing Combine plumbing.
    private func syncState() {
        switch engine.connectionState {
        case .idle:             state = .idle
        case .pairing:          state = .pairing
        case .ready:            state = .ready
        case .degraded(let r):  state = .degraded(r)
        }
    }

    // MARK: Configure + pairing

    public func configure(serverURL: URL) {
        engine.configure(serverURL: serverURL)
        syncState()
    }

    /// qrJSON = the scanned QR payload, decoded into the official MobileLoginPayload.
    public func beginPairing(qrJSON: Data, deviceName: String) async throws -> RemotePairingStatus {
        let payload = try decodePayload(qrJSON)
        let r = try await attempt { try await self.engine.beginPairing(deviceName: deviceName, payload: payload) }
        syncState()
        return .init(status: r.status, deviceName: r.deviceName, expiresAt: r.expiresAt)
    }

    public func pollPairing(qrJSON: Data) async throws -> RemotePairingStatus {
        let payload = try decodePayload(qrJSON)
        let r = try await attempt { try await self.engine.pollPairing(payload: payload) }
        return .init(status: r.status, deviceName: r.deviceName, expiresAt: r.expiresAt)
    }

    /// Completes the trio; on success the service is .ready (tokens memory-only).
    public func completePairing(qrJSON: Data) async throws {
        let payload = try decodePayload(qrJSON)
        try await attempt { try await self.engine.completePairing(payload: payload) }
        syncState()
    }

    /// Re-auth / self-host path with an already-held access token.
    public func bootstrap(serverURL: URL, accessToken: String) {
        engine.bootstrap(serverURL: serverURL, accessToken: accessToken)
        syncState()
    }

    public func updateToken(_ accessToken: String) { engine.updateToken(accessToken) }

    // MARK: Session round-trip

    @discardableResult
    public func startSession(
        connectorId: String,
        projectId: String,
        runtime: String,
        runtimeId: String? = nil,
        title: String? = nil,
        cwd: String? = nil,
        content: String,
        clientMessageId: String
    ) async throws -> RemoteSessionCreated {
        let r = try await attempt {
            try await self.engine.startSession(
                connectorId: connectorId, projectId: projectId,
                runtime: runtime, runtimeId: runtimeId,
                title: title, cwd: cwd,
                content: content, clientMessageId: clientMessageId
            )
        }
        return .init(sessionId: r.session.id, sessionMetaJSON: try encode(r.session))
    }

    /// Returns the official action `result` payload verbatim (JSON passthrough);
    /// throws .rejected when the server did not accept the operation.
    @discardableResult
    public func send(sessionId: String, content: String, clientMessageId: String) async throws -> Data {
        let r = try await attempt {
            try await self.engine.send(sessionId: sessionId, content: content, clientMessageId: clientMessageId)
        }
        return try absorb(r)
    }

    @discardableResult
    public func interrupt(sessionId: String) async throws -> Data {
        try absorb(try await attempt { try await self.engine.interrupt(sessionId: sessionId) })
    }

    // MARK: Out-seam

    public func events(sessionId: String) async throws -> AsyncThrowingStream<RemoteWireEvent, Error> {
        let upstream = try await attempt { try await self.engine.events(sessionId: sessionId) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await e in upstream {
                        continuation.yield(try RemoteWireEvent(from: e, encoder: self.encoder))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func recover(sessionId: String, after cursor: String) async throws -> RemoteRecovery {
        let r = try await attempt { try await self.engine.recover(sessionId: sessionId, after: cursor) }
        return .init(
            events: try r.events.map { try RemoteWireEvent(from: $0, encoder: self.encoder) },
            nextCursor: r.nextCursor,
            snapshotRequired: r.snapshotRequired
        )
    }

    // MARK: Notices (batch7)

    public func noticeSnapshot(sessionId: String) async throws -> [RemoteNotice] {
        let snap = try await attempt { try await self.engine.noticeSnapshot(sessionId: sessionId) }
        return try snap.notices.map { try self.mapNotice($0) }
    }

    /// actionId/input mirror the official V2RuntimeNoticeRespondRequest exactly
    /// (input = raw JSON, decoded into the official JSONValue — passthrough).
    public func respondToNotice(sessionId: String, noticeId: String,
                                actionId: String, inputJSON: Data?) async throws -> Data {
        let input = try inputJSON.map { try JSONDecoder().decode(JSONValue.self, from: $0) }
        let req = V2RuntimeNoticeRespondRequest(actionId: actionId, input: input)
        return try absorb(try await attempt {
            try await self.engine.respondToNotice(sessionId: sessionId, noticeId: noticeId, request: req)
        })
    }

    private func mapNotice(_ n: V2RuntimeNotice) throws -> RemoteNotice {
        RemoteNotice(
            id: n.noticeId, sessionId: n.sessionId, type: n.type,
            title: n.title, message: n.message, severity: n.severity,
            status: n.status.rawValue, responseRequired: n.responseRequired,
            actions: n.actions.map { a in
                RemoteNoticeAction(
                    id: a.actionId, label: a.label, style: a.style,
                    input: RemoteNoticeActionInput(
                        required: a.input.required,
                        schemaJSON: try? a.input.schema.map { try self.encoder.encode($0) },
                        uiSchemaJSON: try? a.input.uiSchema.map { try self.encoder.encode($0) }
                    )
                )
            },
            revision: n.revision, expiresAt: n.expiresAt,
            rawJSON: try encoder.encode(n.raw)
        )
    }

    // MARK: Lifecycle

    public func reset() {
        engine.reset()
        syncState()
    }

    // MARK: Mapping helpers (verbatim passthroughs, zero invented fields)

    private func decodePayload(_ qrJSON: Data) throws -> MobileLoginPayload {
        try JSONDecoder().decode(MobileLoginPayload.self, from: qrJSON)
    }

    private func encode<T: Encodable>(_ v: T) throws -> Data {
        try encoder.encode(v)
    }

    /// ok/result/error semantics = official requireSuccess(), mapped to public error.
    private func absorb(_ r: V2RuntimeActionResponse) throws -> Data {
        if r.ok { return try r.result.map(encoder.encode) ?? Data("{}".utf8) }
        throw RemoteServiceError.rejected(code: r.error?.code, message: r.error?.message ?? "The runtime did not accept this operation.")
    }

    private func attempt<T>(_ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch let e as RemoteBackendError {
            switch e {
            case .notConfigured: throw RemoteServiceError.notConfigured
            case .notReady:      throw RemoteServiceError.notReady
            }
        }
        catch let e as V2RuntimeError {
            throw RemoteServiceError.rejected(code: e.code, message: e.message)
        }
        catch { throw RemoteServiceError.transport(error) }
    }
}

private extension RemoteWireEvent {
    init(from e: V2SessionEvent, encoder: JSONEncoder) throws {
        self.eventId = e.eventId
        self.sequence = e.sequence
        self.cursor = e.cursor
        self.type = e.type
        self.sessionId = e.sessionId
        self.emittedAt = e.emittedAt
        self.payloadJSON = try encoder.encode(e.payload)
    }
}
